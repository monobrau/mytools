#Requires -Version 5.1
<#
.SYNOPSIS
    Force classic Outlook on a shared lab PC to stop keeping a local mailbox cache.

.DESCRIPTION
    A lab computer collects one OST per person. This writes the Outlook policy that
    turns Cached Exchange Mode off for new and existing profiles, and sets NoOST so
    Outlook will not create or use an offline mailbox file.

    Every local user hive is updated, plus the Default profile so the next person
    who signs in gets the same setting. Personal PST archives are not touched.

    Default is a dry run. -Apply writes the policy. -RemoveCache also deletes
    existing .ost and .nst files (Outlook is closed first). A domain GPO that
    turns Cached Exchange Mode back on will overwrite this at the next gpupdate.

.PARAMETER Apply
    Write the policy into each user hive. Without this switch the script only reports.

.PARAMETER RemoveCache
    With -Apply, delete .ost and .nst files under each profile. Requires -Apply
    so Outlook cannot rebuild the cache from the old setting.

.PARAMETER Remediate
    Same as -Apply -RemoveCache. The launcher sends this for Clean up.

.PARAMETER CheckOnly
    Dry run. Same as omitting -Apply. The launcher sends this for Scan.
    If both -CheckOnly and -Remediate are passed, the run stays a dry run.

.PARAMETER Versions
    Office versions to set. Default is 15.0 (Outlook 2013) and 16.0 (2016, 2019, 2021, Microsoft 365).

.PARAMETER NoExit
    Keep the PowerShell host open (Backstage).

.PARAMETER Exit
    Always call exit with the result code (Commands / automation).

.EXAMPLE
    .\Disable-OutlookLocalCache.ps1

.EXAMPLE
    .\Disable-OutlookLocalCache.ps1 -Apply -RemoveCache
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$RemoveCache,
    [switch]$Remediate,
    [switch]$CheckOnly,
    [string[]]$Versions = @('15.0', '16.0'),
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptVersion = '1.0.0'

function Write-OlkLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts][$Level] $Message"
}

function Test-OlkShouldExitProcess {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-OlkRun {
    param([Parameter(Mandatory)][int]$Code)
    $global:LASTEXITCODE = $Code
    if (Test-OlkShouldExitProcess) { exit $Code }
    Write-OlkLog ("Done. ResultCode={0} (PowerShell host kept open)." -f $Code)
}

function Format-OlkBytes {
    param([int64]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Test-OlkAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-OlkDword {
    param($Key, [string]$Name, [int]$Expected)
    $cur = $Key.GetValue($Name, $null)
    if ($null -eq $cur) { return $false }
    try { return ([int]$cur -eq $Expected) } catch { return $false }
}

function Set-OlkDword {
    param($Root, [string]$Path, [string]$Name, [int]$Value, [bool]$DoWrite)
    $key = $null
    try {
        $key = $Root.CreateSubKey($Path)
        if (-not $key) { throw "Could not open $Path" }
        $already = Test-OlkDword -Key $key -Name $Name -Expected $Value
        if (-not $already -and $DoWrite) {
            $key.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]::DWord)
        }
        return $already
    }
    finally {
        if ($key) { $key.Dispose() }
    }
}

function Get-OlkCacheFiles {
    param([string]$Directory)
    if ([string]::IsNullOrWhiteSpace($Directory)) { return @() }
    if (-not (Test-Path -LiteralPath $Directory)) { return @() }
    @(Get-ChildItem -LiteralPath $Directory -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '^\.(ost|nst)$' })
}

