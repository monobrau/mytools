#Requires -Version 5.1
<#
.SYNOPSIS
    Checks (and optionally remediates) Classic Microsoft Teams / per-user Teams remnants.

.DESCRIPTION
    ScreenConnect-friendly vuln-scan helper. Detects Teams Machine-Wide Installer, per-user
    Classic Teams under LocalAppData, Teams Installer folder, Run keys, and shortcuts.
    New Teams (MSTeams) is informational only.

    Default: check only.
    -Remediate: uninstall MWI, remove installer folder/run keys, uninstall/delete per-user Classic.

    Exit 0 = clean. Exit 2 = remnants still present. Exit 1 = error.

.PARAMETER Remediate
    Remove Classic Teams remnants only (MWI, classic per-user folder, classic Run keys,
    Teams Installer folder). Never removes New Teams (MSTeams Appx).

.PARAMETER ForceClassicUserRemoval
    With -Remediate: remove classic per-user installs even when New Teams is not detected.
    Default is safer: only strip classic per-user when New Teams is present on the device.

.PARAMETER Detailed
    Include low-signal items; with check, shortcuts fail the result.

.PARAMETER Json
    Emit a JSON summary object after the log lines.

.PARAMETER NoExit
    Keep the PowerShell host open (Backstage).

.PARAMETER Exit
    Always call exit with the result code (Commands / automation).
#>
[CmdletBinding()]
param(
    [switch]$Remediate,
    [switch]$ForceClassicUserRemoval,
    [switch]$Detailed,
    [switch]$Json,
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptVersion = '1.2.0'
$KnownMwiGuid = '{731F6BAA-A986-45A4-8936-7C3AAAAA760B}'

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

function Test-PathSafe {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { return [bool](Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue) }
    catch { return $false }
}

function Get-FileVersionSafe {
    param([string]$Path)
    if (-not (Test-PathSafe -Path $Path)) { return $null }
    try {
        return [string](Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue).VersionInfo.FileVersion
    }
    catch { return $null }
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

function Get-UserProfileRoots {
    $roots = @()
    $seen = @{}
    $skip = @('Public', 'Default', 'Default User', 'All Users', 'desktop.ini')

    $profilesKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    Get-ChildItem -Path $profilesKey -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
        $profilePath = [string]$p.ProfileImagePath
        if ([string]::IsNullOrWhiteSpace($profilePath)) { return }
        $name = [string](Split-Path -Leaf $profilePath)
        if ($skip -contains $name) { return }
        if ($profilePath -match '(?i)ServiceProfiles|systemprofile|Windows\\System32') { return }
        if (-not (Test-PathSafe -Path $profilePath)) { return }
        $key = $profilePath.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { return }
        $seen[$key] = $true
        $roots += [pscustomobject]@{
            Name = $name
            Path = $profilePath
            Sid  = [string]$_.PSChildName
        }
    }

    $usersRoot = Join-Path $env:SystemDrive 'Users'
    if (Test-PathSafe -Path $usersRoot) {
        Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $name = [string]$_.Name
            if ($skip -contains $name) { return }
            $full = [string]$_.FullName
            $key = $full.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { return }
            $seen[$key] = $true
            $roots += [pscustomobject]@{
                Name = $name
                Path = $full
                Sid  = ''
            }
        }
    }

    return ,$roots
}

function Add-Finding {
    param(
        [System.Collections.ArrayList]$List,
        [string]$Category,
        [string]$Path,
        [string]$Detail,
        [string]$Severity = 'fail'
    )
    [void]$List.Add([pscustomobject]@{
            Category = $Category
            Path     = $Path
            Detail   = $Detail
            Severity = $Severity
        })
}

function Get-ClassicTeamsMachineWide {
    @(
        Get-UninstallEntries | Where-Object {
            $_.DisplayName -and (
                $_.DisplayName -like 'Teams Machine-Wide Installer*' -or
                $_.DisplayName -like 'Teams Machine Wide Installer*'
            )
        }
    )
}

