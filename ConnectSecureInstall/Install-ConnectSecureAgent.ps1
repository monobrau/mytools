#Requires -Version 5.1
<#
.SYNOPSIS
    Silent-install ConnectSecure (CyberCNS) Windows agent.

.DESCRIPTION
    Downloads the current Windows agent from the ConnectSecure agentlink API and
    installs with -c / -e / -j / -i.

    If a leftover CyberCNSAgent service exists (Stopped/Disabled is common),
    it is deleted first so the installer does not fail with
    "service CyberCNSAgent already exists". Running processes still block install.

    Never hardcode real company/env/token values. Pass them at run time.

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
    [Parameter(Mandatory = $true)]
    [string]$CompanyId,

    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [Parameter(Mandatory = $true)]
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

if ([string]::IsNullOrWhiteSpace($CompanyId) -or
    [string]::IsNullOrWhiteSpace($EnvironmentId) -or
    [string]::IsNullOrWhiteSpace($InstallToken)) {
    Write-Output 'ERROR: -CompanyId, -EnvironmentId, and -InstallToken are required.'
    $script:ExitCode = 2
    if ($Exit) { exit $script:ExitCode }
    return
}

$existing = @(Get-CyberCnsServices)
$running = @($existing | Where-Object { $_.State -eq 'Running' })
if ($running.Count -gt 0) {
    Write-Output 'CyberCNS service already Running. Use ConnectSecure agent repair to wipe + reinstall.'
    $existing | Format-Table Name, State, StartMode, PathName -AutoSize | Out-String | Write-Output
    $script:ExitCode = 0
    if ($Exit) { exit $script:ExitCode }
    return
}

if ($existing.Count -gt 0) {
    Write-Section 'Leftover CyberCNS service found (not running). Removing so install can proceed'
    $existing | Format-Table Name, State, StartMode, PathName -AutoSize | Out-String | Write-Output
    foreach ($s in $existing) {
        Remove-CyberCnsServiceRecord $s.Name
    }
    Start-Sleep -Seconds 3
    $left = @(Get-CyberCnsServices)
    if ($left.Count -gt 0) {
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
    }
    if ($left.Count -gt 0) {
        Write-Output 'ERROR: leftover CyberCNS service still registered. Reboot, then run ConnectSecure agent repair.'
        $left | Format-Table Name, State, PathName -AutoSize | Out-String | Write-Output
        $script:ExitCode = 3
        if ($Exit) { exit $script:ExitCode }
        return
    }
}

$installerPath = 'C:\cybercnsagent.exe'

Write-Section 'Downloading Windows agent from ConnectSecure agentlink'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    $source = Invoke-RestMethod -Method Get -Uri 'https://configuration.myconnectsecure.com/api/v4/configuration/agentlink?ostype=windows'
    Invoke-WebRequest -Uri $source -OutFile $installerPath -UseBasicParsing
}
catch {
    Write-Output ("ERROR: download failed: {0}" -f $_.Exception.Message)
    $script:ExitCode = 4
    if ($Exit) { exit $script:ExitCode }
    return
}

Write-Section 'Installing agent (-c / -e / -j / -i)'
& $installerPath -c $CompanyId -e $EnvironmentId -j $InstallToken -i
$installExit = $LASTEXITCODE

Write-Section 'Done. Checking CyberCNS services'
Get-CyberCnsServices |
    Format-Table Name, State, StartMode, PathName -AutoSize |
    Out-String |
    Write-Output

if ($installExit -and $installExit -ne 0) {
    $script:ExitCode = $installExit
}
else {
    $script:ExitCode = 0
}

if ($Exit) { exit $script:ExitCode }
