#Requires -Version 5.1
<#
.SYNOPSIS
    Verifies Classic Microsoft Teams / per-user Teams remnants are gone after cleanup.

.DESCRIPTION
    ScreenConnect-friendly post-cleanup check for vuln-scan remediation evidence.
    Detects Teams Machine-Wide Installer, per-user Classic Teams under LocalAppData,
    Teams Installer folder, Run keys, and common shortcuts. Reports New Teams (MSTeams)
    as informational only.

    Exit 0 = no classic remnants. Exit 2 = remnants found. Exit 1 = error.

.PARAMETER Detailed
    Include low-signal items (empty folders, shortcuts without Teams.exe).

.PARAMETER Json
    Emit a JSON summary object after the log lines.

.PARAMETER NoExit
    Keep the PowerShell host open (Backstage). Implied for interactive ScriptBlock runs.

.PARAMETER Exit
    Always call exit with the result code (Commands / automation).
#>
[CmdletBinding()]
param(
    [switch]$Detailed,
    [switch]$Json,
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptVersion = '1.0.0'

try {
    [Net.ServicePointManager]::SecurityProtocol = (
        [Net.ServicePointManager]::SecurityProtocol -bor
        [Net.SecurityProtocolType]::Tls12
    )
}
catch {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
}

function Write-TeamsLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    # Write-Host so logs do not pollute return values.
    Write-Host "[$ts][$Level] $Message"
}

function Test-TeamsShouldExitProcess {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-TeamsCheck {
    param([Parameter(Mandatory)][int]$Code)
    $global:LASTEXITCODE = $Code
    try { $global:TeamsClassicCheckResultCode = $Code } catch { }
    if (Test-TeamsShouldExitProcess) { exit $Code }
    Write-TeamsLog ("Done. ResultCode={0} (PowerShell host kept open)." -f $Code)
}

function Test-IsWindowsHost {
    if ($null -ne (Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue)) {
        return [bool]$IsWindows
    }
    return ($env:OS -like 'Windows*')
}

function Get-UninstallEntries {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
    }
}

function Get-FileVersionSafe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return [string](Get-Item -LiteralPath $Path).VersionInfo.FileVersion
    }
    catch { return $null }
}

function Get-UserProfileRoots {
    $roots = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $skip = @('Public', 'Default', 'Default User', 'All Users', 'desktop.ini')

    $profilesKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    Get-ChildItem -Path $profilesKey -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
        $profilePath = [string]$p.ProfileImagePath
        if (-not $profilePath) { return }
        $name = Split-Path -Leaf $profilePath
        if ($skip -contains $name) { return }
        if ($profilePath -match '(?i)\\(ServiceProfiles|systemprofile|config\\systemprofile)\\') { return }
        if ($profilePath -match '(?i)\\Windows\\System32\\') { return }
        $exists = $false
        try { $exists = Test-Path -LiteralPath $profilePath -ErrorAction SilentlyContinue } catch { $exists = $false }
        if (-not $exists) { return }
        $key = $profilePath.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { return }
        $seen[$key] = $true
        $roots.Add([pscustomobject]@{
                Name = $name
                Path = $profilePath
                Sid  = [string]$_.PSChildName
            })
    }

    $usersRoot = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $usersRoot) {
        Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if ($skip -contains $_.Name) { return }
            $key = $_.FullName.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { return }
            $seen[$key] = $true
            $roots.Add([pscustomobject]@{
                    Name = $_.Name
                    Path = $_.FullName
                    Sid  = ''
                })
        }
    }

    return @($roots)
}

function Add-Finding {
    param(
        $List,
        [string]$Category,
        [string]$Path,
        [string]$Detail,
        [string]$Severity = 'fail'
    )
    $List.Add([pscustomobject]@{
            Category = $Category
            Path     = $Path
            Detail   = $Detail
            Severity = $Severity
        }) | Out-Null
}

function Get-ClassicTeamsMachineWide {
    $hits = @(
        Get-UninstallEntries | Where-Object {
            $_.DisplayName -and (
                $_.DisplayName -like 'Teams Machine-Wide Installer*' -or
                $_.DisplayName -like 'Teams Machine Wide Installer*'
            )
        }
    )
    return $hits
}

function Get-ClassicTeamsArpEntries {
    # Classic desktop ARP (not New Teams MSIX). Exclude Machine-Wide (handled separately).
    $hits = @(
        Get-UninstallEntries | Where-Object {
            $_.DisplayName -and
            $_.DisplayName -match '^(Microsoft )?Teams$' -and
            $_.DisplayName -notlike '*Machine-Wide*' -and
            $_.DisplayName -notlike '*Machine Wide*' -and
            $_.Publisher -match 'Microsoft'
        }
    )
    return $hits
}

