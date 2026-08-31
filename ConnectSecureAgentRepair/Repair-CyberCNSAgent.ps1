#Requires -Version 5.1
<#
.SYNOPSIS
    Check / remediate a stuck ConnectSecure (CyberCNS) Windows agent, then optionally reinstall.

.DESCRIPTION
    If CyberCNSAgent and CyberCNSAgentMonitor are both Running, reports and exits.
    Otherwise follows the vendor uninstall.bat sequence (stop/delete CyberCNSAgent,
    taskkill helpers, cybercnsagent.exe --internalAssetArgument uninstallservice,
    rmdir folder), then downloads a fresh agent and reinstalls.

    Dry-run (default without -Remediate): report service/process/folder state only.
    Reinstall requires -CompanyId, -EnvironmentId, and -InstallToken (do not hardcode secrets).

.PARAMETER CheckOnly
    Report state only; make no changes.

.PARAMETER Remediate
    Vendor uninstall.bat steps, then download and reinstall.

.PARAMETER CompanyId
    Installer -c value (company id).

.PARAMETER EnvironmentId
    Installer -e value (environment id).

.PARAMETER InstallToken
    Installer -j value (install JWT / token). Never commit real tokens to git.

.PARAMETER Exit
    Call exit with a status code (ScreenConnect Commands). Omit in Backstage.
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Remediate,
    [string]$CompanyId,
    [string]$EnvironmentId,
    [string]$InstallToken,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$script:ExitCode = 0

function Write-Section([string]$Message) {
    Write-Output "=== $Message ==="
}

function Get-CyberCnsServices {
    $byCim = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.PathName -like '*cybercns*' -or $_.Name -like 'CyberCNS*' -or $_.Name -like 'ConnectSecure*' })
    $names = @('CyberCNSAgent', 'CyberCNSAgentMonitor', 'ConnectSecureAgentMonitor')
    $byName = foreach ($n in $names) {
        Get-Service -Name $n -ErrorAction SilentlyContinue
    }
    @($byCim + $byName) | Sort-Object Name -Unique
}

function Get-CyberCnsProcesses {
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -like '*cybercns*' }
}

function Invoke-Sc([string[]]$ScArgs) {
    $out = & sc.exe @ScArgs 2>&1 | Out-String
    $out = $out.Trim()
    if ($out) { Write-Output $out }
}

# Mirrors C:\Program Files (x86)\CyberCNSAgent\uninstall.bat (vendor copy):
#   ping wait, sc stop/delete CyberCNSAgent, taskkill helpers,
#   cybercnsagent.exe --internalAssetArgument uninstallservice, rmdir folder
function Invoke-CyberCnsUninstallBat {
    $pf86 = ${env:ProgramFiles(x86)}
    if (-not $pf86) { $pf86 = 'C:\Program Files (x86)' }
    $folder = Join-Path $pf86 'CyberCNSAgent'
    $exe = Join-Path $folder 'cybercnsagent.exe'

    Write-Section 'Vendor uninstall.bat sequence'
    Write-Output 'Wait 5 seconds'
    Start-Sleep -Seconds 5

    Invoke-Sc @('stop', 'CyberCNSAgentMonitor')
    Start-Sleep -Seconds 5
    Invoke-Sc @('delete', 'CyberCNSAgentMonitor')

    Start-Sleep -Seconds 5
    Invoke-Sc @('stop', 'CyberCNSAgent')
    Start-Sleep -Seconds 5
    Invoke-Sc @('delete', 'CyberCNSAgent')
    Start-Sleep -Seconds 5

    foreach ($im in @('osqueryi.exe', 'nmap.exe', 'cyberutilities.exe')) {
        Write-Output ("taskkill /IM {0} /F" -f $im)
        $tk = & taskkill.exe /IM $im /F 2>&1 | Out-String
        if ($tk.Trim()) { Write-Output $tk.Trim() }
    }

    if (Test-Path -LiteralPath $exe) {
        Write-Output 'cybercnsagent.exe --internalAssetArgument uninstallservice'
        Push-Location $pf86
        try {
            & $exe --internalAssetArgument uninstallservice
        }
        finally {
            Pop-Location
        }
    }
    else {
        Write-Output ("Agent exe not found at {0}; skipping uninstallservice" -f $exe)
    }

    if (Test-Path -LiteralPath $folder) {
        Write-Output ("rmdir {0} /s /q" -f $folder)
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    }

    # uninstall.bat often leaves a ghost service: "Failed to Read Description"
    # because the exe is gone but the SCM/registry key remains.
    Remove-CyberCnsGhostServices
}

