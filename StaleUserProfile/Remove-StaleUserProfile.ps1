#Requires -Version 5.1
<#
.SYNOPSIS
    List or remove Windows user profiles that have not signed in for a long time.

.DESCRIPTION
    For a shared lab PC. This removes the profile folder and the profile-list
    entry. It does not delete the user account. The next sign-in creates a
    new profile.

    Default is a dry run. -Remediate removes only the profiles the dry run
    would list. -CheckOnly forces a dry run even when -Remediate is also passed.

    Age is the older of the profile's last logoff time and NTUSER.DAT.
    Win32_UserProfile.LastUseTime is not used. On a lab image that value is
    often today for every profile.

    A profile is kept when it is loaded, special, under the Windows directory,
    belongs to the signed-in user, is a direct member of the local
    Administrators group, or is the built-in Administrator (RID 500).
    Nested domain groups are not expanded.
    A profile with no logoff time and no NTUSER.DAT is listed and kept.

.PARAMETER Days
    Last logoff or NTUSER.DAT must be older than this many days. 1 to 3650.

.PARAMETER Weeks
    Last logoff or NTUSER.DAT must be older than this many weeks. 1 to 520.
    A week is 7 days back from now.

.PARAMETER Months
    Last logoff or NTUSER.DAT must be older than this many calendar months.
    Default is 2. 1 to 120. Pass only one of -Days, -Weeks, or -Months.

.PARAMETER CheckOnly
    Dry run. The launcher sends this for Scan.

.PARAMETER Remediate
    Remove the profiles the dry run would list. The launcher sends this for Clean up.

.PARAMETER NoExit
    Keep the PowerShell host open (Backstage).

.PARAMETER Exit
    Always call exit with the result code (Commands / automation).
#>
[CmdletBinding(DefaultParameterSetName = 'Months')]
param(
    [Parameter(ParameterSetName = 'Days')]
    [int]$Days,

    [Parameter(ParameterSetName = 'Weeks')]
    [int]$Weeks,

    [Parameter(ParameterSetName = 'Months')]
    [int]$Months = 2,

    [switch]$CheckOnly,
    [switch]$Remediate,
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Test-StaleShouldExit {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-StaleRun {
    param([Parameter(Mandatory = $true)][int]$Code)
    $global:LASTEXITCODE = $Code
    if (Test-StaleShouldExit) { exit $Code }
}

function Test-StaleAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-StaleLogoffTime {
    param([string]$Sid)
    if (-not $Sid) { return $null }
    $base = $null
    $key = $null
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64)
        $key = $base.OpenSubKey("SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$Sid")
        if (-not $key) { return $null }
        $highObj = $key.GetValue('LocalProfileUnloadTimeHigh')
        $lowObj = $key.GetValue('LocalProfileUnloadTimeLow')
        if ($null -eq $highObj -or $null -eq $lowObj) { return $null }
        $fileTime = ([int64]([uint32]$highObj) -shl 32) -bor [int64]([uint32]$lowObj)
        if ($fileTime -le 0) { return $null }
        $when = [datetime]::FromFileTime($fileTime)
        if ($when.Year -lt 1980) { return $null }
        return $when
    } catch {
        return $null
    } finally {
        if ($key) { $key.Close() }
        if ($base) { $base.Close() }
    }
}

function Get-StaleNtUserTime {
    param([string]$Path)
    if (-not $Path) { return $null }
    try {
        $ntuser = Join-Path $Path 'NTUSER.DAT'
        if (-not (Test-Path -LiteralPath $ntuser -ErrorAction Stop)) { return $null }
        $when = (Get-Item -LiteralPath $ntuser -Force -ErrorAction Stop).LastWriteTime
        if ($when.Year -lt 1980) { return $null }
        return $when
    } catch {
        return $null
    }
}