function Get-ClassicTeamsArpEntries {
    @(
        Get-UninstallEntries | Where-Object {
            $_.DisplayName -and
            $_.DisplayName -match '^(Microsoft )?Teams$' -and
            $_.DisplayName -notlike '*Machine-Wide*' -and
            $_.DisplayName -notlike '*Machine Wide*' -and
            $_.Publisher -match 'Microsoft'
        }
    )
}

function Test-NewTeamsPresent {
    $info = @()
    try {
        $pkgs = @()
        $pkgs += @(Get-AppxPackage -AllUsers -Name '*MSTeams*' -ErrorAction SilentlyContinue)
        $pkgs += @(Get-AppxPackage -AllUsers -Name '*MicrosoftTeams*' -ErrorAction SilentlyContinue)
        foreach ($pkg in ($pkgs | Sort-Object Name -Unique)) {
            $info += ("{0} {1}" -f $pkg.Name, $pkg.Version)
        }
    }
    catch { }
    return @($info | Select-Object -Unique)
}

function Invoke-TeamsScan {
    $findings = New-Object System.Collections.ArrayList

    foreach ($item in (Get-ClassicTeamsMachineWide)) {
        Add-Finding -List $findings -Category 'MachineWideInstaller' -Path ([string]$item.PSPath) `
            -Detail ("{0} version={1} guid={2}" -f $item.DisplayName, $item.DisplayVersion, $item.PSChildName)
    }

    foreach ($item in (Get-ClassicTeamsArpEntries)) {
        Add-Finding -List $findings -Category 'ClassicArp' -Path ([string]$item.PSPath) `
            -Detail ("{0} version={1}" -f $item.DisplayName, $item.DisplayVersion)
    }

    foreach ($dir in @("${env:ProgramFiles(x86)}\Teams Installer", "$env:ProgramFiles\Teams Installer")) {
        if (Test-PathSafe -Path $dir) {
            $teamsExe = Join-Path $dir 'Teams.exe'
            $ver = Get-FileVersionSafe -Path $teamsExe
            $detail = if ($ver) { "Teams Installer folder present; Teams.exe version=$ver" } else { 'Teams Installer folder present' }
            Add-Finding -List $findings -Category 'TeamsInstallerFolder' -Path $dir -Detail $detail
        }
    }

    foreach ($rk in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        )) {
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

    $profiles = Get-UserProfileRoots
    Write-TeamsLog ("Scanning {0} user profile(s) for Classic Teams..." -f @($profiles).Count)

    foreach ($profile in $profiles) {
        $teamsRoot = Join-Path $profile.Path 'AppData\Local\Microsoft\Teams'
        $teamsExe = Join-Path $teamsRoot 'current\Teams.exe'
        $updateExe = Join-Path $teamsRoot 'Update.exe'
        $squirrel = Join-Path $teamsRoot 'Squirrel.exe'

        if (Test-PathSafe -Path $teamsExe) {
            $ver = Get-FileVersionSafe -Path $teamsExe
            Add-Finding -List $findings -Category 'PerUserTeamsExe' -Path $teamsExe `
                -Detail ("profile={0} version={1}" -f $profile.Name, $(if ($ver) { $ver } else { 'unknown' }))
        }
        elseif (Test-PathSafe -Path $updateExe) {
            Add-Finding -List $findings -Category 'PerUserUpdateExe' -Path $updateExe `
                -Detail ("profile={0}" -f $profile.Name)
        }
        elseif (Test-PathSafe -Path $squirrel) {
            Add-Finding -List $findings -Category 'PerUserSquirrel' -Path $squirrel `
                -Detail ("profile={0}" -f $profile.Name)
        }
        elseif ((Test-PathSafe -Path $teamsRoot) -and $Detailed) {
            Add-Finding -List $findings -Category 'PerUserTeamsFolder' -Path $teamsRoot `
                -Detail ("profile={0} (folder only)" -f $profile.Name) -Severity 'warn'
        }
        elseif (Test-PathSafe -Path $teamsRoot) {
            $any = $null
            try {
                $any = Get-ChildItem -LiteralPath $teamsRoot -Recurse -File -ErrorAction SilentlyContinue |
                    Select-Object -First 1
            }
            catch { $any = $null }
            if ($any) {
                Add-Finding -List $findings -Category 'PerUserTeamsFolder' -Path $teamsRoot `
                    -Detail ("profile={0} (files present, no current\\Teams.exe)" -f $profile.Name)
            }
        }

        foreach ($folder in @(
                (Join-Path $profile.Path 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup')
                (Join-Path $profile.Path 'Desktop')
            )) {
            if (-not (Test-PathSafe -Path $folder)) { continue }
            Get-ChildItem -LiteralPath $folder -Filter '*Teams*.lnk' -ErrorAction SilentlyContinue | ForEach-Object {
                $sev = if ($Detailed) { 'fail' } else { 'warn' }
                Add-Finding -List $findings -Category 'Shortcut' -Path $_.FullName `
                    -Detail ("profile={0}" -f $profile.Name) -Severity $sev
            }
        }
    }

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

    return $findings
}