function Test-NewTeamsPresent {
    $info = New-Object System.Collections.Generic.List[string]
    try {
        $pkgs = @(Get-AppxPackage -AllUsers -Name '*MSTeams*' -ErrorAction SilentlyContinue)
        $pkgs += @(Get-AppxPackage -AllUsers -Name '*MicrosoftTeams*' -ErrorAction SilentlyContinue)
        foreach ($pkg in ($pkgs | Sort-Object Name -Unique)) {
            [void]$info.Add(("{0} {1}" -f $pkg.Name, $pkg.Version))
        }
    }
    catch { }

    $bootstrap = @(
        "${env:ProgramFiles(x86)}\Teams Installer\Teams.exe"
        "$env:ProgramFiles\WindowsApps"
    )
    # Presence of ms-teams protocol / WindowsApps folder alone is weak; Appx is primary.
    return @($info | Select-Object -Unique)
}

# --- main ---
$hostEdition = if ($PSVersionTable.PSEdition) { [string]$PSVersionTable.PSEdition } else { 'Desktop' }
Write-TeamsLog ("TeamsClassicRemnantCheck {0}" -f $ScriptVersion)
Write-TeamsLog ("Host: PowerShell {0} ({1})" -f $PSVersionTable.PSVersion, $hostEdition)
Write-TeamsLog ("User: {0}" -f [Security.Principal.WindowsIdentity]::GetCurrent().Name)

if (-not (Test-IsWindowsHost)) {
    Write-TeamsLog 'Windows only.' 'ERROR'
    Complete-TeamsCheck -Code 1
    return
}

$findings = New-Object System.Collections.Generic.List[object]

# 1) Machine-Wide Installer
$mwi = Get-ClassicTeamsMachineWide
foreach ($item in $mwi) {
    Add-Finding -List $findings -Category 'MachineWideInstaller' -Path ([string]$item.PSPath) `
        -Detail ("{0} version={1} guid={2}" -f $item.DisplayName, $item.DisplayVersion, $item.PSChildName)
}

# 2) Classic ARP (rare for classic; still report)
foreach ($item in (Get-ClassicTeamsArpEntries)) {
    Add-Finding -List $findings -Category 'ClassicArp' -Path ([string]$item.PSPath) `
        -Detail ("{0} version={1}" -f $item.DisplayName, $item.DisplayVersion)
}

# 3) Program Files Teams Installer (classic MWI payload folder)
$installerDirs = @(
    "${env:ProgramFiles(x86)}\Teams Installer"
    "$env:ProgramFiles\Teams Installer"
)
foreach ($dir in $installerDirs) {
    if (Test-Path -LiteralPath $dir) {
        $teamsExe = Join-Path $dir 'Teams.exe'
        $ver = Get-FileVersionSafe -Path $teamsExe
        $detail = if ($ver) { "Teams Installer folder present; Teams.exe version=$ver" } else { 'Teams Installer folder present' }
        Add-Finding -List $findings -Category 'TeamsInstallerFolder' -Path $dir -Detail $detail
    }
}