function Remove-CyberCnsGhostServices {
    Write-Section 'Removing leftover CyberCNS service records (ghost / Failed to Read Description)'
    $names = @('CyberCNSAgent', 'CyberCNSAgentMonitor', 'ConnectSecureAgentMonitor')

    # 1072 "marked for deletion" completes when the last SC_HANDLE is closed.
    # services.msc / Event Viewer (mmc.exe) is the usual holder — not a reboot.
    Write-Output 'Closing MMC (services.msc / Event Viewer) so SCM can finish the delete'
    $tk = & taskkill.exe /F /IM mmc.exe 2>&1 | Out-String
    if ($tk.Trim()) { Write-Output $tk.Trim() }
    Start-Sleep -Seconds 2

    foreach ($n in $names) {
        Invoke-Sc @('stop', $n)
        Invoke-Sc @('delete', $n)
        $cim = Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue
        if ($cim) {
            try { $cim | Invoke-CimMethod -MethodName Delete -ErrorAction Stop | Out-Null } catch { }
        }
        foreach ($set in @('CurrentControlSet', 'ControlSet001', 'ControlSet002')) {
            $reg = "HKLM:\SYSTEM\$set\Services\$n"
            if (Test-Path -LiteralPath $reg) {
                Write-Output ("Removing {0}" -f $reg)
                Remove-Item -LiteralPath $reg -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Start-Sleep -Seconds 2

    $still = @(Get-Service -Name $names -ErrorAction SilentlyContinue)
    if ($still.Count -gt 0) {
        Write-Output 'Service still listed after MMC kill. Close Task Manager / Computer Management if open, then re-check in a NEW PowerShell. Get-Service in this window can hold the handle.'
        $still | Format-Table Status, Name, DisplayName -AutoSize | Out-String | Write-Output
    }
}

$installFolder = ${env:ProgramFiles(x86)}
if (-not $installFolder) { $installFolder = $env:ProgramFiles }
$installFolder = Join-Path $installFolder 'CyberCNSAgent'
$installerPath = 'C:\cybercnsagent.exe'

Write-Section 'Checking current CyberCNS service state'
$existingSvc = @(Get-CyberCnsServices)
$existingSvc | Format-Table Name, State, StartMode, PathName -AutoSize | Out-String | Write-Output

$agentRunning = $existingSvc | Where-Object { $_.Name -eq 'CyberCNSAgent' -and $_.State -eq 'Running' }
$monitorRunning = $existingSvc | Where-Object { $_.Name -eq 'CyberCNSAgentMonitor' -and $_.State -eq 'Running' }

if ($agentRunning -and $monitorRunning) {
    Write-Section 'Both CyberCNSAgent and CyberCNSAgentMonitor are already running. No action needed.'
    if ($Exit) { exit 0 }
    return
}

if ($CheckOnly -or -not $Remediate) {
    Write-Section 'Services not both healthy (CheckOnly / dry-run — no changes)'
    $procs = @(Get-CyberCnsProcesses)
    if ($procs.Count -gt 0) {
        Write-Output 'Processes:'
        $procs | Format-Table Id, ProcessName, Path -AutoSize | Out-String | Write-Output
    }
    Write-Output ("Install folder present: {0}" -f (Test-Path -LiteralPath $installFolder))
    Write-Output 'Re-run with -Remediate -CompanyId ... -EnvironmentId ... -InstallToken ... to repair/reinstall.'
    $script:ExitCode = 1
    if ($Exit) { exit $script:ExitCode }
    return
}

if ([string]::IsNullOrWhiteSpace($CompanyId) -or
    [string]::IsNullOrWhiteSpace($EnvironmentId) -or
    [string]::IsNullOrWhiteSpace($InstallToken)) {
    Write-Output 'ERROR: -Remediate requires -CompanyId, -EnvironmentId, and -InstallToken.'
    $script:ExitCode = 2
    if ($Exit) { exit $script:ExitCode }
    return
}

Write-Section 'Services not healthy, proceeding with remediation'
Set-Location C:\

Invoke-CyberCnsUninstallBat

$svc = @(Get-CyberCnsServices)
$proc = @(Get-CyberCnsProcesses)
if ($svc.Count -gt 0 -or $proc.Count -gt 0) {
    Write-Section 'Remnant still present after uninstall.bat steps. Reboot, then re-run -Remediate.'
    if ($svc.Count -gt 0) {
        Write-Output 'Service state:'
        $svc | Format-Table Name, State, PathName -AutoSize | Out-String | Write-Output
    }
    if ($proc.Count -gt 0) {
        Write-Output 'Process state:'
        $proc | Format-Table Id, ProcessName, Path -AutoSize | Out-String | Write-Output
    }
    $script:ExitCode = 3
    if ($Exit) { exit $script:ExitCode }
    return
}

Write-Section 'Downloading fresh agent installer'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    $source = Invoke-RestMethod -Method Get -Uri 'https://configuration.myconnectsecure.com/api/v4/configuration/agentlink?ostype=windows'
    Invoke-WebRequest -Uri $source -OutFile $installerPath -UseBasicParsing
} catch {
    Write-Output ("ERROR: download failed: {0}" -f $_.Exception.Message)
    $script:ExitCode = 4
    if ($Exit) { exit $script:ExitCode }
    return
}

Write-Section 'Installing agent'
& $installerPath -c $CompanyId -e $EnvironmentId -j $InstallToken -i
$installExit = $LASTEXITCODE

Write-Section 'Done. Verifying service state'
Get-CyberCnsServices | Format-Table Name, State, StartMode, PathName -AutoSize | Out-String | Write-Output

if ($installExit -and $installExit -ne 0) {
    $script:ExitCode = $installExit
} else {
    $script:ExitCode = 0
}

if ($Exit) { exit $script:ExitCode }
