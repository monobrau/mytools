#Requires -Version 5.1
<#
.SYNOPSIS
    Checks installed HP Support Assistant version and silently updates to the latest SoftPaq.

.DESCRIPTION
    Designed for ConnectWise ScreenConnect Backstage (SYSTEM) and the Commands tab (#!ps).
    Resolves the latest package from winget-pkgs (GitHub) or winget CLI (HPInc.HPSupportAssistant),
    compares to the installed DisplayVersion, downloads the SoftPaq from ftp.hp.com, and installs
    silently.

    Check-only by default. Pass -Update to install when older (or missing). Pass -Force to reinstall
    even when already current.

.PARAMETER Update
    Download and silently install when installed version is older than latest (or not installed).

.PARAMETER Force
    Reinstall even if installed version is equal to or newer than latest. Implies -Update.

.PARAMETER SoftPaqUrl
    Optional override SoftPaq URL (skips winget-pkgs lookup). Still uses -LatestVersion if provided.

.PARAMETER LatestVersion
    Optional override for the "latest" version string used in comparisons (e.g. 9.47.41.0).

.PARAMETER WorkingDirectory
    Folder for download/extract. Default: %ProgramData%\HpSupportAssistantUpdate

.PARAMETER NoExit
    Do not call exit (keeps ScreenConnect Backstage PowerShell open). Implied automatically
    when the script is invoked via ScriptBlock in an interactive host.

.PARAMETER Exit
    Always call exit with the result code (use for ScreenConnect Commands / automation).
#>
[CmdletBinding()]
param(
    [switch]$Update,
    [switch]$Force,
    [string]$SoftPaqUrl,
    [string]$LatestVersion,
    [string]$WorkingDirectory = (Join-Path $env:ProgramData 'HpSupportAssistantUpdate'),
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptVersion = '1.0.3'
$WingetPackageId = 'HPInc.HPSupportAssistant'
$WingetManifestApi = 'https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/h/HPInc/HPSupportAssistant'
# Do NOT match "HP Support Solutions Framework" — that is a companion with a different version scheme (12.x vs HPSA 9.x).
$HpsaDisplayNamePattern = '^HP Support Assistant(\s|$)'
$FrameworkDisplayNamePattern = '^HP Support Solutions Framework(\s|$)'

if ($Force) { $Update = $true }

# TLS 1.2 for Windows PowerShell 5.1 / older .NET; harmless on pwsh (.NET Core).
try {
    [Net.ServicePointManager]::SecurityProtocol = (
        [Net.ServicePointManager]::SecurityProtocol -bor
        [Net.SecurityProtocolType]::Tls12
    )
}
catch {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
}

function Write-HpsaLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Output "[$ts][$Level] $Message"
}

function Test-IsWindowsHost {
    if ($null -ne (Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue)) {
        return [bool]$IsWindows
    }
    return ($env:OS -like 'Windows*')
}

function Test-IsElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function ConvertTo-HpsaVersion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $clean = ($Text -replace '[^\d\.]', '').Trim('.')
    if ([string]::IsNullOrWhiteSpace($clean)) { return $null }
    # Force array: a single Split result is a [string] in Windows PowerShell (Count = length).
    $parts = @($clean.Split('.') | Where-Object { $_ -ne '' })
    while ($parts.Count -lt 2) { $parts += '0' }
    if ($parts.Count -gt 4) { $parts = $parts[0..3] }
    try { return [version](($parts -join '.')) } catch { return $null }
}

function ConvertTo-HpsaText {
    # Normalize Invoke-WebRequest Content for Windows PowerShell 5.1 and pwsh 7+.
    param($Content)
    if ($null -eq $Content) { return '' }
    if ($Content -is [byte[]]) {
        return [System.Text.Encoding]::UTF8.GetString($Content)
    }
    $text = [string]$Content
    if ($text.Length -gt 0 -and [int][char]$text[0] -eq 0xFEFF) {
        $text = $text.Substring(1)
    }
    return $text
}

function Invoke-HpsaWebRequest {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [hashtable]$Headers,
        [string]$OutFile,
        [int]$TimeoutSec = 60
    )
    $params = @{
        Uri             = $Uri
        UseBasicParsing = $true
        TimeoutSec      = $TimeoutSec
    }
    if ($Headers) { $params['Headers'] = $Headers }
    if ($OutFile) { $params['OutFile'] = $OutFile }
    return Invoke-WebRequest @params
}

