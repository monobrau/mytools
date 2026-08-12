#Requires -Version 5.1
<#
.SYNOPSIS
    Patch installed .NET 6+ runtimes/SDKs to the latest security release within each major version.

.DESCRIPTION
    Detects installed Microsoft.NETCore.App, WindowsDesktop, AspNetCore, and SDK majors (6+).
    For each installed major, compares to Microsoft release-metadata and silently installs
    the latest patch for that same major only (never jumps 6->7, 8->9, etc.).

    Does not install new majors that are not already present.
    .NET Framework is out of scope (use Windows Update / separate tooling).

.PARAMETER CheckOnly
    Report status only; do not download or install.

.PARAMETER Force
    Reinstall latest patchers even when versions already match.

.PARAMETER Architecture
    win-x64 and/or win-x86. Default: architectures that appear installed (fallback win-x64).

.PARAMETER WorkingDirectory
    Download folder. Default: %ProgramData%\DotNetUpdate

.PARAMETER NoExit
    Keep the PowerShell host open (Backstage / nested orchestrator).

.PARAMETER Exit
    Always exit with a result code (Commands tab).
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Force,
    [string[]]$Architecture,
    [string]$WorkingDirectory = (Join-Path $env:ProgramData 'DotNetUpdate'),
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptVersion = '1.0.1'
$MinMajor = 6
$ReleaseMetaBase = 'https://builds.dotnet.microsoft.com/dotnet/release-metadata'

try {
    [Net.ServicePointManager]::SecurityProtocol = (
        [Net.ServicePointManager]::SecurityProtocol -bor
        [Net.SecurityProtocolType]::Tls12
    )
}
catch {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
}

function Write-DnLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts][$Level] $Message"
}

function Write-DnVerdict {
    param([string]$Status, [string]$Detail)
    Write-Host ''
    Write-Host ("======== DOTNET UPDATE STATUS: {0} ========" -f $Status)
    if ($Detail) { Write-Host $Detail }
    Write-Host '================================================'
    Write-Host ''
}

function Test-DnShouldExitProcess {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-Dn {
    param([Parameter(Mandatory)][int]$Code)
    $global:LASTEXITCODE = $Code
    try { $global:DotNetUpdateResultCode = $Code } catch { }
    if (Test-DnShouldExitProcess) { exit $Code }
    Write-DnLog ("Done. ResultCode={0} (PowerShell host kept open)." -f $Code)
}

function ConvertTo-DnVersion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $clean = ($Text -replace '[^\d\.].*$', '')
    if ([string]::IsNullOrWhiteSpace($clean)) { return $null }
    try { return [version]$clean } catch {
        $parts = @($clean -split '\.')
        while ($parts.Count -lt 2) { $parts += '0' }
        try { return [version](($parts[0..([Math]::Min(3, $parts.Count - 1))] -join '.')) } catch { return $null }
    }
}

function Get-DotNetInstallRoots {
    @(
        (Join-Path $env:ProgramFiles 'dotnet')
        (Join-Path ${env:ProgramFiles(x86)} 'dotnet')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
}

function Get-InstalledDotNetComponents {
    $items = New-Object System.Collections.Generic.List[object]
    $roots = @(Get-DotNetInstallRoots)
    if ($roots.Count -eq 0) { return @() }

    # Aka slugs must match aka.ms/dotnet/{major}.0/{slug}-{arch}.exe
    # Wrong: runtime-win-x64.exe (tiny non-EXE). Correct: dotnet-runtime-win-x64.exe
    $map = @(
        [pscustomobject]@{ Kind = 'Runtime'; Rel = 'shared\Microsoft.NETCore.App'; Aka = 'dotnet-runtime' }
        [pscustomobject]@{ Kind = 'Desktop'; Rel = 'shared\Microsoft.WindowsDesktop.App'; Aka = 'windowsdesktop-runtime' }
        [pscustomobject]@{ Kind = 'AspNetCore'; Rel = 'shared\Microsoft.AspNetCore.App'; Aka = 'aspnetcore-runtime' }
        [pscustomobject]@{ Kind = 'SDK'; Rel = 'sdk'; Aka = 'dotnet-sdk' }
    )

    foreach ($root in $roots) {
        $arch = if ($root -match ' \(x86\)|Program Files \(x86\)') { 'win-x86' } else { 'win-x64' }
        foreach ($m in $map) {
            $dir = Join-Path $root $m.Rel
            if (-not (Test-Path -LiteralPath $dir)) { continue }
            Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $ver = ConvertTo-DnVersion $_.Name
                if (-not $ver) { return }
                if ($ver.Major -lt $MinMajor) { return }
                $items.Add([pscustomobject]@{
                        Kind         = $m.Kind
                        AkaSlug      = $m.Aka
                        Version      = $_.Name
                        VersionObj   = $ver
                        Major        = [int]$ver.Major
                        Architecture = $arch
                        Path         = $_.FullName
                    }) | Out-Null
            }
        }
    }

    # Prefer highest patch per Kind/Major/Arch
    $items | Group-Object Kind, Major, Architecture | ForEach-Object {
        $_.Group | Sort-Object VersionObj -Descending | Select-Object -First 1
    }
}

