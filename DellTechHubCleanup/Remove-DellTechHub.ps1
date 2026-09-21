#Requires -Version 5.1
<#
.SYNOPSIS
    Scan or remove Dell TechHub, DTP, and SupportAssist.

.DESCRIPTION
    SentinelOne often flags techhub.dll. TechHub/DTP are SupportAssist's
    diagnostics stack, so Apply removes those plus SupportAssist itself.
    Dell Command | Update and the OS Recovery plugin stay installed.

.PARAMETER CheckOnly
    Report only.

.PARAMETER Remediate
    Stop TechHub/DTP/SupportAssist, uninstall ARP entries, delete leftover folders.

.PARAMETER Exit
    Call exit with a status code (ScreenConnect Commands).
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Remediate,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'
$script:ExitCode = 0

function Test-IsAdmin {
    $p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RemovalRoots {
    @(
        (Join-Path $env:ProgramFiles 'Dell\TechHub')
        (Join-Path ${env:ProgramFiles(x86)} 'Dell\TechHub')
        (Join-Path $env:ProgramFiles 'Dell\DTP')
        (Join-Path ${env:ProgramFiles(x86)} 'Dell\DTP')
        (Join-Path $env:ProgramData 'Dell\TechHub')
        (Join-Path $env:ProgramFiles 'Dell\SupportAssist')
        (Join-Path ${env:ProgramFiles(x86)} 'Dell\SupportAssist')
        (Join-Path $env:ProgramFiles 'Dell\SupportAssistAgent')
        (Join-Path ${env:ProgramFiles(x86)} 'Dell\SupportAssistAgent')
        (Join-Path $env:ProgramData 'Dell\SupportAssist')
    )
}

function Test-UnderRemovalRoot {
    param([string]$Path)
    if (-not $Path) { return $false }
    $clean = ($Path -replace '^"', '' -replace '"$', '')
    foreach ($root in Get-RemovalRoots) {
        if ($clean.Length -ge $root.Length -and $clean.Substring(0, $root.Length) -ieq $root) {
            return $true
        }
    }
    return $false
}

function Get-UninstallEntries {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
}

function Get-TechHubArp {
    Get-UninstallEntries | Where-Object {
        $_.DisplayName -match '(?i)TechHub|Dell Core Services'
    }
}

function Get-SupportAssistArp {
    Get-UninstallEntries | Where-Object {
        $_.DisplayName -match '(?i)SupportAssist' -and
        $_.DisplayName -notmatch '(?i)OS Recovery|SARemediation|Remediation'
    }
}

function Get-KeptDellArp {
    Get-UninstallEntries | Where-Object {
        $_.DisplayName -match '(?i)Dell Command \| Update|(?<!SupportAssist )Dell Update|OS Recovery'
    }
}

function Get-RemovalFolders {
    Get-RemovalRoots | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
}

function Get-RemovalProcesses {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '(?i)TechHub|Dell\.CoreServices|SupportAssist' -or (Test-UnderRemovalRoot $_.ExecutablePath)
    }
}

function Get-RemovalServices {
    @(Get-Service -Name '*TechHub*','*SupportAssist*' -ErrorAction SilentlyContinue) + @(
        Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object {
            Test-UnderRemovalRoot $_.PathName
        } | ForEach-Object { Get-Service -Name $_.Name -ErrorAction SilentlyContinue }
    ) | Where-Object { $_ } | Sort-Object Name -Unique
}

function Invoke-ArpUninstall {
    param($Entry)
    $name = [string]$Entry.DisplayName
    $raw = [string]$Entry.QuietUninstallString
    if (-not $raw) { $raw = [string]$Entry.UninstallString }
    if (-not $raw) {
        Write-Output ("No uninstall string: " + $name)
        return
    }
    Write-Output ("Uninstalling " + $name)
    if ($raw -match '(?i)msiexec' -and $raw -match '\{[0-9A-Fa-f-]{36}\}') {
        $guid = $Matches[0]
        $p = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru
        Write-Output ("msiexec /x $guid exit " + [string]$p.ExitCode)
        return
    }
    $exe = $null
    $arg = ''
    if ($raw -match '^"([^"]+)"\s*(.*)$') {
        $exe = $Matches[1]
        $arg = [string]$Matches[2]
    } else {
        $parts = $raw.Trim() -split '\s+', 2
        $exe = $parts[0]
        if ($parts.Count -gt 1) { $arg = $parts[1] }
    }
    if (-not $Entry.QuietUninstallString -and $arg -notmatch '(?i)(/S\b|/quiet|/qn|/silent)') {
        $arg = ($arg + ' /S /quiet /norestart').Trim()
    }
    if (-not (Test-Path -LiteralPath $exe)) {
        Write-Output ("Uninstall exe missing: " + $exe)
        return
    }
    $p = Start-Process -FilePath $exe -ArgumentList $arg -Wait -PassThru -ErrorAction SilentlyContinue
    if ($p) { Write-Output ("Uninstall exit " + [string]$p.ExitCode + " " + $name) }
}

