#Requires -Version 5.1
<#
.SYNOPSIS
    Lists distinct ScreenConnect (ConnectWise Control) instance IDs on this PC.
    -Remediate removes installs whose instance ID is not on the allow list.

.DESCRIPTION
    The default is read-only. Does not use Apps and Features as the source of truth.
    Collects IDs from the services registry, uninstall keys, MSI products, processes
    (including renamed binaries), on-disk client folders, scheduled tasks, Run keys,
    service-install events, and ScreenConnect event providers. Prints each instance ID once.

    Authorized = instance ID is on the allow list.
    ROGUE      = instance ID was found and is not on the allow list.
    A service, process, task, or Run key that matches ScreenConnect but has no instance
    ID is one Review line. Files with no ID (old ClickOnce caches, plugin DLLs) are skipped.
    -Remediate does not remove Review lines and does not remove an allow-listed ID.

    Exit codes: 0 = none or authorized only, 1 = Review (no ID, more than one
    product version on an ID, or event history only), 2 = a live ROGUE install.
    After -Remediate, 2 means a rogue install is still present or the session
    is not elevated. Event history is not an install and is not deleted.

.PARAMETER AllowedInstanceIds
    16 character hex instance IDs considered legitimate.

.PARAMETER EventDays
    How far back to read System event 7045. Default 30.

.PARAMETER OutCsv
    Optional path. Writes one row per instance ID.

.PARAMETER CheckOnly
    Scan only. Wins over -Remediate.

.PARAMETER Remediate
    Stop, uninstall, and delete ScreenConnect installs whose instance ID is not on
    the allow list. Allow-listed IDs are kept. Requires elevation.

.PARAMETER FromTask
    Internal. Set when the detached removal task is running.

.PARAMETER NoExit
    Keep the PowerShell host open (ScreenConnect Backstage).

.PARAMETER Exit
    Always exit the process with the result code (ScreenConnect Commands).

.EXAMPLE
    .\Find-RogueScreenConnect.ps1

.EXAMPLE
    .\Find-RogueScreenConnect.ps1 -Remediate

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
    [switch]$CheckOnly,
    [switch]$Remediate,
    [switch]$FromTask,
    [switch]$NoExit,
    [switch]$Exit
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$AllowedInstanceIds = @($AllowedInstanceIds | ForEach-Object { $_.ToLower() })
if ($FromTask) {
    try { Start-Transcript -LiteralPath (Join-Path $env:SystemRoot 'Temp\Remove-RogueScClient.log') -Force | Out-Null } catch { }
}
$ScPattern = 'ScreenConnect|ConnectWise ?Control|[?&]e=(Access|Support|Meeting)&y=Guest'
$ById = @{}
$NoIdSet = New-Object 'System.Collections.Generic.HashSet[string]'
$LiveIds = New-Object 'System.Collections.Generic.HashSet[string]'

function Test-ScShouldExitProcess {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-ScHunt {
    param([Parameter(Mandatory)][int]$Code)
    if ($FromTask) { Clear-ScRemovalTask }
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
    param([string]$Text, [string]$Version, [string]$File, [switch]$Bare, [switch]$History)
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
        if (-not $History) { [void]$script:LiveIds.Add($id) }
        Add-ScVersion -Id $id -Version $fileVersion
    }
}

function Test-ScIdToken {
    param([string]$Text, [string]$Id)
    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Id)) { return $false }
    return $Text -match ('(?i)(?<![0-9a-f])' + [regex]::Escape($Id) + '(?![0-9a-f])')
}

function Test-ScAllowedText {
    param([string]$Text)
    foreach ($allowed in $AllowedInstanceIds) {
        if (Test-ScIdToken $Text $allowed) { return $true }
    }
    return $false
}

function Get-ScNativePath {
    param([string]$Relative)
    $sysnative = Join-Path $env:SystemRoot (Join-Path 'SysNative' $Relative)
    if ($env:PROCESSOR_ARCHITEW6432 -and (Test-Path -LiteralPath $sysnative)) { return $sysnative }
    return Join-Path $env:SystemRoot (Join-Path 'System32' $Relative)
}

function Test-ScSafeDeleteDir {
    param([string]$Dir, [string]$Id, [switch]$ServiceImage)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $false }
    try { $full = [IO.Path]::GetFullPath($Dir.Trim().Trim('"')) } catch { return $false }
    if ([string]::IsNullOrWhiteSpace($full)) { return $false }
    if (Test-ScAllowedText $full) { return $false }
    if ($full -notmatch $ScPattern) { return $false }
    if (-not $ServiceImage -and -not (Test-ScIdToken $full $Id)) { return $false }
    $leaf = Split-Path -Path $full -Leaf
    if ($leaf -match '^(?i)(Temp|Local|Roaming|Downloads|Desktop|Apps|2\.0|Windows|Users|System32|SysWOW64|ProgramData)$') { return $false }
    if ($leaf -match '^(?i)Program Files( \(x86\))?$') { return $false }
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, (Join-Path $env:SystemRoot 'Temp'))) {
        if ($root) { [void]$roots.Add($root) }
    }
    $users = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $users) {
        Get-ChildItem -LiteralPath $users -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            foreach ($sub in @('AppData\Local', 'AppData\Roaming', 'Downloads', 'Desktop')) {
                [void]$roots.Add((Join-Path $_.FullName $sub))
            }
        }
    }
    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) { continue }
        try { $rootFull = [IO.Path]::GetFullPath($root) } catch { continue }
        $prefix = $rootFull.TrimEnd('\') + '\'
        if ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and $full.Length -gt $prefix.Length) {
            return $true
        }
    }
    return $false
}