function Get-DotNetReleaseMetadata {
    param([Parameter(Mandatory)][int]$Major)
    $uri = "{0}/{1}.0/releases.json" -f $ReleaseMetaBase, $Major
    Write-DnLog ("Fetching release metadata: {0}" -f $uri)
    return Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 60
}

function Get-AkaMsDownloadUrl {
    param(
        [Parameter(Mandatory)][int]$Major,
        [Parameter(Mandatory)][string]$AkaSlug,
        [Parameter(Mandatory)][string]$Architecture
    )
    # https://aka.ms/dotnet/8.0/dotnet-runtime-win-x64.exe
    return ("https://aka.ms/dotnet/{0}.0/{1}-{2}.exe" -f $Major, $AkaSlug, $Architecture)
}

function Resolve-DotNetInstallerUrl {
    param(
        [Parameter(Mandatory)]$Meta,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$TargetVersion,
        [Parameter(Mandatory)][string]$Architecture,
        [Parameter(Mandatory)][int]$Major,
        [Parameter(Mandatory)][string]$AkaSlug
    )
    # Prefer version-pinned builds.dotnet.microsoft.com URLs from release-metadata.
    try {
        $files = @()
        if ($Kind -eq 'SDK') {
            $rel = @($Meta.releases) | Where-Object { $_.sdk -and $_.sdk.version -eq $TargetVersion } | Select-Object -First 1
            if ($rel) { $files = @($rel.sdk.files) }
        }
        else {
            $rel = @($Meta.releases) | Where-Object { $_.'release-version' -eq $TargetVersion } | Select-Object -First 1
            if ($rel) {
                switch ($Kind) {
                    'Runtime' { $files = @($rel.runtime.files) }
                    'Desktop' { $files = @($rel.windowsdesktop.files) }
                    'AspNetCore' { $files = @($rel.'aspnetcore-runtime'.files) }
                }
            }
        }
        $exe = @($files) | Where-Object {
                $_.rid -eq $Architecture -and
                $_.url -and
                ($_.name -like '*.exe')
            } | Select-Object -First 1
        if ($exe -and $exe.url) { return [string]$exe.url }
    }
    catch { }
    return (Get-AkaMsDownloadUrl -Major $Major -AkaSlug $AkaSlug -Architecture $Architecture)
}

function Install-DotNetPackage {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$DestPath
    )
    Write-DnLog ("Downloading {0}" -f $Url)
    $wc = New-Object Net.WebClient
    $wc.Headers.Add('User-Agent', "DotNetUpdate/$ScriptVersion")
    $wc.DownloadFile($Url, $DestPath)
    $len = (Get-Item -LiteralPath $DestPath).Length
    $hdr = [System.IO.File]::ReadAllBytes($DestPath)
    $isMz = ($hdr.Length -ge 2 -and $hdr[0] -eq 0x4D -and $hdr[1] -eq 0x5A)
    if ($len -lt 1MB -or -not $isMz) {
        throw ("Download invalid (bytes={0} MZ={1}) - URL may be wrong: {2}" -f $len, $isMz, $Url)
    }
    Write-DnLog ("Downloaded {0:N0} bytes -> {1}" -f $len, $DestPath)
    Write-DnLog 'Installing silently (/install /quiet /norestart)...'
    $p = Start-Process -FilePath $DestPath -ArgumentList '/install', '/quiet', '/norestart' -PassThru -Wait -WindowStyle Hidden
    Write-DnLog ("Installer exit code: {0}" -f $p.ExitCode)
    # 0 = success, 3010 = success reboot required
    return [int]$p.ExitCode
}