function Get-StaleAge {
    param([string]$Sid, [string]$Path)
    $logoff = Get-StaleLogoffTime $Sid
    $ntuser = Get-StaleNtUserTime $Path
    if ($logoff -and $ntuser) {
        if ($ntuser -lt $logoff) {
            return [pscustomobject]@{ When = $ntuser; Source = 'ntuser.dat' }
        }
        return [pscustomobject]@{ When = $logoff; Source = 'last logoff' }
    }
    if ($logoff) { return [pscustomobject]@{ When = $logoff; Source = 'last logoff' } }
    if ($ntuser) { return [pscustomobject]@{ When = $ntuser; Source = 'ntuser.dat' } }
    return [pscustomobject]@{ When = $null; Source = 'none' }
}

function Get-StaleAccount {
    param([string]$Sid)
    if (-not $Sid) { return '' }
    try {
        return ([Security.Principal.SecurityIdentifier]$Sid).Translate([Security.Principal.NTAccount]).Value
    } catch {
        return $Sid
    }
}

function Format-StaleSize {
    param($Bytes)
    if ($null -eq $Bytes) { return 'size unknown' }
    $n = [int64]$Bytes
    if ($n -ge 1GB) { return ('{0:N1} GB' -f ($n / 1GB)) }
    return ('{0:N0} MB' -f ($n / 1MB))
}

function Get-StaleFolderBytes {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        return [int64]$fso.GetFolder($Path).Size
    } catch {
        return $null
    }
}

function Get-StaleAdminSids {
    $sidList = New-Object System.Collections.Generic.List[string]
    $group = [ADSI]'WinNT://./Administrators,group'
    foreach ($member in @($group.Invoke('Members'))) {
        $bytes = $member.GetType().InvokeMember('objectSid', 'GetProperty', $null, $member, $null)
        $sid = (New-Object Security.Principal.SecurityIdentifier($bytes, 0)).Value
        if ($sid) { [void]$sidList.Add($sid) }
    }
    return @($sidList)
}

function Get-StaleRows {
    param(
        [Parameter(Mandatory = $true)][datetime]$Cutoff,
        [string[]]$AdminSids,
        [bool]$AdminKnown
    )
    $current = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $rows = New-Object System.Collections.Generic.List[psobject]
    foreach ($profile in @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop)) {
        $sid = [string]$profile.SID
        $path = [string]$profile.LocalPath
        $age = Get-StaleAge -Sid $sid -Path $path
        $last = $age.When
        $source = [string]$age.Source
        $name = Get-StaleAccount $sid
        $reason = $null
        $underWindows = $false
        if ($path -and $env:SystemRoot) {
            $windowsRoot = $env:SystemRoot.TrimEnd('\') + '\'
            $underWindows = $path.StartsWith($windowsRoot, [StringComparison]::OrdinalIgnoreCase)
        }
        if ($profile.Special) {
            $reason = 'special profile'
        } elseif ($underWindows -or $sid -match '^S-1-5-(18|19|20|80-)') {
            $reason = 'Windows service profile'
        } elseif ($sid -match '-500$') {
            $reason = 'built-in Administrator'
        } elseif ($sid -and $sid -eq $current) {
            $reason = 'signed-in user'
        } elseif ($profile.Loaded) {
            $reason = 'signed in now'
        } elseif (-not $AdminKnown) {
            $reason = 'Administrators group could not be read'
        } elseif ($AdminSids -contains $sid) {
            $reason = 'local administrator'
        } elseif (-not $last) {
            $reason = 'no logoff time'
        } elseif ($last -gt $Cutoff) {
            $reason = 'used since the cutoff'
        }
        $action = 'Remove'
        if ($reason) { $action = 'Keep' }
        [void]$rows.Add([pscustomobject]@{
            Action  = $action
            Reason  = $reason
            Name    = $name
            Path    = $path
            LastUse = $last
            Source  = $source
            Sid     = $sid
            Profile = $profile
        })
    }
    return @($rows)
}

