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
#>
[CmdletBinding()]
param(
    [switch]$Update,
    [switch]$Force,
    [string]$SoftPaqUrl,
    [string]$LatestVersion,
    [string]$WorkingDirectory = (Join-Path $env:ProgramData 'HpSupportAssistantUpdate')
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.0.0'
$WingetPackageId = 'HPInc.HPSupportAssistant'
$WingetManifestApi = 'https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/h/HPInc/HPSupportAssistant'
$DisplayNamePattern = 'HP Support Assistant|HP Support Solutions Framework'

if ($Force) { $Update = $true }

function Write-HpsaLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Output "[$ts][$Level] $Message"
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
    # Normalize to up to 4 parts for [version]
    $parts = $clean.Split('.') | Where-Object { $_ -ne '' }
    while ($parts.Count -lt 2) { $parts += '0' }
    if ($parts.Count -gt 4) { $parts = $parts[0..3] }
    try { return [version](($parts -join '.')) } catch { return $null }
}

function Get-InstalledHpSupportAssistant {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $hits = foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -and ($_.DisplayName -match $DisplayNamePattern)
        }
    }

    $best = $hits |
        ForEach-Object {
            [pscustomobject]@{
                DisplayName     = [string]$_.DisplayName
                DisplayVersion  = [string]$_.DisplayVersion
                Publisher       = [string]$_.Publisher
                UninstallString = [string]$_.UninstallString
                InstallLocation = [string]$_.InstallLocation
                Version         = ConvertTo-HpsaVersion -Text ([string]$_.DisplayVersion)
            }
        } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    return $best
}

function Invoke-GitHubJson {
    param([Parameter(Mandatory)][string]$Uri)
    $headers = @{
        'User-Agent' = "HpSupportAssistantUpdate/$ScriptVersion"
        'Accept'     = 'application/vnd.github+json'
    }
    $resp = Invoke-WebRequest -Uri $Uri -Headers $headers -UseBasicParsing -TimeoutSec 60
    return ($resp.Content | ConvertFrom-Json)
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
    $yaml = (Invoke-WebRequest -Uri $yamlUrl -UseBasicParsing -TimeoutSec 60).Content
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

# --- main ---
Write-HpsaLog ("HpSupportAssistantUpdate {0}" -f $ScriptVersion)
Write-HpsaLog ("User: {0} | Elevated: {1} | Force={2} Update={3}" -f `
        [Security.Principal.WindowsIdentity]::GetCurrent().Name, (Test-IsElevated), $Force, $Update)

if ($env:OS -notlike '*Windows*') {
    Write-HpsaLog 'Windows only.' 'ERROR'
    exit 1
}

$installed = Get-InstalledHpSupportAssistant
if ($installed) {
    Write-HpsaLog ("Installed: {0} {1}" -f $installed.DisplayName, $installed.DisplayVersion)
}
else {
    Write-HpsaLog 'Installed: not found'
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
    exit 1
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
    if ($needUpdate) { exit 2 } else { exit 0 }
}

if (-not $needUpdate) {
    Write-HpsaLog 'Nothing to do.'
    exit 0
}

if (-not (Test-IsElevated)) {
    Write-HpsaLog 'Elevation required for install (run as SYSTEM / Administrator).' 'ERROR'
    exit 1
}

New-Item -ItemType Directory -Path $WorkingDirectory -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$softpaqPath = Join-Path $WorkingDirectory ("sp_hpsa_$stamp.exe")
$extractDir = Join-Path $WorkingDirectory ("extract_$stamp")

try {
    Write-HpsaLog "Downloading SoftPaq to $softpaqPath"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $latest.InstallerUrl -OutFile $softpaqPath -UseBasicParsing -TimeoutSec 600

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
        exit $exitCode
    }

    Write-HpsaLog "Update finished with exit code $exitCode." 'ERROR'
    exit $exitCode
}
catch {
    Write-HpsaLog $_.Exception.Message 'ERROR'
    exit 1
}
finally {
    # Keep SoftPaq for troubleshooting on failure; remove extract tree always.
    if ($extractDir -and (Test-Path -LiteralPath $extractDir)) {
        Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