function Stop-RemovalHolders {
    foreach ($s in @(Get-RemovalServices)) {
        Write-Output ("Stop-Service " + $s.Name)
        Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue
    }
    foreach ($p in @(Get-RemovalProcesses)) {
        Write-Output ("taskkill PID " + [string]$p.ProcessId + " " + $p.Name)
        & "$env:SystemRoot\System32\taskkill.exe" /F /T /PID $p.ProcessId 2>$null | Out-Null
    }
    foreach ($im in @(
            'Dell.TechHub.exe',
            'Dell.CoreServices.Client.exe',
            'Dell.TechHub.Instrumentation.SubAgent.exe',
            'Dell.TechHub.Instrumentation.UserProcess.exe',
            'Dell.TechHub.Analytics.SubAgent.exe',
            'Dell.TechHub.DataManager.SubAgent.exe',
            'Dell.TechHub.Diagnostics.SubAgent.exe',
            'SupportAssistAgent.exe',
            'SupportAssist.exe'
        )) {
        & "$env:SystemRoot\System32\taskkill.exe" /F /T /IM $im 2>$null | Out-Null
    }
}

Write-Output '=== Dell TechHub / SupportAssist ==='
if (-not (Test-IsAdmin)) {
    Write-Output 'WARNING: Not elevated. Scan may be incomplete; Apply needs elevated PowerShell/SYSTEM.'
}

$svcList = @(Get-RemovalServices)
$folders = @(Get-RemovalFolders)
$arpTh = @(Get-TechHubArp)
$arpSa = @(Get-SupportAssistArp)
$kept = @(Get-KeptDellArp)
$procs = @(Get-RemovalProcesses)

if ($svcList.Count -eq 0) {
    Write-Output 'Target services: none'
} else {
    Write-Output ("Target services: " + [string]$svcList.Count)
    foreach ($s in $svcList) {
        Write-Output ("  " + $s.Name + " " + [string]$s.Status)
    }
}

Write-Output ("ARP TechHub/Core Services: " + [string]$arpTh.Count)
foreach ($e in $arpTh) {
    Write-Output ("  " + $e.DisplayName + " " + [string]$e.DisplayVersion)
}

Write-Output ("ARP SupportAssist (will uninstall): " + [string]$arpSa.Count)
foreach ($e in $arpSa) {
    Write-Output ("  " + $e.DisplayName + " " + [string]$e.DisplayVersion)
}

Write-Output ("Dell Update / OS Recovery (kept): " + [string]$kept.Count)
foreach ($e in $kept) {
    Write-Output ("  " + $e.DisplayName + " " + [string]$e.DisplayVersion)
}

Write-Output ("Target folders: " + [string]$folders.Count)
foreach ($d in $folders) { Write-Output ("  " + $d) }

if ($procs.Count -gt 0) {
    Write-Output ("Processes: " + [string]$procs.Count)
    $procs | ForEach-Object { Write-Output ("  " + $_.Name + " PID " + [string]$_.ProcessId) }
}

$present = [bool]($svcList.Count -gt 0 -or $folders.Count -gt 0 -or $arpTh.Count -gt 0 -or $arpSa.Count -gt 0)
if (-not $present) {
    Write-Output 'TechHub, DTP, and SupportAssist not found.'
    if ($Exit) { exit 0 }
    return
}

if ($CheckOnly -or -not $Remediate) {
    Write-Output 'Re-run with -Remediate to remove TechHub, DTP, and SupportAssist. Dell Update stays.'
    $script:ExitCode = 1
    if ($Exit) { exit $script:ExitCode }
    return
}

Write-Output '=== Removing TechHub / DTP / SupportAssist ==='
Stop-RemovalHolders
foreach ($e in @($arpTh + $arpSa)) { Invoke-ArpUninstall -Entry $e }
Stop-RemovalHolders

foreach ($s in @(Get-RemovalServices)) {
    Write-Output ("sc.exe delete " + $s.Name)
    & "$env:SystemRoot\System32\sc.exe" delete $s.Name | Out-Null
}

foreach ($d in @(Get-RemovalFolders)) {
    Write-Output ("Remove " + $d)
    Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $d) {
        $left = @(Get-RemovalProcesses | Where-Object { Test-UnderRemovalRoot $_.ExecutablePath })
        Write-Output ("LOCKED " + $d)
        if ($left.Count -gt 0) {
            $left | ForEach-Object { Write-Output ("  still running " + $_.Name + " PID " + [string]$_.ProcessId) }
            Write-Output 'Reboot, then Apply again.'
        }
    }
}

$svc3 = @(Get-RemovalServices)
$folders2 = @(Get-RemovalFolders)
$arpTh2 = @(Get-TechHubArp)
$arpSa2 = @(Get-SupportAssistArp)
Write-Output ("Services left: " + [string]$svc3.Count)
Write-Output ("Folders left: " + [string]$folders2.Count)
foreach ($d in $folders2) { Write-Output ("  " + $d) }
Write-Output ("ARP TechHub left: " + [string]$arpTh2.Count)
Write-Output ("ARP SupportAssist left: " + [string]$arpSa2.Count)

if ($svc3.Count -gt 0 -or $folders2.Count -gt 0 -or $arpTh2.Count -gt 0 -or $arpSa2.Count -gt 0) {
    $script:ExitCode = 2
} else {
    $script:ExitCode = 0
    Write-Output 'TechHub, DTP, and SupportAssist removed. Dell Update was left installed.'
}

if ($Exit) { exit $script:ExitCode }