function Get-UninstallEntries {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
    }
}

function Get-HpSupportFrameworkCompanion {
    $hit = Get-UninstallEntries | Where-Object {
        $_.DisplayName -and ($_.DisplayName -match $FrameworkDisplayNamePattern)
    } | Select-Object -First 1

    if (-not $hit) { return $null }
    return [pscustomobject]@{
        DisplayName    = [string]$hit.DisplayName
        DisplayVersion = [string]$hit.DisplayVersion
        Version        = ConvertTo-HpsaVersion -Text ([string]$hit.DisplayVersion)
    }
}

function Get-HpsaVersionFromFiles {
    $candidates = @(
        "${env:ProgramFiles(x86)}\HP\HP Support Framework\HPSF.exe"
        "${env:ProgramFiles(x86)}\Hewlett-Packard\HP Support Framework\HPSF.exe"
        "${env:ProgramFiles(x86)}\HP\HP Support Framework\HPSupportAssistant.exe"
        "${env:ProgramFiles(x86)}\Hewlett-Packard\HP Support Framework\HPSupportAssistant.exe"
        "${env:ProgramFiles}\HP\HP Support Framework\HPSF.exe"
        "${env:ProgramFiles}\Hewlett-Packard\HP Support Framework\HPSF.exe"
    )

    foreach ($path in $candidates) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $fv = [version](Get-Item -LiteralPath $path).VersionInfo.FileVersion
            # SoftPaq / winget HPSA versions are 9.x (sometimes 8.x). Framework binaries often report 12.x — skip those.
            if ($fv.Major -ge 8 -and $fv.Major -le 11) {
                return [pscustomobject]@{
                    DisplayName     = 'HP Support Assistant (file)'
                    DisplayVersion  = $fv.ToString()
                    Publisher       = 'HP'
                    UninstallString = ''
                    InstallLocation = [string](Split-Path -Parent $path)
                    Version         = $fv
                    Source          = "file:$path"
                }
            }
        }
        catch { }
    }
    return $null
}

function Get-HpsaVersionFromAppx {
    try {
        $pkg = Get-AppxPackage -Name '*HPSupportAssistant*' -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending |
            Select-Object -First 1
        if (-not $pkg) {
            $pkg = Get-AppxPackage -AllUsers -Name '*HPSupportAssistant*' -ErrorAction SilentlyContinue |
                Sort-Object Version -Descending |
                Select-Object -First 1
        }
        if (-not $pkg) { return $null }

        $ver = ConvertTo-HpsaVersion -Text ([string]$pkg.Version)
        if (-not $ver) { return $null }
        return [pscustomobject]@{
            DisplayName     = [string]$pkg.Name
            DisplayVersion  = [string]$pkg.Version
            Publisher       = [string]$pkg.Publisher
            UninstallString = ''
            InstallLocation = [string]$pkg.InstallLocation
            Version         = $ver
            Source          = 'appx'
        }
    }
    catch { return $null }
}

function Get-InstalledHpSupportAssistant {
    # ARP: product name only (never Solutions Framework — different version lineage).
    $arpHits = @(
        Get-UninstallEntries | Where-Object {
            $_.DisplayName -and ($_.DisplayName -match $HpsaDisplayNamePattern)
        }
    )

    $bestArp = $arpHits |
        ForEach-Object {
            [pscustomobject]@{
                DisplayName     = [string]$_.DisplayName
                DisplayVersion  = [string]$_.DisplayVersion
                Publisher       = [string]$_.Publisher
                UninstallString = [string]$_.UninstallString
                InstallLocation = [string]$_.InstallLocation
                Version         = ConvertTo-HpsaVersion -Text ([string]$_.DisplayVersion)
                Source          = 'arp'
            }
        } |
        Where-Object { $_.Version } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($bestArp) { return $bestArp }

    $fromFile = Get-HpsaVersionFromFiles
    if ($fromFile) { return $fromFile }

    $fromAppx = Get-HpsaVersionFromAppx
    if ($fromAppx) { return $fromAppx }

    return $null
}

