#Requires -Version 5.1
<#
.SYNOPSIS
    Lists distinct ScreenConnect (ConnectWise Control) instance IDs on this PC.

.DESCRIPTION
    Read-only. Does not use Apps and Features as the source of truth. Collects IDs from
    the services registry, uninstall keys, MSI products, processes (including renamed
    binaries), on-disk client folders, scheduled tasks, Run keys, service-install events,
    and ScreenConnect event providers. Prints each instance ID once.

    Authorized = instance ID is on the allow list.
    ROGUE      = instance ID was found and is not on the allow list.
    A service, process, task, or Run key that matches ScreenConnect but has no instance
    ID is one Review line. Files with no ID (old ClickOnce caches, plugin DLLs) are skipped.

    Exit codes: 0 = none or authorized only, 1 = Review (no ID, or more than one
    product version on an ID), 2 = ROGUE found.

.PARAMETER AllowedInstanceIds
    16 character hex instance IDs considered legitimate.

.PARAMETER EventDays
    How far back to read System event 7045. Default 30.

.PARAMETER OutCsv
    Optional path. Writes one row per instance ID.

.PARAMETER NoExit
    Keep the PowerShell host open (ScreenConnect Backstage).

.PARAMETER Exit
    Always exit the process with the result code (ScreenConnect Commands).

.EXAMPLE
    .\Find-RogueScreenConnect.ps1

.EXAMPLE
    .\Find-RogueScreenConnect.ps1 -OutCsv C:\Windows\Temp\sc-ids.csv
#>
[CmdletBinding()]
param(
    [string[]]$AllowedInstanceIds = @(
        '8e1512c8736de3b9',   # primary
        'fb310accf083cff0'    # ad hoc
    ),
    [int]$EventDays = 30,
    [string]$OutCsv,
    [switch]$NoExit,
    [switch]$Exit
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$AllowedInstanceIds = @($AllowedInstanceIds | ForEach-Object { $_.ToLower() })
$ScPattern = 'ScreenConnect|ConnectWise ?Control|[?&]e=(Access|Support|Meeting)&y=Guest'
$ById = @{}
$NoIdSet = New-Object 'System.Collections.Generic.HashSet[string]'

function Test-ScShouldExitProcess {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-ScHunt {
    param([Parameter(Mandatory)][int]$Code)
    $global:LASTEXITCODE = $Code
    if (Test-ScShouldExitProcess) { exit $Code }
}

function Get-ScInstanceIds([string]$Text) {
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    if ([string]::IsNullOrEmpty($Text)) { return @() }
    foreach ($rx in @(
            '\(([0-9a-fA-F]{16})\)',
            'ScreenConnect Client[ _]([0-9a-fA-F]{16})'
        )) {
        foreach ($m in [regex]::Matches($Text, $rx)) {
            [void]$set.Add($m.Groups[1].Value.ToLower())
        }
    }
    return @($set)
}

function Add-ScVersion {
    param([string]$Id, [string]$Version)
    if ([string]::IsNullOrWhiteSpace($Id) -or [string]::IsNullOrWhiteSpace($Version)) { return }
    if (-not $ById.ContainsKey($Id)) {
        $ById[$Id] = New-Object 'System.Collections.Generic.HashSet[string]'
    }
    [void]$ById[$Id].Add($Version.Trim())
}

function Get-IdsFromFileBytes([string]$File) {
    if ([string]::IsNullOrWhiteSpace($File) -or -not (Test-Path -LiteralPath $File -PathType Leaf)) { return @() }
    $item = Get-Item -LiteralPath $File -Force
    if ($item.Length -le 0 -or $item.Length -gt 8MB) { return @() }
    if ($item.Extension -notin '.exe', '.msi') { return @() }
    try {
        $ascii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($item.FullName))
        return @(Get-ScInstanceIds $ascii)
    }
    catch { return @() }
}

function Add-ScHit {
    param([string]$Text, [string]$Version, [string]$File, [switch]$Bare)
    $ids = @(Get-ScInstanceIds "$Text $File")
    if ($ids.Count -eq 0 -and $File) { $ids = @(Get-IdsFromFileBytes $File) }
    $ids = @($ids | Where-Object { $_ } | Select-Object -Unique)
    if ($ids.Count -eq 0) {
        $blob = "$Text $File"
        if ($Bare -and $blob -match $ScPattern) {
            # Per-session guest clients use a GUID, not a 16-character instance ID.
            if ($blob -match '\([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\)') { return }
            if ($blob -match '[?&]y=Guest') { return }
            [void]$script:NoIdSet.Add($blob.Trim())
        }
        return
    }
    $fileVersion = $Version
    if ($File -and (Test-Path -LiteralPath $File -PathType Leaf)) {
        try {
            $pv = (Get-Item -LiteralPath $File -Force).VersionInfo.ProductVersion
            if ($pv) { $fileVersion = $pv }
        }
        catch { }
    }
    foreach ($id in $ids) {
        if (-not $ById.ContainsKey($id)) {
            $ById[$id] = New-Object 'System.Collections.Generic.HashSet[string]'
        }
        Add-ScVersion -Id $id -Version $fileVersion
    }
}

function Add-ScFiles {
    param([string]$Root, [int]$Depth)
    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root)) { return }
    foreach ($filter in @('ScreenConnect*', 'ConnectWiseControl*')) {
        Get-ChildItem -LiteralPath $Root -Filter $filter -Force -Recurse -Depth $Depth -ErrorAction SilentlyContinue |
            ForEach-Object {
                if ($_.PSIsContainer) {
                    if ($_.Name -match '\(([0-9a-fA-F]{16})\)') { Add-ScHit -Text $_.FullName }
                }
                else {
                    Add-ScHit -Text $_.FullName -File $_.FullName
                }
            }
    }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning 'Not elevated. Other users'' processes and some profile folders will be missed.'
}

