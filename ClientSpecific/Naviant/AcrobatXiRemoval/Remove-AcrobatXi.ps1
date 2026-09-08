#Requires -Version 5.1
<#
.SYNOPSIS
    Detect Adobe Acrobat XI (EOL) and optionally uninstall it; report Foxit PDF Reader / Editor.

.DESCRIPTION
    Client-specific EOL removal for Acrobat XI Standard/Pro (11.x). Does not remove
    Acrobat DC, Reader, or current perpetual/subscription Acrobat.

    Scan (default / -CheckOnly): report Acrobat XI and Foxit status only.
    -Uninstall / -Remediate: remove Acrobat XI. Skips uninstall if Foxit
    Reader/Editor is not found, unless -Force is also set.

    This script cannot detect a business dependency on Acrobat XI. Scan first;
    do not run -Uninstall on hosts that must keep XI.

.PARAMETER CheckOnly
    Report only; make no changes.

.PARAMETER Uninstall
    Silently uninstall detected Acrobat XI products.

.PARAMETER Remediate
    Same as -Uninstall (ScToolLauncher Apply mode).

.PARAMETER Force
    Uninstall Acrobat XI even when Foxit Reader/Editor is not installed.

.PARAMETER Exit
    Call exit with a status code (ScreenConnect Commands). Omit in Backstage.
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Uninstall,
    [switch]$Remediate,
    [switch]$Force,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$script:ExitCode = 0

function Write-Section([string]$Message) {
    Write-Output "=== $Message ==="
}

function Get-UninstallEntries {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($p in $paths) {
        Get-ItemProperty -Path $p -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName }
    }
}

function Test-IsAcrobatXi {
    param($Entry)
    $name = [string]$Entry.DisplayName
    $ver = [string]$Entry.DisplayVersion
    if ($name -match 'Reader') { return $false }
    if ($name -notmatch 'Adobe Acrobat') { return $false }
    if ($name -match 'DC|2020|2021|2022|2023|2024|2025|2026') { return $false }
    if ($name -match '\bXI\b|\b11\b') { return $true }
    if ($ver -match '^11\.') { return $true }
    return $false
}

function Test-IsFoxitReader {
    param($Entry)
    $name = [string]$Entry.DisplayName
    return [bool]($name -match 'Foxit' -and $name -match 'Reader' -and $name -notmatch 'Editor|Phantom')
}

function Test-IsFoxitEditor {
    param($Entry)
    $name = [string]$Entry.DisplayName
    return [bool]($name -match 'Foxit' -and $name -match 'Editor|PhantomPDF|Phantom PDF')
}

function Format-ProductLine {
    param($Entry)
    $ver = if ($Entry.DisplayVersion) { $Entry.DisplayVersion } else { '?' }
    '{0} ({1})' -f $Entry.DisplayName, $ver
}

