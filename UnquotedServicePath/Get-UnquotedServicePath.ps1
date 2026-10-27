#Requires -Version 5.1
<#
.SYNOPSIS
    Report unquoted service paths and the next step for each one.

.DESCRIPTION
    A service whose binary path contains a space and is not wrapped in quotes
    can be started from an earlier folder in that path. This check lists those
    services. Windows Defender and Sense are called out and left alone.

    When Users, Everyone, or Authenticated Users can write one of the split
    folders, the line includes an elevated sc.exe command that quotes the
    binary. The script does not change the service.

.PARAMETER Exit
    Call exit with a status code (ScreenConnect Commands).

.PARAMETER NoExit
    Keep the PowerShell host open (Backstage).
#>
[CmdletBinding()]
param(
    [switch]$Exit,
    [switch]$NoExit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$write = [Security.AccessControl.FileSystemRights]'Write,Modify,FullControl,Delete,CreateFiles,AppendData,CreateDirectories,WriteData'
$rows = New-Object System.Collections.Generic.List[object]

function Complete-UnquotedRun {
    param([int]$Code)
    if ($Exit) { exit $Code }
    if ($NoExit) { return }
    if ($PSCommandPath) { exit $Code }
}

Get-CimInstance Win32_Service | ForEach-Object {
    $name = $_.Name
    $p = [string]$_.PathName
    if (-not $p -or $p.StartsWith('"')) { return }
    if ($p -notmatch '(?i)^(.*\.exe)\b') { return }
    $exe = $Matches[1]
    $rest = $p.Substring($Matches[0].Length).Trim()
    if ($exe -notmatch ' ') { return }

    $platform = ($name -match '^(Sense|DefenderUpdateSvc|WinDefend|MDCoreSvc|WdNisSvc)$') -or ($exe -match '(?i)\\Microsoft\\Windows Defender|Windows Defender Advanced Threat Protection\\')
    if ($platform) {
        $rows.Add([pscustomobject]@{
            Name   = $name
            Status = 'leave it - Windows platform'
            Exe    = $exe
            Next   = 'Do not quote this one. Windows ships it unquoted, and a quote can break Defender or Sense.'
            Bad    = $false
        }) | Out-Null
        return
    }

    $bits = $exe.Split(' ')
    $built = ''
    $dirs = @()
    foreach ($bit in $bits[0..($bits.Length - 2)]) {
        $built = if ($built) { "$built $bit" } else { $bit }
        $folder = Split-Path -Parent "$built.exe"
        if ($folder -and $dirs -notcontains $folder) { $dirs += $folder }
    }

    $writers = @()
    $unreadable = @()
    foreach ($folder in $dirs) {
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        try {
            $acl = Get-Acl -LiteralPath $folder
        } catch {
            $unreadable += $folder
            continue
        }
        foreach ($ace in @($acl.Access)) {
            if ($ace.AccessControlType -ne 'Allow') { continue }
            $id = [string]$ace.IdentityReference
            if ($id -notmatch '(^|\\)(Everyone|Users|Authenticated Users)$') { continue }
            if (($ace.FileSystemRights -band $write) -ne 0) { $writers += "$id can write $folder" }
        }
    }
    $writers = @($writers | Select-Object -Unique)

    $image = '"' + $exe + '"'
    if ($rest) { $image = $image + ' ' + $rest }
    $quote = '& "$env:SystemRoot\System32\sc.exe" config ''' + ($name -replace "'", "''") + ''' binPath= ''' + ($image -replace "'", "''") + ''''

    if ($writers) {
        $rows.Add([pscustomobject]@{
            Name   = $name
            Status = ($writers -join '; ')
            Exe    = $exe
            Next   = "Quote the binary, then restart the service if it was running. Review this first. It is not applied by the check.`n  $quote"
            Bad    = $true
        }) | Out-Null
    } elseif ($unreadable) {
        $rows.Add([pscustomobject]@{
            Name   = $name
            Status = ('could not read ACL on ' + ($unreadable -join ' | '))
            Exe    = $exe
            Next   = "Re-run elevated, then quote the binary if a user can write a split folder.`n  $quote"
            Bad    = $true
        }) | Out-Null
    } else {
        $checked = if ($dirs) { $dirs -join ' | ' } else { 'no folder' }
        $rows.Add([pscustomobject]@{
            Name   = $name
            Status = "no user write on $checked"
            Exe    = $exe
            Next   = 'No change. The path is unquoted, but Users, Everyone, and Authenticated Users cannot write those folders.'
            Bad    = $false
        }) | Out-Null
    }
}

if ($rows.Count -eq 0) {
    Write-Output 'Safe'
    Write-Output 'No service needs a quote.'
    Complete-UnquotedRun -Code 0
    return
}

$bad = @($rows | Where-Object { $_.Bad })
if ($bad.Count -gt 0) {
    Write-Output 'Action needed'
} else {
    Write-Output 'Safe'
}
foreach ($row in $rows) {
    Write-Output ("$($row.Name) - $($row.Status) - $($row.Exe)")
    Write-Output ("  Next: $($row.Next)")
}
if ($bad.Count -gt 0) {
    Complete-UnquotedRun -Code 1
} else {
    Complete-UnquotedRun -Code 0
}