function Test-ScSafeDeleteFile {
    param([string]$File)
    if ([string]::IsNullOrWhiteSpace($File)) { return $false }
    try { $full = [IO.Path]::GetFullPath($File.Trim().Trim('"')) } catch { return $false }
    if (Test-ScAllowedText $full) { return $false }
    $leaf = Split-Path -Path $full -Leaf
    if ($leaf -notmatch $ScPattern) { return $false }
    if ($full -notmatch '(?i)\.(exe|dll|msi)$') { return $false }
    $parent = Split-Path -Path $full -Parent
    if ([string]::IsNullOrWhiteSpace($parent)) { return $false }
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, (Join-Path $env:SystemRoot 'Temp'))) {
        if ($root) { [void]$roots.Add($root) }
    }
    $users = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $users) {
        foreach ($userDir in @(Get-ChildItem -LiteralPath $users -Directory -Force -ErrorAction SilentlyContinue)) {
            foreach ($sub in @('Downloads', 'Desktop', 'AppData\Local', 'AppData\Roaming')) {
                [void]$roots.Add((Join-Path $userDir.FullName $sub))
            }
        }
    }
    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) { continue }
        try { $rootFull = [IO.Path]::GetFullPath($root) } catch { continue }
        $prefix = $rootFull.TrimEnd('\') + '\'
        if ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-ScExeFromImage {
    param([string]$Image)
    if ([string]::IsNullOrWhiteSpace($Image)) { return $null }
    if ($Image -match '"([^"]+\.exe)"') { return $Matches[1] }
    if ($Image -match '([A-Za-z]:\\[^"\s]+\.exe)') { return $Matches[1] }
    return $null
}

function Get-ScMatchingServices {
    param([string]$Id)
    $list = New-Object System.Collections.Generic.List[object]
    try {
        $hklm64 = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64)
        $svcRoot = $hklm64.OpenSubKey('SYSTEM\CurrentControlSet\Services')
        if (-not $svcRoot) { return @() }
        foreach ($name in $svcRoot.GetSubKeyNames()) {
            $k = $svcRoot.OpenSubKey($name)
            if (-not $k) { continue }
            $display = [string]$k.GetValue('DisplayName')
            $image = [string]$k.GetValue('ImagePath')
            $k.Close()
            $blob = "$name $display $image"
            if (Test-ScAllowedText $blob) { continue }
            if (-not (Test-ScIdToken $blob $Id)) { continue }
            if ($blob -notmatch $ScPattern) { continue }
            [void]$list.Add([pscustomobject]@{ Name = $name; Image = $image; Display = $display })
        }
        $svcRoot.Close()
    }
    catch { }
    return @($list)
}

function Get-ScMatchingArp {
    param([string]$Id)
    $list = New-Object System.Collections.Generic.List[object]
    $views = @(
        [Microsoft.Win32.RegistryView]::Registry64,
        [Microsoft.Win32.RegistryView]::Registry32
    )
    foreach ($view in $views) {
        try {
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
                    $display = [string]$k.GetValue('DisplayName')
                    $uninstall = [string]$k.GetValue('UninstallString')
                    $quiet = [string]$k.GetValue('QuietUninstallString')
                    $location = [string]$k.GetValue('InstallLocation')
                    $k.Close()
                    $blob = "$display $uninstall $quiet $location"
                    if (Test-ScAllowedText $blob) { continue }
                    if (-not (Test-ScIdToken $blob $Id)) { continue }
                    if ($blob -notmatch $ScPattern) { continue }
                    [void]$list.Add([pscustomobject]@{
                            DisplayName          = $display
                            UninstallString      = $uninstall
                            QuietUninstallString = $quiet
                            InstallLocation      = $location
                            Hive                 = 'LocalMachine'
                            View                 = $view
                            SubKey               = "$sub\$name"
                        })
                }
                $root.Close()
            }
            $base.Close()
        }
        catch { }
    }
    try {
        $hkUsers = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::Users,
            [Microsoft.Win32.RegistryView]::Default)
        foreach ($sid in $hkUsers.GetSubKeyNames()) {
            if ($sid -notmatch '^S-1-5-21-[\d-]+$') { continue }
            $sub = "$sid\Software\Microsoft\Windows\CurrentVersion\Uninstall"
            $root = $hkUsers.OpenSubKey($sub)
            if (-not $root) { continue }
            foreach ($name in $root.GetSubKeyNames()) {
                $k = $root.OpenSubKey($name)
                if (-not $k) { continue }
                $display = [string]$k.GetValue('DisplayName')
                $uninstall = [string]$k.GetValue('UninstallString')
                $quiet = [string]$k.GetValue('QuietUninstallString')
                $location = [string]$k.GetValue('InstallLocation')
                $k.Close()
                $blob = "$display $uninstall $quiet $location"
                if (Test-ScAllowedText $blob) { continue }
                if (-not (Test-ScIdToken $blob $Id)) { continue }
                if ($blob -notmatch $ScPattern) { continue }
                [void]$list.Add([pscustomobject]@{
                        DisplayName          = $display
                        UninstallString      = $uninstall
                        QuietUninstallString = $quiet
                        InstallLocation      = $location
                        Hive                 = 'Users'
                        View                 = [Microsoft.Win32.RegistryView]::Default
                        SubKey               = "$sub\$name"
                    })
            }
            $root.Close()
        }
        $hkUsers.Close()
    }
    catch { }
    return @($list)
}

