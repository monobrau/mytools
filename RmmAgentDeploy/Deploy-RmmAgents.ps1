#Requires -Version 5.1
<#
.SYNOPSIS
    Non-GPO deploy of ConnectWise Automate and/or Huntress to online machines missing them.

.DESCRIPTION
    Run elevated as a domain admin on a machine that can reach C$ and create
    scheduled tasks on the targets. Reads a coverage CSV. For each online host
    with remote admin OK and Automate or Huntress missing, stages a SYSTEM task
    that installs the missing agent.

    Automate uses the Braingears Install-Automate function (location token).
    Huntress uses a pre-downloaded HuntressInstaller.exe and /ACCT_KEY /ORG_KEY /S.

    Each target logs to C:\Windows\Temp\rr-deploy.log and deletes the staged
    installer and script when the task finishes.

.PARAMETER Only
    Pilot: one or more computer names from the CSV Name column.

.PARAMETER AutomateServer
    Automate server hostname.

.PARAMETER LocationID
    Automate location id for Install-Automate.

.PARAMETER AutomateToken
    Windows installer token for that location. Not stored in this repo.

.PARAMETER HuntressAcctKey
    Huntress account key. Not stored in this repo.

.PARAMETER HuntressOrgKey
    Huntress organization key.

.PARAMETER HuntressExe
    Local path to HuntressInstaller.exe. Copied only to hosts missing Huntress.

.PARAMETER CoverageCsv
    CSV with columns Name, Online, RemoteAdmin, Automate, Huntress.
    Online must be True, RemoteAdmin OK, and Automate or Huntress MISSING.

.PARAMETER Exclude
    Computer names to skip (domain controllers, hypervisors, machines you do not want touched).

.EXAMPLE
    .\Deploy-RmmAgents.ps1 -Only 'CONTOSO-PC01' -AutomateServer 'automate.example.com' -LocationID 1 -AutomateToken '<token>' -HuntressAcctKey '<acct>' -HuntressOrgKey 'contoso' -Exclude 'DC01','DC02'
#>
[CmdletBinding()]
param(
    [string[]]$Only,
    [Parameter(Mandatory)][string]$AutomateServer,
    [Parameter(Mandatory)][int]$LocationID,
    [Parameter(Mandatory)][string]$AutomateToken,
    [Parameter(Mandatory)][string]$HuntressAcctKey,
    [Parameter(Mandatory)][string]$HuntressOrgKey,
    [string]$HuntressExe = 'C:\Support\HuntressInstaller.exe',
    [string]$CoverageCsv = 'C:\Support\coverage.csv',
    [string[]]$Exclude = @()
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

if ($AutomateToken -match '__AUTOMATE_TOKEN__|__ACCT__|__ORG__') {
    throw 'Automate token contains a script placeholder.'
}
if ($HuntressAcctKey -match '__AUTOMATE_TOKEN__|__ACCT__|__ORG__' -or $HuntressOrgKey -match '__AUTOMATE_TOKEN__|__ACCT__|__ORG__') {
    throw 'Huntress key contains a script placeholder.'
}
if (-not (Test-Path -LiteralPath $CoverageCsv)) { throw "Missing $CoverageCsv" }
if (-not (Test-Path -LiteralPath $HuntressExe)) { throw "Missing $HuntressExe" }

$endpointTemplate = @'
Start-Transcript -Path C:\Windows\Temp\rr-deploy.log -Append | Out-Null
try {
    try {
        if (-not (Get-Service LTService -ErrorAction SilentlyContinue)) {
            [Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
            Invoke-Expression (New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/Braingears/PowerShell/master/Automate-Module.psm1')
            Install-Automate -Server '__AUTOMATE_SERVER__' -LocationID __LOCATION_ID__ -Token '__AUTOMATE_TOKEN__' -Force
        } else { 'Automate already installed' }
    }
    catch { "AUTOMATE ERROR: $($_.Exception.Message)" }
    Start-Sleep -Seconds 20
    "LTService after install step: $((Get-Service LTService -ErrorAction SilentlyContinue).Status)"

    try {
        if (-not (Get-Service | Where-Object Name -like 'Huntress*') -and (Test-Path C:\Windows\Temp\HuntressInstaller.exe)) {
            $p = Start-Process C:\Windows\Temp\HuntressInstaller.exe -ArgumentList '/ACCT_KEY="__ACCT__" /ORG_KEY="__ORG__" /S' -Wait -PassThru
            "Huntress installer exit code: $($p.ExitCode)"
        } else { 'Huntress already installed or installer not staged' }
    }
    catch { "HUNTRESS ERROR: $($_.Exception.Message)" }
    "Huntress services after install step: $((Get-Service | Where-Object Name -like 'Huntress*').Name -join ', ')"
}
finally {
    Remove-Item C:\Windows\Temp\HuntressInstaller.exe, C:\Windows\Temp\rr-deploy.ps1 -Force -ErrorAction SilentlyContinue
    schtasks.exe /delete /tn RR-AgentDeploy /f | Out-Null
    Stop-Transcript | Out-Null
}
'@

$endpoint = $endpointTemplate.
    Replace('__AUTOMATE_SERVER__', $AutomateServer).
    Replace('__LOCATION_ID__', [string]$LocationID).
    Replace('__AUTOMATE_TOKEN__', $AutomateToken).
    Replace('__ACCT__', $HuntressAcctKey).
    Replace('__ORG__', $HuntressOrgKey)

$targets = @(Import-Csv -LiteralPath $CoverageCsv | Where-Object {
    $_.Online -eq 'True' -and
    $_.RemoteAdmin -eq 'OK' -and
    ($_.Automate -eq 'MISSING' -or $_.Huntress -eq 'MISSING') -and
    $Exclude -notcontains $_.Name
})
if ($Only) {
    $targets = @($targets | Where-Object { $Only -contains $_.Name })
}

if (-not $targets) {
    Write-Warning 'No matching targets.'
    return
}
Write-Host ("Deploying to {0} machine(s)..." -f $targets.Count) -ForegroundColor Cyan

$results = foreach ($t in $targets) {
    $name = $t.Name
    $dest = "\\$name\C$\Windows\Temp"
    $status = 'Started'
    try {
        Set-Content -LiteralPath "$dest\rr-deploy.ps1" -Value $endpoint -Encoding ASCII -ErrorAction Stop
        if ($t.Huntress -eq 'MISSING') {
            Copy-Item -LiteralPath $HuntressExe -Destination "$dest\HuntressInstaller.exe" -Force -ErrorAction Stop
        }

        schtasks.exe /create /s $name /ru SYSTEM /sc once /st 23:59 /rl HIGHEST /f /tn RR-AgentDeploy /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Windows\Temp\rr-deploy.ps1" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "task create failed (exit $LASTEXITCODE)" }

        schtasks.exe /run /s $name /tn RR-AgentDeploy 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "task run failed (exit $LASTEXITCODE)" }
    }
    catch {
        $status = "FAILED: $($_.Exception.Message)"
    }

    [pscustomobject]@{
        Name     = $name
        Automate = $t.Automate
        Huntress = $t.Huntress
        Status   = $status
    }
}

$results | Format-Table -AutoSize
$outCsv = Join-Path (Split-Path -Parent $CoverageCsv) 'deploy-results.csv'
$results | Export-Csv -LiteralPath $outCsv -NoTypeInformation
Write-Host "Results: $outCsv" -ForegroundColor Cyan
Write-Host 'Installs run in the background. Check C:\Windows\Temp\rr-deploy.log on a target, then rerun the coverage check in about 15 minutes.' -ForegroundColor Cyan