# --- main ---
Write-DnLog ("DotNetUpdate {0}" -f $ScriptVersion)
Write-DnLog ("User: {0} | CheckOnly={1} Force={2}" -f `
        [Security.Principal.WindowsIdentity]::GetCurrent().Name, $CheckOnly, $Force)
Write-DnLog 'Policy: same-major security patches only for .NET 6+ (Runtime / Desktop / ASP.NET / SDK). Never jumps majors.'

$installed = @(Get-InstalledDotNetComponents)
if ($installed.Count -eq 0) {
    Write-DnVerdict -Status 'SKIPPED - NO .NET 6+ DETECTED' -Detail 'No Microsoft.NETCore / Desktop / AspNetCore / SDK majors >= 6 found under Program Files\dotnet.'
    Complete-Dn -Code 0
    return
}

if ($Architecture -and $Architecture.Count -gt 0) {
    $wantArch = @($Architecture | ForEach-Object { $_.ToLowerInvariant() })
    $installed = @($installed | Where-Object { $wantArch -contains $_.Architecture })
}

Write-DnLog ("Detected {0} component(s):" -f $installed.Count)
foreach ($c in ($installed | Sort-Object Major, Kind, Architecture)) {
    Write-DnLog ("  {0,-12} major={1} arch={2} installed={3}" -f $c.Kind, $c.Major, $c.Architecture, $c.Version)
}

$metaCache = @{}
$plan = New-Object System.Collections.Generic.List[object]
$unknown = 0

foreach ($c in $installed) {
    if (-not $metaCache.ContainsKey($c.Major)) {
        try {
            $metaCache[$c.Major] = Get-DotNetReleaseMetadata -Major $c.Major
        }
        catch {
            Write-DnLog ("Failed metadata for {0}.0: {1}" -f $c.Major, $_.Exception.Message) 'ERROR'
            $metaCache[$c.Major] = $null
            $unknown++
            continue
        }
    }
    $meta = $metaCache[$c.Major]
    if (-not $meta) { continue }

    $targetText = if ($c.Kind -eq 'SDK') { [string]$meta.'latest-sdk' } else { [string]$meta.'latest-runtime' }
    $target = ConvertTo-DnVersion $targetText
    $local = $c.VersionObj
    $needs = $false
    if ($Force) { $needs = $true }
    elseif ($local -and $target -and ($local -lt $target)) { $needs = $true }
    elseif (-not $target) { $unknown++; continue }

    $url = Resolve-DotNetInstallerUrl -Meta $meta -Kind $c.Kind -TargetVersion $targetText `
        -Architecture $c.Architecture -Major $c.Major -AkaSlug $c.AkaSlug
    $plan.Add([pscustomobject]@{
            Kind         = $c.Kind
            Major        = $c.Major
            Architecture = $c.Architecture
            Installed    = $c.Version
            Target       = $targetText
            NeedsUpdate  = $needs
            AkaSlug      = $c.AkaSlug
            Url          = $url
        }) | Out-Null
}