function Test-IsClassicTeamsProcess {
    param($Process)
    # Never touch New Teams (ms-teams / WindowsApps / MSTeams).
    $path = ''
    try { $path = [string]$Process.Path } catch { $path = '' }
    if ([string]::IsNullOrWhiteSpace($path)) {
        try { $path = [string]$Process.MainModule.FileName } catch { $path = '' }
    }
    $name = [string]$Process.ProcessName
    if ($name -match '(?i)^ms-teams$') { return $false }
    if ($path -match '(?i)WindowsApps|MSTeams|ms-teams\.exe') { return $false }

    # Classic squirrel client / updater only.
    if ($path -match '(?i)\\AppData\\Local\\Microsoft\\Teams\\') { return $true }
    if ($path -match '(?i)\\Teams Installer\\') { return $true }
    if ($name -match '(?i)^(Teams|Update|Squirrel)$' -and $path -match '(?i)\\Teams') { return $true }
    return $false
}

function Stop-ClassicTeamsProcesses {
    # Do NOT stop ms-teams - that is New Teams.
    foreach ($n in @('Teams', 'Update', 'Squirrel')) {
        Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not (Test-IsClassicTeamsProcess -Process $_)) {
                Write-TeamsLog ("Skipping non-classic process {0} (PID {1})" -f $_.ProcessName, $_.Id)
                return
            }
            try {
                Write-TeamsLog ("Stopping classic process {0} (PID {1})" -f $_.ProcessName, $_.Id)
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
            catch { }
        }
    }
}

function Test-ShortcutTargetsClassicTeams {
    param([string]$LnkPath)
    try {
        $sh = New-Object -ComObject WScript.Shell
        $sc = $sh.CreateShortcut($LnkPath)
        $target = [string]$sc.TargetPath
        $args = [string]$sc.Arguments
        if ($target -match '(?i)WindowsApps|ms-teams|MSTeams') { return $false }
        if ($target -match '(?i)\\AppData\\Local\\Microsoft\\Teams\\') { return $true }
        if ($target -match '(?i)\\Teams Installer\\') { return $true }
        if ($args -match '(?i)Local\\Microsoft\\Teams') { return $true }
        return $false
    }
    catch { return $false }
}

