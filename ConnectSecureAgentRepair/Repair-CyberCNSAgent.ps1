#Requires -Version 5.1
<#
.SYNOPSIS
    Check / remediate a stuck ConnectSecure (CyberCNS) Windows agent, then optionally reinstall.

.DESCRIPTION
    If CyberCNSAgent and CyberCNSAgentMonitor are both Running, reports and exits.
    Otherwise stops/deletes services, kills processes, removes the install folder, downloads
    a fresh Windows agent, and installs with company/environment/token parameters.

    Dry-run (default without -Remediate): report service/process/folder state only.
    Reinstall requires -CompanyId, -EnvironmentId, and -InstallToken (do not hardcode secrets).

.PARAMETER CheckOnly
    Report state only; make no changes.

.PARAMETER Remediate
    Stop/delete services, kill processes, remove install folder, download and reinstall.

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
    Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.PathName -like '*cybercns*' }
}

function Get-CyberCnsProcesses {
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -like '*cybercns*' }
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

Write-Section 'Stopping and deleting CyberCNSAgentMonitor service'
& sc.exe stop CyberCNSAgentMonitor | Out-Null
Start-Sleep -Seconds 2
& sc.exe delete CyberCNSAgentMonitor | Out-Null

Write-Section 'Stopping and deleting CyberCNSAgent service'
& sc.exe stop CyberCNSAgent | Out-Null
Start-Sleep -Seconds 2
& sc.exe delete CyberCNSAgent | Out-Null

Write-Section 'Killing any lingering CyberCNS processes'
Stop-Process -Name cybercnsagentmonitor -Force -ErrorAction SilentlyContinue
Stop-Process -Name cybercnsagent -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Section 'Checking for surviving service/process'
$svc = @(Get-CyberCnsServices)
$proc = @(Get-CyberCnsProcesses)

if ($svc.Count -gt 0 -or $proc.Count -gt 0) {
    Write-Section 'CyberCNS service/process still present after kill attempt. Reboot before reinstall. Stopping here.'
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

Write-Section 'Clean. Removing install folder'
if (Test-Path -LiteralPath $installFolder) {
    Remove-Item -LiteralPath $installFolder -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Section 'Downloading fresh agent installer'
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