Write-Host "Scanning $env:COMPUTERNAME for ScreenConnect instance IDs..."

# Services (registry, including entries hidden from the SCM)
try {
    $hklm64 = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    $svcRoot = $hklm64.OpenSubKey('SYSTEM\CurrentControlSet\Services')
    if ($svcRoot) {
        foreach ($name in $svcRoot.GetSubKeyNames()) {
            $k = $svcRoot.OpenSubKey($name)
            if (-not $k) { continue }
            $display = [string]$k.GetValue('DisplayName')
            $image = [string]$k.GetValue('ImagePath')
            $blob = "$name $display $image"
            if ($blob -match $ScPattern) {
                $exe = $null
                if ($image -match '"([^"]+\.exe)"') { $exe = $Matches[1] }
                elseif ($image -match '([A-Za-z]:\\[^ ]+\.exe)') { $exe = $Matches[1] }
                Add-ScHit -Text $blob -File $exe -Bare
            }
        }
    }
}
catch { }

# Uninstall keys: 64-bit, 32-bit, and loaded user hives
try {
    $views = @(
        [Microsoft.Win32.RegistryView]::Registry64,
        [Microsoft.Win32.RegistryView]::Registry32
    )
    foreach ($view in $views) {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
        foreach ($sub in @(
                'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
            )) {
            $root = $base.OpenSubKey($sub)
            if (-not $root) { continue }
            foreach ($name in $root.GetSubKeyNames()) {
                $k = $root.OpenSubKey($name)
                if (-not $k) { continue }
                $blob = @(
                    $k.GetValue('DisplayName'),
                    $k.GetValue('Publisher'),
                    $k.GetValue('InstallLocation'),
                    $k.GetValue('UninstallString'),
                    $k.GetValue('DisplayVersion')
                ) -join ' '
                if ($blob -match $ScPattern) {
                    Add-ScHit -Text $blob -Version ([string]$k.GetValue('DisplayVersion')) -File ([string]$k.GetValue('InstallLocation')) -Bare
                }
            }
        }
    }

    $hkUsers = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::Users,
        [Microsoft.Win32.RegistryView]::Default)
    foreach ($sid in $hkUsers.GetSubKeyNames()) {
        if ($sid -notmatch '^S-1-5-21-[\d-]+$') { continue }
        $root = $hkUsers.OpenSubKey("$sid\Software\Microsoft\Windows\CurrentVersion\Uninstall")
        if (-not $root) { continue }
        foreach ($name in $root.GetSubKeyNames()) {
            $k = $root.OpenSubKey($name)
            if (-not $k) { continue }
            $blob = @(
                $k.GetValue('DisplayName'),
                $k.GetValue('Publisher'),
                $k.GetValue('InstallLocation'),
                $k.GetValue('UninstallString')
            ) -join ' '
            if ($blob -match $ScPattern) {
                Add-ScHit -Text $blob -Version ([string]$k.GetValue('DisplayVersion')) -Bare
            }
        }
    }
}
catch { }

