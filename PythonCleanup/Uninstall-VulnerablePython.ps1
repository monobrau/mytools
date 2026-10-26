#Requires -Version 5.1
<#
.SYNOPSIS
    Report or remove vulnerable CPython installs on Windows.

.DESCRIPTION
    Finds Python Software Foundation installs (Programs and Features, official
    install folders, and the Microsoft Store package). An install is vulnerable
    when its branch is end of life, or when it is older than the current
    security release for a supported branch.

    End of life as of 2026-10-26: 2.x and 3.0 through 3.10.
    Supported floors (python.org, 2026-10-26): 3.11.18, 3.12.16, 3.13.18,
    3.14.10, 3.15.2. A newer branch with no floor in this script is left alone.

    The Python Launcher, Anaconda, Miniconda, and copies inside other apps
    are not removed. Nothing is rebooted.

.PARAMETER CheckOnly
    Report only.

.PARAMETER Remediate
    Uninstall vulnerable installs. Without this switch nothing is removed.

.PARAMETER EolOnly
    Remove only end-of-life branches (3.10 and older, including Python 2).
    Leave supported branches even when they are behind the current release.

.PARAMETER NoExit
    Keep the PowerShell host open (Backstage).

.PARAMETER Exit
    Call exit with a status code (ScreenConnect Commands).
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Remediate,
    [switch]$EolOnly,
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$script:ExitCode = 0
$script:Floors = @{
    '3.11' = [version]::new(3, 11, 18)
    '3.12' = [version]::new(3, 12, 16)
    '3.13' = [version]::new(3, 13, 18)
    '3.14' = [version]::new(3, 14, 10)
    '3.15' = [version]::new(3, 15, 2)
}

function Write-Line {
    param([string]$Message)
    Write-Output $Message
}

function Test-IsAdmin {
    $p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-ShouldExit {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    return $false
}

function Complete-Run {
    param([int]$Code)
    $script:ExitCode = $Code
    $global:LASTEXITCODE = $Code
    if (Test-ShouldExit) { exit $Code }
}

function ConvertTo-PythonVersion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    if ($Text -match '(\d+)\.(\d+)\.(\d+)') {
        return [version]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
    }
    if ($Text -match '(\d+)\.(\d+)') {
        return [version]::new([int]$Matches[1], [int]$Matches[2], 0)
    }
    return $null
}

function Get-PythonVerdict {
    param($Version, [switch]$EolOnly)
    if (-not $Version) {
        return @{ Vulnerable = $false; Reason = 'version unknown' }
    }
    $branch = '{0}.{1}' -f $Version.Major, $Version.Minor
    $eol = ($Version.Major -lt 3) -or ($Version.Major -eq 3 -and $Version.Minor -le 10)
    if ($eol) {
        return @{ Vulnerable = $true; Reason = "EOL ($branch)" }
    }
    if ($EolOnly) {
        return @{ Vulnerable = $false; Reason = 'supported' }
    }
    if (-not $script:Floors.ContainsKey($branch)) {
        return @{ Vulnerable = $false; Reason = "no floor for $branch (kept)" }
    }
    $floor = $script:Floors[$branch]
    if ($Version -lt $floor) {
        return @{ Vulnerable = $true; Reason = "older than $floor" }
    }
    return @{ Vulnerable = $false; Reason = 'current' }
}

function Test-CPythonName {
    param([string]$Name, [string]$Publisher)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if ($Name -match '(?i)Launcher|Anaconda|Miniconda|PyPy|IronPython|ActivePython|WinPython') { return $false }
    if ($Publisher -match '(?i)Python Software Foundation' -and $Name -match '(?i)^Python \d') { return $true }
    if ($Name -match '(?i)^Python \d+\.\d+') { return $true }
    return $false
}

function Get-PythonArch {
    param([string]$Name, [string]$View)
    if ($Name -match '(?i)\(64-bit\)') { return '64-bit' }
    if ($Name -match '(?i)\(32-bit\)') { return '32-bit' }
    if ($View -eq 'x86') { return '32-bit' }
    return '64-bit'
}

