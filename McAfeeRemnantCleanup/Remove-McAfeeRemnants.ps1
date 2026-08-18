#Requires -Version 5.1
<#
.SYNOPSIS
    Detect and remove leftover McAfee AppX packages and Program Files folder.

.PARAMETER CheckOnly
    Report presence only.

.PARAMETER Remediate
    Kill McAfee processes, remove AppX for all users, disable leftover services, delete Program Files\McAfee.

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

$folder = 'C:\Program Files\McAfee'
$appx = @(Get-AppxPackage -AllUsers | Where-Object { $_.Name -match 'McAfee' })
$folderPresent = Test-Path -LiteralPath $folder

Write-Output ("McAfee AppX packages: {0}" -f $appx.Count)
Write-Output ("McAfee folder present: {0}" -f $folderPresent)

if (-not $appx -and -not $folderPresent) {
    Write-Output 'McAfee not found - skipping.'
    if ($Exit) { exit 0 }
    return
}

if ($CheckOnly -or -not $Remediate) {
    if ($appx.Count -gt 0) {
        $appx | Select-Object Name, Version, PackageFullName | Format-Table -AutoSize | Out-String | Write-Output
    }
    Write-Output 'Re-run with -Remediate to remove remnants.'
    $script:ExitCode = 1
    if ($Exit) { exit $script:ExitCode }
    return
}

$procs = @(
    'mc-fw-host', 'mc-launch', 'mc-sync-agent', 'mc-wps-secdashboardservice',
    'mc-dad', 'mc-neo-host', 'browserhost', 'servicehost', 'uihost', 'updater'
)
foreach ($p in $procs) {
    & taskkill.exe /f /im "$p.exe" 2>$null | Out-Null
}

Get-Process | Where-Object { $_.Path -match 'McAfee' } | Stop-Process -Force -ErrorAction SilentlyContinue

$appx | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

@(
    'mc-fw-host',
    'mc-wps-secdashboardservice',
    'mc-wps-update',
    'McpManagementService'
) | ForEach-Object {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$_" -Name 'Start' -Value 4 -ErrorAction SilentlyContinue
}

if (Test-Path -LiteralPath $folder) {
    & icacls.exe $folder /grant administrators:F /t | Out-Null
    Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
}

$appx2 = @(Get-AppxPackage -AllUsers | Where-Object { $_.Name -match 'McAfee' })
Write-Output ("McAfee folder: {0}" -f $(if (Test-Path -LiteralPath $folder) { 'Still present' } else { 'Gone' }))
Write-Output ("APPX: {0}" -f $(if ($appx2.Count -gt 0) { 'Still present' } else { 'Gone' }))

if ((Test-Path -LiteralPath $folder) -or $appx2.Count -gt 0) {
    $script:ExitCode = 2
} else {
    $script:ExitCode = 0
}

if ($Exit) { exit $script:ExitCode }
