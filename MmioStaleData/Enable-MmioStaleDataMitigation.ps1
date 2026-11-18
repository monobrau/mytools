#Requires -Version 5.1
<#
.SYNOPSIS
    Set the Windows registry mitigation for Intel MMIO stale data.

.DESCRIPTION
    CVE-2022-21123, CVE-2022-21125, CVE-2022-21127, and CVE-2022-21166 are
    processor flaws. Nothing is installed. The scanner looks for
    FeatureSettingsOverride and FeatureSettingsOverrideMask under
    Session Manager\Memory Management.

    Intel, keys missing, Hyper-Threading on:  Override 72,      Mask 3.
    Intel, keys missing, Hyper-Threading off: Override 8264,    Mask 3.
    -IncludeBhi adds CVE-2022-0001:           Override 8388680 or 8396872.

    8264 and 8396872 are the Microsoft values that keep Hyper-Threading
    disabled. This script uses them only when logical processors are not
    greater than cores. It does not turn Hyper-Threading off on a CPU
    that still has it.

    AMD is reported as a false positive and is not changed.
    Override values 1, 2, or 3 (the disable bits) are not changed.
    Any other existing override is not replaced.
    72, 8264, 8388680, and 8396872 with mask 3 are already applied.

    The script does not reboot. The keys do nothing until the next restart.
    OEM microcode is separate.

.PARAMETER CheckOnly
    Report only. This is what the launcher sends for Scan.

.PARAMETER Remediate
    Write the registry values when the rules above allow it.

.PARAMETER IncludeBhi
    Also set the Branch History Injection bit (CVE-2022-0001).
    Off by default.

.PARAMETER NoExit
    Keep the PowerShell host open (Backstage).

.PARAMETER Exit
    Always call exit with the result code (Commands / automation).
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Remediate,
    [switch]$IncludeBhi,
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptVersion = '1.0.0'
$SubKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
$OverrideWithHt = [uint32]72
$OverrideWithoutHt = [uint32]8264
$OverrideWithHtAndBhi = [uint32]8388680
$OverrideWithoutHtAndBhi = [uint32]8396872
$MaskValue = [uint32]3

function Write-MmioLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts][$Level] $Message"
}

function Write-MmioVerdict {
    param(
        [Parameter(Mandatory)][string]$Status,
        [string]$Detail
    )
    Write-Host ''
    Write-Host ('======== MMIO STALE DATA: {0} ========' -f $Status)
    if ($Detail) { Write-Host $Detail }
    Write-Host '================================================'
    Write-Host ''
}

