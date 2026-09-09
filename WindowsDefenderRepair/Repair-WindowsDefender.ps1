#Requires -Version 5.1
<#
.SYNOPSIS
    Re-enable Windows Defender real-time protection and start the Defender services.

.DESCRIPTION
    Backstage / elevated only. Set-MpPreference and Defender CIM often fail in
    ScreenConnect Commands; paste the launcher Backstage one-liner instead.

    -CheckOnly reports WinDefend / WdNisSvc / Sense, RTP, and tamper
    protection. Repair covers disabled services, policy/preference Disable*
    keys, ForceDefenderPassiveMode, WSC-related services, then Set-MpPreference
    after WinDefend is Running (retry once if RTP stays off).

.PARAMETER CheckOnly
    Report service state, real-time protection, and tamper protection only.

.PARAMETER ResetPlatform
    Nuclear option: run MpCmdRun.exe -ResetPlatform from the current Defender
    Platform folder, then apply the real-time protection repair.

.PARAMETER Exit
    Call exit with a status code. Omit in Backstage.
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$ResetPlatform,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$script:ExitCode = 0

$script:PolWd = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
$script:PolRtp = Join-Path $script:PolWd 'Real-Time Protection'
$script:PolAtp = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection'
$script:PrefWd = 'HKLM:\SOFTWARE\Microsoft\Windows Defender'
$script:PrefRtp = Join-Path $script:PrefWd 'Real-Time Protection'
$script:PrefAtp = 'HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection'

function Write-Line([string]$Message) {
    Write-Host $Message
    try { [Console]::Out.Flush() } catch { }
}

function Write-Section([string]$Message) {
    Write-Line "=== $Message ==="
}

function Get-MpCmdRunPath {
    $root = Join-Path $env:ProgramData 'Microsoft\Windows Defender\Platform'
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    $dirs = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
        Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending)
    foreach ($dir in $dirs) {
        $exe = Join-Path $dir.FullName 'MpCmdRun.exe'
        if (Test-Path -LiteralPath $exe) { return $exe }
    }
    return $null
}

function Get-DwordValue([string]$Path, [string]$Name) {
    try {
        $item = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
        $val = $item.$Name
        if ($null -eq $val) { return '(missing)' }
        return [string]$val
    } catch {
        return '(missing)'
    }
}

function Set-DefenderDword([string]$Path, [string]$Name, [int]$Value) {
    $parent = Split-Path $Path -Parent
    $leaf = Split-Path $Path -Leaf
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -Path $parent -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        if ($parent) {
            New-Item -Path $parent -Name $leaf -Force | Out-Null
        } else {
            New-Item -Path $Path -Force | Out-Null
        }
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType DWORD -Force | Out-Null
}

function Write-ServiceLine([string]$Name) {
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Line ("{0}: (not installed)" -f $Name)
        return $null
    }
    Write-Line ("{0}: {1} ({2})" -f $Name, $svc.Status, $svc.StartType)
    return $svc
}

function Write-WscProducts {
    $avs = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue)
    if ($avs.Count -eq 0) {
        Write-Line 'AntiVirusProduct: (none)'
        return @()
    }
    foreach ($av in $avs) {
        Write-Line ("AntiVirusProduct: {0}" -f $av.displayName)
    }
    return $avs
}