function Stop-AcrobatXiProcesses {
    foreach ($n in @('Acrobat', 'AcroCEF', 'AdobeCollabSync')) {
        Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Uninstall-AcrobatXiProduct {
    param($Entry)
    $name = [string]$Entry.DisplayName
    $guid = [string]$Entry.PSChildName
    Write-Output ("Uninstalling: {0}" -f $name)
    if ($guid -match '^\{[0-9A-Fa-f-]+\}$') {
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $guid, '/qn', '/norestart') -Wait -PassThru -NoNewWindow
        Write-Output ("msiexec /x {0} exit {1}" -f $guid, $p.ExitCode)
        return ($p.ExitCode -eq 0 -or $p.ExitCode -eq 1605 -or $p.ExitCode -eq 3010)
    }
    $us = [string]$Entry.UninstallString
    if ([string]::IsNullOrWhiteSpace($us)) {
        Write-Output 'ERROR: No ProductCode or UninstallString.'
        return $false
    }
    Write-Output ("UninstallString (not msiexec GUID): {0}" -f $us)
    Write-Output 'ERROR: Non-MSI uninstall is not automated. Record as exception.'
    return $false
}

$all = @(Get-UninstallEntries)
$xi = @($all | Where-Object { Test-IsAcrobatXi $_ } | Sort-Object DisplayName -Unique)
$foxitReader = @($all | Where-Object { Test-IsFoxitReader $_ } | Sort-Object DisplayName -Unique)
$foxitEditor = @($all | Where-Object { Test-IsFoxitEditor $_ } | Sort-Object DisplayName -Unique)
$hasFoxit = ($foxitReader.Count -gt 0 -or $foxitEditor.Count -gt 0)

Write-Section 'Acrobat XI + Foxit evidence'
Write-Output ("ComputerName: {0}" -f $env:COMPUTERNAME)
Write-Output ("AcrobatXiPresent: {0}" -f $(if ($xi.Count -gt 0) { 'Yes' } else { 'No' }))
if ($xi.Count -gt 0) {
    foreach ($e in $xi) { Write-Output ("AcrobatXiProduct: {0}" -f (Format-ProductLine $e)) }
} else {
    Write-Output 'AcrobatXiProduct: (none)'
}
if ($foxitReader.Count -gt 0) {
    foreach ($e in $foxitReader) { Write-Output ("FoxitReader: {0}" -f (Format-ProductLine $e)) }
} else {
    Write-Output 'FoxitReader: (none)'
}
if ($foxitEditor.Count -gt 0) {
    foreach ($e in $foxitEditor) { Write-Output ("FoxitEditor: {0}" -f (Format-ProductLine $e)) }
} else {
    Write-Output 'FoxitEditor: (none)'
}

$doUninstall = ($Uninstall -or $Remediate) -and -not $CheckOnly

if (-not $doUninstall) {
    if ($xi.Count -gt 0) {
        Write-Output 'Action: CheckOnly'
        Write-Output 'Result: Acrobat XI present. Re-run with -Uninstall to remove (skipped here if Foxit is missing unless -Force).'
        Write-Output 'Exception: If this host has a documented Acrobat XI business dependency, do not uninstall.'
        $script:ExitCode = 1
    } else {
        Write-Output 'Action: CheckOnly'
        Write-Output 'Result: Acrobat XI not installed.'
        if (-not $hasFoxit) {
            Write-Output 'Exception: No Foxit Reader or Editor detected.'
        }
        $script:ExitCode = 0
    }
    if ($Exit) { exit $script:ExitCode }
    return
}

if ($xi.Count -eq 0) {
    Write-Output 'Action: Uninstall'
    Write-Output 'Result: Nothing to remove (Acrobat XI not installed).'
    if (-not $hasFoxit) {
        Write-Output 'Exception: No Foxit Reader or Editor detected.'
    }
    if ($Exit) { exit 0 }
    return
}

if (-not $hasFoxit -and -not $Force) {
    Write-Output 'Action: Skipped'
    Write-Output 'Result: Acrobat XI left installed because Foxit Reader/Editor was not found. Use -Force to uninstall anyway, or install Foxit first.'
    Write-Output 'Exception: Missing Foxit; Acrobat XI not removed.'
    $script:ExitCode = 3
    if ($Exit) { exit $script:ExitCode }
    return
}

if (-not $hasFoxit -and $Force) {
    Write-Output 'Warning: -Force uninstall without Foxit Reader/Editor.'
}

Write-Output 'Action: Uninstall'
Stop-AcrobatXiProcesses
$failed = $false
foreach ($e in $xi) {
    if (-not (Uninstall-AcrobatXiProduct $e)) { $failed = $true }
}

$after = @(Get-UninstallEntries | Where-Object { Test-IsAcrobatXi $_ })
if ($after.Count -gt 0) {
    foreach ($e in $after) { Write-Output ("StillPresent: {0}" -f (Format-ProductLine $e)) }
    Write-Output 'Result: Uninstall incomplete.'
    $script:ExitCode = 2
} elseif ($failed) {
    Write-Output 'Result: Uninstall reported failure; Acrobat XI no longer in Uninstall registry.'
    $script:ExitCode = 0
} else {
    Write-Output 'Result: Acrobat XI removed.'
    $script:ExitCode = 0
}

if ($Exit) { exit $script:ExitCode }
