#Requires -Version 5.1
<#
.SYNOPSIS
    Turn on the Windows Speculative Store Bypass mitigation (CVE-2018-3639).

.DESCRIPTION
    Sets the SSBD bit in FeatureSettingsOverride and makes sure
    FeatureSettingsOverrideMask honors the low mitigation bits. Other bits
    already in FeatureSettingsOverride are left in place, so a later mitigation
    such as Branch History Injection is not cleared.

    This does not install Windows updates and does not apply OEM CPU microcode.
    A scanner that still says "Updates Required" after this registry change
    needs those. The script does not restart the PC. The mitigation is not
    active until the next restart.

.PARAMETER CheckOnly
    Report the registry values and microcode hint. This is what the launcher
    sends for Scan.

.PARAMETER Remediate
    Write the registry values. If both -CheckOnly and -Remediate are passed,
    the run stays a dry run.

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
$SubKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
$SsbdBit = [uint32]8
$MaskBits = [uint32]3

function Write-SsbLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts][$Level] $Message"
}

function Test-SsbShouldExitProcess {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-SsbRun {
    param([Parameter(Mandatory)][int]$Code)
    $global:LASTEXITCODE = $Code
    if (Test-SsbShouldExitProcess) { exit $Code }
    Write-SsbLog ("Done. ResultCode={0} (PowerShell host kept open)." -f $Code)
}

function Test-SsbAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Convert-SsbDword($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        $text = $Value.Trim()
        if ($text -match '^0x[0-9a-fA-F]+$') { return [uint32]$text }
        $n = 0
        if ([uint32]::TryParse($text, [ref]$n)) { return $n }
        return $null
    }
    try { return [uint32]$Value } catch { return $null }
}

function Format-SsbDword($Value) {
    $n = Convert-SsbDword $Value
    if ($null -eq $n) {
        if ($null -eq $Value) { return 'missing' }
        return [string]$Value
    }
    return ('{0} (0x{1:X})' -f $n, $n)
}

function Format-SsbBytes($Value) {
    if ($null -eq $Value) { return 'missing' }
    if ($Value -is [byte[]]) {
        return ([BitConverter]::ToString($Value))
    }
    return [string]$Value
}

function Get-SsbValue {
    param([string]$Name)
    $base = $null
    $key = $null
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64)
        $key = $base.OpenSubKey($SubKey)
        if (-not $key) { return $null }
        return $key.GetValue($Name, $null)
    }
    finally {
        if ($key) { $key.Dispose() }
        if ($base) { $base.Dispose() }
    }
}

function Set-SsbDword {
    param([string]$Name, [uint32]$Value)
    $base = $null
    $key = $null
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64)
        $key = $base.CreateSubKey($SubKey)
        $signed = [System.BitConverter]::ToInt32([System.BitConverter]::GetBytes($Value), 0)
        $key.SetValue($Name, $signed, [Microsoft.Win32.RegistryValueKind]::DWord)
    }
    finally {
        if ($key) { $key.Dispose() }
        if ($base) { $base.Dispose() }
    }
}

function Write-SsbCpuHint {
    try {
        $cpu = Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction Stop
    }
    catch {
        Write-SsbLog 'CPU microcode: processor key could not be read.' 'WARN'
        return
    }
    $name = [string]$cpu.ProcessorNameString
    if ($name) { Write-SsbLog ("CPU: {0}" -f $name.Trim()) }
    $current = Format-SsbBytes $cpu.'Update Revision'
    $previous = Format-SsbBytes $cpu.'Previous Update Revision'
    Write-SsbLog ("Microcode revision: {0}. Previous: {1}." -f $current, $previous)
    if ($current -eq $previous -or $previous -eq 'missing') {
        Write-SsbLog 'Windows is not showing a newer microcode than the firmware shipped. OEM firmware can still leave a scanner finding open.' 'WARN'
    }
    else {
        Write-SsbLog 'Windows loaded a microcode revision that differs from the firmware revision.'
    }
}

if ($CheckOnly) { $Remediate = $false }