function Test-ScDirUsedByAllowed {
    param([string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $false }
    try { $full = [IO.Path]::GetFullPath($Dir.Trim().Trim('"')) } catch { return $false }
    $prefix = $full.TrimEnd('\') + '\'
    try {
        $hklm64 = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64)
        $svcRoot = $hklm64.OpenSubKey('SYSTEM\CurrentControlSet\Services')
        if (-not $svcRoot) { return $false }
        foreach ($name in $svcRoot.GetSubKeyNames()) {
            $k = $svcRoot.OpenSubKey($name)
            if (-not $k) { continue }
            $display = [string]$k.GetValue('DisplayName')
            $image = [string]$k.GetValue('ImagePath')
            $k.Close()
            $blob = "$name $display $image"
            if (-not (Test-ScAllowedText $blob) -or $blob -notmatch $ScPattern) { continue }
            $exe = Get-ScExeFromImage $image
            if (-not $exe) { continue }
            try { $exeFull = [IO.Path]::GetFullPath($exe) } catch { continue }
            if ($exeFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                $svcRoot.Close()
                return $true
            }
        }
        $svcRoot.Close()
    }
    catch { }
    return $false
}

function Get-ScNamedInstallDirs {
    param([string]$Id)
    $jobs = New-Object System.Collections.Generic.List[object]
    foreach ($pair in @(
            @{ Root = $env:ProgramFiles; Depth = 3 },
            @{ Root = ${env:ProgramFiles(x86)}; Depth = 3 },
            @{ Root = $env:ProgramData; Depth = 4 },
            @{ Root = (Join-Path $env:SystemRoot 'Temp'); Depth = 3 }
        )) { [void]$jobs.Add($pair) }
    $users = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $users) {
        foreach ($userDir in @(Get-ChildItem -LiteralPath $users -Directory -Force -ErrorAction SilentlyContinue)) {
            foreach ($pair in @(
                    @{ Root = (Join-Path $userDir.FullName 'Downloads'); Depth = 1 },
                    @{ Root = (Join-Path $userDir.FullName 'Desktop'); Depth = 1 },
                    @{ Root = (Join-Path $userDir.FullName 'AppData\Roaming'); Depth = 3 },
                    @{ Root = (Join-Path $userDir.FullName 'AppData\Local'); Depth = 2 },
                    @{ Root = (Join-Path $userDir.FullName 'AppData\Local\Apps\2.0'); Depth = 6 }
                )) { [void]$jobs.Add($pair) }
        }
    }
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($job in $jobs) {
        if ([string]::IsNullOrWhiteSpace($job.Root) -or -not (Test-Path -LiteralPath $job.Root)) { continue }
        Get-ChildItem -LiteralPath $job.Root -Directory -Force -Recurse -Depth $job.Depth -ErrorAction SilentlyContinue |
            ForEach-Object {
                if (-not (Test-ScIdToken $_.Name $Id)) { return }
                if ($_.Name -notmatch $ScPattern -and $_.FullName -notmatch $ScPattern) { return }
                if (-not (Test-ScSafeDeleteDir -Dir $_.FullName -Id $Id)) { return }
                [void]$found.Add($_.FullName)
            }
    }
    $kept = @()
    foreach ($dir in @($found | Select-Object -Unique | Sort-Object Length)) {
        $inside = $false
        foreach ($parent in $kept) {
            if ($dir.StartsWith($parent.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { $inside = $true }
        }
        if (-not $inside) { $kept += $dir }
    }
    return $kept
}

function Wait-ScProcess {
    param($Process, [int]$Seconds)
    if (-not $Process) { return 1 }
    $deadline = (Get-Date).AddSeconds($Seconds)
    while (-not $Process.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        try { $Process.Refresh() } catch { break }
    }
    if (-not $Process.HasExited) {
        Write-Host "Timed out after $Seconds seconds. Stopping pid $($Process.Id)."
        try { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue } catch { }
        return 1
    }
    return [int]$Process.ExitCode
}

function Invoke-ScUninstallCommand {
    param([string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    $CommandLine = $CommandLine.Trim()
    if (Test-ScAllowedText $CommandLine) {
        Write-Host 'Skipped an uninstall command that names an allow-listed instance.'
        return 1
    }
    if ($CommandLine -match '(?i)msiexec(?:\.exe)?"?\s+/(?:x|i)\s*(\{[0-9a-fA-F-]+\})') {
        $guid = $Matches[1]
        $msiexec = Get-ScNativePath 'msiexec.exe'
        Write-Host "msiexec /X$guid /qn /norestart"
        $proc = Start-Process -FilePath $msiexec -ArgumentList @("/X$guid", '/qn', '/norestart') -PassThru -WindowStyle Hidden
        return (Wait-ScProcess -Process $proc -Seconds 180)
    }
    $exe = $null
    $rest = ''
    if ($CommandLine -match '^"([^"]+\.exe)"\s*(.*)$') {
        $exe = $Matches[1]
        $rest = $Matches[2]
    }
    elseif ($CommandLine -match '^([A-Za-z]:\\[^"\s]+\.exe)\s*(.*)$') {
        $exe = $Matches[1]
        $rest = $Matches[2]
    }
    if (-not $exe) {
        Write-Host "Unrecognized uninstall command: $CommandLine"
        return 1
    }
    if (-not (Test-Path -LiteralPath $exe)) {
        Write-Host "Uninstall program is already gone: $exe"
        return 1605
    }
    if (Test-ScAllowedText $exe) {
        Write-Host "Skipped an uninstall program under an allow-listed instance: $exe"
        return 1
    }
    $tokens = @()
    if (-not [string]::IsNullOrWhiteSpace($rest)) {
        $tokens = @($rest.Trim() -split '\s+' | Where-Object { $_ })
    }
    $hasUninstall = $false
    foreach ($token in $tokens) {
        if ($token -match '(?i)^uninstall$') { $hasUninstall = $true }
    }
    if (-not $hasUninstall) { $tokens = @('uninstall') + $tokens }
    $joined = $tokens -join ' '
    if ($joined -notmatch '(?i)(/quiet|/qn|(^|\s)/s(\s|$)|-quiet|--quiet)') { $tokens += '/quiet' }
    Write-Host ("Running $exe " + ($tokens -join ' '))
    $proc = Start-Process -FilePath $exe -ArgumentList $tokens -PassThru -WindowStyle Hidden
    return (Wait-ScProcess -Process $proc -Seconds 120)
}

function Stop-ScRogueProcesses {
    param([string]$Id, [string[]]$Dirs, [string[]]$Files)
    Get-CimInstance Win32_Process | ForEach-Object {
        if ($_.ProcessId -eq $PID) { return }
        $blob = "$($_.Name) $($_.ExecutablePath) $($_.CommandLine)"
        if ($blob -match 'Find-RogueScreenConnect|ScreenConnectRogueHunt|Remove-RogueScClient') { return }
        if (Test-ScAllowedText $blob) { return }
        $under = $false
        if ($_.ExecutablePath) {
            foreach ($dir in $Dirs) {
                $prefix = $dir.TrimEnd('\') + '\'
                if ($_.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $under = $true }
            }
            foreach ($file in $Files) {
                if ($_.ExecutablePath -eq $file) { $under = $true }
            }
        }
        $hit = (Test-ScIdToken $blob $Id) -or $under
        if (-not $hit) { return }
        if ($blob -notmatch $ScPattern -and -not $under) { return }
        Write-Host "Stopping process $($_.ProcessId) $($_.Name)"
        $taskkill = Get-ScNativePath 'taskkill.exe'
        & $taskkill /F /PID $_.ProcessId | Out-Null
    }
}

function Remove-ScArpKey {
    param($Hit)
    $blob = "$($Hit.DisplayName) $($Hit.UninstallString) $($Hit.SubKey)"
    if (Test-ScAllowedText $blob) {
        Write-Host "Refusing to delete an uninstall key that names an allow-listed instance."
        return
    }
    $hive = [Microsoft.Win32.RegistryHive]::LocalMachine
    if ($Hit.Hive -eq 'Users') { $hive = [Microsoft.Win32.RegistryHive]::Users }
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $Hit.View)
        Write-Host "Removing stale uninstall key $($Hit.SubKey)"
        $base.DeleteSubKeyTree($Hit.SubKey, $false)
        $base.Close()
    }
    catch {
        Write-Host "Could not remove uninstall key $($Hit.SubKey): $($_.Exception.Message)"
    }
}

function Remove-ScRunValues {
    param([string]$Id)
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
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
            foreach ($sub in $runSubs) {
                $k = $base.OpenSubKey($sub, $true)
                if (-not $k) { continue }
                foreach ($valueName in @($k.GetValueNames())) {
                    $val = [string]$k.GetValue($valueName)
                    $blob = "$valueName $val"
                    if (Test-ScAllowedText $blob) { continue }
                    if (-not (Test-ScIdToken $blob $Id)) { continue }
                    if ($blob -notmatch $ScPattern) { continue }
                    Write-Host "Removing Run value $valueName"
                    try { $k.DeleteValue($valueName, $false) } catch { Write-Host $_.Exception.Message }
                }
                $k.Close()
            }
            $base.Close()
        }
        catch { }
    }
    try {
        $hkUsers = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::Users,
            [Microsoft.Win32.RegistryView]::Default)
        foreach ($sid in $hkUsers.GetSubKeyNames()) {
            if ($sid -notmatch '^S-1-5-21-[\d-]+$') { continue }
            foreach ($leaf in @('Run', 'RunOnce')) {
                $path = "$sid\Software\Microsoft\Windows\CurrentVersion\$leaf"
                $k = $hkUsers.OpenSubKey($path, $true)
                if (-not $k) { continue }
                foreach ($valueName in @($k.GetValueNames())) {
                    $val = [string]$k.GetValue($valueName)
                    $blob = "$valueName $val"
                    if (Test-ScAllowedText $blob) { continue }
                    if (-not (Test-ScIdToken $blob $Id)) { continue }
                    if ($blob -notmatch $ScPattern) { continue }
                    Write-Host "Removing Run value $valueName"
                    try { $k.DeleteValue($valueName, $false) } catch { Write-Host $_.Exception.Message }
                }
                $k.Close()
            }
        }
        $hkUsers.Close()
    }
    catch { }
}

