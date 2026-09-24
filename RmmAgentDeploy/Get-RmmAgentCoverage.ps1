#Requires -Version 5.1
<#
.SYNOPSIS
    Build the coverage CSV that Deploy-RmmAgents.ps1 reads.

.DESCRIPTION
    Run elevated as a domain admin on a machine with the ActiveDirectory module.
    Lists enabled Windows computers that logged on within -Days, pings each one,
    and queries LTService and Huntress* over the remote Service Control Manager.

    RemoteAdmin is OK only when that service query succeeds. Automate and Huntress
    are MISSING when the matching service is absent. Deploy-RmmAgents.ps1 targets
    rows where Online is True, RemoteAdmin is OK, and either agent is MISSING.

.PARAMETER Days
    Include computers whose LastLogonDate is newer than this many days. Default 30.

.PARAMETER OutputPath
    CSV path. Default C:\Support\coverage.csv.

.PARAMETER SearchBase
    Optional OU distinguished name. Default is the whole domain.

.EXAMPLE
    .\Get-RmmAgentCoverage.ps1
    .\Get-RmmAgentCoverage.ps1 -Days 14 -OutputPath 'C:\Support\coverage.csv'
#>
[CmdletBinding()]
param(
    [int]$Days = 30,
    [string]$OutputPath = 'C:\Support\coverage.csv',
    [string]$SearchBase
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-ADComputer -ErrorAction SilentlyContinue)) {
    throw 'Get-ADComputer is not available. Run this on a domain controller or a machine with RSAT ActiveDirectory.'
}

$since = (Get-Date).AddDays(-1 * [math]::Abs($Days))
$adParams = @{
    Filter     = 'Enabled -eq $true'
    Properties = @('LastLogonDate', 'OperatingSystem', 'CanonicalName')
}
if ($SearchBase) { $adParams['SearchBase'] = $SearchBase }

$computers = @(Get-ADComputer @adParams | Where-Object {
    $_.LastLogonDate -and
    $_.LastLogonDate -gt $since -and
    $_.OperatingSystem -like '*Windows*'
})

Write-Host ("Checking {0} computer(s) active in the last {1} day(s)..." -f $computers.Count, $Days)

$out = foreach ($c in $computers) {
    $r = [ordered]@{
        Name        = $c.Name
        OU          = ($c.CanonicalName -replace '/[^/]+$', '')
        OS          = $c.OperatingSystem
        Online      = $false
        RemoteAdmin = ''
        Automate    = ''
        Huntress    = ''
    }
    if (Test-Connection -ComputerName $c.DNSHostName -Count 1 -Quiet -ErrorAction SilentlyContinue) {
        $r.Online = $true
        try {
            $svc = @(Get-Service -ComputerName $c.DNSHostName -ErrorAction Stop |
                Where-Object { $_.Name -eq 'LTService' -or $_.Name -like 'Huntress*' })
            $r.RemoteAdmin = 'OK'
            $lt = @($svc | Where-Object { $_.Name -eq 'LTService' })
            $r.Automate = if ($lt.Count -gt 0) { [string]$lt[0].Status } else { 'MISSING' }
            $r.Huntress = if (@($svc | Where-Object { $_.Name -like 'Huntress*' }).Count -gt 0) { 'Installed' } else { 'MISSING' }
        }
        catch {
            $r.RemoteAdmin = $_.Exception.Message.Split('.')[0]
        }
    }
    [pscustomobject]$r
}

$out = @($out | Sort-Object Online, RemoteAdmin, Name)
$out | Format-Table -AutoSize

$dir = Split-Path -Parent $OutputPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
$out | Export-Csv -LiteralPath $OutputPath -NoTypeInformation
Write-Host ("Wrote {0} ({1} row(s))." -f $OutputPath, $out.Count)
