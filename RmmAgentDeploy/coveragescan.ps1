#Requires -Version 5.1
<#
.SYNOPSIS
    Huntress-only coverage scan. Parallel ping, then a short DCOM service check.

.DESCRIPTION
    Run elevated as a domain admin on a machine with the ActiveDirectory module.
    Lists enabled Windows computers that logged on within -Days, pings them in
    parallel, and queries Huntress* services over DCOM for hosts that answer.

    RemoteAdmin is OK only when that service query succeeds. Huntress is MISSING
    when no Huntress* service is present.

.PARAMETER Days
    Include computers whose LastLogonDate is newer than this many days. Default 30.

.PARAMETER OutputPath
    CSV path. Default C:\Support\huntress-coverage.csv.

.PARAMETER SearchBase
    Optional OU distinguished name. Default is the whole domain.

.EXAMPLE
    .\coveragescan.ps1
    .\coveragescan.ps1 -Days 14 -OutputPath 'C:\Support\huntress-coverage.csv'
#>
[CmdletBinding()]
param(
    [int]$Days = 30,
    [string]$OutputPath = 'C:\Support\huntress-coverage.csv',
    [string]$SearchBase,
    [int]$PingTimeoutMs = 400,
    [int]$RpcTimeoutSec = 8,
    [int]$Throttle = 25
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

$pings = New-Object System.Collections.Generic.List[object]
$tasks = New-Object 'System.Collections.Generic.List[System.Threading.Tasks.Task]'
foreach ($c in $computers) {
    if (-not $c.DNSHostName) { continue }
    $ping = New-Object System.Net.NetworkInformation.Ping
    try {
        $task = $ping.SendPingAsync([string]$c.DNSHostName, $PingTimeoutMs)
    }
    catch {
        $ping.Dispose()
        continue
    }
    if (-not $task) {
        $ping.Dispose()
        continue
    }
    [void]$tasks.Add($task)
    [void]$pings.Add([pscustomobject]@{
        Computer = $c
        Ping     = $ping
        PingTask = $task
    })
}

if ($tasks.Count -gt 0) {
    [void][System.Threading.Tasks.Task]::WaitAll($tasks.ToArray(), 20000)
}

$online = New-Object System.Collections.Generic.List[object]
foreach ($item in $pings) {
    $task = $item.PingTask
    $up = $false
    if ($task.IsCompleted -and -not $task.IsFaulted -and -not $task.IsCanceled) {
        $up = $task.Result.Status -eq [System.Net.NetworkInformation.IPStatus]::Success
    }
    $item.Ping.Dispose()
    if ($up) { [void]$online.Add($item.Computer) }
}

Write-Host ("{0} host(s) answered ping. Querying Huntress services..." -f $online.Count)

$check = {
    param($ComputerName, $TimeoutSec)
    $ErrorActionPreference = 'Stop'
    try {
        $opt = New-CimSessionOption -Protocol Dcom
        $session = New-CimSession -ComputerName $ComputerName -SessionOption $opt -OperationTimeoutSec $TimeoutSec -ErrorAction Stop
        try {
            @(Get-CimInstance -CimSession $session -ClassName Win32_Service -Filter "Name LIKE 'Huntress%'" -OperationTimeoutSec $TimeoutSec -ErrorAction Stop |
                Select-Object -ExpandProperty Name)
        }
        finally {
            Remove-CimSession $session -ErrorAction SilentlyContinue
        }
    }
    catch {
        # Return a short marker string the parent maps into RemoteAdmin.
        $msg = $_.Exception.Message
        if ($msg -match 'RPC server is unavailable') { 'ERR:RPC unavailable' }
        elseif ($msg -match '(?i)timed?\s*out') { 'ERR:timeout' }
        elseif ($msg -match 'Access is denied') { 'ERR:access denied' }
        else {
            $short = ($msg -split '[:.]')[-1].Trim().Trim('"')
            if (-not $short) { $short = 'remote query failed' }
            "ERR:$short"
        }
    }
}

$pool = [runspacefactory]::CreateRunspacePool(1, $Throttle)
$pool.Open()
$work = New-Object System.Collections.Generic.List[object]
foreach ($c in $online) {
    $ps = [powershell]::Create().AddScript($check).AddArgument([string]$c.DNSHostName).AddArgument($RpcTimeoutSec)
    $ps.RunspacePool = $pool
    [void]$work.Add([pscustomobject]@{
        Computer   = $c
        PowerShell = $ps
        Handle     = $ps.BeginInvoke()
        Started    = Get-Date
    })
}

$svcResult = @{}
$pending = New-Object System.Collections.Generic.List[object]
foreach ($w in $work) { [void]$pending.Add($w) }

while ($pending.Count -gt 0) {
    $still = New-Object System.Collections.Generic.List[object]
    foreach ($w in $pending) {
        $done = $w.Handle.IsCompleted
        $late = ((Get-Date) - $w.Started).TotalSeconds -gt ($RpcTimeoutSec + 4)
        if (-not $done -and -not $late) {
            [void]$still.Add($w)
            continue
        }
        if ($done) {
            try {
                $raw = @($w.PowerShell.EndInvoke($w.Handle))
                $err = @($raw | Where-Object { $_ -is [string] -and $_.StartsWith('ERR:') })
                if ($err.Count -gt 0) {
                    $svcResult[$w.Computer.Name] = $err[0]
                }
                else {
                    $svcResult[$w.Computer.Name] = @($raw | Where-Object { $_ -and $_ -notlike 'ERR:*' })
                }
            }
            catch {
                $msg = $_.Exception.Message
                if ($msg -match 'RPC server is unavailable') { $svcResult[$w.Computer.Name] = 'ERR:RPC unavailable' }
                elseif ($msg -match '(?i)timed?\s*out') { $svcResult[$w.Computer.Name] = 'ERR:timeout' }
                else { $svcResult[$w.Computer.Name] = 'ERR:remote query failed' }
            }
        }
        else {
            $svcResult[$w.Computer.Name] = 'ERR:timeout'
            try { $w.PowerShell.Stop() } catch {}
        }
        $w.PowerShell.Dispose()
    }
    $pending = $still
    if ($pending.Count -gt 0) { Start-Sleep -Milliseconds 200 }
}

$pool.Close()
$pool.Dispose()

$onlineNames = @{}
foreach ($c in $online) { $onlineNames[$c.Name] = $true }

$out = foreach ($c in $computers) {
    $isOnline = [bool]$onlineNames.ContainsKey($c.Name)
    $r = [ordered]@{
        Name        = $c.Name
        OU          = ($c.CanonicalName -replace '/[^/]+$', '')
        OS          = $c.OperatingSystem
        Online      = $isOnline
        RemoteAdmin = ''
        Huntress    = ''
    }
    if ($isOnline) {
        if (-not $svcResult.ContainsKey($c.Name)) {
            $r.RemoteAdmin = 'timeout'
        }
        else {
            $hit = $svcResult[$c.Name]
            if ($hit -is [string] -and $hit.StartsWith('ERR:')) {
                $r.RemoteAdmin = $hit.Substring(4)
            }
            else {
                $r.RemoteAdmin = 'OK'
                $r.Huntress = if (@($hit | Where-Object { $_ }).Count -gt 0) { 'Installed' } else { 'MISSING' }
            }
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
