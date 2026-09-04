#Requires -Version 5.1
<#
.SYNOPSIS
    Re-enable Windows Defender real-time protection and start the Defender services.

.PARAMETER ResetPlatform
    Nuclear option: run MpCmdRun.exe -ResetPlatform from the current Defender
    Platform folder, then apply the real-time protection repair.

.PARAMETER Exit
    Call exit with a status code (ScreenConnect Commands). Omit in Backstage.
#>
[CmdletBinding()]
param(
    [switch]$ResetPlatform,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$script:ExitCode = 0

function Write-Section([string]$Message) {
    Write-Output "=== $Message ==="
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

if ($ResetPlatform) {
    Write-Section 'Nuclear: MpCmdRun -ResetPlatform'
    $mpCmd = Get-MpCmdRunPath
    if (-not $mpCmd) {
        Write-Output 'ERROR: MpCmdRun.exe not found under %ProgramData%\Microsoft\Windows Defender\Platform.'
        $script:ExitCode = 2
        if ($Exit) { exit $script:ExitCode }
        return
    }
    Write-Output $mpCmd
    & $mpCmd -ResetPlatform
    $resetExit = $LASTEXITCODE
    Write-Output ("MpCmdRun exit: {0}" -f $resetExit)
    if ($null -ne $resetExit -and $resetExit -ne 0) {
        $script:ExitCode = 3
    }
}

Write-Section 'Re-enable Defender real-time protection'
Set-MpPreference -DisableRealtimeMonitoring $false
Set-MpPreference -DisableIOAVProtection $false
New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Name 'Real-Time Protection' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' -Name 'DisableBehaviorMonitoring' -Value 0 -PropertyType DWORD -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' -Name 'DisableOnAccessProtection' -Value 0 -PropertyType DWORD -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' -Name 'DisableScanOnRealtimeEnable' -Value 0 -PropertyType DWORD -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Name 'DisableAntiSpyware' -Value 0 -PropertyType DWORD -Force | Out-Null

Write-Section 'Start Defender services'
Start-Service WinDefend
Start-Service WdNisSvc

Write-Section 'Service state'
Get-Service -Name WinDefend, WdNisSvc -ErrorAction SilentlyContinue |
    Format-Table Name, Status, StartType -AutoSize | Out-String | Write-Output

$pref = Get-MpPreference -ErrorAction SilentlyContinue
if ($pref) {
    Write-Output ("DisableRealtimeMonitoring: {0}" -f $pref.DisableRealtimeMonitoring)
    Write-Output ("DisableIOAVProtection: {0}" -f $pref.DisableIOAVProtection)
}

$wd = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
if (-not $wd -or $wd.Status -ne 'Running') {
    Write-Output 'ERROR: WinDefend is not Running.'
    $script:ExitCode = 1
}

if ($Exit) { exit $script:ExitCode }
