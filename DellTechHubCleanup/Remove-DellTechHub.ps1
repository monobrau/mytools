#Requires -Version 5.1
<#
.SYNOPSIS
    Scan or remove Dell TechHub (DellTechHub service, TechHub/DTP folders, *TechHub*.dll).

.DESCRIPTION
    SentinelOne often flags techhub.dll. This removes the shared TechHub component
    Dell Update / SupportAssist use for hardware diagnostics. Dell Command | Update
    is left installed. SupportAssist hardware scans will stop working.

.PARAMETER CheckOnly
    Report only.

.PARAMETER Remediate
    Stop TechHub, run ARP uninstall for TechHub / Dell Core Services, delete the
    service and leftover folders/DLLs.

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

function Get-RelatedDellArp {
    Get-UninstallEntries | Where-Object {
        $_.DisplayName -match '(?i)SupportAssist|Dell Command \| Update|Dell Update'
    }
}

function Get-TechHubFolders {
    @(
        (Join-Path $env:ProgramFiles 'Dell\TechHub')
        (Join-Path ${env:ProgramFiles(x86)} 'Dell\TechHub')
        (Join-Path $env:ProgramFiles 'Dell\DTP')
        (Join-Path ${env:ProgramFiles(x86)} 'Dell\DTP')
        (Join-Path $env:ProgramData 'Dell\TechHub')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
}

function Get-TechHubDlls {
    $roots = @(
        (Join-Path $env:ProgramFiles 'Dell')
        (Join-Path ${env:ProgramFiles(x86)} 'Dell')
        (Join-Path $env:ProgramData 'Dell')
    )
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Recurse -Filter '*TechHub*.dll' -ErrorAction SilentlyContinue
    }
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

Write-Output '=== Dell TechHub ==='
if (-not (Test-IsAdmin)) {
    Write-Output 'WARNING: Not elevated. Scan may be incomplete; Apply needs Backstage/SYSTEM.'
}

$svc = Get-Service -Name DellTechHub -ErrorAction SilentlyContinue
$folders = @(Get-TechHubFolders)
$dlls = @(Get-TechHubDlls | Sort-Object FullName -Unique)
$arp = @(Get-TechHubArp)
$related = @(Get-RelatedDellArp)
$procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)TechHub|Dell\.CoreServices' })

if ($svc) {
    Write-Output ("Service DellTechHub: " + [string]$svc.Status + " StartType=" + [string]$svc.StartType)
} else {
    Write-Output 'Service DellTechHub: not found'
}

Write-Output ("ARP TechHub/Core Services: " + [string]$arp.Count)
foreach ($e in $arp) {
    Write-Output ("  " + $e.DisplayName + " " + [string]$e.DisplayVersion)
}

Write-Output ("Related Dell apps (left installed): " + [string]$related.Count)
foreach ($e in $related) {
    Write-Output ("  " + $e.DisplayName + " " + [string]$e.DisplayVersion)
}

Write-Output ("Folders: " + [string]$folders.Count)
foreach ($d in $folders) { Write-Output ("  " + $d) }

Write-Output ("*TechHub*.dll: " + [string]$dlls.Count)
foreach ($f in $dlls) {
    Write-Output ("  " + $f.FullName + " " + [string]$f.Length + " bytes")
}

if ($procs.Count -gt 0) {
    Write-Output 'Processes:'
    $procs | ForEach-Object { Write-Output ("  " + $_.Name + " PID " + [string]$_.Id) }
}

$present = [bool]($svc -or $folders.Count -gt 0 -or $dlls.Count -gt 0 -or $arp.Count -gt 0)
if (-not $present) {
    Write-Output 'Dell TechHub not found.'
    if ($Exit) { exit 0 }
    return
}

if ($CheckOnly -or -not $Remediate) {
    Write-Output 'Re-run with -Remediate to remove TechHub (SupportAssist hardware scans will break).'
    $script:ExitCode = 1
    if ($Exit) { exit $script:ExitCode }
    return
}

Write-Output '=== Removing TechHub ==='
foreach ($p in $procs) {
    Write-Output ("Stop-Process " + $p.Name + " PID " + [string]$p.Id)
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}
if ($svc) {
    Write-Output 'Stop-Service DellTechHub'
    Stop-Service -Name DellTechHub -Force -ErrorAction SilentlyContinue
}

foreach ($e in $arp) { Invoke-ArpUninstall -Entry $e }

$svc2 = Get-Service -Name DellTechHub -ErrorAction SilentlyContinue
if ($svc2) {
    Stop-Service -Name DellTechHub -Force -ErrorAction SilentlyContinue
    Write-Output 'sc.exe delete DellTechHub'
    & "$env:SystemRoot\System32\sc.exe" delete DellTechHub | Out-Null
}

foreach ($im in @('Dell.TechHub.exe', 'Dell.CoreServices.Client.exe')) {
    & "$env:SystemRoot\System32\taskkill.exe" /F /T /IM $im 2>$null | Out-Null
}

foreach ($d in @(Get-TechHubFolders)) {
    Write-Output ("Remove " + $d)
    Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $d) {
        Write-Output ("LOCKED " + $d + " (S1 may have quarantined/locked techhub.dll; rerun after S1 releases it)")
    }
}

foreach ($f in @(Get-TechHubDlls)) {
    Write-Output ("Remove " + $f.FullName)
    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $f.FullName) {
        Write-Output ("LOCKED " + $f.FullName)
    }
}

$svc3 = Get-Service -Name DellTechHub -ErrorAction SilentlyContinue
$folders2 = @(Get-TechHubFolders)
$dlls2 = @(Get-TechHubDlls)
$arp2 = @(Get-TechHubArp)
Write-Output ("Service DellTechHub: " + $(if ($svc3) { [string]$svc3.Status } else { 'gone' }))
Write-Output ("Folders left: " + [string]$folders2.Count)
Write-Output ("DLLs left: " + [string]$dlls2.Count)
Write-Output ("ARP left: " + [string]$arp2.Count)
foreach ($f in $dlls2) { Write-Output ("  " + $f.FullName) }

if ($svc3 -or $folders2.Count -gt 0 -or $dlls2.Count -gt 0 -or $arp2.Count -gt 0) {
    $script:ExitCode = 2
} else {
    $script:ExitCode = 0
    Write-Output 'Dell TechHub removed.'
}

if ($Exit) { exit $script:ExitCode }