function Remove-ScTasks {
    param([string]$Id)
    Get-ScheduledTask | ForEach-Object {
        if ($_.TaskName -eq 'RemoveRogueScClient') { return }
        $actions = ($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' '
        $blob = "$($_.TaskName) $actions"
        if (Test-ScAllowedText $blob) { return }
        if (-not (Test-ScIdToken $blob $Id)) { return }
        if ($blob -notmatch $ScPattern) { return }
        Write-Host "Removing scheduled task $($_.TaskPath)$($_.TaskName)"
        try {
            Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        }
        catch { Write-Host $_.Exception.Message }
    }
}

function Remove-ScEventProviders {
    param([string]$Id)
    try {
        $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64)
        foreach ($rel in @(
                'SYSTEM\CurrentControlSet\Services\EventLog\Application',
                'SYSTEM\CurrentControlSet\Services\EventLog\System'
            )) {
            $root = $hklm.OpenSubKey($rel)
            if (-not $root) { continue }
            foreach ($name in @($root.GetSubKeyNames())) {
                if (Test-ScAllowedText $name) { continue }
                if (-not (Test-ScIdToken $name $Id)) { continue }
                if ($name -notmatch $ScPattern) { continue }
                Write-Host "Removing event source $name"
                try { $hklm.DeleteSubKeyTree("$rel\$name", $false) } catch { Write-Host $_.Exception.Message }
            }
            $root.Close()
        }
        $pubRel = 'SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers'
        $pubs = $hklm.OpenSubKey($pubRel)
        if ($pubs) {
            foreach ($guid in @($pubs.GetSubKeyNames())) {
                $k = $pubs.OpenSubKey($guid)
                if (-not $k) { continue }
                $vals = New-Object System.Collections.Generic.List[string]
                foreach ($valueName in $k.GetValueNames()) { [void]$vals.Add([string]$k.GetValue($valueName)) }
                $k.Close()
                $blob = "$guid $($vals -join ' ')"
                if (Test-ScAllowedText $blob) { continue }
                if (-not (Test-ScIdToken $blob $Id)) { continue }
                if ($blob -notmatch $ScPattern) { continue }
                Write-Host "Removing event publisher $guid"
                try { $hklm.DeleteSubKeyTree("$pubRel\$guid", $false) } catch { Write-Host $_.Exception.Message }
            }
            $pubs.Close()
        }
        $hklm.Close()
    }
    catch { }
}

