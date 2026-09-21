<#
.SYNOPSIS
    Pull AD computer names and check Webroot leftovers via C$ admin shares.

.DESCRIPTION
    Run from a DC or RSAT box as Domain Admin. Imports computer objects from
    Active Directory (or a name list), then probes each host's administrative
    share for WRSA.exe, ProgramData\WRData, and the GPO uninstall log.

    Unreachable or admin$-blocked hosts are reported; that is not proof Webroot
    is gone. Do not commit live client names or site keys.

.PARAMETER Domain
    AD DNS name. Defaults to the current domain.

.PARAMETER ComputerName
    Check only these names (skips the AD query).

.PARAMETER InputFile
    Text file of computer names, one per line.

.PARAMETER IncludeServers
    Include OS names that contain Server. Default is workstations only
    (plus computers with a blank OperatingSystem).

.PARAMETER SkipPing
    Do not ICMP-ping first. Use when ICMP is blocked but C$ works.

.PARAMETER ThrottleLimit
    Parallel host checks. Default: 20.

.PARAMETER PingMs
    ICMP timeout in milliseconds. Default: 400. Test-Connection is not used
    (it is slow on offline hosts).

.PARAMETER OutputPath
    CSV path. Default: C:\Windows\Temp\Webroot-Fleet-Status.csv

.PARAMETER Exit
    Accepted for ScToolLauncher Commands pastes. Ignored.

.PARAMETER NoExit
    Accepted for ScToolLauncher PowerShell pastes. Ignored.

.EXAMPLE
    .\Get-WebrootFleetStatus.ps1
    .\Get-WebrootFleetStatus.ps1 -Domain contoso.com
    .\Get-WebrootFleetStatus.ps1 -ComputerName PC01,PC02
#>

[CmdletBinding()]
param(
    [string]$Domain,

    [string[]]$ComputerName,

    [string]$InputFile,

    [switch]$IncludeServers,

    [switch]$SkipPing,

    [int]$ThrottleLimit = 20,

    [int]$PingMs = 400,

    [string]$OutputPath = 'C:\Windows\Temp\Webroot-Fleet-Status.csv',

    [switch]$Exit,

    [switch]$NoExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$null = $Exit
$null = $NoExit

$names = New-Object System.Collections.Generic.List[string]
$osByName = @{}

if ($ComputerName) {
    foreach ($n in $ComputerName) {
        $t = ([string]$n).Trim()
        if ($t) { [void]$names.Add($t) }
    }
}

if ($InputFile) {
    if (-not (Test-Path -LiteralPath $InputFile)) {
        throw "Input file not found: $InputFile"
    }
    Get-Content -LiteralPath $InputFile | ForEach-Object {
        $t = $_.Trim()
        if ($t -and $t -notmatch '^\s*#') { [void]$names.Add($t) }
    }
}

if ($names.Count -eq 0) {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw "ActiveDirectory module is missing. Install RSAT, or pass -ComputerName / -InputFile."
    }
    Import-Module ActiveDirectory -ErrorAction Stop
    if (-not $Domain) {
        $Domain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name
    }
    Write-Output ("Loading computers from AD domain $Domain ...")
    $comps = @(Get-ADComputer -Server $Domain -Filter { Enabled -eq $true } -Properties DNSHostName, OperatingSystem)
    foreach ($c in $comps) {
        $os = [string]$c.OperatingSystem
        if (-not $IncludeServers -and $os -and $os -match 'Server') { continue }
        $n = [string]$c.DNSHostName
        if (-not $n) { $n = [string]$c.Name }
        if (-not $n) { continue }
        [void]$names.Add($n)
        $osByName[$n] = $os
    }
}

$unique = @($names | Select-Object -Unique)
$total = $unique.Count
if ($ThrottleLimit -lt 1) { $ThrottleLimit = 1 }
Write-Output ("Checking $total host(s) via C`$ (parallel $ThrottleLimit, ping ${PingMs}ms) ...")