function Test-PythonBundleName {
    param([string]$Name)
    return $Name -match '(?i)^Python \d+\.\d+\.\d+( \((64|32)-bit\))?$'
}

function Open-MachineKey {
    try {
        return [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64)
    }
    catch {
        return [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Default)
    }
}

function Add-ArpFromKey {
    param($BaseKey, [string]$Scope, $List, $Skipped)
    if (-not $BaseKey) { return }
    foreach ($rel in @(
            'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )) {
        $view = 'x64'
        if ($rel -match 'WOW6432') { $view = 'x86' }
        $un = $null
        try { $un = $BaseKey.OpenSubKey($rel) } catch { $un = $null }
        if (-not $un) { continue }
        try {
            foreach ($name in @($un.GetSubKeyNames())) {
                $sub = $null
                try { $sub = $un.OpenSubKey($name) } catch { continue }
                if (-not $sub) { continue }
                try {
                    $display = [string]$sub.GetValue('DisplayName')
                    $publisher = [string]$sub.GetValue('Publisher')
                    if ($display -match '(?i)^Python Launcher\b') {
                        if ($Skipped -notcontains 'Python Launcher') { [void]$Skipped.Add('Python Launcher') }
                        continue
                    }
                    if (-not (Test-CPythonName -Name $display -Publisher $publisher)) { continue }
                    $version = ConvertTo-PythonVersion $display
                    if (-not $version) { $version = ConvertTo-PythonVersion ([string]$sub.GetValue('DisplayVersion')) }
                    $product = ''
                    if ($name -match '^\{[0-9A-Fa-f-]{36}\}$') { $product = $name }
                    [void]$List.Add([pscustomobject]@{
                            DisplayName          = $display
                            DisplayVersion       = [string]$sub.GetValue('DisplayVersion')
                            Publisher            = $publisher
                            Version              = $version
                            Arch                 = (Get-PythonArch -Name $display -View $view)
                            Scope                = $Scope
                            InstallLocation      = ([string]$sub.GetValue('InstallLocation')).TrimEnd('\')
                            UninstallString      = [string]$sub.GetValue('UninstallString')
                            QuietUninstallString = [string]$sub.GetValue('QuietUninstallString')
                            ProductCode          = $product
                            Bundle               = (Test-PythonBundleName $display)
                        })
                }
                finally { $sub.Dispose() }
            }
        }
        finally { $un.Dispose() }
    }
}

function Get-UserProfiles {
    $list = New-Object System.Collections.Generic.List[object]
    $root = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    foreach ($item in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
        $sid = $item.PSChildName
        if ($sid -notmatch '^S-1-5-21-' -or $sid -like '*.bak') { continue }
        $path = ''
        try {
            $path = [Environment]::ExpandEnvironmentVariables([string](Get-ItemProperty -LiteralPath $item.PSPath).ProfileImagePath)
        }
        catch { continue }
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        $leaf = Split-Path $path -Leaf
        if ($leaf -in @('Public', 'Default', 'Default User', 'All Users')) { continue }
        $nt = Join-Path $path 'NTUSER.DAT'
        if (-not (Test-Path -LiteralPath $nt -ErrorAction SilentlyContinue)) { continue }
        $list.Add([pscustomobject]@{
                Name        = $leaf
                Sid         = $sid
                NtUser      = $nt
                ProfilePath = $path
            })
    }
    return $list.ToArray()
}

function Dismount-UserHive {
    param([string]$Mount)
    $reg = Join-Path $env:SystemRoot 'System32\reg.exe'
    for ($try = 1; $try -le 8; $try++) {
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $reg unload "HKU\$Mount" 2>&1 | Out-Null
        $code = $LASTEXITCODE
        $ErrorActionPreference = $prev
        if ($code -eq 0) { return $true }
        Start-Sleep -Milliseconds 400
    }
    return $false
}

function Add-ProfileArp {
    param($UserProfile, $List, $Skipped)
    $mounted = $false
    $mount = $null
    if ($UserProfile.Sid -and (Test-Path -LiteralPath "Registry::HKEY_USERS\$($UserProfile.Sid)")) {
        $mount = $UserProfile.Sid
    }
    else {
        $mount = 'Py' + [guid]::NewGuid().ToString('N')
        $reg = Join-Path $env:SystemRoot 'System32\reg.exe'
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $loadOut = & $reg load "HKU\$mount" $UserProfile.NtUser 2>&1
        $loadCode = $LASTEXITCODE
        $ErrorActionPreference = $prev
        if ($loadCode -ne 0) {
            Write-Line ("Hive: could not load {0} ({1})" -f $UserProfile.Name, (($loadOut | Out-String).Trim()))
            return
        }
        $mounted = $true
    }
    $root = $null
    try {
        $root = [Microsoft.Win32.Registry]::Users.OpenSubKey($mount, $false)
        if ($root) { Add-ArpFromKey -BaseKey $root -Scope $UserProfile.Name -List $List -Skipped $Skipped }
    }
    finally {
        if ($root) { $root.Dispose() }
        if ($mounted) {
            if (-not (Dismount-UserHive -Mount $mount)) {
                Write-Line ("Hive: still loaded at HKU\{0} for {1}" -f $mount, $UserProfile.Name)
            }
        }
    }
}

function Get-ArpEntries {
    $list = New-Object System.Collections.Generic.List[object]
    $skipped = New-Object System.Collections.Generic.List[string]
    $hklm = Open-MachineKey
    try { Add-ArpFromKey -BaseKey $hklm -Scope 'Machine' -List $list -Skipped $skipped }
    finally { if ($hklm) { $hklm.Dispose() } }
    try {
        $hkcu = [Microsoft.Win32.Registry]::CurrentUser
        Add-ArpFromKey -BaseKey $hkcu -Scope 'CurrentUser' -List $list -Skipped $skipped
    }
    catch { }
    if (Test-IsAdmin) {
        foreach ($userProfile in @(Get-UserProfiles)) {
            Add-ProfileArp -UserProfile $userProfile -List $list -Skipped $skipped
        }
    }
    else {
        Write-Line 'Hive: not elevated, so other users'' per-user installs are not listed.'
    }
    $deduped = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($entry in $list) {
        $id = $entry.ProductCode
        if (-not $id) { $id = $entry.QuietUninstallString }
        if (-not $id) { $id = $entry.UninstallString }
        if (-not $id) { $id = '{0}|{1}|{2}' -f $entry.DisplayName, $entry.Scope, $entry.InstallLocation }
        $key = $id.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$deduped.Add($entry)
    }
    return @{ Entries = $deduped.ToArray(); Skipped = @($skipped.ToArray() | Select-Object -Unique) }
}

function Get-OfficialPythonHomes {
    $homes = New-Object System.Collections.Generic.List[object]
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, 'C:\')) {
        if ($root) { [void]$roots.Add($root) }
    }
    foreach ($userProfile in @(Get-UserProfiles)) {
        $userRoot = Join-Path $userProfile.ProfilePath 'AppData\Local\Programs\Python'
        if ($userRoot) { [void]$roots.Add($userRoot) }
    }
    $currentLocal = Join-Path $env:LOCALAPPDATA 'Programs\Python'
    if ($currentLocal) { [void]$roots.Add($currentLocal) }

    $seen = @{}
    foreach ($root in @($roots)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            if ($dir.Name -notmatch '(?i)^Python(\d{2,3}|2\.7)$') { continue }
            $full = $dir.FullName.TrimEnd('\')
            $key = $full.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $py = Join-Path $full 'python.exe'
            if (-not (Test-Path -LiteralPath $py)) { continue }
            $scope = 'Folder'
            if ($full -match '(?i)\\Users\\([^\\]+)\\') { $scope = $Matches[1] }
            elseif ($full -match '(?i)\\Program Files') { $scope = 'Machine' }
            [void]$homes.Add([pscustomobject]@{
                    Path  = $full
                    Exe   = $py
                    Scope = $scope
                })
        }
    }
    return $homes.ToArray()
}

function Get-PythonExeVersion {
    param([string]$Exe)
    try {
        $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($Exe)
        foreach ($text in @($info.ProductVersion, $info.FileVersion)) {
            $parsed = ConvertTo-PythonVersion $text
            if ($parsed -and $parsed.Build -ge 0 -and $parsed.Build -lt 100) { return $parsed }
        }
    }
    catch { }
    return $null
}

function Get-StorePackages {
    $pkgs = @()
    try { $pkgs = @(Get-AppxPackage -Name 'PythonSoftwareFoundation.Python.*' -AllUsers -ErrorAction SilentlyContinue) } catch { $pkgs = @() }
    if ($pkgs.Count -eq 0) {
        try { $pkgs = @(Get-AppxPackage -Name 'PythonSoftwareFoundation.Python.*' -ErrorAction SilentlyContinue) } catch { $pkgs = @() }
    }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($pkg in @($pkgs)) {
        if (-not $pkg) { continue }
        $version = ConvertTo-PythonVersion ([string]$pkg.Version)
        [void]$list.Add([pscustomobject]@{
                Name            = [string]$pkg.Name
                PackageFullName = [string]$pkg.PackageFullName
                Version         = $version
                Scope           = 'Store'
            })
    }
    return $list.ToArray()
}

function Stop-PythonUnder {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $prefix = $Path.TrimEnd('\') + '\'
    $procs = @(Get-Process -Name python, pythonw -ErrorAction SilentlyContinue | Where-Object {
            $_.Path -and $_.Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
        })
    foreach ($proc in $procs) {
        Write-Line ("Stop: {0} PID {1}" -f $proc.ProcessName, $proc.Id)
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-QuietUninstall {
    param($Entry)
    $command = $Entry.QuietUninstallString
    if ([string]::IsNullOrWhiteSpace($command)) { $command = $Entry.UninstallString }
    if ([string]::IsNullOrWhiteSpace($command) -and $Entry.ProductCode) {
        $command = "msiexec.exe /X$($Entry.ProductCode)"
    }
    if ([string]::IsNullOrWhiteSpace($command)) {
        Write-Line ("No uninstall string: {0}" -f $Entry.DisplayName)
        return 1
    }
    $exe = $null
    $arg = ''
    $trim = $command.Trim()
    if ($trim -match '^"([^"]+)"\s*(.*)$') {
        $exe = $Matches[1]
        $arg = [string]$Matches[2]
    }
    else {
        $parts = $trim -split '\s+', 2
        $exe = $parts[0]
        if ($parts.Count -gt 1) { $arg = $parts[1] }
    }
    if ($exe -match '(?i)msiexec(\.exe)?$' -or $command -match '(?i)msiexec') {
        $guid = $Entry.ProductCode
        if (-not $guid -and $command -match '\{[0-9A-Fa-f-]{36}\}') { $guid = $Matches[0] }
        if (-not $guid) {
            Write-Line ("No product code: {0}" -f $Entry.DisplayName)
            return 1
        }
        $msi = Join-Path $env:SystemRoot 'System32\msiexec.exe'
        Write-Line ("msiexec /x $guid /qn /norestart")
        $p = Start-Process -FilePath $msi -ArgumentList @('/x', $guid, '/qn', '/norestart') -Wait -PassThru -WindowStyle Hidden
        if ($p) { return [int]$p.ExitCode }
        return 1
    }
    if (-not (Test-Path -LiteralPath $exe)) {
        Write-Line ("Uninstall exe missing: $exe")
        return 1
    }
    if ($arg -notmatch '(?i)(^|\s)/quiet(\s|$)') { $arg = ($arg + ' /quiet').Trim() }
    if ($arg -notmatch '(?i)/uninstall') { $arg = ($arg + ' /uninstall').Trim() }
    Write-Line ("Running $exe $arg")
    $p = Start-Process -FilePath $exe -ArgumentList $arg -Wait -PassThru -WindowStyle Hidden
    if ($p) { return [int]$p.ExitCode }
    return 1
}

function Test-UninstallOk {
    param([int]$Code)
    return $Code -in 0, 3010, 1641, 1605
}

function Get-GroupKey {
    param($Entry)
    $ver = if ($Entry.Version) { [string]$Entry.Version } else { 'unknown' }
    return '{0}|{1}|{2}|{3}' -f $Entry.Scope, $Entry.Arch, $ver, $Entry.InstallLocation
}

function Build-Targets {
    param($Arp, $Homes, $Store)
    $targets = New-Object System.Collections.Generic.List[object]
    $locations = @{}
    $groups = @{}
    foreach ($entry in @($Arp)) {
        $key = Get-GroupKey $entry
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = New-Object System.Collections.Generic.List[object]
        }
        [void]$groups[$key].Add($entry)
        if ($entry.InstallLocation) { $locations[$entry.InstallLocation.ToLowerInvariant()] = $true }
    }
    foreach ($key in @($groups.Keys)) {
        $entries = $groups[$key].ToArray()
        $bundle = @($entries | Where-Object { $_.Bundle } | Select-Object -First 1)
        $head = if ($bundle.Count -gt 0) { $bundle[0] } else { $entries[0] }
        $verdict = Get-PythonVerdict -Version $head.Version -EolOnly:$EolOnly
        [void]$targets.Add([pscustomobject]@{
                Kind        = 'Arp'
                Display     = $head.DisplayName
                Version     = $head.Version
                Arch        = $head.Arch
                Scope       = $head.Scope
                Path        = $head.InstallLocation
                Reason      = $verdict.Reason
                Vulnerable  = [bool]$verdict.Vulnerable
                Entries     = $entries
                PackageName = ''
            })
    }
    foreach ($pyHome in @($Homes)) {
        if ($locations.ContainsKey($pyHome.Path.ToLowerInvariant())) { continue }
        $version = Get-PythonExeVersion -Exe $pyHome.Exe
        $verdict = Get-PythonVerdict -Version $version -EolOnly:$EolOnly
        [void]$targets.Add([pscustomobject]@{
                Kind        = 'Folder'
                Display     = ('Python {0}' -f $(if ($version) { $version } else { 'unknown' }))
                Version     = $version
                Arch        = ''
                Scope       = $pyHome.Scope
                Path        = $pyHome.Path
                Reason      = $verdict.Reason
                Vulnerable  = [bool]$verdict.Vulnerable
                Entries     = @()
                PackageName = ''
            })
    }
    foreach ($pkg in @($Store)) {
        $verdict = Get-PythonVerdict -Version $pkg.Version -EolOnly:$EolOnly
        $reason = $verdict.Reason
        $vulnerable = [bool]$verdict.Vulnerable
        if ($pkg.Version -and $pkg.Version.Build -ge 100 -and -not $vulnerable) {
            $reason = "store build $($pkg.Version) (kept; patch level is not a CPython version)"
        }
        [void]$targets.Add([pscustomobject]@{
                Kind        = 'Store'
                Display     = $pkg.Name
                Version     = $pkg.Version
                Arch        = ''
                Scope       = 'Store'
                Path        = ''
                Reason      = $reason
                Vulnerable  = $vulnerable
                Entries     = @()
                PackageName = $pkg.PackageFullName
            })
    }
    return $targets.ToArray()
}

function Format-Target {
    param($Target)
    $ver = if ($Target.Version) { [string]$Target.Version } else { 'unknown' }
    $where = $Target.Scope
    if ($Target.Arch) { $where = '{0} {1}' -f $Target.Scope, $Target.Arch }
    $path = ''
    if ($Target.Path) { $path = ' | ' + $Target.Path }
    return ('{0} {1} | {2} | {3}{4}' -f $Target.Display, $ver, $where, $Target.Reason, $path)
}

function Remove-Target {
    param($Target)
    if ($Target.Path) { Stop-PythonUnder -Path $Target.Path }
    if ($Target.Kind -eq 'Folder') {
        Write-Line ("Remove folder: {0}" -f $Target.Path)
        Remove-Item -LiteralPath $Target.Path -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $Target.Path) {
            Write-Line ("LOCKED {0}" -f $Target.Path)
            return $false
        }
        return $true
    }
    if ($Target.Kind -eq 'Store') {
        Write-Line ("Remove-AppxPackage {0}" -f $Target.PackageName)
        try {
            Remove-AppxPackage -Package $Target.PackageName -AllUsers -ErrorAction Stop
        }
        catch {
            try { Remove-AppxPackage -Package $Target.PackageName -ErrorAction Stop }
            catch {
                Write-Line ("Store remove failed: {0}" -f $_.Exception.Message)
                return $false
            }
        }
        return $true
    }
    $ordered = @($Target.Entries | Sort-Object @{ Expression = { -not $_.Bundle } })
    $bundleOk = $false
    $anyFail = $false
    foreach ($entry in $ordered) {
        if ($bundleOk -and -not $entry.Bundle) { continue }
        $code = Invoke-QuietUninstall -Entry $entry
        Write-Line ("Uninstall exit {0}: {1}" -f $code, $entry.DisplayName)
        if (Test-UninstallOk $code) {
            if ($entry.Bundle) { $bundleOk = $true }
        }
        else { $anyFail = $true }
    }
    return -not $anyFail
}

Write-Line '=== Vulnerable Python ==='
$admin = Test-IsAdmin
Write-Line ("Elevated: {0}" -f $admin)
if ($EolOnly) { Write-Line 'Scope: end-of-life branches only (3.10 and older).' }
else { Write-Line 'Scope: end-of-life branches, and supported branches older than the current security release.' }

$arpPack = Get-ArpEntries
$homes = @(Get-OfficialPythonHomes)
$store = @(Get-StorePackages)
$targets = @(Build-Targets -Arp $arpPack.Entries -Homes $homes -Store $store)

foreach ($skip in @($arpPack.Skipped)) {
    Write-Line ("Skip: {0}" -f $skip)
}

$vulnerable = @($targets | Where-Object { $_.Vulnerable })
$kept = @($targets | Where-Object { -not $_.Vulnerable })
Write-Line ("Found: {0}" -f $targets.Count)
Write-Line ("Vulnerable: {0}" -f $vulnerable.Count)
Write-Line ("Kept: {0}" -f $kept.Count)
foreach ($item in $vulnerable) { Write-Line ("Remove: {0}" -f (Format-Target $item)) }
foreach ($item in $kept) { Write-Line ("Keep: {0}" -f (Format-Target $item)) }

if ($vulnerable.Count -eq 0) {
    Write-Line 'Result: No vulnerable CPython install found.'
    Complete-Run -Code 0
    return
}

if ($CheckOnly -or -not $Remediate) {
    Write-Line 'Action: CheckOnly'
    Write-Line 'Result: Vulnerable CPython is still installed. Re-run with -Remediate to remove it.'
    Complete-Run -Code 1
    return
}

if (-not $admin) {
    Write-Line 'Result: -Remediate needs an elevated PowerShell or SYSTEM. Nothing was removed.'
    Complete-Run -Code 2
    return
}

Write-Line 'Action: Remove'
$failed = 0
foreach ($item in $vulnerable) {
    if (-not (Remove-Target $item)) { $failed++ }
}

$afterPack = Get-ArpEntries
$afterHomes = @(Get-OfficialPythonHomes)
$afterStore = @(Get-StorePackages)
$after = @(Build-Targets -Arp $afterPack.Entries -Homes $afterHomes -Store $afterStore)
$left = @($after | Where-Object { $_.Vulnerable })
Write-Line ("Vulnerable left: {0}" -f $left.Count)
foreach ($item in $left) { Write-Line ("Still installed: {0}" -f (Format-Target $item)) }

if ($left.Count -gt 0 -or $failed -gt 0) {
    Write-Line 'Result: One or more vulnerable installs could not be removed.'
    Complete-Run -Code 2
    return
}

Write-Line 'Result: Vulnerable CPython installs were removed. Current installs were left in place.'
Complete-Run -Code 0