if (-not (Test-SsbAdmin)) {
    Write-SsbLog 'Run this from an elevated PowerShell window.' 'ERROR'
    Complete-SsbRun -Code 1
    return
}

$doWrite = [bool]$Remediate
Write-SsbLog ("SpeculativeStoreBypass {0} on {1}" -f $ScriptVersion, $env:COMPUTERNAME)
Write-SsbLog ("Mode: {0}" -f $(if ($doWrite) { 'APPLY' } else { 'SCAN' }))
Write-SsbLog 'CVE-2018-3639. Bit 8 of FeatureSettingsOverride enables SSBD. Other override bits are kept. This does not install Windows updates or OEM microcode, and it does not restart the PC.'

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    Write-SsbLog ("OS: {0} build {1}" -f $os.Caption, $os.BuildNumber)
}
catch {
    Write-SsbLog 'OS caption could not be read.' 'WARN'
}
Write-SsbCpuHint

$overrideRaw = Get-SsbValue -Name 'FeatureSettingsOverride'
$maskRaw = Get-SsbValue -Name 'FeatureSettingsOverrideMask'
$override = Convert-SsbDword $overrideRaw
$mask = Convert-SsbDword $maskRaw
if ($null -eq $override) { $override = [uint32]0 }
if ($null -eq $mask) { $mask = [uint32]0 }

$wantedOverride = $override -bor $SsbdBit
$wantedMask = $mask -bor $MaskBits
$overrideOk = (($override -band $SsbdBit) -eq $SsbdBit)
$maskOk = (($mask -band $MaskBits) -eq $MaskBits)

Write-SsbLog ("FeatureSettingsOverride: {0}" -f (Format-SsbDword $overrideRaw))
Write-SsbLog ("FeatureSettingsOverrideMask: {0}" -f (Format-SsbDword $maskRaw))

if ($overrideOk -and $maskOk) {
    Write-SsbLog 'PASS: the SSBD registry mitigation is set. It is active only after a restart. Windows updates and OEM firmware are separate.'
    Complete-SsbRun -Code 0
    return
}

if (-not $doWrite) {
    Write-SsbLog ("WOULD SET FeatureSettingsOverride {0} -> {1}" -f (Format-SsbDword $overrideRaw), (Format-SsbDword $wantedOverride))
    if (-not $maskOk) {
        Write-SsbLog ("WOULD SET FeatureSettingsOverrideMask {0} -> {1}" -f (Format-SsbDword $maskRaw), (Format-SsbDword $wantedMask))
    }
    Write-SsbLog 'SCAN: registry change pending. Re-run with -Remediate, then restart. Install quality Windows updates separately if the scanner still says updates are required.'
    Complete-SsbRun -Code 2
    return
}

if (-not $overrideOk) {
    Set-SsbDword -Name 'FeatureSettingsOverride' -Value $wantedOverride
    Write-SsbLog ("SET FeatureSettingsOverride {0} -> {1}" -f (Format-SsbDword $overrideRaw), (Format-SsbDword $wantedOverride))
}
if (-not $maskOk) {
    Set-SsbDword -Name 'FeatureSettingsOverrideMask' -Value $wantedMask
    Write-SsbLog ("SET FeatureSettingsOverrideMask {0} -> {1}" -f (Format-SsbDword $maskRaw), (Format-SsbDword $wantedMask))
}

$afterOverride = Convert-SsbDword (Get-SsbValue -Name 'FeatureSettingsOverride')
$afterMask = Convert-SsbDword (Get-SsbValue -Name 'FeatureSettingsOverrideMask')
if ($null -eq $afterOverride) { $afterOverride = [uint32]0 }
if ($null -eq $afterMask) { $afterMask = [uint32]0 }
if ((($afterOverride -band $SsbdBit) -ne $SsbdBit) -or (($afterMask -band $MaskBits) -ne $MaskBits)) {
    Write-SsbLog 'Registry write did not stick.' 'ERROR'
    Complete-SsbRun -Code 1
    return
}

Write-SsbLog 'PASS: SSBD registry mitigation is set. Restart the PC before it is active. This did not install Windows updates or OEM microcode.' 'WARN'
Complete-SsbRun -Code 0
