#Requires -Version 5.1
<#
.SYNOPSIS
    Enable the strict WinVerifyTrust Authenticode padding check (CVE-2013-3900).

.DESCRIPTION
    Windows already contains this check. It stays off until EnableCertPaddingCheck
    is set. A 64-bit PC needs the value in both the native registry view and the
    32-bit view. A restart is required before the check actually changes signature
    validation. The script does not restart the PC.

    Signed installers that put extra data in the signature are treated as unsigned
    after the restart.

    Default is a dry run. -Remediate writes DWORD 1 where the value is missing.
    An existing string "1" is already compliant and is left as-is.

.PARAMETER CheckOnly
    Report the registry values. This is what the launcher sends for Scan.

.PARAMETER Remediate
    Write the missing values. If both -CheckOnly and -Remediate are passed, the
    run stays a dry run.

.PARAMETER NoExit
    Keep the PowerShell host open (Backstage).

.PARAMETER Exit
    Always call exit with the result code (Commands / automation).
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Remediate,
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptVersion = '1.0.0'
$SubKey = 'Software\Microsoft\Cryptography\Wintrust\Config'
$ValueName = 'EnableCertPaddingCheck'

function Write-WvtLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts][$Level] $Message"
}

function Test-WvtShouldExitProcess {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-WvtRun {
    param([Parameter(Mandatory)][int]$Code)
    $global:LASTEXITCODE = $Code
    if (Test-WvtShouldExitProcess) { exit $Code }
    Write-WvtLog ("Done. ResultCode={0} (PowerShell host kept open)." -f $Code)
}

function Test-WvtAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WvtViews {
    if ([Environment]::Is64BitOperatingSystem) {
        return @(
            [pscustomobject]@{ Label = '64-bit'; View = [Microsoft.Win32.RegistryView]::Registry64 }
            [pscustomobject]@{ Label = '32-bit'; View = [Microsoft.Win32.RegistryView]::Registry32 }
        )
    }
    return @(
        [pscustomobject]@{ Label = '32-bit'; View = [Microsoft.Win32.RegistryView]::Registry32 }
    )
}

function Format-WvtValue($Value) {
    if ($null -eq $Value) { return 'missing' }
    $kind = $Value.GetType().Name
    return ("{0} ({1})" -f $Value, $kind)
}

function Test-WvtEnabled($Value) {
    if ($null -eq $Value) { return $false }
    if ($Value -is [string]) { return $Value.Trim() -eq '1' }
    try { return ([int64]$Value -eq 1) } catch { return $false }
}

function Get-WvtValue {
    param($View)
    $base = $null
    $key = $null
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $View)
        $key = $base.OpenSubKey($SubKey)
        if (-not $key) { return $null }
        return $key.GetValue($ValueName, $null)
    }
    finally {
        if ($key) { $key.Dispose() }
        if ($base) { $base.Dispose() }
    }
}

function Set-WvtDword {
    param($View)
    $base = $null
    $key = $null
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $View)
        $key = $base.CreateSubKey($SubKey)
        $key.SetValue($ValueName, 1, [Microsoft.Win32.RegistryValueKind]::DWord)
    }
    finally {
        if ($key) { $key.Dispose() }
        if ($base) { $base.Dispose() }
    }
}

if ($CheckOnly) { $Remediate = $false }

if (-not (Test-WvtAdmin)) {
    Write-WvtLog 'Run this from an elevated PowerShell window.' 'ERROR'
    Complete-WvtRun -Code 1
    return
}

$doWrite = [bool]$Remediate
Write-WvtLog ("WinVerifyTrustPadding {0} on {1}" -f $ScriptVersion, $env:COMPUTERNAME)
Write-WvtLog ("Mode: {0}" -f $(if ($doWrite) { 'APPLY' } else { 'SCAN' }))
Write-WvtLog 'CVE-2013-3900. EnableCertPaddingCheck=1 turns on strict Authenticode padding checks. A restart is required before validation changes. This script does not restart the PC.'

$gaps = 0
foreach ($entry in (Get-WvtViews)) {
    $current = Get-WvtValue -View $entry.View
    $ok = Test-WvtEnabled $current
    if ($ok) {
        Write-WvtLog ("{0} view already set: {1}" -f $entry.Label, (Format-WvtValue $current))
        continue
    }
    $gaps++
    if ($doWrite) {
        Set-WvtDword -View $entry.View
        $after = Get-WvtValue -View $entry.View
        if (-not (Test-WvtEnabled $after)) {
            Write-WvtLog ("{0} view write did not stick. Now: {1}" -f $entry.Label, (Format-WvtValue $after)) 'ERROR'
            Complete-WvtRun -Code 1
            return
        }
        Write-WvtLog ("SET {0} view: {1} -> {2}" -f $entry.Label, (Format-WvtValue $current), (Format-WvtValue $after))
    }
    else {
        Write-WvtLog ("WOULD SET {0} view: {1} -> DWord 1" -f $entry.Label, (Format-WvtValue $current))
    }
}

if ($gaps -eq 0) {
    Write-WvtLog 'PASS: strict Authenticode padding check is enabled in every required registry view.'
    Complete-WvtRun -Code 0
    return
}
if (-not $doWrite) {
    Write-WvtLog 'SCAN: registry change pending. Re-run with -Remediate. Restart afterwards so the check takes effect.'
    Complete-WvtRun -Code 2
    return
}
Write-WvtLog 'PASS: registry values are set. Restart the PC before the stricter signature check is in effect.' 'WARN'
Complete-WvtRun -Code 0