function Write-DefenderHealth {
    Write-Section 'Defender health'
    Write-Line ("ComputerName: {0}" -f $env:COMPUTERNAME)
    Write-Line ("Action: {0}" -f $(if ($CheckOnly) { 'CheckOnly' } else { 'Verify' }))

    $wd = Write-ServiceLine 'WinDefend'
    $nis = Write-ServiceLine 'WdNisSvc'
    [void](Write-ServiceLine 'Sense')
    if (-not $CheckOnly) {
        [void](Write-ServiceLine 'MdCoreSvc')
        [void](Write-ServiceLine 'SecurityHealthService')
        [void](Write-ServiceLine 'wscsvc')
    }

    $st = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($st) {
        Write-Line ("RealTimeProtectionEnabled: {0}" -f $st.RealTimeProtectionEnabled)
        Write-Line ("AMServiceEnabled: {0}" -f $st.AMServiceEnabled)
        Write-Line ("AntivirusEnabled: {0}" -f $st.AntivirusEnabled)
        Write-Line ("IsTamperProtected: {0}" -f $st.IsTamperProtected)
        Write-Line ("AMRunningMode: {0}" -f $st.AMRunningMode)
    } else {
        Write-Line 'RealTimeProtectionEnabled: (empty)'
        Write-Line 'AMServiceEnabled: (empty)'
        Write-Line 'AntivirusEnabled: (empty)'
        Write-Line 'IsTamperProtected: (empty)'
        Write-Line 'AMRunningMode: (empty)'
        Write-Line 'Get-MpComputerStatus: (empty) — Defender CIM may still be down.'
    }

    $pref = Get-MpPreference -ErrorAction SilentlyContinue
    if ($pref) {
        Write-Line ("DisableRealtimeMonitoring: {0}" -f $pref.DisableRealtimeMonitoring)
        Write-Line ("DisableIOAVProtection: {0}" -f $pref.DisableIOAVProtection)
        Write-Line ("DisableBehaviorMonitoring: {0}" -f $pref.DisableBehaviorMonitoring)
    }

    if (-not $CheckOnly) {
        Write-Line ("ForceDefenderPassiveMode (policy ATP): {0}" -f (Get-DwordValue $script:PolAtp 'ForceDefenderPassiveMode'))
        Write-Line ("ForceDefenderPassiveMode (HKLM Defender): {0}" -f (Get-DwordValue $script:PrefWd 'ForceDefenderPassiveMode'))
    }

    $ok = $true
    if (-not $wd -or $wd.Status -ne 'Running') {
        Write-Line 'Result: WinDefend is not Running.'
        $ok = $false
    }
    if ($nis -and $nis.Status -ne 'Running') {
        Write-Line 'Result: WdNisSvc is not Running.'
        $ok = $false
    }
    if (-not $st) {
        Write-Line 'Result: Defender status unavailable.'
        $ok = $false
    } elseif (-not $st.RealTimeProtectionEnabled) {
        Write-Line 'Result: Real-time protection is off.'
        $ok = $false
    }
    if ($ok) {
        Write-Line 'Result: WinDefend running; real-time protection on.'
    }
    return $ok
}

function Wait-WinDefend {
    param([int]$TimeoutSeconds = 45)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Enable-AndStartService {
    param(
        [string]$Name,
        [ValidateSet('Automatic', 'Manual')]
        [string]$StartupType = 'Manual'
    )
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Line ("{0}: (not installed)" -f $Name)
        return
    }
    if ($svc.StartType -eq 'Disabled') {
        try {
            Set-Service -Name $Name -StartupType $StartupType
            Write-Line ("{0}: StartType was Disabled, set to {1}" -f $Name, $StartupType)
        } catch {
            $startVal = if ($StartupType -eq 'Automatic') { 2 } else { 3 }
            try {
                Set-ItemProperty -LiteralPath ("HKLM:\SYSTEM\CurrentControlSet\Services\{0}" -f $Name) -Name Start -Value $startVal -Force
                Write-Line ("{0}: StartType Disabled; wrote service Start={1}" -f $Name, $startVal)
            } catch {
                Write-Line ("{0}: cannot enable ({1})" -f $Name, $_.Exception.Message)
            }
        }
    }
    try {
        $cur = Get-Service -Name $Name -ErrorAction Stop
        if ($cur.Status -ne 'Running') {
            Start-Service -Name $Name
        }
        $after = Get-Service -Name $Name
        Write-Line ("{0}: {1} ({2})" -f $Name, $after.Status, $after.StartType)
        if ($Name -eq 'WinDefend' -and $after.Status -ne 'Running') { $script:ExitCode = 1 }
    } catch {
        Write-Line ("{0}: start failed ({1})" -f $Name, $_.Exception.Message)
        if ($Name -eq 'WinDefend') { $script:ExitCode = 1 }
    }
}

