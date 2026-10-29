#Requires -Version 5.1
<#
.SYNOPSIS
    Launch the Pale Moon Portable copy in C:\ProgramData\PaleMoonPortable.

.DESCRIPTION
    For an admin PC. Paste the one-liner into ScreenConnect Backstage or a
    local PowerShell window. It does not download anything. Install first
    with Install-PaleMoonPortable.ps1, which uses this same folder.
#>
[CmdletBinding()]
param(
    [switch]$NoExit,
    [switch]$Exit,
    [switch]$NoLaunch,
    [string]$Destination
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Complete-PaleMoonStart {
    param([Parameter(Mandatory = $true)][int]$Code)
    $global:LASTEXITCODE = $Code
    if ($Exit) { exit $Code }
    if ($NoExit) { return }
    if ($PSCommandPath) { exit $Code }
}

try {
    if (-not $Destination) {
        $Destination = Join-Path $env:ProgramData 'PaleMoonPortable'
    }
    $launcher = Join-Path $Destination 'Palemoon-Portable.exe'
    if (-not (Test-Path -LiteralPath $launcher)) {
        Write-Output "Pale Moon Portable is not in $Destination. Run the install tool first."
        Complete-PaleMoonStart -Code 1
        return
    }

    $prefix = $Destination.TrimEnd('\') + '\'
    $running = @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
        })
    if ($NoLaunch) {
        Write-Output "Ready: $launcher"
    } elseif ($running.Count -gt 0) {
        Write-Output 'Pale Moon is already running.'
    } else {
        Start-Process -FilePath $launcher -WorkingDirectory $Destination | Out-Null
        Write-Output "Started $launcher"
    }
    Complete-PaleMoonStart -Code 0
} catch {
    Write-Output ("Pale Moon portable launch failed: {0}" -f $_.Exception.Message)
    Complete-PaleMoonStart -Code 1
}