# MSI product registrations
try {
    $hklm64 = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    $products = $hklm64.OpenSubKey('SOFTWARE\Classes\Installer\Products')
    if ($products) {
        foreach ($name in $products.GetSubKeyNames()) {
            $k = $products.OpenSubKey($name)
            if (-not $k) { continue }
            $product = [string]$k.GetValue('ProductName')
            if ($product -match $ScPattern) { Add-ScHit -Text $product -Bare }
        }
    }
}
catch { }

# Processes, including a renamed exe whose version resource still says ScreenConnect
try {
    Get-CimInstance Win32_Process | ForEach-Object {
        if ($_.ProcessId -eq $PID) { return }
        if ($_.CommandLine -match 'Find-RogueScreenConnect|ScreenConnectRogueHunt') { return }
        $blob = "$($_.Name) $($_.ExecutablePath) $($_.CommandLine)"
        $hit = $blob -match $ScPattern
        if (-not $hit -and $_.ExecutablePath) {
            $vi = (Get-Item -LiteralPath $_.ExecutablePath -Force).VersionInfo
            if ("$($vi.OriginalFilename) $($vi.ProductName) $($vi.CompanyName) $($vi.FileDescription)" -match 'ScreenConnect') {
                $hit = $true
            }
        }
        if ($hit) { Add-ScHit -Text $blob -File $_.ExecutablePath -Bare }
    }
}
catch { }

# On disk: install folders, ClickOnce, temp, downloads, desktop. Bounded depth.
try {
    Add-ScFiles -Root $env:ProgramFiles -Depth 2
    Add-ScFiles -Root ${env:ProgramFiles(x86)} -Depth 2
    Add-ScFiles -Root $env:ProgramData -Depth 4
    Add-ScFiles -Root "$env:SystemRoot\Temp" -Depth 2
    Get-ChildItem "$env:SystemDrive\Users" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Add-ScFiles -Root (Join-Path $_.FullName 'AppData\Local\Apps\2.0') -Depth 6
        Add-ScFiles -Root (Join-Path $_.FullName 'AppData\Roaming') -Depth 3
        Add-ScFiles -Root (Join-Path $_.FullName 'Downloads') -Depth 1
        Add-ScFiles -Root (Join-Path $_.FullName 'Desktop') -Depth 1
    }
}
catch { }