function Enable-MpRealtimePreferences {
    $names = @(
        'DisableRealtimeMonitoring',
        'DisableIOAVProtection',
        'DisableBehaviorMonitoring',
        'DisableBlockAtFirstSeen',
        'DisableIntrusionPreventionSystem',
        'DisableScriptScanning',
        'DisableEmailScanning',
        'DisableArchiveScanning'
    )
    foreach ($n in $names) {
        try {
            $splat = @{ $n = $false }
            Set-MpPreference @splat
        } catch {
            Write-Line ("Set-MpPreference {0}: {1}" -f $n, $_.Exception.Message)
        }
    }
}

function Write-RepairException {
    $st = Get-MpComputerStatus -ErrorAction SilentlyContinue
    $mode = if ($st) { [string]$st.AMRunningMode } else { '' }
    $tamper = if ($st -and $st.IsTamperProtected) { $true } else { $false }
    $polRtp = Get-DwordValue $script:PolRtp 'DisableRealtimeMonitoring'
    $polAs = Get-DwordValue $script:PolWd 'DisableAntiSpyware'
    $passive = Get-DwordValue $script:PolAtp 'ForceDefenderPassiveMode'
    $avs = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue)
    $otherAv = @($avs | Where-Object { $_.displayName -and $_.displayName -notmatch 'Defender|Windows Security' })

    if ($mode -eq 'Passive' -or $passive -eq '1') {
        Write-Line 'Exception: Defender is in Passive mode. Another AV (Wolf / S1 / third-party) or ForceDefenderPassiveMode=1 is in control. Uninstall the other AV, set ForceDefenderPassiveMode=0, then reboot and rerun.'
    } elseif ($tamper) {
        Write-Line 'Exception: Tamper Protection is on and may be blocking preference/registry writes. Clear the disable policy in the security portal or GPO, then rerun.'
    } elseif ($polRtp -eq '1' -or $polAs -eq '1') {
        Write-Line 'Exception: Policy still has DisableRealtimeMonitoring or DisableAntiSpyware=1 (GPO/Intune likely reapplied). Change the policy, then rerun. Do not gpupdate if that policy disables Defender.'
    } elseif ($otherAv.Count -gt 0) {
        Write-Line 'Exception: Another Security Center AV is registered. Uninstall it (or complete Wolf/S1 cutover), reboot, then rerun.'
    } else {
        Write-Line 'Exception: RTP stayed off. Check Tamper Protection, GPO DisableRealtimeMonitoring, ForceDefenderPassiveMode, and other WSC AVs. Reboot if services were just re-enabled from Disabled.'
    }
}

if ($CheckOnly) {
    if (-not (Write-DefenderHealth)) { $script:ExitCode = 1 }
    if ($Exit) { exit $script:ExitCode }
    return
}

if ($ResetPlatform) {
    Write-Section 'Nuclear: MpCmdRun -ResetPlatform'
    $mpCmd = Get-MpCmdRunPath
    if (-not $mpCmd) {
        Write-Line 'ERROR: MpCmdRun.exe not found under %ProgramData%\Microsoft\Windows Defender\Platform.'
        $script:ExitCode = 2
        if ($Exit) { exit $script:ExitCode }
        return
    }
    Write-Line $mpCmd
    & $mpCmd -ResetPlatform
    $resetExit = $LASTEXITCODE
    Write-Line ("MpCmdRun exit: {0}" -f $resetExit)
    if ($null -ne $resetExit -and $resetExit -ne 0) {
        $script:ExitCode = 3
    }
}