function Invoke-GitHubJson {
    param([Parameter(Mandatory)][string]$Uri)
    $headers = @{
        'User-Agent' = "HpSupportAssistantUpdate/$ScriptVersion"
        'Accept'     = 'application/vnd.github+json'
    }
    $resp = Invoke-HpsaWebRequest -Uri $Uri -Headers $headers -TimeoutSec 60
    $json = ConvertTo-HpsaText -Content $resp.Content
    return ($json | ConvertFrom-Json)
}

function Get-LatestHpSupportAssistantFromWingetCli {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { return $null }

    $out = & winget.exe show --id $WingetPackageId --exact --accept-source-agreements 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($out)) { return $null }

    $ver = $null
    $url = $null
    foreach ($line in ($out -split "`r?`n")) {
        if ($line -match '^\s*Version:\s*(.+)\s*$') { $ver = $Matches[1].Trim() }
        if ($line -match '^\s*Installer Url:\s*(.+)\s*$') { $url = $Matches[1].Trim() }
    }
    if (-not $ver -or -not $url) { return $null }

    return [pscustomobject]@{
        Version      = $ver
        VersionObj   = ConvertTo-HpsaVersion -Text $ver
        InstallerUrl = $url
        Sha256       = $null
        Source       = 'winget-cli'
        PackageId    = $WingetPackageId
    }
}

function Get-LatestHpSupportAssistantFromWingetPkgs {
    $dirs = @(Invoke-GitHubJson -Uri $WingetManifestApi)
    $versionNames = @(
        $dirs |
            Where-Object { $_.type -eq 'dir' -and $_.name -match '^\d' } |
            ForEach-Object { [string]$_.name }
    )
    if ($versionNames.Count -eq 0) {
        throw 'No version folders found in winget-pkgs for HPInc.HPSupportAssistant.'
    }

    $sorted = @($versionNames | Sort-Object { ConvertTo-HpsaVersion -Text $_ } -Descending)
    $latestName = [string]$sorted[0]
    $files = @(Invoke-GitHubJson -Uri "$WingetManifestApi/$latestName")
    $installer = $files | Where-Object { $_.name -like '*.installer.yaml' } | Select-Object -First 1
    if (-not $installer) {
        throw "No installer.yaml found for winget package version $latestName."
    }

    $yamlUrl = [string]$installer.download_url
    if (-not $yamlUrl) {
        $yamlUrl = "https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests/h/HPInc/HPSupportAssistant/$latestName/$($installer.name)"
    }
    $yamlResp = Invoke-HpsaWebRequest -Uri $yamlUrl -TimeoutSec 60
    $yaml = ConvertTo-HpsaText -Content $yamlResp.Content
    $urlMatch = [regex]::Match($yaml, 'InstallerUrl:\s*(\S+)')
    $hashMatch = [regex]::Match($yaml, 'InstallerSha256:\s*([A-Fa-f0-9]{64})')
    if (-not $urlMatch.Success) {
        throw "InstallerUrl missing from manifest $latestName."
    }

    return [pscustomobject]@{
        Version      = $latestName
        VersionObj   = ConvertTo-HpsaVersion -Text $latestName
        InstallerUrl = $urlMatch.Groups[1].Value.Trim()
        Sha256       = if ($hashMatch.Success) { $hashMatch.Groups[1].Value.ToUpperInvariant() } else { $null }
        Source       = 'winget-pkgs'
        PackageId    = $WingetPackageId
    }
}