function Add-OlkCachePath {
    param($Bag, [string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if ($item -and $item.Extension -match '^\.(ost|nst)$') {
            $Bag[$item.FullName.ToLower()] = $item
        }
        return
    }
    foreach ($file in (Get-OlkCacheFiles -Directory $Path)) {
        $Bag[$file.FullName.ToLower()] = $file
    }
}

function Stop-OlkOutlook {
    $procs = @(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return }
    Write-OlkLog ("Stopping {0} classic Outlook process(es) so cache files can be deleted." -f $procs.Count)
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Dismount-OlkHive {
    param([string]$Mount)
    $reg = Join-Path $env:SystemRoot 'System32\reg.exe'
    for ($try = 1; $try -le 8; $try++) {
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $reg unload "HKU\$Mount" 2>&1 | Out-Null
        $code = $LASTEXITCODE
        $ErrorActionPreference = $prev
        if ($code -eq 0) { return $true }
        Start-Sleep -Milliseconds 400
    }
    return $false
}

function Get-OlkProfiles {
    $list = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $root = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    foreach ($item in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
        $sid = $item.PSChildName
        if ($sid -notmatch '^S-1-5-21-' -or $sid -like '*.bak') { continue }
        $path = [Environment]::ExpandEnvironmentVariables([string](Get-ItemProperty -LiteralPath $item.PSPath).ProfileImagePath)
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        $leaf = Split-Path $path -Leaf
        if ($leaf -in @('Public', 'Default', 'Default User', 'All Users')) { continue }
        $nt = Join-Path $path 'NTUSER.DAT'
        if (-not (Test-Path -LiteralPath $nt)) { continue }
        $seen[$path.ToLower()] = $true
        $list.Add([pscustomobject]@{
            Name        = $leaf
            NtUser      = $nt
            Sid         = $sid
            ProfilePath = $path
        })
    }

    $profilesDir = [Environment]::ExpandEnvironmentVariables(
        [string](Get-ItemProperty -LiteralPath $root).ProfilesDirectory)
    $defaultProfile = Join-Path $profilesDir 'Default'
    $defaultNt = Join-Path $defaultProfile 'NTUSER.DAT'
    if ((Test-Path -LiteralPath $defaultNt) -and -not $seen[$defaultProfile.ToLower()]) {
        $list.Add([pscustomobject]@{
            Name        = 'Default (new users)'
            NtUser      = $defaultNt
            Sid         = $null
            ProfilePath = $defaultProfile
        })
    }
    @($list | Sort-Object Name)
}

function Invoke-OlkProfile {
    param($Profile, [bool]$DoWrite, [string[]]$OfficeVersions)
    $mounted = $false
    $mount = $null
    $rootKey = $null
    $policyGaps = New-Object System.Collections.Generic.List[string]
    $cacheBag = @{}

    if ($Profile.Sid -and (Test-Path -LiteralPath "Registry::HKEY_USERS\$($Profile.Sid)")) {
        $mount = $Profile.Sid
    }
    else {
        $mount = 'OLK' + [guid]::NewGuid().ToString('N')
        $reg = Join-Path $env:SystemRoot 'System32\reg.exe'
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $loadOut = & $reg load "HKU\$mount" $Profile.NtUser 2>&1
        $loadCode = $LASTEXITCODE
        $ErrorActionPreference = $prev
        if ($loadCode -ne 0) {
            throw ("Could not load {0}: {1}" -f $Profile.NtUser, (($loadOut | Out-String).Trim()))
        }
        $mounted = $true
    }

    try {
        $rootKey = [Microsoft.Win32.Registry]::Users.OpenSubKey($mount, $true)
        if (-not $rootKey) { throw "Could not open HKU\$mount" }

        foreach ($ver in $OfficeVersions) {
            $policyPath = "Software\Policies\Microsoft\Office\$ver\Outlook\Cached Mode"
            $ostPath = "Software\Microsoft\Office\$ver\Outlook\OST"
            $enableOk = Set-OlkDword -Root $rootKey -Path $policyPath -Name 'Enable' -Value 0 -DoWrite $DoWrite
            $noOstOk = Set-OlkDword -Root $rootKey -Path $ostPath -Name 'NoOST' -Value 3 -DoWrite $DoWrite
            if (-not $enableOk) { $policyGaps.Add("$ver Cached Mode Enable=0") }
            if (-not $noOstOk) { $policyGaps.Add("$ver NoOST=3") }

            $outlookKey = $rootKey.OpenSubKey("Software\Microsoft\Office\$ver\Outlook")
            if ($outlookKey) {
                try {
                    $force = [string]$outlookKey.GetValue('ForceOSTPath', '')
                    Add-OlkCachePath -Bag $cacheBag -Path $force
                }
                finally { $outlookKey.Dispose() }
            }
        }

        Add-OlkCachePath -Bag $cacheBag -Path (Join-Path $Profile.ProfilePath 'AppData\Local\Microsoft\Outlook')
    }
    finally {
        if ($rootKey) { $rootKey.Dispose() }
        if ($mounted) {
            if (-not (Dismount-OlkHive -Mount $mount)) {
                Write-OlkLog ("Hive for {0} is still loaded at HKU\{1}. Reboot will release it." -f $Profile.Name, $mount) 'WARN'
            }
        }
    }

    [pscustomobject]@{
        Gaps  = @($policyGaps)
        Files = @($cacheBag.Values)
    }
}

if (-not (Test-OlkAdmin)) {
    Write-OlkLog 'Run this from an elevated PowerShell window. Other users'' hives can only be loaded by an administrator.' 'ERROR'
    Complete-OlkRun -Code 1
    return
}

if ($Remediate) {
    $Apply = $true
    $RemoveCache = $true
}
if ($CheckOnly) {
    $Apply = $false
    $RemoveCache = $false
}

if ($RemoveCache -and -not $Apply) {
    Write-OlkLog '-RemoveCache only runs with -Apply, so Outlook cannot rebuild the cache from the old setting.' 'ERROR'
    Complete-OlkRun -Code 1
    return
}

foreach ($ver in $Versions) {
    if ($ver -notmatch '^\d+\.\d+$') {
        Write-OlkLog ("Office version '{0}' is not in the form 16.0." -f $ver) 'ERROR'
        Complete-OlkRun -Code 1
        return
    }
}

$mode = if ($Apply -and $RemoveCache) { 'APPLY + DELETE CACHE' } elseif ($Apply) { 'APPLY' } else { 'SCAN' }
Write-OlkLog ("OutlookDisableCache {0} on {1}" -f $ScriptVersion, $env:COMPUTERNAME)
Write-OlkLog ("Mode: {0}" -f $mode)
Write-OlkLog ("Office versions: {0}" -f ($Versions -join ', '))
Write-OlkLog 'Policy Enable=0 turns Cached Exchange Mode off. NoOST=3 blocks creating or using an OST. PST archives are left alone.'

$profiles = @(Get-OlkProfiles)
if ($profiles.Count -eq 0) {
    Write-OlkLog 'No user profiles found.' 'WARN'
    Complete-OlkRun -Code 1
    return
}

if ($Apply -and $RemoveCache) { Stop-OlkOutlook }

$gapProfiles = 0
$failed = 0
$cacheBytes = [int64]0
$cacheFiles = 0
$deletedBytes = [int64]0
$locked = 0

foreach ($profile in $profiles) {
    Write-OlkLog ("--- {0} ---" -f $profile.Name)
    try {
        $result = Invoke-OlkProfile -Profile $profile -DoWrite ([bool]$Apply) -OfficeVersions $Versions
    }
    catch {
        $failed++
        Write-OlkLog ("FAILED {0}: {1}" -f $profile.Name, $_.Exception.Message) 'ERROR'
        continue
    }

    if ($result.Gaps.Count -gt 0) {
        $gapProfiles++
        $verb = if ($Apply) { 'SET' } else { 'WOULD SET' }
        Write-OlkLog ("{0} {1}" -f $verb, ($result.Gaps -join '; '))
    }
    else {
        Write-OlkLog 'Policy already forces online mode.'
    }

    foreach ($file in @($result.Files | Sort-Object FullName)) {
        $cacheFiles++
        $cacheBytes += [int64]$file.Length
        if ($Apply -and $RemoveCache) {
            try {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                $deletedBytes += [int64]$file.Length
                Write-OlkLog ("DELETED {0}  {1}" -f (Format-OlkBytes $file.Length), $file.FullName)
            }
            catch {
                $locked++
                Write-OlkLog ("LOCKED {0}  {1}  {2}" -f (Format-OlkBytes $file.Length), $file.FullName, $_.Exception.Message) 'WARN'
            }
        }
        else {
            $verb = if ($RemoveCache) { 'WOULD DELETE' } else { 'CACHE' }
            Write-OlkLog ("{0} {1}  {2}" -f $verb, (Format-OlkBytes $file.Length), $file.FullName)
        }
    }
}

Write-OlkLog ("Profiles: {0}. Policy gaps: {1}. Cache files: {2} ({3}). Failures: {4}." -f `
    $profiles.Count, $gapProfiles, $cacheFiles, (Format-OlkBytes $cacheBytes), $failed)
if ($Apply -and $RemoveCache) {
    Write-OlkLog ("Deleted {0}. Still locked: {1}." -f (Format-OlkBytes $deletedBytes), $locked)
}
elseif ($cacheFiles -gt 0 -and -not $RemoveCache) {
    Write-OlkLog 'Cache files are still on disk. Re-run with -Apply -RemoveCache to delete .ost and .nst files.'
}

if ($failed -gt 0 -or $locked -gt 0) {
    Write-OlkLog 'FAIL: one or more profiles or cache files could not be updated.' 'ERROR'
    Complete-OlkRun -Code 1
    return
}
if (-not $Apply) {
    if ($gapProfiles -gt 0 -or $cacheFiles -gt 0) {
        Write-OlkLog 'SCAN: changes pending. Re-run with -Apply -RemoveCache to enforce online mode and delete the cache.'
        Complete-OlkRun -Code 2
        return
    }
    Write-OlkLog 'PASS: no policy gaps and no local mailbox cache.'
    Complete-OlkRun -Code 0
    return
}
Write-OlkLog 'PASS: online mode is set for every profile that could be opened.'
Complete-OlkRun -Code 0