function Get-ScProviderHits {
    param([string]$Id)
    $hits = @()
    try {
        $hits = @(
            [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.GetProviderNames() |
                Where-Object {
                    (Test-ScIdToken $_ $Id) -and ($_ -match $ScPattern) -and -not (Test-ScAllowedText $_)
                }
        )
    }
    catch { }
    return $hits
}

function Add-ScDirTarget {
    param($Set, [string]$Dir, [string]$Id, [switch]$ServiceImage)
    if (-not (Test-ScSafeDeleteDir -Dir $Dir -Id $Id -ServiceImage:$ServiceImage)) { return }
    try { $full = [IO.Path]::GetFullPath($Dir.Trim().Trim('"')) } catch { return }
    [void]$Set.Add($full)
}

function Remove-ScRogueInstall {
    param([string]$Id)
    $id = $Id.ToLower()
    if ($AllowedInstanceIds -contains $id) {
        Write-Host "Refusing to remove allow-listed $id" -ForegroundColor Yellow
        return
    }
    Write-Host ''
    Write-Host "Removing ROGUE $id" -ForegroundColor Red
    $dirs = New-Object 'System.Collections.Generic.HashSet[string]'
    $files = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($dir in @(Get-ScNamedInstallDirs -Id $id)) {
        if (Test-ScDirUsedByAllowed $dir) {
            Write-Host "Keeping folder $dir because an allow-listed client uses it."
            continue
        }
        Add-ScDirTarget -Set $dirs -Dir $dir -Id $id
    }
    $services = @(Get-ScMatchingServices -Id $id)
    foreach ($svc in $services) {
        $exe = Get-ScExeFromImage $svc.Image
        if (-not $exe) { continue }
        $parent = Split-Path -Path $exe -Parent
        if (Test-ScDirUsedByAllowed $parent) {
            Write-Host "Keeping folder $parent because an allow-listed client uses it."
        }
        elseif (Test-ScSafeDeleteDir -Dir $parent -Id $id -ServiceImage) { Add-ScDirTarget -Set $dirs -Dir $parent -Id $id -ServiceImage }
        elseif (Test-ScSafeDeleteFile $exe) {
            try { [void]$files.Add([IO.Path]::GetFullPath($exe)) } catch { }
        }
    }
    $arp = @(Get-ScMatchingArp -Id $id)
    foreach ($hit in $arp) {
        if ($hit.InstallLocation -and -not (Test-ScDirUsedByAllowed $hit.InstallLocation)) {
            Add-ScDirTarget -Set $dirs -Dir $hit.InstallLocation -Id $id -ServiceImage
        }
        foreach ($cmd in @($hit.QuietUninstallString, $hit.UninstallString)) {
            $exe = Get-ScExeFromImage $cmd
            if (-not $exe) { continue }
            $parent = Split-Path -Path $exe -Parent
            if (Test-ScDirUsedByAllowed $parent) { continue }
            if (Test-ScSafeDeleteDir -Dir $parent -Id $id -ServiceImage) { Add-ScDirTarget -Set $dirs -Dir $parent -Id $id -ServiceImage }
        }
    }
    $dirList = New-Object System.Collections.Generic.List[string]
    foreach ($dir in $dirs) { [void]$dirList.Add($dir) }
    $fileList = New-Object System.Collections.Generic.List[string]
    foreach ($file in $files) { [void]$fileList.Add($file) }
    $sc = Get-ScNativePath 'sc.exe'
    foreach ($svc in $services) {
        Write-Host "Disabling service $($svc.Name)"
        & $sc @('config', $svc.Name, 'start=', 'disabled') | Out-Null
    }
    Stop-ScRogueProcesses -Id $id -Dirs $dirList -Files $fileList
    foreach ($svc in $services) {
        Write-Host "Stopping service $($svc.Name)"
        & $sc @('stop', $svc.Name) | Out-Null
    }
    Start-Sleep -Seconds 2
    $ran = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($hit in $arp) {
        $cmd = $hit.QuietUninstallString
        if ([string]::IsNullOrWhiteSpace($cmd)) { $cmd = $hit.UninstallString }
        if ([string]::IsNullOrWhiteSpace($cmd)) { continue }
        if (-not $ran.Add($cmd.Trim().ToLower())) { continue }
        $code = Invoke-ScUninstallCommand -CommandLine $cmd
        Write-Host "Uninstall exit $code ($($hit.DisplayName))"
    }
    Stop-ScRogueProcesses -Id $id -Dirs $dirList -Files $fileList
    foreach ($svc in $services) {
        Write-Host "Deleting service $($svc.Name)"
        & $sc @('delete', $svc.Name) | Out-Null
        if ($LASTEXITCODE -eq 1072) {
            Write-Host "Service $($svc.Name) is marked for deletion and goes away at the next restart."
        }
        elseif ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1060) {
            Write-Host "sc delete $($svc.Name) exited $LASTEXITCODE"
        }
    }
    foreach ($dir in ($dirList | Sort-Object Length -Descending)) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        if (-not (Test-ScSafeDeleteDir -Dir $dir -Id $id -ServiceImage)) { continue }
        Write-Host "Removing folder $dir"
        try { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Continue } catch { Write-Host $_.Exception.Message }
        if (Test-Path -LiteralPath $dir) {
            $attrib = Get-ScNativePath 'attrib.exe'
            & $attrib -R -S -H "$dir\*" /S /D | Out-Null
            try { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Continue } catch { Write-Host $_.Exception.Message }
        }
    }
    foreach ($file in $fileList) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        if (-not (Test-ScSafeDeleteFile $file)) { continue }
        Write-Host "Removing file $file"
        try { Remove-Item -LiteralPath $file -Force -ErrorAction Continue } catch { Write-Host $_.Exception.Message }
    }
    Remove-ScRunValues -Id $id
    Remove-ScTasks -Id $id
    Remove-ScEventProviders -Id $id
    $stillDirs = @($dirList | Where-Object { Test-Path -LiteralPath $_ })
    if ($stillDirs.Count -eq 0 -and @(Get-ScMatchingServices -Id $id).Count -eq 0) {
        foreach ($hit in @(Get-ScMatchingArp -Id $id)) { Remove-ScArpKey -Hit $hit }
    }
    return @($dirList)
}

