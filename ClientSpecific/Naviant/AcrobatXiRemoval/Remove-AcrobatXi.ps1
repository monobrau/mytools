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

    Uninstall waits for the Windows Installer mutex, retries MSI 1618, and
    uses silent msiexec with REBOOT=ReallySuppress and Restart Manager off.
    A verbose log is written to %SystemRoot%\Temp\AcrobatXi-uninstall.log.
    Commands output is flushed so ScreenConnect is not blank during msiexec.

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
$script:MsiLogPath = Join-Path $env:SystemRoot 'Temp\AcrobatXi-uninstall.log'

function Write-Line([string]$Message) {
    Write-Host $Message
    try { [Console]::Out.Flush() } catch { }
    try { [Console]::Error.Flush() } catch { }
}

function Write-Section([string]$Message) {
    Write-Line "=== $Message ==="
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

function Test-MsiMutexFree {
    $m = $null
    try {
        $m = [System.Threading.Mutex]::new($false, 'Global\_MSIExecute')
        $got = $m.WaitOne(0)
        if ($got) {
            try { [void]$m.ReleaseMutex() } catch { }
            return $true
        }
        return $false
    } catch {
        return $true
    } finally {
        if ($m) { $m.Dispose() }
    }
}

function Wait-WindowsInstaller {
    param([int]$TimeoutSeconds = 180)
    if (Test-MsiMutexFree) {
        Write-Line 'WindowsInstaller: ready'
        return $true
    }
    Write-Line 'WindowsInstaller: busy — waiting (do not start another uninstall)'
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 15
        if (Test-MsiMutexFree) {
            Write-Line 'WindowsInstaller: ready'
            return $true
        }
        $left = [Math]::Max(0, [int]($deadline - (Get-Date)).TotalSeconds)
        Write-Line ("WindowsInstaller: still busy ({0}s left)" -f $left)
    }
    Write-Line 'WindowsInstaller: still busy after wait'
    return $false
}