function Invoke-ClassicTeamsRemediate {
    Write-TeamsLog 'Starting Classic-only Teams remediation (New Teams / MSTeams will be left alone)...'

    $newTeams = @(Test-NewTeamsPresent)
    $newTeamsPresent = ($newTeams.Count -gt 0)
    if ($newTeamsPresent) {
        Write-TeamsLog ("New Teams detected - safe to remove Classic per-user clients: {0}" -f ($newTeams -join '; '))
    }
    else {
        Write-TeamsLog 'New Teams NOT detected. Will remove MWI/installer/run keys, but skip per-user Classic folders unless -ForceClassicUserRemoval.' 'WARN'
    }

    Stop-ClassicTeamsProcesses

    # Machine-wide Classic stager (does not remove New Teams).
    $guids = New-Object System.Collections.ArrayList
    [void]$guids.Add($KnownMwiGuid)
    foreach ($item in (Get-ClassicTeamsMachineWide)) {
        $g = [string]$item.PSChildName
        if ($g -and -not ($guids -contains $g)) { [void]$guids.Add($g) }
    }

    foreach ($guid in $guids) {
        if ($guid -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { continue }
        Write-TeamsLog ("msiexec /x {0} /qn /norestart (Classic MWI)" -f $guid)
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $guid, '/qn', '/norestart') `
            -Wait -PassThru -WindowStyle Hidden
        Write-TeamsLog ("msiexec exit: {0}" -f $p.ExitCode)
    }

    foreach ($rk in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        )) {
        foreach ($name in @('Teams', 'com.squirrel.Teams.Teams', 'TeamsMachineInstaller')) {
            try {
                $props = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
                if ($null -ne $props -and $null -ne $props.$name) {
                    $val = [string]$props.$name
                    if ($val -match '(?i)WindowsApps|ms-teams|MSTeams') {
                        Write-TeamsLog ("Skipping Run value (looks like New Teams): {0}\{1}" -f $rk, $name)
                        continue
                    }
                    Write-TeamsLog ("Removing Classic Run value {0}\{1}" -f $rk, $name)
                    Remove-ItemProperty -Path $rk -Name $name -Force -ErrorAction SilentlyContinue
                }
            }
            catch { }
        }
    }

    foreach ($dir in @("${env:ProgramFiles(x86)}\Teams Installer", "$env:ProgramFiles\Teams Installer")) {
        if (Test-PathSafe -Path $dir) {
            Write-TeamsLog ("Removing Classic installer folder {0}" -f $dir)
            try { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
            catch { Write-TeamsLog ("Could not remove {0}: {1}" -f $dir, $_.Exception.Message) 'WARN' }
        }
    }

    $removePerUser = $newTeamsPresent -or $ForceClassicUserRemoval
    if (-not $removePerUser) {
        Write-TeamsLog 'Skipping per-user Classic removal (no New Teams on device). Use -ForceClassicUserRemoval to override.' 'WARN'
    }

    foreach ($profile in (Get-UserProfileRoots)) {
        $teamsRoot = Join-Path $profile.Path 'AppData\Local\Microsoft\Teams'
        $updateExe = Join-Path $teamsRoot 'Update.exe'
        $classicExe = Join-Path $teamsRoot 'current\Teams.exe'
        $isClassicTree = (Test-PathSafe -Path $updateExe) -or (Test-PathSafe -Path $classicExe) -or (Test-PathSafe -Path (Join-Path $teamsRoot 'Squirrel.exe'))

        if ($removePerUser -and $isClassicTree) {
            if (Test-PathSafe -Path $updateExe) {
                Write-TeamsLog ("Per-user Classic silent uninstall: {0}" -f $updateExe)
                try {
                    $p = Start-Process -FilePath $updateExe -ArgumentList @('--uninstall', '-s') `
                        -Wait -PassThru -WindowStyle Hidden
                    Write-TeamsLog ("Update.exe uninstall exit: {0} (profile={1})" -f $p.ExitCode, $profile.Name)
                }
                catch {
                    Write-TeamsLog ("Update.exe uninstall failed for {0}: {1}" -f $profile.Name, $_.Exception.Message) 'WARN'
                }
            }
            if (Test-PathSafe -Path $teamsRoot) {
                Write-TeamsLog ("Removing Classic per-user folder: {0}" -f $teamsRoot)
                try { Remove-Item -LiteralPath $teamsRoot -Recurse -Force -ErrorAction SilentlyContinue }
                catch { Write-TeamsLog ("Could not remove {0}" -f $teamsRoot) 'WARN' }
            }
        }
        elseif ($isClassicTree -and -not $removePerUser) {
            Write-TeamsLog ("Kept Classic per-user folder (no New Teams / no force): {0}" -f $teamsRoot) 'WARN'
        }

        # Shortcuts: only delete those that target Classic paths (never New Teams).
        foreach ($folder in @(
                (Join-Path $profile.Path 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup')
                (Join-Path $profile.Path 'Desktop')
                (Join-Path $profile.Path 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs')
            )) {
            if (-not (Test-PathSafe -Path $folder)) { continue }
            Get-ChildItem -LiteralPath $folder -Filter '*Teams*.lnk' -Recurse -ErrorAction SilentlyContinue |
                ForEach-Object {
                    if (Test-ShortcutTargetsClassicTeams -LnkPath $_.FullName) {
                        Write-TeamsLog ("Removing Classic shortcut {0}" -f $_.FullName)
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        Write-TeamsLog ("Keeping shortcut (not Classic target): {0}" -f $_.FullName)
                    }
                }
        }
    }

    Get-ChildItem 'HKU:\' -ErrorAction SilentlyContinue | Where-Object {
        $_.PSChildName -match '^S-1-5-21-\d+-\d+-\d+-\d+$'
    } | ForEach-Object {
        $rk = Join-Path $_.PSPath 'Software\Microsoft\Windows\CurrentVersion\Run'
        foreach ($name in @('Teams', 'com.squirrel.Teams.Teams')) {
            try {
                $props = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
                if ($null -ne $props -and $null -ne $props.$name) {
                    $val = [string]$props.$name
                    if ($val -match '(?i)WindowsApps|ms-teams|MSTeams') {
                        Write-TeamsLog ("Skipping HKU Run (New Teams): {0}" -f $name)
                        continue
                    }
                    Write-TeamsLog ("Removing Classic HKU Run {0}" -f $name)
                    Remove-ItemProperty -Path $rk -Name $name -Force -ErrorAction SilentlyContinue
                }
            }
            catch { }
        }
    }

    Write-TeamsLog 'Remediation pass complete. Re-scanning...'
    Write-TeamsLog 'Note: Office/PROPLUS can reinstall Classic MWI if classic Teams remains in the Office deployment channel.' 'WARN'
}