function Get-ScLiveEvidence {
    param([string]$Id, [string[]]$PlannedDirs)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($svc in @(Get-ScMatchingServices -Id $Id)) { [void]$lines.Add("service $($svc.Name)") }
    foreach ($hit in @(Get-ScMatchingArp -Id $Id)) { [void]$lines.Add("uninstall $($hit.DisplayName)") }
    foreach ($dir in @(Get-ScNamedInstallDirs -Id $Id)) { [void]$lines.Add("folder $dir") }
    foreach ($dir in $PlannedDirs) {
        if ($dir -and (Test-Path -LiteralPath $dir)) { [void]$lines.Add("folder $dir") }
    }
    Get-CimInstance Win32_Process | ForEach-Object {
        if ($_.ProcessId -eq $PID) { return }
        $blob = "$($_.Name) $($_.ExecutablePath) $($_.CommandLine)"
        if ($blob -match 'Find-RogueScreenConnect|ScreenConnectRogueHunt|Remove-RogueScClient') { return }
        if (Test-ScAllowedText $blob) { return }
        if ((Test-ScIdToken $blob $Id) -and ($blob -match $ScPattern)) {
            [void]$lines.Add("process $($_.ProcessId) $($_.Name)")
        }
    }
    try {
        Get-ScheduledTask | ForEach-Object {
            if ($_.TaskName -eq 'RemoveRogueScClient') { return }
            $actions = ($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' '
            $blob = "$($_.TaskName) $actions"
            if (Test-ScAllowedText $blob) { return }
            if ((Test-ScIdToken $blob $Id) -and ($blob -match $ScPattern)) {
                [void]$lines.Add("task $($_.TaskName)")
            }
        }
    }
    catch { }
    foreach ($name in @(Get-ScProviderHits -Id $Id)) { [void]$lines.Add("event provider $name") }
    return @($lines | Select-Object -Unique)
}

function Test-ScHostedByInstance {
    param([string]$Id)
    try {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$PID"
        $guard = 0
        while ($proc -and $guard -lt 8) {
            $blob = "$($proc.Name) $($proc.ExecutablePath) $($proc.CommandLine)"
            if ($blob -notmatch 'Find-RogueScreenConnect|ScreenConnectRogueHunt|Remove-RogueScClient') {
                if ((Test-ScIdToken $blob $Id) -and -not (Test-ScAllowedText $blob)) { return $true }
            }
            if (-not $proc.ParentProcessId -or $proc.ParentProcessId -eq $proc.ProcessId) { break }
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.ParentProcessId)"
            $guard++
        }
    }
    catch { }
    return $false
}