$work = {
    param($HostName, $OperatingSystem, $SkipPing, $PingMs)

    function Test-FastPing {
        param([string]$Name, [int]$TimeoutMs)
        try {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $reply = $ping.Send($Name, $TimeoutMs)
            return ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
        }
        catch {
            return $false
        }
    }
    function Test-SharePath {
        param([string]$Unc)
        try {
            return [bool](Test-Path -LiteralPath $Unc -ErrorAction Stop)
        }
        catch {
            return $false
        }
    }

    $reachable = $false
    $share = $false
    $wrsa = $false
    $wrdata = $false
    $gpoLog = $false
    $note = ''

    if (-not $SkipPing) {
        $reachable = Test-FastPing -Name $HostName -TimeoutMs $PingMs
        if (-not $reachable) {
            return [pscustomobject]@{
                Computer        = $HostName
                OperatingSystem = $OperatingSystem
                Reachable       = $false
                AdminShare      = $false
                WrsaPresent     = $false
                WrDataPresent   = $false
                GpoLog          = $false
                Note            = 'no ping'
            }
        }
    }

    $cRoot = "\\$HostName\C$"
    $share = Test-SharePath -Unc "$cRoot\Windows"
    if (-not $share) {
        return [pscustomobject]@{
            Computer        = $HostName
            OperatingSystem = $OperatingSystem
            Reachable       = [bool]$SkipPing
            AdminShare      = $false
            WrsaPresent     = $false
            WrDataPresent   = $false
            GpoLog          = $false
            Note            = 'admin share failed'
        }
    }

    $wrsa = (Test-SharePath -Unc "$cRoot\Program Files (x86)\Webroot\WRSA.exe") -or
    (Test-SharePath -Unc "$cRoot\Program Files\Webroot\WRSA.exe")
    $wrdata = Test-SharePath -Unc "$cRoot\ProgramData\WRData"
    $gpoLog = Test-SharePath -Unc "$cRoot\Windows\Temp\Webroot-GPO-Uninstall.log"

    return [pscustomobject]@{
        Computer        = $HostName
        OperatingSystem = $OperatingSystem
        Reachable       = $true
        AdminShare      = $true
        WrsaPresent     = $wrsa
        WrDataPresent   = $wrdata
        GpoLog          = $gpoLog
        Note            = ''
    }
}

$pool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit)
$pool.Open()
$jobs = New-Object System.Collections.Generic.List[object]
foreach ($hostName in $unique) {
    $os = ''
    if ($osByName.ContainsKey($hostName)) { $os = $osByName[$hostName] }
    $ps = [powershell]::Create().AddScript($work).AddArgument($hostName).AddArgument($os).AddArgument([bool]$SkipPing).AddArgument($PingMs)
    $ps.RunspacePool = $pool
    $jobs.Add([pscustomobject]@{ Pipe = $ps; Handle = $ps.BeginInvoke() })
}

$rows = New-Object System.Collections.Generic.List[object]
$done = 0
while ($jobs.Count -gt 0) {
    $left = New-Object System.Collections.Generic.List[object]
    foreach ($j in $jobs) {
        if ($j.Handle.IsCompleted) {
            try {
                $result = $j.Pipe.EndInvoke($j.Handle)
                if ($null -ne $result) {
                    foreach ($r in $result) {
                        if ($null -ne $r) { [void]$rows.Add($r) }
                    }
                }
            }
            catch {
                $rows.Add([pscustomobject]@{
                        Computer        = '?'
                        OperatingSystem = ''
                        Reachable       = $false
                        AdminShare      = $false
                        WrsaPresent     = $false
                        WrDataPresent   = $false
                        GpoLog          = $false
                        Note            = $_.Exception.Message
                    })
            }
            finally {
                $j.Pipe.Dispose()
            }
            $done++
            Write-Progress -Activity 'Webroot fleet check' -Status "$done / $total" -PercentComplete (($done / [math]::Max($total, 1)) * 100)
        }
        else {
            $left.Add($j)
        }
    }
    $jobs = $left
    if ($jobs.Count -gt 0) { Start-Sleep -Milliseconds 50 }
}

$pool.Close()
$pool.Dispose()
Write-Progress -Activity 'Webroot fleet check' -Completed

# PS 5.1: @($List[object] of PSCustomObject) throws "Argument types do not match"
if ($rows.Count -gt 0) {
    $out = $rows.ToArray()
}
else {
    $out = @()
}
$present = @($out | Where-Object { $_.WrsaPresent -or $_.WrDataPresent }).Count
$clear = @($out | Where-Object { $_.AdminShare -and -not $_.WrsaPresent -and -not $_.WrDataPresent }).Count
$down = @($out | Where-Object { -not $_.AdminShare }).Count

Write-Output ''
Write-Output "=== Webroot fleet status ==="
Write-Output ("Hosts: $total  Present: $present  Clear (share OK): $clear  Unreachable/no share: $down")
if ($out.Count -gt 0) {
    $out | Sort-Object WrsaPresent, AdminShare, Computer -Descending | Format-Table -AutoSize
}
try {
    $dir = Split-Path -Parent $OutputPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    if ($out.Count -gt 0) {
        $out | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Output ("CSV: $OutputPath")
    }
    else {
        Write-Warning 'No host results to export.'
    }
}
catch {
    Write-Warning ("CSV not written: $($_.Exception.Message)")
}