function Stop-AcrobatXiProcesses {
    foreach ($n in @('Acrobat', 'AcroCEF', 'AcroDist', 'AcroBroker', 'AdobeCollabSync', 'AdobeARM')) {
        Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Test-MsiexecSuccess([int]$Code) {
    return ($Code -eq 0 -or $Code -eq 1605 -or $Code -eq 3010)
}

function Uninstall-AcrobatXiProduct {
    param($Entry)
    $name = [string]$Entry.DisplayName
    $guid = [string]$Entry.PSChildName
    Write-Line ("Uninstalling: {0}" -f $name)
    if ($guid -notmatch '^\{[0-9A-Fa-f-]+\}$') {
        $us = [string]$Entry.UninstallString
        if ([string]::IsNullOrWhiteSpace($us)) {
            Write-Line 'ERROR: No ProductCode or UninstallString.'
            return $false
        }
        Write-Line ("UninstallString (not msiexec GUID): {0}" -f $us)
        Write-Line 'ERROR: Non-MSI uninstall is not automated. Record as exception.'
        return $false
    }

    Write-Line ("ProductCode: {0}" -f $guid)
    Write-Line ("MsiexecLog: {0}" -f $script:MsiLogPath)
    [void](Wait-WindowsInstaller -TimeoutSeconds 180)
    Stop-AcrobatXiProcesses

    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Write-Line ("msiexec /x attempt {0}/{1} — this can take 10+ minutes; do not rerun or Force" -f $attempt, $maxAttempts)
        $argList = @(
            '/x', $guid, '/qn', '/norestart',
            'REBOOT=ReallySuppress',
            'MSIRESTARTMANAGERCONTROL=Disable',
            '/L*v', $script:MsiLogPath
        )
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $argList -Wait -PassThru -NoNewWindow
        $code = [int]$p.ExitCode
        Write-Line ("msiexec /x {0} exit {1}" -f $guid, $code)
        if (Test-MsiexecSuccess $code) { return $true }
        if ($code -eq 1618 -and $attempt -lt $maxAttempts) {
            Write-Line 'msiexec 1618 (another install in progress) — waiting to retry'
            [void](Wait-WindowsInstaller -TimeoutSeconds 180)
            continue
        }
        return $false
    }
    return $false
}

$all = @(Get-UninstallEntries)
$xi = @($all | Where-Object { Test-IsAcrobatXi $_ } | Sort-Object DisplayName -Unique)
$foxitReader = @($all | Where-Object { Test-IsFoxitReader $_ } | Sort-Object DisplayName -Unique)
$foxitEditor = @($all | Where-Object { Test-IsFoxitEditor $_ } | Sort-Object DisplayName -Unique)
$hasFoxit = ($foxitReader.Count -gt 0 -or $foxitEditor.Count -gt 0)

Write-Section 'Acrobat XI + Foxit evidence'
Write-Line ("ComputerName: {0}" -f $env:COMPUTERNAME)
Write-Line ("AcrobatXiPresent: {0}" -f $(if ($xi.Count -gt 0) { 'Yes' } else { 'No' }))
if ($xi.Count -gt 0) {
    foreach ($e in $xi) { Write-Line ("AcrobatXiProduct: {0}" -f (Format-ProductLine $e)) }
} else {
    Write-Line 'AcrobatXiProduct: (none)'
}
if ($foxitReader.Count -gt 0) {
    foreach ($e in $foxitReader) { Write-Line ("FoxitReader: {0}" -f (Format-ProductLine $e)) }
} else {
    Write-Line 'FoxitReader: (none)'
}
if ($foxitEditor.Count -gt 0) {
    foreach ($e in $foxitEditor) { Write-Line ("FoxitEditor: {0}" -f (Format-ProductLine $e)) }
} else {
    Write-Line 'FoxitEditor: (none)'
}

$doUninstall = ($Uninstall -or $Remediate) -and -not $CheckOnly

if (-not $doUninstall) {
    if ($xi.Count -gt 0) {
        Write-Line 'Action: CheckOnly'
        Write-Line 'Result: Acrobat XI present. Re-run with -Uninstall to remove (skipped here if Foxit is missing unless -Force).'
        Write-Line 'Exception: If this host has a documented Acrobat XI business dependency, do not uninstall.'
        $script:ExitCode = 1
    } else {
        Write-Line 'Action: CheckOnly'
        Write-Line 'Result: Acrobat XI not installed.'
        if (-not $hasFoxit) {
            Write-Line 'Exception: No Foxit Reader or Editor detected.'
        }
        $script:ExitCode = 0
    }
    if ($Exit) { exit $script:ExitCode }
    return
}

if ($xi.Count -eq 0) {
    Write-Line 'Action: Uninstall'
    Write-Line 'Result: Nothing to remove (Acrobat XI not installed).'
    if (-not $hasFoxit) {
        Write-Line 'Exception: No Foxit Reader or Editor detected.'
    }
    if ($Exit) { exit 0 }
    return
}

if (-not $hasFoxit -and -not $Force) {
    Write-Line 'Action: Skipped'
    Write-Line 'Result: Acrobat XI left installed because Foxit Reader/Editor was not found. Use -Force to uninstall anyway, or install Foxit first.'
    Write-Line 'Exception: Missing Foxit; Acrobat XI not removed.'
    $script:ExitCode = 3
    if ($Exit) { exit $script:ExitCode }
    return
}

if (-not $hasFoxit -and $Force) {
    Write-Line 'Warning: -Force uninstall without Foxit Reader/Editor.'
}

Write-Line 'Action: Uninstall'
Stop-AcrobatXiProcesses
$failed = $false
foreach ($e in $xi) {
    if (-not (Uninstall-AcrobatXiProduct $e)) { $failed = $true }
}

$after = @(Get-UninstallEntries | Where-Object { Test-IsAcrobatXi $_ })
if ($after.Count -gt 0) {
    foreach ($e in $after) { Write-Line ("StillPresent: {0}" -f (Format-ProductLine $e)) }
    Write-Line 'Result: Uninstall incomplete.'
    $script:ExitCode = 2
} elseif ($failed) {
    Write-Line 'Result: Uninstall reported failure; Acrobat XI no longer in Uninstall registry.'
    $script:ExitCode = 0
} else {
    Write-Line 'Result: Acrobat XI removed.'
    $script:ExitCode = 0
}

if ($Exit) { exit $script:ExitCode }