# 4) HKLM Run
$runKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
)
foreach ($rk in $runKeys) {
    try {
        $props = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
        if ($null -eq $props) { continue }
        foreach ($name in @('Teams', 'com.squirrel.Teams.Teams', 'TeamsMachineInstaller')) {
            if ($null -ne $props.$name) {
                Add-Finding -List $findings -Category 'RunKeyHKLM' -Path "$rk\$name" `
                    -Detail ([string]$props.$name)
            }
        }
    }
    catch { }
}

# 5) Per-user classic Teams
$profiles = Get-UserProfileRoots
Write-TeamsLog ("Scanning {0} user profile(s) for Classic Teams..." -f $profiles.Count)

foreach ($profile in $profiles) {
    $teamsRoot = Join-Path $profile.Path 'AppData\Local\Microsoft\Teams'
    $teamsExe = Join-Path $teamsRoot 'current\Teams.exe'
    $updateExe = Join-Path $teamsRoot 'Update.exe'
    $squirrel = Join-Path $teamsRoot 'Squirrel.exe'

    if (Test-Path -LiteralPath $teamsExe) {
        $ver = Get-FileVersionSafe -Path $teamsExe
        Add-Finding -List $findings -Category 'PerUserTeamsExe' -Path $teamsExe `
            -Detail ("profile={0} version={1}" -f $profile.Name, $(if ($ver) { $ver } else { 'unknown' }))
    }
    elseif (Test-Path -LiteralPath $updateExe) {
        Add-Finding -List $findings -Category 'PerUserUpdateExe' -Path $updateExe `
            -Detail ("profile={0}" -f $profile.Name)
    }
    elseif (Test-Path -LiteralPath $squirrel) {
        Add-Finding -List $findings -Category 'PerUserSquirrel' -Path $squirrel `
            -Detail ("profile={0}" -f $profile.Name)
    }
    elseif ((Test-Path -LiteralPath $teamsRoot) -and $Detailed) {
        Add-Finding -List $findings -Category 'PerUserTeamsFolder' -Path $teamsRoot `
            -Detail ("profile={0} (folder only)" -f $profile.Name) -Severity 'warn'
    }
    elseif (Test-Path -LiteralPath $teamsRoot) {
        # Non-empty classic tree without current\Teams.exe still counts as remnant.
        $any = Get-ChildItem -LiteralPath $teamsRoot -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($any) {
            Add-Finding -List $findings -Category 'PerUserTeamsFolder' -Path $teamsRoot `
                -Detail ("profile={0} (files present, no current\\Teams.exe)" -f $profile.Name)
        }
    }

    $shortcutFolders = @(
        (Join-Path $profile.Path 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup')
        (Join-Path $profile.Path 'Desktop')
    )
    foreach ($folder in $shortcutFolders) {
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        Get-ChildItem -LiteralPath $folder -Filter '*Teams*.lnk' -ErrorAction SilentlyContinue | ForEach-Object {
            $sev = if ($Detailed) { 'fail' } else { 'warn' }
            Add-Finding -List $findings -Category 'Shortcut' -Path $_.FullName `
                -Detail ("profile={0}" -f $profile.Name) -Severity $sev
        }
    }
}

# Loaded user Run keys (HKU)
Get-ChildItem 'HKU:\' -ErrorAction SilentlyContinue | Where-Object {
    $_.PSChildName -match '^S-1-5-21-\d+-\d+-\d+-\d+$'
} | ForEach-Object {
    $rk = Join-Path $_.PSPath 'Software\Microsoft\Windows\CurrentVersion\Run'
    try {
        $props = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
        if ($null -eq $props) { return }
        foreach ($name in @('Teams', 'com.squirrel.Teams.Teams')) {
            if ($null -ne $props.$name) {
                Add-Finding -List $findings -Category 'RunKeyHKU' -Path "$rk\$name" `
                    -Detail ([string]$props.$name)
            }
        }
    }
    catch { }
}

$newTeams = Test-NewTeamsPresent
if ($newTeams.Count -gt 0) {
    Write-TeamsLog ("New Teams present (informational): {0}" -f ($newTeams -join '; '))
}
else {
    Write-TeamsLog 'New Teams (MSTeams Appx): not detected'
}

$fails = @($findings | Where-Object { $_.Severity -eq 'fail' })
$warns = @($findings | Where-Object { $_.Severity -eq 'warn' })

Write-TeamsLog ("Findings: {0} fail, {1} warn" -f $fails.Count, $warns.Count)

if ($fails.Count -eq 0 -and $warns.Count -eq 0) {
    Write-TeamsLog 'PASS: no Classic / per-user Teams remnants detected.'
}
else {
    foreach ($f in $findings) {
        $lvl = if ($f.Severity -eq 'fail') { 'ERROR' } else { 'WARN' }
        Write-TeamsLog -Level $lvl -Message ("[{0}] {1}: {2} | {3}" -f $f.Severity.ToUpperInvariant(), $f.Category, $f.Path, $f.Detail)
    }
    if ($fails.Count -gt 0) {
        Write-TeamsLog 'FAIL: Classic Teams remnants still present - cleanup incomplete for vuln remediation.' 'ERROR'
    }
    else {
        Write-TeamsLog 'WARN-only findings (shortcuts/empty). Re-run with cleanup if scanners still flag the host.' 'WARN'
    }
}

if ($Json) {
    $summary = [pscustomobject]@{
        ScriptVersion = $ScriptVersion
        FailCount     = $fails.Count
        WarnCount     = $warns.Count
        NewTeams      = $newTeams
        Findings      = @($findings)
        Compliant     = ($fails.Count -eq 0)
    }
    $summary | ConvertTo-Json -Depth 6
}

# Exit 2 if any fail findings; warn-only still 0 unless -Detailed wants otherwise.
# Treat warn-only as non-zero (2) when -Detailed so automation can catch shortcuts.
if ($fails.Count -gt 0) {
    Complete-TeamsCheck -Code 2
    return
}
if ($Detailed -and $warns.Count -gt 0) {
    Complete-TeamsCheck -Code 2
    return
}
Complete-TeamsCheck -Code 0
return
