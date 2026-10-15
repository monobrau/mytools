#Requires -Version 5.1
<#
.SYNOPSIS
    Disable the Windows PowerShell 2.0 optional features.

.DESCRIPTION
    Turns off MicrosoftWindowsPowerShellV2 and MicrosoftWindowsPowerShellV2Root.
    That is the CIS / vuln-scanner control for PowerShell 2.0. A feature that is
    already Disabled, DisablePending, or missing (removed SKU) counts as done.

    Default is to disable. The script does not restart the PC. A scanner finding
    can stay open until the next restart.

.PARAMETER NoExit
    Keep the PowerShell host open (Backstage).

.PARAMETER Exit
    Always call exit with the result code (Commands / automation).
#>
[CmdletBinding()]
param(
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptVersion = '1.0.0'
$FeatureNames = @(
    'MicrosoftWindowsPowerShellV2',
    'MicrosoftWindowsPowerShellV2Root'
)

function Write-Psv2Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts][$Level] $Message"
}

function Test-Psv2ShouldExitProcess {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-Psv2Run {
    param([Parameter(Mandatory)][int]$Code)
    $global:LASTEXITCODE = $Code
    if (Test-Psv2ShouldExitProcess) { exit $Code }
    Write-Psv2Log ("Done. ResultCode={0} (PowerShell host kept open)." -f $Code)
}

function Test-Psv2Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Psv2DismExe {
    $sysNative = Join-Path $env:WINDIR 'SysNative\dism.exe'
    $system32 = Join-Path $env:WINDIR 'System32\dism.exe'
    if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem -and (Test-Path -LiteralPath $sysNative)) {
        return $sysNative
    }
    return $system32
}

function Test-Psv2UseCmdlet {
    if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
        return $false
    }
    return [bool](Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)
}

function Convert-Psv2State([string]$Raw) {
    $text = ([string]$Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return 'Missing' }
    $compact = $text -replace '\s+', ''
    switch -Regex ($compact) {
        '^(Enabled|EnablePending)$' { return 'Enabled' }
        '^(Disabled|DisabledWithPayloadRemoved|DisablePending)$' { return 'Disabled' }
        default { return $text }
    }
}

function Get-Psv2FeatureState {
    param([string]$Name, [bool]$UseCmdlet)
    if ($UseCmdlet) {
        try {
            $feat = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction Stop
            if ($null -eq $feat) { return 'Missing' }
            return Convert-Psv2State ([string]$feat.State)
        }
        catch {
            $msg = [string]$_.Exception.Message
            if ($msg -match '0x800f080c|cannot find|not found|does not exist') {
                return 'Missing'
            }
            throw
        }
    }

    $dism = Get-Psv2DismExe
    $output = & $dism /online /english /get-featureinfo /featurename:$Name 2>&1 | Out-String
    if ($output -match '0x800f080c' -or ($LASTEXITCODE -ne 0 -and $output -notmatch 'Feature Name')) {
        return 'Missing'
    }
    if ($output -match '(?im)^\s*State\s*:\s*(.+?)\s*$') {
        return Convert-Psv2State $Matches[1]
    }
    throw ("DISM did not report a state for {0}." -f $Name)
}

function Disable-Psv2Feature {
    param([string]$Name, [bool]$UseCmdlet)
    if ($UseCmdlet) {
        $result = Disable-WindowsOptionalFeature -Online -FeatureName $Name -NoRestart -ErrorAction Stop
        $need = $false
        if ($result -and $result.PSObject.Properties['RestartNeeded']) {
            $need = [string]$result.RestartNeeded -match 'Yes|True|^1$'
        }
        return $need
    }

    $dism = Get-Psv2DismExe
    $null = & $dism /online /english /disable-feature /featurename:$Name /norestart 2>&1
    $code = $LASTEXITCODE
    if ($code -eq 0) { return $false }
    if ($code -eq 3010) { return $true }
    throw ("DISM disable {0} failed with exit {1}." -f $Name, $code)
}

if (-not (Test-Psv2Admin)) {
    Write-Psv2Log 'Run this from an elevated PowerShell window.' 'ERROR'
    Complete-Psv2Run -Code 1
    return
}

Write-Psv2Log ("PowerShellV2Disable {0} on {1}" -f $ScriptVersion, $env:COMPUTERNAME)
Write-Psv2Log 'Mode: APPLY'
Write-Psv2Log 'Disables the PowerShell 2.0 optional features. Does not restart the PC.'

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    Write-Psv2Log ("OS: {0} build {1}" -f $os.Caption, $os.BuildNumber)
}
catch {
    Write-Psv2Log 'OS caption could not be read.' 'WARN'
}

$useCmdlet = Test-Psv2UseCmdlet
Write-Psv2Log ("DISM path: {0}" -f $(if ($useCmdlet) { 'PowerShell cmdlet' } else { Get-Psv2DismExe }))

$disabledNow = 0
$alreadyOk = 0
$restartNeeded = $false

foreach ($name in $FeatureNames) {
    try {
        $state = Get-Psv2FeatureState -Name $name -UseCmdlet $useCmdlet
    }
    catch {
        Write-Psv2Log ("{0}: could not read state. {1}" -f $name, $_.Exception.Message) 'ERROR'
        Complete-Psv2Run -Code 1
        return
    }

    Write-Psv2Log ("{0}: {1}" -f $name, $state)

    if ($state -eq 'Missing' -or $state -eq 'Disabled') {
        $alreadyOk++
        continue
    }
    if ($state -ne 'Enabled') {
        Write-Psv2Log ("{0}: unexpected state {1}." -f $name, $state) 'ERROR'
        Complete-Psv2Run -Code 1
        return
    }

    try {
        $need = Disable-Psv2Feature -Name $name -UseCmdlet $useCmdlet
    }
    catch {
        Write-Psv2Log ("{0}: disable failed. {1}" -f $name, $_.Exception.Message) 'ERROR'
        Complete-Psv2Run -Code 1
        return
    }

    if ($need) { $restartNeeded = $true }

    try {
        $after = Get-Psv2FeatureState -Name $name -UseCmdlet $useCmdlet
    }
    catch {
        Write-Psv2Log ("{0}: disable ran but state could not be re-read. {1}" -f $name, $_.Exception.Message) 'ERROR'
        Complete-Psv2Run -Code 1
        return
    }

    if ($after -ne 'Disabled' -and $after -ne 'Missing') {
        Write-Psv2Log ("{0}: still {1} after disable." -f $name, $after) 'ERROR'
        Complete-Psv2Run -Code 1
        return
    }

    Write-Psv2Log ("DISABLED {0}: Enabled -> {1}" -f $name, $after)
    $disabledNow++
}

if ($disabledNow -eq 0) {
    Write-Psv2Log 'PASS: PowerShell 2.0 optional features are already disabled or not present.'
    Complete-Psv2Run -Code 0
    return
}

if ($restartNeeded) {
    Write-Psv2Log 'PASS: PowerShell 2.0 is disabled. Restart the PC before a scanner finding will clear. This script did not reboot.' 'WARN'
}
else {
    Write-Psv2Log 'PASS: PowerShell 2.0 is disabled. Restart later if a scanner still shows the finding. This script did not reboot.' 'WARN'
}
Complete-Psv2Run -Code 0