Write-Host ''
Write-DnLog '===== ASSESSMENT ====='
foreach ($p in $plan) {
    $state = if ($p.NeedsUpdate) { 'UPDATE_AVAILABLE' } else { 'UP_TO_DATE' }
    Write-DnLog ("{0,-12} {1}.x {2,-8} local={3,-12} latest={4,-12} {5}" -f `
            $p.Kind, $p.Major, $p.Architecture, $p.Installed, $p.Target, $state)
}

$toUpdate = @($plan | Where-Object { $_.NeedsUpdate })
if ($toUpdate.Count -eq 0 -and $unknown -eq 0) {
    Write-DnVerdict -Status 'UP TO DATE - NO UPDATES NEEDED' `
        -Detail 'All installed .NET 6+ components are on/above the latest patch for their major.'
    Complete-Dn -Code 0
    return
}

if ($CheckOnly) {
    if ($toUpdate.Count -gt 0) {
        Write-DnVerdict -Status 'UPDATE AVAILABLE - UPDATES NEEDED' `
            -Detail ("{0} component(s) behind latest same-major security release." -f $toUpdate.Count)
        Complete-Dn -Code 2
        return
    }
    Write-DnVerdict -Status 'UNKNOWN - COULD NOT VERIFY' -Detail 'One or more majors failed release-metadata lookup.'
    Complete-Dn -Code 1
    return
}

if (-not (Test-Path -LiteralPath $WorkingDirectory)) {
    New-Item -ItemType Directory -Path $WorkingDirectory -Force | Out-Null
}

$failures = 0
$updated = 0
foreach ($p in $toUpdate) {
    Write-DnLog ("--- Updating {0} {1}.x ({2}) {3} -> {4} ---" -f $p.Kind, $p.Major, $p.Architecture, $p.Installed, $p.Target)
    $file = Join-Path $WorkingDirectory ("{0}-{1}.0-{2}.exe" -f $p.AkaSlug, $p.Major, $p.Architecture)
    try {
        $code = Install-DotNetPackage -Url $p.Url -DestPath $file
        if ($code -eq 0 -or $code -eq 3010) {
            $updated++
            if ($code -eq 3010) {
                Write-DnLog 'Installer requested reboot (3010) - patch applied; reboot when convenient.' 'WARN'
            }
        }
        else {
            Write-DnLog ("Installer failed with exit {0}" -f $code) 'ERROR'
            $failures++
        }
    }
    catch {
        Write-DnLog $_.Exception.Message 'ERROR'
        $failures++
    }
}

# Re-scan
$after = @(Get-InstalledDotNetComponents)
$stillBehind = 0
foreach ($p in $toUpdate) {
    $now = @($after | Where-Object {
            $_.Kind -eq $p.Kind -and $_.Major -eq $p.Major -and $_.Architecture -eq $p.Architecture
        }) | Select-Object -First 1
    $target = ConvertTo-DnVersion $p.Target
    if ($now -and $target -and ($now.VersionObj -ge $target)) {
        Write-DnLog ("OK {0} {1}.x {2}: now {3}" -f $p.Kind, $p.Major, $p.Architecture, $now.Version)
    }
    else {
        $cur = if ($now) { $now.Version } else { '(missing)' }
        Write-DnLog ("STILL BEHIND {0} {1}.x {2}: {3} (target {4})" -f $p.Kind, $p.Major, $p.Architecture, $cur, $p.Target) 'WARN'
        $stillBehind++
    }
}

if ($stillBehind -gt 0) {
    if ($failures -gt 0) {
        Write-DnVerdict -Status 'ERROR - ONE OR MORE INSTALLS FAILED' `
            -Detail ("updated={0} failures={1} stillBehind={2}" -f $updated, $failures, $stillBehind)
        Complete-Dn -Code 1
        return
    }
    Write-DnVerdict -Status 'UPDATE AVAILABLE - STILL BEHIND AFTER ATTEMPT' `
        -Detail ("updated={0} stillBehind={1}. Reboot or re-run -CheckOnly." -f $updated, $stillBehind)
    Complete-Dn -Code 2
    return
}

# Host is current: do not ERROR on download attempts that Desktop (or another package) already covered.
if ($failures -gt 0) {
    Write-DnLog ("Note: {0} install attempt(s) failed, but all targets are current after re-scan." -f $failures) 'WARN'
}
Write-DnVerdict -Status 'UPDATED - ON LATEST SAME-MAJOR PATCHES' `
    -Detail ("Successfully patched {0} component(s)." -f $updated)
Complete-Dn -Code 0
return
