#Requires -Version 5.1
<#
.SYNOPSIS
    List or remove Exchange Online transport rules matching Inky / IPW / IOC Strip.

.DESCRIPTION
    Intended for an already-connected Exchange Online PowerShell session
    (Connect-ExchangeOnline). Not an endpoint ScreenConnect tool — paste into
    an elevated EXO session on an admin workstation.

    Default is dry-run (list only). Pass -Delete to remove without interactive prompt.

.PARAMETER CheckOnly
    List matching rules only (default behavior).

.PARAMETER Delete
    Remove matching rules (no Read-Host confirmation).

.PARAMETER NamePattern
    Regex matched against rule Name. Default: IPW|Inky|IOC Strip

.PARAMETER Exit
    Call exit with a status code when used from automation.
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Delete,
    [string]$NamePattern = 'IPW|Inky|IOC Strip',
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$script:ExitCode = 0

if (-not (Get-Command Get-TransportRule -ErrorAction SilentlyContinue)) {
    Write-Output 'ERROR: Get-TransportRule not available. Connect-ExchangeOnline first, then re-run.'
    $script:ExitCode = 2
    if ($Exit) { exit $script:ExitCode }
    return
}

Write-Output ''
Write-Output '=== STEP 1: Searching for Inky/IPW transport rules ==='

$rules = @(Get-TransportRule | Where-Object { $_.Name -match $NamePattern } | Sort-Object Priority)

if ($rules.Count -eq 0) {
    Write-Output 'No Inky/IPW rules found. Nothing to do.'
    if ($Exit) { exit 0 }
    return
}

Write-Output ("Found {0} rule(s):" -f $rules.Count)
$rules | Format-Table Name, State, Priority -AutoSize | Out-String | Write-Output

if ($CheckOnly -or -not $Delete) {
    Write-Output 'Dry-run only. Re-run with -Delete to remove these rules (no interactive confirm).'
    $script:ExitCode = 1
    if ($Exit) { exit $script:ExitCode }
    return
}

Write-Output '=== STEP 2: Removing rules ==='
foreach ($rule in $rules) {
    try {
        Remove-TransportRule -Identity $rule.Name -Confirm:$false
        Write-Output ("Removed: {0}" -f $rule.Name)
    } catch {
        Write-Output ("Failed to remove: {0} -- {1}" -f $rule.Name, $_.Exception.Message)
        $script:ExitCode = 3
    }
}

Write-Output '=== STEP 3: Verifying removal ==='
$anyRemaining = $false
foreach ($rule in $rules) {
    $check = Get-TransportRule -Identity $rule.Name -ErrorAction SilentlyContinue
    if ($check) {
        Write-Output ("STILL EXISTS: {0}" -f $rule.Name)
        $anyRemaining = $true
        $script:ExitCode = 3
    } else {
        Write-Output ("Confirmed gone: {0}" -f $rule.Name)
    }
}

if (-not $anyRemaining) {
    Write-Output 'All matching Inky/IPW rules successfully removed.'
    if ($script:ExitCode -eq 0) { $script:ExitCode = 0 }
} else {
    Write-Output 'Some rules were not removed. Review errors above.'
}

if ($Exit) { exit $script:ExitCode }