function Clear-ScRemovalTask {
    try { Unregister-ScheduledTask -TaskName 'RemoveRogueScClient' -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    $temp = Join-Path $env:SystemRoot 'Temp\Remove-RogueScClient.ps1'
    if (Test-Path -LiteralPath $temp) {
        try { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue } catch { }
    }
    try { Stop-Transcript | Out-Null } catch { }
}

function Start-ScDetachedRemoval {
    param([string]$ScriptBody)
    if ([string]::IsNullOrWhiteSpace($ScriptBody) -or $ScriptBody.Length -lt 500) { return $false }
    $temp = Join-Path $env:SystemRoot 'Temp\Remove-RogueScClient.ps1'
    try {
        $utf8 = New-Object System.Text.UTF8Encoding $true
        [IO.File]::WriteAllText($temp, $ScriptBody, $utf8)
        $ps = Get-ScNativePath 'WindowsPowerShell\v1.0\powershell.exe'
        $idArg = ($AllowedInstanceIds -join ',')
        $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$temp`" -Remediate -FromTask -Exit -AllowedInstanceIds $idArg"
        $action = New-ScheduledTaskAction -Execute $ps -Argument $arg
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName 'RemoveRogueScClient' -Action $action -Principal $principal -Force | Out-Null
        Start-ScheduledTask -TaskName 'RemoveRogueScClient'
        return $true
    }
    catch {
        Write-Host "Detached removal did not start: $($_.Exception.Message)"
        Clear-ScRemovalTask
        return $false
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
        if ($_.CommandLine -match 'Find-RogueScreenConnect|ScreenConnectRogueHunt|Remove-RogueScClient') { return }
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
        if ($_.TaskName -eq 'RemoveRogueScClient') { return }
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
            Add-ScHit -Text "$svcName $image" -Bare -History
        }
}
catch { }

try {
    [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.GetProviderNames() |
        Where-Object { $_ -match 'ScreenConnect|ConnectWise Control' } |
        ForEach-Object { Add-ScHit -Text $_ -History }
}
catch { }

$rows = foreach ($id in $ById.Keys) {
    $versions = @($ById[$id] | Sort-Object)
    [pscustomobject]@{
        Verdict  = $(
            if ($AllowedInstanceIds -contains $id) { 'Authorized' }
            elseif ($LiveIds.Contains($id)) { 'ROGUE' }
            else { 'History' }
        )
        Id       = $id
        Versions = ($versions -join ', ')
    }
}
$order = @{ 'ROGUE' = 0; 'History' = 1; 'Authorized' = 2 }
$rows = @($rows | Sort-Object @{ e = { $order[$_.Verdict] } }, Id)

$versionSkew = @($rows | Where-Object { @($_.Versions -split ',\s*' | Where-Object { $_ }).Count -gt 1 }).Count
$noId = $NoIdSet.Count
Write-Host ''
if ($rows.Count -eq 0 -and $noId -eq 0) {
    Write-Host 'No ScreenConnect instance IDs found.' -ForegroundColor Green
}
foreach ($row in $rows) {
    $color = if ($row.Verdict -eq 'ROGUE') { 'Red' } elseif ($row.Verdict -eq 'History') { 'Yellow' } else { 'Green' }
    $suffix = if ($row.Versions) { "  $($row.Versions)" } else { '' }
    if ($row.Verdict -eq 'History' -and -not $suffix) { $suffix = '  (event history only)' }
    Write-Host ("{0,-12} {1}{2}" -f $row.Verdict, $row.Id, $suffix) -ForegroundColor $color
}
if ($noId -gt 0) {
    Write-Host ("{0,-12} (no instance id) x{1}" -f 'Review', $noId) -ForegroundColor Yellow
}

$rogue = @($rows | Where-Object Verdict -eq 'ROGUE').Count
$auth = @($rows | Where-Object Verdict -eq 'Authorized').Count
$history = @($rows | Where-Object Verdict -eq 'History').Count
Write-Host ''
Write-Host "Summary ${env:COMPUTERNAME}: ROGUE=$rogue  Authorized=$auth  History=$history  ReviewNoId=$noId" -ForegroundColor Cyan

if ($OutCsv) {
    $rows | Select-Object @{ n = 'Computer'; e = { $env:COMPUTERNAME } }, Verdict, Id, Versions |
        Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Wrote $OutCsv"
}

if ($rogue -gt 0 -and (-not $Remediate -or $CheckOnly)) {
    Write-Host 'Scan only. Run again with -Remediate to remove rogue installs. Allow-listed IDs are kept.'
}

$code = 0
if ($Remediate -and -not $CheckOnly -and $rogue -gt 0) {
    if (-not $isAdmin) {
        Write-Host 'Not elevated. Rogue installs were not removed.' -ForegroundColor Yellow
        $code = 2
    }
    else {
        $rogueIds = @($rows | Where-Object { $_.Verdict -eq 'ROGUE' } | Select-Object -ExpandProperty Id)
        $hosted = $false
        if (-not $FromTask) {
            foreach ($id in $rogueIds) {
                if (Test-ScHostedByInstance $id) { $hosted = $true }
            }
        }
        if ($hosted) {
            $definition = $MyInvocation.MyCommand.Definition
            if (Start-ScDetachedRemoval -ScriptBody $definition) {
                Write-Host 'This session is a rogue client. Removal was handed to scheduled task RemoveRogueScClient and continues after this connection drops.'
                Write-Host 'Log: C:\Windows\Temp\Remove-RogueScClient.log'
                $code = 0
                $hosted = $true
            }
            else {
                Write-Host 'Could not start a detached removal. Removing in this session. The connection may drop.' -ForegroundColor Yellow
                $hosted = $false
            }
        }
        if (-not $hosted) {
            foreach ($allowed in $AllowedInstanceIds) { Write-Host "Keeping allow-listed $allowed" -ForegroundColor Green }
            $planned = @{}
            foreach ($id in $rogueIds) {
                if ($AllowedInstanceIds -contains $id) {
                    Write-Host "Refusing to remove allow-listed $id" -ForegroundColor Yellow
                    continue
                }
                $planned[$id] = @(Remove-ScRogueInstall -Id $id)
            }
            $left = 0
            foreach ($id in $rogueIds) {
                if ($AllowedInstanceIds -contains $id) { continue }
                $live = @(Get-ScLiveEvidence -Id $id -PlannedDirs @($planned[$id]))
                if ($live.Count -gt 0) {
                    $left++
                    Write-Host "Still present ${id}:" -ForegroundColor Red
                    $live | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
                }
                else { Write-Host "Removed $id" -ForegroundColor Green }
            }
            if ($left -gt 0) { $code = 2 }
            elseif ($noId -gt 0 -or $versionSkew -gt 0 -or $history -gt 0) { $code = 1 }
            else { $code = 0 }
        }
    }
}
elseif ($rogue -gt 0) { $code = 2 }
elseif ($noId -gt 0 -or $versionSkew -gt 0 -or $history -gt 0) { $code = 1 }
else { $code = 0 }

if ($Remediate -and -not $CheckOnly -and $rogue -eq 0) {
    Write-Host 'No rogue installs to remove.'
}
Complete-ScHunt -Code $code