function Test-MmioShouldExitProcess {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-MmioRun {
    param([Parameter(Mandatory)][int]$Code)
    $global:LASTEXITCODE = $Code
    if (Test-MmioShouldExitProcess) { exit $Code }
    Write-MmioLog ("Done. ResultCode={0} (PowerShell host kept open)." -f $Code)
}

function Test-MmioAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Convert-MmioDword($Value) {
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

function Format-MmioDword($Value) {
    $n = Convert-MmioDword $Value
    if ($null -eq $n) {
        if ($null -eq $Value) { return 'missing' }
        return [string]$Value
    }
    return ('{0} (0x{1:X})' -f $n, $n)
}

function Get-MmioValue {
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

function Set-MmioDword {
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

function Get-MmioTargetOverride {
    param([bool]$HyperThreadingOn, [bool]$WithBhi)
    if ($HyperThreadingOn) {
        if ($WithBhi) { return $OverrideWithHtAndBhi }
        return $OverrideWithHt
    }
    if ($WithBhi) { return $OverrideWithoutHtAndBhi }
    return $OverrideWithoutHt
}

if ($CheckOnly) { $Remediate = $false }

if (-not (Test-MmioAdmin)) {
    Write-MmioLog 'Run this from an elevated PowerShell window.' 'ERROR'
    Complete-MmioRun -Code 1
    return
}

$doWrite = [bool]$Remediate
Write-MmioLog ("MmioStaleData {0} on {1}" -f $ScriptVersion, $env:COMPUTERNAME)
Write-MmioLog ("Mode: {0}. IncludeBhi={1}" -f $(if ($doWrite) { 'APPLY' } else { 'SCAN' }), $IncludeBhi.IsPresent)
Write-MmioLog 'CVE-2022-21123 / 21125 / 21127 / 21166. Registry only. No installer. No reboot.'

$cores = 0
$logical = 0
$vendors = New-Object System.Collections.Generic.List[string]
$cpuNames = New-Object System.Collections.Generic.List[string]
try {
    foreach ($cpu in @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)) {
        $cores += [int]$cpu.NumberOfCores
        $logical += [int]$cpu.NumberOfLogicalProcessors
        $vendor = [string]$cpu.Manufacturer
        $cpuName = [string]$cpu.Name
        if ($vendor) { [void]$vendors.Add($vendor.Trim()) }
        if ($cpuName) { [void]$cpuNames.Add($cpuName.Trim()) }
    }
}
catch {
    Write-MmioLog 'Win32_Processor could not be read.' 'ERROR'
    Complete-MmioRun -Code 1
    return
}

$vendorText = (@($vendors | Select-Object -Unique) -join ', ')
$cpuText = (@($cpuNames | Select-Object -Unique) -join ' | ')
$htOn = ($logical -gt $cores)
Write-MmioLog ("CPU: {0}" -f $cpuText)
Write-MmioLog ("Vendor: {0}. Cores={1}. Logical={2}. HyperThreading={3}" -f $vendorText, $cores, $logical, $(if ($htOn) { 'on' } else { 'off' }))

$manufacturer = ''
$model = ''
$vm = $false
try {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $manufacturer = [string]$cs.Manufacturer
    $model = [string]$cs.Model
    if ($cs.HypervisorPresent) { $vm = $true }
    if ("$manufacturer $model" -match 'VMware|Virtual|KVM|Xen|QEMU|Hyper-V') { $vm = $true }
    Write-MmioLog ("Computer: {0} {1}. VM={2}" -f $manufacturer.Trim(), $model.Trim(), $vm)
}
catch {
    Write-MmioLog 'Win32_ComputerSystem could not be read.' 'WARN'
}

$biosVersion = ''
$biosDate = ''
try {
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
    $biosVersion = [string]$bios.SMBIOSBIOSVersion
    if ($bios.ReleaseDate) {
        $biosDate = ([Management.ManagementDateTimeConverter]::ToDateTime([string]$bios.ReleaseDate)).ToString('yyyy-MM-dd')
    }
    Write-MmioLog ("BIOS: {0} {1}" -f $biosVersion, $biosDate)
    if ($biosDate -and ([datetime]$biosDate) -lt [datetime]'2022-06-14') {
        Write-MmioLog 'BIOS date is before the June 2022 MMIO advisory. The OS keys still need current CPU microcode. Check the PC maker firmware.' 'WARN'
    }
}
catch {
    Write-MmioLog 'Win32_BIOS could not be read.' 'WARN'
}

if ($vm) {
    Write-MmioLog 'This looks like a virtual machine. The hypervisor host also needs current microcode and its own mitigations, or the guest can stay flagged.' 'WARN'
}

$intel = $false
$amd = $false
foreach ($v in $vendors) {
    if ($v -match 'Intel|GenuineIntel') { $intel = $true }
    if ($v -match 'AMD|AuthenticAMD') { $amd = $true }
}
if (-not $intel -and -not $amd -and $cpuText -match 'Intel') { $intel = $true }
if (-not $intel -and -not $amd -and $cpuText -match 'AMD') { $amd = $true }

$overrideRaw = Get-MmioValue -Name 'FeatureSettingsOverride'
$maskRaw = Get-MmioValue -Name 'FeatureSettingsOverrideMask'
$override = Convert-MmioDword $overrideRaw
$mask = Convert-MmioDword $maskRaw
Write-MmioLog ("FeatureSettingsOverride: {0}" -f (Format-MmioDword $overrideRaw))
Write-MmioLog ("FeatureSettingsOverrideMask: {0}" -f (Format-MmioDword $maskRaw))

$priorOverride = Format-MmioDword $overrideRaw
$priorMask = Format-MmioDword $maskRaw
$note = @(
    ("Host: {0}" -f $env:COMPUTERNAME)
    ("CPU: {0}" -f $cpuText)
    ("Hyper-Threading: {0} (cores {1}, logical {2})" -f $(if ($htOn) { 'on' } else { 'off' }), $cores, $logical)
    ("BIOS: {0} {1}" -f $biosVersion, $biosDate)
    ("Prior FeatureSettingsOverride: {0}" -f $priorOverride)
    ("Prior FeatureSettingsOverrideMask: {0}" -f $priorMask)
)

function Write-MmioNote {
    param([string]$ResultLine)
    Write-Host '--- ticket note ---'
    foreach ($line in $note) { Write-Host $line }
    Write-Host $ResultLine
    Write-Host 'Reboot was not performed by this script.'
    Write-Host '--- end ---'
}

if ($amd -and -not $intel) {
    Write-MmioVerdict -Status 'FALSE POSITIVE' -Detail 'AMD CPU. MMIO stale data is an Intel finding. No registry change.'
    Write-MmioNote 'Result: false positive. No change.'
    Complete-MmioRun -Code 0
    return
}

if (-not $intel) {
    Write-MmioVerdict -Status 'NOT INTEL' -Detail 'CPU is not Intel. No registry change.'
    Write-MmioNote 'Result: not an Intel CPU. No change.'
    Complete-MmioRun -Code 1
    return
}

$accepted = @(
    $OverrideWithHt
    $OverrideWithoutHt
    $OverrideWithHtAndBhi
    $OverrideWithoutHtAndBhi
)
$maskOk = ($null -ne $mask -and (($mask -band $MaskValue) -eq $MaskValue))
$acceptedOverride = ($null -ne $override -and ($accepted -contains $override))
if ($acceptedOverride -and $maskOk) {
    $extra = ''
    if ($htOn -and ($override -eq $OverrideWithoutHt -or $override -eq $OverrideWithoutHtAndBhi)) {
        $extra = ' This value disables Hyper-Threading in Windows after the next restart.'
    }
    Write-MmioVerdict -Status 'ALREADY APPLIED' -Detail ("Override {0} with mask covering 3 is already set.{1} It is active only after a restart." -f $override, $extra)
    Write-MmioNote ("Result: already applied ({0} / mask {1})." -f $override, $mask)
    Complete-MmioRun -Code 0
    return
}

if ($null -ne $override -and (($override -band $MaskValue) -ne 0)) {
    Write-MmioVerdict -Status 'LEFT UNCHANGED' -Detail ("Override {0} has a disable bit set (bit 0 Spectre v2, bit 1 Meltdown). Find out why before changing it." -f $override)
    Write-MmioNote 'Result: disable bits are set. No change.'
    Complete-MmioRun -Code 1
    return
}

if ($null -ne $override -and -not $acceptedOverride) {
    Write-MmioVerdict -Status 'LEFT UNCHANGED' -Detail ("Override {0} is already set and is not 72, 8264, 8388680, or 8396872. It was not replaced." -f $override)
    Write-MmioNote 'Result: existing override was left in place.'
    Complete-MmioRun -Code 1
    return
}

if ($acceptedOverride) {
    $target = $override
}
else {
    $target = Get-MmioTargetOverride -HyperThreadingOn $htOn -WithBhi $IncludeBhi.IsPresent
}
$targetText = ("FeatureSettingsOverride {0} and FeatureSettingsOverrideMask {1}" -f $target, $MaskValue)
if (-not $acceptedOverride -and $htOn) {
    Write-MmioLog 'Hyper-Threading is on, so 8264 and 8396872 are not used. Those values disable Hyper-Threading.'
}
elseif (-not $acceptedOverride) {
    Write-MmioLog 'Hyper-Threading is off. The value used here is the Microsoft setting for that state. It does not turn Hyper-Threading back on.'
}

if (-not $doWrite) {
    Write-MmioVerdict -Status 'WOULD SET' -Detail ("Would set {0}. Re-run with -Remediate, then restart. Nothing was written." -f $targetText)
    Write-MmioNote ("Result: would set {0} / {1}. Not written." -f $target, $MaskValue)
    Complete-MmioRun -Code 2
    return
}

if (-not $acceptedOverride) {
    Set-MmioDword -Name 'FeatureSettingsOverride' -Value $target
    Write-MmioLog ("SET FeatureSettingsOverride {0} -> {1}" -f $priorOverride, $target)
}
if (-not $maskOk) {
    Set-MmioDword -Name 'FeatureSettingsOverrideMask' -Value $MaskValue
    Write-MmioLog ("SET FeatureSettingsOverrideMask {0} -> {1}" -f $priorMask, $MaskValue)
}

$afterOverride = Convert-MmioDword (Get-MmioValue -Name 'FeatureSettingsOverride')
$afterMask = Convert-MmioDword (Get-MmioValue -Name 'FeatureSettingsOverrideMask')
if ($afterOverride -ne $target -or $null -eq $afterMask -or (($afterMask -band $MaskValue) -ne $MaskValue)) {
    Write-MmioLog 'Registry write did not stick.' 'ERROR'
    Complete-MmioRun -Code 1
    return
}

Write-MmioVerdict -Status 'SET' -Detail ("Set {0}. Restart the PC before it is active. OEM microcode is separate." -f $targetText)
Write-MmioNote ("Result: set {0} / {1}. Reboot still required." -f $target, $MaskValue)
Complete-MmioRun -Code 0