# Scheduled tasks and Run keys
try {
    Get-ScheduledTask | ForEach-Object {
        $actions = ($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' '
        $blob = "$($_.TaskName) $actions"
        if ($blob -match $ScPattern) { Add-ScHit -Text $blob -Bare }
    }
}
catch { }

try {
    $runSubs = @(
        'SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'
    )
    foreach ($view in @(
            [Microsoft.Win32.RegistryView]::Registry64,
            [Microsoft.Win32.RegistryView]::Registry32
        )) {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
        foreach ($sub in $runSubs) {
            $k = $base.OpenSubKey($sub)
            if (-not $k) { continue }
            foreach ($valueName in $k.GetValueNames()) {
                $val = [string]$k.GetValue($valueName)
                if ("$valueName $val" -match $ScPattern) { Add-ScHit -Text "$valueName $val" -Bare }
            }
        }
    }
    $hkUsers = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::Users,
        [Microsoft.Win32.RegistryView]::Default)
    foreach ($sid in $hkUsers.GetSubKeyNames()) {
        if ($sid -notmatch '^S-1-5-21-[\d-]+$') { continue }
        foreach ($leaf in @('Run', 'RunOnce')) {
            $k = $hkUsers.OpenSubKey("$sid\Software\Microsoft\Windows\CurrentVersion\$leaf")
            if (-not $k) { continue }
            foreach ($valueName in $k.GetValueNames()) {
                $val = [string]$k.GetValue($valueName)
                if ("$valueName $val" -match $ScPattern) { Add-ScHit -Text "$valueName $val" -Bare }
            }
        }
    }
}
catch { }

# Service install events and provider names (IDs remain after the client is removed)
try {
    $since = (Get-Date).AddDays(-1 * [Math]::Abs($EventDays))
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 7045; StartTime = $since } -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match $ScPattern } |
        ForEach-Object {
            $svcName = [string]$_.Properties[0].Value
            $image = [string]$_.Properties[1].Value
            Add-ScHit -Text "$svcName $image" -Bare
        }
}
catch { }

try {
    [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.GetProviderNames() |
        Where-Object { $_ -match 'ScreenConnect|ConnectWise Control' } |
        ForEach-Object { Add-ScHit -Text $_ }
}
catch { }

$rows = foreach ($id in $ById.Keys) {
    $versions = @($ById[$id] | Sort-Object)
    [pscustomobject]@{
        Verdict  = $(if ($AllowedInstanceIds -contains $id) { 'Authorized' } else { 'ROGUE' })
        Id       = $id
        Versions = ($versions -join ', ')
    }
}
$order = @{ 'ROGUE' = 0; 'Authorized' = 1 }
$rows = @($rows | Sort-Object @{ e = { $order[$_.Verdict] } }, Id)

$versionSkew = @($rows | Where-Object { @($_.Versions -split ',\s*' | Where-Object { $_ }).Count -gt 1 }).Count
$noId = $NoIdSet.Count
Write-Host ''
if ($rows.Count -eq 0 -and $noId -eq 0) {
    Write-Host 'No ScreenConnect instance IDs found.' -ForegroundColor Green
}
foreach ($row in $rows) {
    $color = if ($row.Verdict -eq 'ROGUE') { 'Red' } else { 'Green' }
    $suffix = if ($row.Versions) { "  $($row.Versions)" } else { '' }
    Write-Host ("{0,-12} {1}{2}" -f $row.Verdict, $row.Id, $suffix) -ForegroundColor $color
}
if ($noId -gt 0) {
    Write-Host ("{0,-12} (no instance id) x{1}" -f 'Review', $noId) -ForegroundColor Yellow
}

$rogue = @($rows | Where-Object Verdict -eq 'ROGUE').Count
$auth = @($rows | Where-Object Verdict -eq 'Authorized').Count
Write-Host ''
Write-Host "Summary ${env:COMPUTERNAME}: ROGUE=$rogue  Authorized=$auth  ReviewNoId=$noId" -ForegroundColor Cyan

if ($OutCsv) {
    $rows | Select-Object @{ n = 'Computer'; e = { $env:COMPUTERNAME } }, Verdict, Id, Versions |
        Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Wrote $OutCsv"
}

if ($rogue -gt 0) { Complete-ScHunt -Code 2 }
elseif ($noId -gt 0 -or $versionSkew -gt 0) { Complete-ScHunt -Code 1 }
else { Complete-ScHunt -Code 0 }