Write-Section 'Policy / registry (enable RTP, leave Passive)'
$rtpDisableNames = @(
    'DisableRealtimeMonitoring',
    'DisableBehaviorMonitoring',
    'DisableOnAccessProtection',
    'DisableScanOnRealtimeEnable',
    'DisableIOAVProtection',
    'DisableIntrusionPreventionSystem',
    'DisableRawWriteNotification'
)
foreach ($n in $rtpDisableNames) {
    Set-DefenderDword $script:PolRtp $n 0
    if (Test-Path -LiteralPath $script:PrefRtp) {
        try { Set-DefenderDword $script:PrefRtp $n 0 } catch { Write-Line ("{0} preference registry: {1}" -f $n, $_.Exception.Message) }
    }
}
Set-DefenderDword $script:PolWd 'DisableAntiSpyware' 0
Set-DefenderDword $script:PolWd 'DisableAntiVirus' 0
if (Test-Path -LiteralPath $script:PrefWd) {
    try { Set-DefenderDword $script:PrefWd 'DisableAntiSpyware' 0 } catch { }
    try { Set-DefenderDword $script:PrefWd 'DisableAntiVirus' 0 } catch { }
    try { Set-DefenderDword $script:PrefWd 'ForceDefenderPassiveMode' 0 } catch { }
}
Set-DefenderDword $script:PolAtp 'ForceDefenderPassiveMode' 0
if (Test-Path -LiteralPath $script:PrefAtp) {
    try { Set-DefenderDword $script:PrefAtp 'ForceDefenderPassiveMode' 0 } catch { }
}

Write-Section 'Enable + start services'
Enable-AndStartService -Name 'WinDefend' -StartupType Automatic
Enable-AndStartService -Name 'WdNisSvc' -StartupType Manual
Enable-AndStartService -Name 'Sense' -StartupType Manual
Enable-AndStartService -Name 'MdCoreSvc' -StartupType Manual
Enable-AndStartService -Name 'SecurityHealthService' -StartupType Manual
Enable-AndStartService -Name 'wscsvc' -StartupType Automatic
if (-not (Wait-WinDefend)) {
    Write-Line 'ERROR: WinDefend did not reach Running.'
    $script:ExitCode = 1
}

Write-Section 'Set-MpPreference (after WinDefend is Running)'
Enable-MpRealtimePreferences

$st = Get-MpComputerStatus -ErrorAction SilentlyContinue
$pref = Get-MpPreference -ErrorAction SilentlyContinue
$stillOff = (-not $st -or -not $st.RealTimeProtectionEnabled -or ($pref -and $pref.DisableRealtimeMonitoring -eq $true))
if ($stillOff) {
    Write-Line 'RTP still off — restarting WinDefend and retrying Set-MpPreference'
    try { Restart-Service -Name WinDefend -Force -ErrorAction Stop } catch { Write-Line ("Restart-Service WinDefend: {0}" -f $_.Exception.Message) }
    [void](Wait-WinDefend)
    Enable-MpRealtimePreferences
}

Write-Section 'Policy / preference registry'
Write-Line ("Policy DisableAntiSpyware: {0}" -f (Get-DwordValue $script:PolWd 'DisableAntiSpyware'))
Write-Line ("Policy DisableAntiVirus: {0}" -f (Get-DwordValue $script:PolWd 'DisableAntiVirus'))
Write-Line ("Policy DisableRealtimeMonitoring: {0}" -f (Get-DwordValue $script:PolRtp 'DisableRealtimeMonitoring'))
Write-Line ("Policy DisableBehaviorMonitoring: {0}" -f (Get-DwordValue $script:PolRtp 'DisableBehaviorMonitoring'))
Write-Line ("Policy DisableOnAccessProtection: {0}" -f (Get-DwordValue $script:PolRtp 'DisableOnAccessProtection'))
Write-Line ("Policy DisableIOAVProtection: {0}" -f (Get-DwordValue $script:PolRtp 'DisableIOAVProtection'))
Write-Line ("Policy ForceDefenderPassiveMode: {0}" -f (Get-DwordValue $script:PolAtp 'ForceDefenderPassiveMode'))
Write-Line ("HKLM Defender RTP DisableRealtimeMonitoring: {0}" -f (Get-DwordValue $script:PrefRtp 'DisableRealtimeMonitoring'))
Write-Line ("HKLM Defender ForceDefenderPassiveMode: {0}" -f (Get-DwordValue $script:PrefWd 'ForceDefenderPassiveMode'))

Write-Section 'Security Center AV'
[void](Write-WscProducts)

if (-not (Write-DefenderHealth)) {
    Write-RepairException
    $script:ExitCode = 1
}

if ($Exit) { exit $script:ExitCode }