function Get-LatestHpSupportAssistantPackage {
    # Prefer GitHub winget-pkgs under ScreenConnect SYSTEM (winget is often missing/flaky as SYSTEM).
    $errors = New-Object System.Collections.Generic.List[string]

    try {
        return (Get-LatestHpSupportAssistantFromWingetPkgs)
    }
    catch { [void]$errors.Add("winget-pkgs: $($_.Exception.Message)") }

    try {
        $fromCli = Get-LatestHpSupportAssistantFromWingetCli
        if ($fromCli) { return $fromCli }
        [void]$errors.Add('winget-cli: no Version/Installer Url from winget show')
    }
    catch { [void]$errors.Add("winget-cli: $($_.Exception.Message)") }

    throw ("Unable to resolve latest HP Support Assistant package. " + ($errors -join ' | '))
}

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Invoke-SoftPaqSilentInstall {
    param(
        [Parameter(Mandatory)]
        [string]$SoftPaqPath,
        [Parameter(Mandatory)]
        [string]$ExtractDir
    )

    # Prefer SoftPaq silent install (/s). Fallback: extract then InstallHPSA.exe /S /v/qn.
    Write-HpsaLog "Running SoftPaq silent install: `"$SoftPaqPath`" /s"
    $p = Start-Process -FilePath $SoftPaqPath -ArgumentList '/s' -Wait -PassThru -WindowStyle Hidden
    Write-HpsaLog "SoftPaq /s exit code: $($p.ExitCode)"
    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
        return $p.ExitCode
    }

    Write-HpsaLog "SoftPaq /s returned $($p.ExitCode); trying extract + InstallHPSA.exe" 'WARN'
    if (Test-Path -LiteralPath $ExtractDir) {
        Remove-Item -LiteralPath $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null

    $extractArgs = @('/s', '/e', '/f', "`"$ExtractDir`"")
    $p2 = Start-Process -FilePath $SoftPaqPath -ArgumentList $extractArgs -Wait -PassThru -WindowStyle Hidden
    Write-HpsaLog "SoftPaq extract exit code: $($p2.ExitCode)"
    if ($p2.ExitCode -ne 0) {
        return $p2.ExitCode
    }

    $installer = Get-ChildItem -LiteralPath $ExtractDir -Recurse -Filter 'InstallHPSA.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $installer) {
        Write-HpsaLog 'InstallHPSA.exe not found after SoftPaq extract.' 'ERROR'
        return 2
    }

    Write-HpsaLog "Running `"$($installer.FullName)`" /S /v/qn"
    $p3 = Start-Process -FilePath $installer.FullName -ArgumentList '/S', '/v/qn' -Wait -PassThru -WindowStyle Hidden
    Write-HpsaLog "InstallHPSA exit code: $($p3.ExitCode)"
    return $p3.ExitCode
}

function Test-HpsaShouldExitProcess {
    # exit kills the whole ScreenConnect Backstage console when invoked via ScriptBlock.
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    # File / -File invocation: exit so callers get a process code.
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    # ScriptBlock + interactive host (typical Backstage): keep the console open.
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-Hpsa {
    param([Parameter(Mandatory)][int]$Code)
    $global:LASTEXITCODE = $Code
    try { $global:HpsaResultCode = $Code } catch { }

    if (Test-HpsaShouldExitProcess) {
        exit $Code
    }

    Write-HpsaLog ("Done. ResultCode={0} (PowerShell host kept open)." -f $Code)
    return
}

# --- main ---
$hostEdition = if ($PSVersionTable.PSEdition) { [string]$PSVersionTable.PSEdition } else { 'Desktop' }
Write-HpsaLog ("HpSupportAssistantUpdate {0}" -f $ScriptVersion)
Write-HpsaLog ("Host: PowerShell {0} ({1})" -f $PSVersionTable.PSVersion, $hostEdition)
Write-HpsaLog ("User: {0} | Elevated: {1} | Force={2} Update={3}" -f `
        [Security.Principal.WindowsIdentity]::GetCurrent().Name, (Test-IsElevated), $Force, $Update)

if (-not (Test-IsWindowsHost)) {
    Write-HpsaLog 'Windows only.' 'ERROR'
    Complete-Hpsa -Code 1
    return
}

$framework = Get-HpSupportFrameworkCompanion
if ($framework) {
    Write-HpsaLog ("Companion present (not used for version compare): {0} {1}" -f `
            $framework.DisplayName, $framework.DisplayVersion)
}

$installed = Get-InstalledHpSupportAssistant
if ($installed) {
    $src = if ($installed.Source) { $installed.Source } else { 'arp' }
    Write-HpsaLog ("Installed HPSA: {0} {1} (source={2})" -f `
            $installed.DisplayName, $installed.DisplayVersion, $src)
}
else {
    Write-HpsaLog 'Installed HPSA: not found (Programs and Features / file / AppX)'
}

