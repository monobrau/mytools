#Requires -Version 5.1
<#
.SYNOPSIS
    Updates an already-installed Dell SupportAssist for Home PCs.

.DESCRIPTION
    ScreenConnect Backstage (SYSTEM) and Commands (#!ps). Does not install
    SupportAssist when it is absent. Does not touch OS Recovery, Remediation,
    or TechHub.

    The installer is Dell's current bootstrapper:
    https://downloads.dell.com/serviceability/catalog/SupportAssistInstaller.exe
    Silent switch: /S

    -CheckOnly compares the installed version to -LatestVersion when that is
    set, otherwise to the built-in target (SupportAssist 5.2.0.1519, August 2026).
    Default action updates when the installed copy is older. -Force runs the
    installer even when the installed version is already at the target.
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Force,
    [string]$InstallerUrl = 'https://downloads.dell.com/serviceability/catalog/SupportAssistInstaller.exe',
    [string]$LatestVersion = '5.2.0.1519',
    [string]$WorkingDirectory = (Join-Path $env:ProgramData 'DellSupportAssistUpdate'),
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ScriptVersion = '1.0.0'

try {
    [Net.ServicePointManager]::SecurityProtocol = (
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    )
}
catch {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
}

function Write-DsaLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts][$Level] $Message"
}

function Test-DsaElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function ConvertTo-DsaVersion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $clean = ($Text -replace '[^\d\.]', '').Trim('.')
    if ([string]::IsNullOrWhiteSpace($clean)) { return $null }
    $parts = @($clean.Split('.') | Where-Object { $_ -ne '' })
    while ($parts.Count -lt 2) { $parts += '0' }
    if ($parts.Count -gt 4) { $parts = $parts[0..3] }
    try { return [version]($parts -join '.') } catch { return $null }
}

function Get-InstalledDellSupportAssist {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($root in $roots) {
        foreach ($app in @(Get-ItemProperty -Path $root -ErrorAction SilentlyContinue)) {
            $name = [string]$app.DisplayName
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if ($name -notmatch 'SupportAssist') { continue }
            if ($name -match 'OS Recovery|Remediation|TechHub|Plugin') { continue }
            [void]$rows.Add([pscustomobject]@{
                DisplayName    = $name
                DisplayVersion = [string]$app.DisplayVersion
                Version        = ConvertTo-DsaVersion ([string]$app.DisplayVersion)
                UninstallString = [string]$app.UninstallString
            })
        }
    }
    return @($rows.ToArray())
}

function Test-DsaShouldExitProcess {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-Dsa {
    param([Parameter(Mandatory)][int]$Code)
    $global:LASTEXITCODE = $Code
    try { $global:DellSupportAssistUpdateResultCode = $Code } catch { }
    if (Test-DsaShouldExitProcess) { exit $Code }
    Write-DsaLog ("Done. ResultCode={0} (PowerShell host kept open)." -f $Code)
}

function Install-DellSupportAssist {
    param([string]$Url, [string]$WorkDir)
    if (-not (Test-Path -LiteralPath $WorkDir)) {
        New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    }
    $dest = Join-Path $WorkDir 'SupportAssistInstaller.exe'
    Write-DsaLog ("Downloading {0}" -f $Url)
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', "DellSupportAssistUpdate/$ScriptVersion")
    $wc.DownloadFile($Url, $dest)
    if (-not (Test-Path -LiteralPath $dest) -or (Get-Item -LiteralPath $dest).Length -lt 100000) {
        throw "Installer download looks empty: $dest"
    }
    Write-DsaLog ("Running silent installer: {0} /S" -f $dest)
    $p = Start-Process -FilePath $dest -ArgumentList '/S' -Wait -PassThru -WindowStyle Hidden
    $code = 0
    if ($p -and $null -ne $p.ExitCode) { $code = [int]$p.ExitCode }
    Write-DsaLog ("Installer exit code: {0}" -f $code)
    return $code
}

$target = ConvertTo-DsaVersion $LatestVersion
Write-DsaLog ("DellSupportAssistUpdate {0}" -f $ScriptVersion)
Write-DsaLog ("Target version: {0} | CheckOnly={1} Force={2} Elevated={3}" -f $LatestVersion, $CheckOnly.IsPresent, $Force.IsPresent, (Test-DsaElevated))

$installed = @(Get-InstalledDellSupportAssist)
if ($installed.Count -eq 0) {
    Write-DsaLog 'Dell SupportAssist is not installed. Nothing to update.'
    Complete-Dsa -Code 0
    return
}

foreach ($app in $installed) {
    Write-DsaLog ("Installed: {0} {1}" -f $app.DisplayName, $app.DisplayVersion)
}

$current = $installed | Sort-Object { $_.Version } -Descending | Select-Object -First 1
$behind = $true
if ($current.Version -and $target -and $current.Version -ge $target) { $behind = $false }

if ($CheckOnly) {
    if ($behind) {
        Write-DsaLog ("Update available: {0} -> {1}" -f $current.DisplayVersion, $LatestVersion)
        Complete-Dsa -Code 2
    }
    else {
        Write-DsaLog 'Installed SupportAssist is at or above the target.'
        Complete-Dsa -Code 0
    }
    return
}

if (-not $behind -and -not $Force) {
    Write-DsaLog 'Installed SupportAssist is at or above the target. Use -Force to run the installer anyway.'
    Complete-Dsa -Code 0
    return
}

if (-not (Test-DsaElevated)) {
    Write-DsaLog 'Update requires elevation.' 'ERROR'
    Complete-Dsa -Code 1
    return
}

$installCode = Install-DellSupportAssist -Url $InstallerUrl -WorkDir $WorkingDirectory
$after = @(Get-InstalledDellSupportAssist)
foreach ($app in $after) {
    Write-DsaLog ("After install: {0} {1}" -f $app.DisplayName, $app.DisplayVersion)
}

$ok = @(0, 3010, 1641) -contains $installCode
if (-not $ok) {
    Write-DsaLog 'Installer failed.' 'ERROR'
    Complete-Dsa -Code 1
    return
}

if ($installCode -eq 3010 -or $installCode -eq 1641) {
    Write-DsaLog 'Reboot required to finish the SupportAssist update.' 'WARN'
    Complete-Dsa -Code $installCode
    return
}

Complete-Dsa -Code 0
