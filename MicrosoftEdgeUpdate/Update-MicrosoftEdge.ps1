#Requires -Version 5.1
<#
.SYNOPSIS
    Checks or updates installed Microsoft Edge stable.

.DESCRIPTION
    ScreenConnect Backstage and Commands. Reads the installed stable version
    and compares it to Microsoft's enterprise release list. Does not install
    Edge when it is missing. The verdict is for stable Edge only. Microsoft's
    updater may also refresh other apps it manages, such as WebView2.

    Apply starts the Edge updater already on the PC
    (MicrosoftEdgeUpdate.exe /update). Open Edge windows can keep the old
    version until they close. Does not reboot.

.PARAMETER CheckOnly
    Report only. Does not start the updater.

.PARAMETER Force
    Start the updater even when Edge already matches the current stable release.

.PARAMETER WaitSeconds
    How long to watch the installed version after starting the updater.

.PARAMETER NoExit
    Keep the PowerShell host open (Backstage).

.PARAMETER Exit
    Always exit with the result code (Commands).
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Force,
    [int]$WaitSeconds = 180,
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptVersion = '1.0.0'
$EdgeAppId = '{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'
$ProductsUri = 'https://edgeupdates.microsoft.com/api/products?view=enterprise'

try {
    [Net.ServicePointManager]::SecurityProtocol = (
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    )
}
catch {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
}

function Write-EdgeLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts][$Level] $Message"
}

function Write-EdgeVerdict {
    param(
        [Parameter(Mandatory)][string]$Status,
        [string]$Detail
    )
    Write-Host ''
    Write-Host ('======== MICROSOFT EDGE: {0} ========' -f $Status)
    if ($Detail) { Write-Host $Detail }
    Write-Host '================================================'
    Write-Host ''
}

function Test-EdgeElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Test-EdgeShouldExitProcess {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-Edge {
    param([Parameter(Mandatory)][int]$Code)
    $global:LASTEXITCODE = $Code
    try { $global:MicrosoftEdgeUpdateResultCode = $Code } catch { }
    if (Test-EdgeShouldExitProcess) { exit $Code }
    Write-EdgeLog ("Done. ResultCode={0} (PowerShell host kept open)." -f $Code)
}

function ConvertTo-EdgeVersion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $m = [regex]::Match($Text, '\d+\.\d+\.\d+\.\d+')
    if (-not $m.Success) { return $null }
    try { return [version]$m.Value } catch { return $null }
}

function Get-EdgeClientProperty {
    $roots = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients'
        'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients'
    )
    foreach ($root in $roots) {
        $key = Join-Path $root $EdgeAppId
        if (-not (Test-Path -LiteralPath $key)) { continue }
        $p = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($p) { return $p }
    }
    return $null
}

function Get-EdgeExePath {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe')
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
    )
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

function Get-EdgeMachine {
    param([string]$Path)
    if (-not $Path) { return $null }
    $fs = $null
    $br = $null
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        $br = New-Object System.IO.BinaryReader($fs)
        $fs.Position = 0x3C
        $pe = $br.ReadInt32()
        $fs.Position = $pe + 4
        switch ($br.ReadUInt16()) {
            0x014C { return 'x86' }
            0x8664 { return 'x64' }
            0xAA64 { return 'arm64' }
            default { return $null }
        }
    }
    catch { return $null }
    finally {
        if ($br) { $br.Dispose() }
        elseif ($fs) { $fs.Dispose() }
    }
}

function Get-InstalledEdge {
    $client = Get-EdgeClientProperty
    $pv = $null
    if ($client) { $pv = ConvertTo-EdgeVersion ([string]$client.pv) }
    $exe = Get-EdgeExePath
    if (-not $pv -and $exe) {
        $pv = ConvertTo-EdgeVersion ([string](Get-Item -LiteralPath $exe).VersionInfo.FileVersion)
    }
    if (-not $pv) { return $null }
    if ($pv -le [version]'0.0.0.0') { return $null }
    [pscustomobject]@{
        Version      = $pv
        Architecture = Get-EdgeMachine $exe
        ExePath      = $exe
    }
}

function Get-LatestStableEdgeVersion {
    param([string]$Architecture)
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', "MicrosoftEdgeUpdate/$ScriptVersion")
    $raw = $wc.DownloadString($ProductsUri)
    $products = $raw | ConvertFrom-Json
    $stable = @($products | Where-Object { $_.Product -eq 'Stable' })
    if ($stable.Count -eq 0) { throw 'Stable channel was not in the Edge release list.' }
    $releases = @($stable[0].Releases | Where-Object { $_.Platform -eq 'Windows' })
    if ($Architecture) {
        $matched = @($releases | Where-Object { $_.Architecture -eq $Architecture })
        if ($matched.Count -gt 0) { $releases = $matched }
    }
    $best = $null
    foreach ($rel in $releases) {
        $ver = ConvertTo-EdgeVersion ([string]$rel.ProductVersion)
        if ($ver -and (-not $best -or $ver -gt $best)) { $best = $ver }
    }
    if (-not $best) { throw 'No Windows stable version was listed.' }
    return $best
}

function Get-EdgeUpdateBlock {
    $paths = @(
        'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
        'HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\EdgeUpdate'
    )
    $appValue = "Update$EdgeAppId"
    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $p = Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        if ($p.UpdateDefault -eq 0) { return "policy $path UpdateDefault=0" }
        $names = @($p.PSObject.Properties.Name)
        if ($names -contains $appValue -and $p.$appValue -eq 0) {
            return "policy $path $appValue=0"
        }
    }
    return $null
}