try {
    if ($SoftPaqUrl) {
        $latest = [pscustomobject]@{
            Version      = if ($LatestVersion) { $LatestVersion } else { 'override' }
            VersionObj   = ConvertTo-HpsaVersion -Text $LatestVersion
            InstallerUrl = $SoftPaqUrl
            Sha256       = $null
            Source       = 'override'
            PackageId    = $WingetPackageId
        }
    }
    else {
        Write-HpsaLog 'Resolving latest SoftPaq (winget-pkgs, then winget CLI)...'
        $latest = Get-LatestHpSupportAssistantPackage
    }
}
catch {
    Write-HpsaLog "Failed to resolve latest package: $($_.Exception.Message)" 'ERROR'
    Complete-Hpsa -Code 1
    return
}

Write-HpsaLog ("Latest:  {0} ({1})" -f $latest.Version, $latest.Source)
Write-HpsaLog ("SoftPaq: {0}" -f $latest.InstallerUrl)

$needUpdate = $false
if (-not $installed -or -not $installed.Version) {
    $needUpdate = $true
    Write-HpsaLog 'Decision: install required (missing or unknown installed version).'
}
elseif ($Force) {
    $needUpdate = $true
    Write-HpsaLog 'Decision: Force reinstall requested.'
}
elseif ($latest.VersionObj -and $installed.Version -lt $latest.VersionObj) {
    $needUpdate = $true
    Write-HpsaLog ("Decision: update needed ({0} < {1})." -f $installed.Version, $latest.VersionObj)
}
elseif ($latest.VersionObj -and $installed.Version -ge $latest.VersionObj) {
    Write-HpsaLog ("Decision: already current ({0} >= {1})." -f $installed.Version, $latest.VersionObj)
}
else {
    # Latest version string not parseable (override without -LatestVersion)
    $needUpdate = $true
    Write-HpsaLog 'Decision: cannot compare versions cleanly; treat as update candidate.' 'WARN'
}

if (-not $Update) {
    Write-HpsaLog 'Check-only complete (pass -Update to install).'
    if ($needUpdate) { Complete-Hpsa -Code 2 } else { Complete-Hpsa -Code 0 }
    return
}

if (-not $needUpdate) {
    Write-HpsaLog 'Nothing to do.'
    Complete-Hpsa -Code 0
    return
}

if (-not (Test-IsElevated)) {
    Write-HpsaLog 'Elevation required for install (run as SYSTEM / Administrator).' 'ERROR'
    Complete-Hpsa -Code 1
    return
}

New-Item -ItemType Directory -Path $WorkingDirectory -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$softpaqPath = Join-Path $WorkingDirectory ("sp_hpsa_$stamp.exe")
$extractDir = Join-Path $WorkingDirectory ("extract_$stamp")

try {
    Write-HpsaLog "Downloading SoftPaq to $softpaqPath"
    Invoke-HpsaWebRequest -Uri $latest.InstallerUrl -OutFile $softpaqPath -TimeoutSec 600 | Out-Null

    if ($latest.Sha256) {
        $actual = Get-FileSha256 -Path $softpaqPath
        if ($actual -ne $latest.Sha256) {
            throw "SHA256 mismatch. Expected $($latest.Sha256), got $actual"
        }
        Write-HpsaLog 'SHA256 verified.'
    }

    $exitCode = Invoke-SoftPaqSilentInstall -SoftPaqPath $softpaqPath -ExtractDir $extractDir
    Start-Sleep -Seconds 3
    $after = Get-InstalledHpSupportAssistant
    if ($after) {
        Write-HpsaLog ("Post-install: {0} {1}" -f $after.DisplayName, $after.DisplayVersion)
    }
    else {
        Write-HpsaLog 'Post-install: HP Support Assistant still not detected in uninstall registry.' 'WARN'
    }

    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-HpsaLog 'Update completed successfully.'
        if ($exitCode -eq 3010) {
            Write-HpsaLog 'Exit 3010: reboot required to finish install.' 'WARN'
        }
        Complete-Hpsa -Code $exitCode
        return
    }

    Write-HpsaLog "Update finished with exit code $exitCode." 'ERROR'
    Complete-Hpsa -Code $exitCode
    return
}
catch {
    Write-HpsaLog $_.Exception.Message 'ERROR'
    Complete-Hpsa -Code 1
    return
}
finally {
    # Keep SoftPaq for troubleshooting on failure; remove extract tree always.
    if ($extractDir -and (Test-Path -LiteralPath $extractDir)) {
        Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