try {
    $count = 0
    $unit = 'month'
    $cutoff = $null
    switch ($PSCmdlet.ParameterSetName) {
        'Days' {
            $count = $Days
            $unit = 'day'
            if ($count -ge 1 -and $count -le 3650) { $cutoff = (Get-Date).AddDays(-1 * $count) }
        }
        'Weeks' {
            $count = $Weeks
            $unit = 'week'
            if ($count -ge 1 -and $count -le 520) { $cutoff = (Get-Date).AddDays(-7 * $count) }
        }
        default {
            $count = $Months
            $unit = 'month'
            if ($count -ge 1 -and $count -le 120) { $cutoff = (Get-Date).AddMonths(-1 * $count) }
        }
    }
    if (-not $cutoff) {
        Write-Output 'Age must be 1 to 3650 days, 1 to 520 weeks, or 1 to 120 months. Nothing was deleted.'
        Complete-StaleRun -Code 2
        return
    }
    $ageLabel = if ($count -eq 1) { "1 $unit" } else { "$count ${unit}s" }
    $remove = [bool]$Remediate -and -not $CheckOnly
    $elevated = Test-StaleAdmin
    $adminSids = @()
    $adminKnown = $true
    try {
        $adminSids = @(Get-StaleAdminSids)
    } catch {
        $adminKnown = $false
        Write-Output ("Could not read the local Administrators group: {0}" -f $_.Exception.Message)
    }

    Write-Output ("Stale user profiles. Last logoff or NTUSER.DAT before {0:yyyy-MM-dd} ({1})." -f $cutoff, $ageLabel)
    if (-not $elevated) {
        Write-Output 'This window is not elevated. The list can be incomplete, and nothing will be deleted.'
    }

    $rows = @(Get-StaleRows -Cutoff $cutoff -AdminSids $adminSids -AdminKnown $adminKnown)
    $removeRows = @($rows | Where-Object { $_.Action -eq 'Remove' })
    $keepRows = @($rows | Where-Object { $_.Action -eq 'Keep' })

    if ($removeRows.Count -eq 0) {
        Write-Output 'Would remove: none'
    } else {
        Write-Output ("Would remove: {0}" -f $removeRows.Count)
        foreach ($row in $rows) {
            if ($row.Action -ne 'Remove') { continue }
            $when = 'unknown'
            if ($row.LastUse) { $when = '{0:yyyy-MM-dd}' -f $row.LastUse }
            $size = Format-StaleSize (Get-StaleFolderBytes $row.Path)
            Write-Output ("  {0}  {1}  {2} {3}  {4}" -f $row.Name, $row.Path, $row.Source, $when, $size)
        }
    }
    Write-Output ("Keep: {0}" -f $keepRows.Count)
    foreach ($row in $rows) {
        if ($row.Action -ne 'Keep') { continue }
        $when = 'unknown'
        if ($row.LastUse) { $when = '{0:yyyy-MM-dd}' -f $row.LastUse }
        Write-Output ("  {0}  {1}  {2}  {3} {4}" -f $row.Name, $row.Path, $row.Reason, $row.Source, $when)
    }
    Write-Output 'User accounts are not deleted. A removed profile is created again at the next sign-in.'

    if (-not $remove) {
        if ($removeRows.Count -gt 0) { Complete-StaleRun -Code 1; return }
        Complete-StaleRun -Code 0
        return
    }
    if (-not $elevated -or -not $adminKnown) {
        Write-Output 'Nothing was deleted.'
        Complete-StaleRun -Code 2
        return
    }

    $failed = 0
    $removed = 0
    foreach ($row in $removeRows) {
        $live = Get-CimInstance -ClassName Win32_UserProfile -Filter ("SID='{0}'" -f ($row.Sid -replace "'", "''")) -ErrorAction SilentlyContinue
        if (-not $live) {
            Write-Output ("Already gone: {0}" -f $row.Path)
            continue
        }
        if ($live.Loaded) {
            Write-Output ("Skipped, signed in now: {0}" -f $row.Path)
            $failed++
            continue
        }
        try {
            Remove-CimInstance -InputObject $live
            Write-Output ("Removed: {0}" -f $row.Path)
            $removed++
        } catch {
            Write-Output ("Failed: {0}  {1}" -f $row.Path, $_.Exception.Message)
            $failed++
        }
    }
    Write-Output ("Removed {0}. Failed {1}." -f $removed, $failed)
    if ($failed -gt 0) { Complete-StaleRun -Code 2; return }
    Complete-StaleRun -Code 0
} catch {
    Write-Output ("Stale profile cleanup failed: {0}" -f $_.Exception.Message)
    Complete-StaleRun -Code 2
}