# --- main ---
$hostEdition = if ($PSVersionTable.PSEdition) { [string]$PSVersionTable.PSEdition } else { 'Desktop' }
Write-TeamsLog ("TeamsClassicRemnantCheck {0}" -f $ScriptVersion)
Write-TeamsLog ("Host: PowerShell {0} ({1})" -f $PSVersionTable.PSVersion, $hostEdition)
Write-TeamsLog ("User: {0} | Remediate={1} ForceClassicUserRemoval={2}" -f `
        [Security.Principal.WindowsIdentity]::GetCurrent().Name, $Remediate, $ForceClassicUserRemoval)

if (-not (Test-IsWindowsHost)) {
    Write-TeamsLog 'Windows only.' 'ERROR'
    Complete-TeamsCheck -Code 1
    return
}

if ($Remediate) {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-TeamsLog 'Elevation required for -Remediate (run as SYSTEM / Administrator).' 'ERROR'
        Complete-TeamsCheck -Code 1
        return
    }
    Invoke-ClassicTeamsRemediate
}

$findings = Invoke-TeamsScan
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
        Write-TeamsLog 'FAIL: Classic Teams remnants still present.' 'ERROR'
        if (-not $Remediate) {
            Write-TeamsLog 'Re-run with -Remediate to remove MWI / per-user Classic / Run keys.' 'WARN'
        }
    }
    else {
        Write-TeamsLog 'WARN-only findings remain.' 'WARN'
    }
}

if ($Json) {
    [pscustomobject]@{
        ScriptVersion = $ScriptVersion
        Remediate     = [bool]$Remediate
        FailCount     = $fails.Count
        WarnCount     = $warns.Count
        NewTeams      = $newTeams
        Findings      = @($findings)
        Compliant     = ($fails.Count -eq 0)
    } | ConvertTo-Json -Depth 6
}

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