function Get-EdgeUpdaterPath {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe')
        (Join-Path $env:ProgramFiles 'Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe')
    )
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

function Start-EdgeUpdateService {
    $svc = Get-Service -Name 'edgeupdate' -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-EdgeLog 'edgeupdate service was not found. Continuing with MicrosoftEdgeUpdate.exe.' 'WARN'
        return
    }
    if ($svc.StartType -eq 'Disabled') {
        Write-EdgeLog 'edgeupdate startup is Disabled. Setting it to Manual.'
        Set-Service -Name 'edgeupdate' -StartupType Manual
    }
    if ($svc.Status -ne 'Running') {
        Start-Service -Name 'edgeupdate' -ErrorAction SilentlyContinue
        $svc = Get-Service -Name 'edgeupdate' -ErrorAction SilentlyContinue
        Write-EdgeLog ("edgeupdate service: {0}" -f $svc.Status)
    }
}

function Start-EdgeUpdater {
    param([string]$UpdaterPath)
    Write-EdgeLog ("Starting {0} /update" -f $UpdaterPath)
    $p = Start-Process -FilePath $UpdaterPath -ArgumentList '/update' -PassThru -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(30)
    while (-not $p.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
        try { $p.Refresh() } catch { break }
    }
    if ($p.HasExited) {
        Write-EdgeLog ("MicrosoftEdgeUpdate.exe exit {0}" -f $p.ExitCode)
        return [int]$p.ExitCode
    }
    Write-EdgeLog 'MicrosoftEdgeUpdate.exe is still running. Watching the installed version.' 'WARN'
    return $null
}

Write-EdgeLog ("MicrosoftEdgeUpdate {0}" -f $ScriptVersion)
$installed = Get-InstalledEdge
if (-not $installed) {
    Write-EdgeVerdict -Status 'NOT INSTALLED' -Detail 'Microsoft Edge stable is not installed. Nothing was installed.'
    Complete-Edge -Code 1
    return
}

Write-EdgeLog ("Installed stable: {0} arch={1}" -f $installed.Version, $installed.Architecture)

$latest = $null
$catalogError = $null
try {
    $latest = Get-LatestStableEdgeVersion -Architecture $installed.Architecture
    Write-EdgeLog ("Current stable: {0}" -f $latest)
}
catch {
    $catalogError = $_.Exception.Message
    Write-EdgeLog ("Could not read the Edge release list: {0}" -f $catalogError) 'WARN'
}

$behind = $true
if ($latest -and $installed.Version -ge $latest) { $behind = $false }

if ($CheckOnly) {
    if ($catalogError) {
        Write-EdgeVerdict -Status 'COULD NOT VERIFY' -Detail ("Installed {0}. {1}" -f $installed.Version, $catalogError)
        Complete-Edge -Code 1
        return
    }
    if ($behind) {
        Write-EdgeVerdict -Status 'UPDATE AVAILABLE' -Detail ("Installed {0} is behind stable {1}." -f $installed.Version, $latest)
        Complete-Edge -Code 2
        return
    }
    Write-EdgeVerdict -Status 'UP TO DATE' -Detail ("Installed {0} is the current stable release." -f $installed.Version)
    Complete-Edge -Code 0
    return
}

if (-not $behind -and -not $Force) {
    Write-EdgeVerdict -Status 'UP TO DATE' -Detail ("Installed {0} is the current stable release. Use -Force to run the updater anyway." -f $installed.Version)
    Complete-Edge -Code 0
    return
}

if (-not (Test-EdgeElevated)) {
    Write-EdgeVerdict -Status 'ERROR' -Detail 'Updating Edge requires an elevated session.'
    Complete-Edge -Code 1
    return
}

$block = Get-EdgeUpdateBlock
if ($block) {
    Write-EdgeVerdict -Status 'BLOCKED BY POLICY' -Detail $block
    Complete-Edge -Code 1
    return
}

$updater = Get-EdgeUpdaterPath
if (-not $updater) {
    Write-EdgeVerdict -Status 'ERROR' -Detail 'MicrosoftEdgeUpdate.exe was not found.'
    Complete-Edge -Code 1
    return
}

$before = $installed.Version
Start-EdgeUpdateService
[void](Start-EdgeUpdater -UpdaterPath $updater)

$deadline = (Get-Date).AddSeconds($WaitSeconds)
$now = $before
do {
    Start-Sleep -Seconds 5
    $again = Get-InstalledEdge
    if ($again) { $now = $again.Version }
    if ($latest -and $now -ge $latest) { break }
    if (-not $latest -and $now -gt $before) { break }
} while ((Get-Date) -lt $deadline)

if ($latest -and $now -ge $latest) {
    Write-EdgeVerdict -Status 'UP TO DATE' -Detail ("Edge is {0}." -f $now)
    Complete-Edge -Code 0
    return
}

$edgeRunning = @(Get-Process -Name 'msedge' -ErrorAction SilentlyContinue).Count -gt 0
$detail = "Installed version is still {0}." -f $now
if ($latest) { $detail = "Installed {0}. Current stable is {1}." -f $now, $latest }
if ($edgeRunning) { $detail += ' Edge is open, so the new version can wait until those windows close.' }
else { $detail += ' The updater was started and had not finished in this wait.' }
Write-EdgeVerdict -Status 'UPDATE STARTED' -Detail $detail
Complete-Edge -Code 2
