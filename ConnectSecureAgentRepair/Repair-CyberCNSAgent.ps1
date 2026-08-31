#Requires -Version 5.1
<#
.SYNOPSIS
    Check / remediate a stuck ConnectSecure (CyberCNS) Windows agent, then optionally reinstall.

.DESCRIPTION
    If CyberCNSAgent and CyberCNSAgentMonitor are both Running, reports and exits.
    Otherwise stops/deletes services (including leftover Stopped/Disabled entries),
    kills processes, removes the install folder, downloads a fresh Windows agent,
    and installs with company/environment/token parameters.

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
        Where-Object { $_.PathName -like '*cybercns*' -or $_.Name -like 'CyberCNS*' }
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

function Remove-CyberCnsServiceRecord([string]$Name) {
    Invoke-Sc @('stop', $Name)
    Start-Sleep -Seconds 1
    Invoke-Sc @('delete', $Name)
    $cim = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if ($cim) {
        try {
            $cim | Invoke-CimMethod -MethodName Delete -ErrorAction Stop | Out-Null
            Write-Output ("CIM Delete invoked for {0}" -f $Name)
        }
        catch {
            Write-Output ("CIM Delete {0}: {1}" -f $Name, $_.Exception.Message)
        }
    }
}

function Clear-CyberCnsRemnants {
    Write-Section 'Stopping/deleting CyberCNS services and killing processes'
    foreach ($name in @('CyberCNSAgentMonitor', 'CyberCNSAgent')) {
        Remove-CyberCnsServiceRecord $name
    }

    foreach ($p in @(Get-CyberCnsProcesses)) {
        Write-Output ("Killing PID {0} {1}" -f $p.Id, $p.ProcessName)
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 3

    for ($i = 1; $i -le 3; $i++) {
        $left = @(Get-CyberCnsServices)
        $procs = @(Get-CyberCnsProcesses)
        if ($left.Count -eq 0 -and $procs.Count -eq 0) { return $true }

        Write-Output ("Retry {0}/3: leftover service={1} process={2}" -f $i, $left.Count, $procs.Count)
        foreach ($p in $procs) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
        foreach ($s in $left) {
            Remove-CyberCnsServiceRecord $s.Name
        }
        Start-Sleep -Seconds 3
    }

    $procs = @(Get-CyberCnsProcesses)
    if ($procs.Count -gt 0) { return $false }

    $left = @(Get-CyberCnsServices)
    if ($left | Where-Object { $_.State -eq 'Running' }) { return $false }

    foreach ($s in $left) {
        $reg = Join-Path 'HKLM:\SYSTEM\CurrentControlSet\Services' $s.Name
        if (Test-Path -LiteralPath $reg) {
            Write-Output ("Removing leftover service registry {0}" -f $reg)
            Remove-Item -LiteralPath $reg -Recurse -Force -ErrorAction SilentlyContinue
        }
        Invoke-Sc @('delete', $s.Name)
    }
    Start-Sleep -Seconds 3

    $left = @(Get-CyberCnsServices)
    return ($left.Count -eq 0)
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

$cleared = Clear-CyberCnsRemnants
$svc = @(Get-CyberCnsServices)
$proc = @(Get-CyberCnsProcesses)

if (-not $cleared -or $svc.Count -gt 0 -or $proc.Count -gt 0) {
    Write-Section 'CyberCNS remnant still present after delete retries. Reboot, then re-run -Remediate.'
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
