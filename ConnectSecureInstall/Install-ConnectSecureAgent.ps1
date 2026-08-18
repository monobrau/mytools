#Requires -Version 5.1
<#
.SYNOPSIS
    Silent-install ConnectSecure (CyberCNS) Windows agent.

.DESCRIPTION
    Downloads the current Windows agent from the ConnectSecure agentlink API and
    installs with -c / -e / -j / -i. Fresh install only (does not uninstall).

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

if ([string]::IsNullOrWhiteSpace($CompanyId) -or
    [string]::IsNullOrWhiteSpace($EnvironmentId) -or
    [string]::IsNullOrWhiteSpace($InstallToken)) {
    Write-Output 'ERROR: -CompanyId, -EnvironmentId, and -InstallToken are required.'
    $script:ExitCode = 2
    if ($Exit) { exit $script:ExitCode }
    return
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
Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
    Where-Object { $_.PathName -like '*cybercns*' } |
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
