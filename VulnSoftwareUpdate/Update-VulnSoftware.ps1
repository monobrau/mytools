#Requires -Version 5.1
<#
.SYNOPSIS
    Detect and silently update common vulnerability-scan software findings.

.DESCRIPTION
    ScreenConnect-oriented orchestrator for ConnectSecure-style
    "Vulnerability Remediation - <Product> - Update Required" tickets.

    Reuses mytools handlers where they exist (M365 Click-to-Run, HP Support Assistant)
    and uses winget / vendor silent installers for other common products.

    Default: check/update installed catalog products except browsers.
    -CheckOnly: verdicts only.
    -Product Id1,Id2: limit to specific catalog IDs (see -List).
    -IncludeBrowsers: also process Chrome / Edge / Firefox (session-disruptive).
    -List: print catalog and exit.

.PARAMETER CheckOnly
    Do not change the system; print per-product status only.

.PARAMETER Product
    One or more catalog IDs (e.g. M365Apps, ShareX, Git). Default: all non-browser products.
    Explicit browser Ids (Chrome, Edge, Firefox) are allowed without -IncludeBrowsers.

.PARAMETER IncludeBrowsers
    Opt-in: include Chrome, Edge, and Firefox in the default catalog run.
    Browser upgrades may close open browser sessions.

.PARAMETER List
    Show catalog IDs and exit.

.PARAMETER Force
    Attempt update even when the host already looks current (where supported).

.PARAMETER ForceAppShutdown
    Passed through to M365 Apps C2R update (closes Office apps). Default off.

.PARAMETER NoExit
    Keep the PowerShell host open (Backstage).

.PARAMETER Exit
    Always exit with a result code (Commands tab).
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [string[]]$Product,
    [switch]$IncludeBrowsers,
    [switch]$List,
    [switch]$Force,
    [switch]$ForceAppShutdown,
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptVersion = '1.4.8'
$MyToolsRepo = 'monobrau/mytools'
$MyToolsRef = 'main'

try {
    [Net.ServicePointManager]::SecurityProtocol = (
        [Net.ServicePointManager]::SecurityProtocol -bor
        [Net.SecurityProtocolType]::Tls12
    )
}
catch {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
}

# Status: UP_TO_DATE | UPDATE_AVAILABLE | UPDATED | SKIPPED_NOT_INSTALLED | MANUAL | ERROR | UNKNOWN
$script:Results = New-Object System.Collections.Generic.List[object]

function Write-VulnLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts][$Level] $Message"
}

function Write-VulnVerdict {
    param([string]$ProductName, [string]$Status, [string]$Detail)
    Write-Host ''
    Write-Host ("======== {0}: {1} ========" -f $ProductName, $Status)
    if ($Detail) { Write-Host $Detail }
    Write-Host '================================================'
}

function Test-VulnShouldExitProcess {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-Vuln {
    param([Parameter(Mandatory)][int]$Code)
    $global:LASTEXITCODE = $Code
    try { $global:VulnSoftwareUpdateResultCode = $Code } catch { }
    if (Test-VulnShouldExitProcess) { exit $Code }
    Write-VulnLog ("Done. ResultCode={0} (PowerShell host kept open)." -f $Code)
}

function ConvertTo-VulnVersion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $clean = ($Text -replace '[^\d\.].*$', '')
    if ([string]::IsNullOrWhiteSpace($clean)) { return $null }
    try { return [version]$clean } catch {
        $parts = ($clean -split '\.') | Select-Object -First 4
        while ($parts.Count -lt 2) { $parts += '0' }
        try { return [version](($parts -join '.')) } catch { return $null }
    }
}

function Get-VulnCatalog {
    @(
        [pscustomobject]@{
            Id = 'M365Apps'; Name = 'Microsoft 365 Apps (Click-to-Run)'
            Method = 'M365C2R'; Notes = 'business + enterprise C2R; not winget'
        }
        [pscustomobject]@{
            Id = 'HpSupportAssistant'; Name = 'HP Support Assistant'
            Method = 'Delegate'
            DelegatePath = 'HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1'
            ResultVariable = 'HpsaResultCode'
            Match = @('HP Support Assistant')
            # Win10: HPSA SoftPaqs stay below patched builds (EOL/vulnerable) -> default uninstall.
            # Win11: default update to patched SoftPaq. Pass -CheckOnly to assess only.
            Notes = 'Win10 uninstall by default (EOL/vulnerable); Win11 update. Use -CheckOnly to skip changes.'
        }
        [pscustomobject]@{
            Id = 'DellSupportAssist'; Name = 'Dell SupportAssist'
            Method = 'Delegate'
            DelegatePath = 'DellSupportAssistUpdate/Update-DellSupportAssist.ps1'
            ResultVariable = 'DellSupportAssistUpdateResultCode'
            Match = @('^Dell SupportAssist$', '^SupportAssist$')
            Notes = 'Updates an installed Home PCs copy via Dell''s bootstrapper. Skips OS Recovery, Remediation, and TechHub. Does not install when absent.'
        }
        [pscustomobject]@{
            Id = 'DotNet'; Name = '.NET 6+ Runtime / Desktop / ASP.NET / SDK'
            Method = 'Delegate'
            DelegatePath = 'DotNetUpdate/Update-DotNetRuntimes.ps1'
            ResultVariable = 'DotNetUpdateResultCode'
            AlwaysRun = $true
            Notes = 'Same-major security patches only; never jumps majors'
        }
        [pscustomobject]@{
            Id = 'VcRedistLegacy'; Name = 'Visual C++ 2005-2013 Redistributable'
            Method = 'Delegate'
            DelegatePath = 'VisualCppUpdate/Update-VisualCppRedistributables.ps1'
            ResultVariable = 'VisualCppUpdateResultCode'
            Match = @(
                'Microsoft Visual C\+\+ 200[5-9].*Redistributable'
                'Microsoft Visual C\+\+ 201[0-3].*Redistributable'
            )
            Notes = 'Final security builds only; does not install missing years. 2015+ stays on VcRedistX64/X86 winget'
        }
        [pscustomobject]@{
            Id = 'ShareX'; Name = 'ShareX'; Method = 'Winget'; WingetId = 'ShareX.ShareX'
            Match = @('ShareX')
        }
        [pscustomobject]@{
            Id = 'AdobeAcrobat'; Name = 'Adobe Acrobat / Reader (64-bit)'
            Method = 'Adobe'; Notes = 'Reader -> Adobe.Acrobat.Reader.64-bit; Pro -> Adobe.Acrobat.Pro'
            Match = @('Adobe Acrobat', 'Adobe Acrobat Reader', 'Adobe Acrobat DC')
        }
        [pscustomobject]@{
            Id = 'VSCode'; Name = 'Microsoft Visual Studio Code'
            Method = 'Winget'; WingetId = 'Microsoft.VisualStudioCode'
            Match = @('Microsoft Visual Studio Code', 'Visual Studio Code')
            Notes = 'User-scope installs may need an interactive user session'
        }
        [pscustomobject]@{
            Id = 'Git'; Name = 'Git'; Method = 'Winget'; WingetId = 'Git.Git'
            Match = @('^Git$', 'Git version')
        }
        [pscustomobject]@{
            Id = 'GIMP'; Name = 'GIMP'; Method = 'Winget'; WingetId = 'GIMP.GIMP.2'
            Match = @('^GIMP', 'GIMP ')
            Notes = 'Pinned to GIMP.GIMP.2 (avoids silent 2.x -> 3.x major jump via GIMP.GIMP)'
        }
        [pscustomobject]@{
            Id = 'Winamp'; Name = 'Winamp'; Method = 'Winget'; WingetId = 'Winamp.Winamp'
            Match = @('Winamp')
        }
        [pscustomobject]@{
            Id = 'Greenshot'; Name = 'Greenshot'; Method = 'Winget'; WingetId = 'Greenshot.Greenshot'
            Match = @('Greenshot')
        }
        [pscustomobject]@{
            Id = 'TeamsNetworkAssessment'; Name = 'Microsoft Teams Network Assessment Tool'
            Method = 'Manual'
            Match = @('Teams Network Assessment', 'Microsoft Teams Network Assessment')
            Notes = 'No reliable winget package; update from Microsoft Download Center'
        }
        [pscustomobject]@{
            Id = 'WinRAR'; Name = 'WinRAR'; Method = 'Winget'; WingetId = 'RARLab.WinRAR'
            Match = @('WinRAR')
        }
        [pscustomobject]@{
            Id = 'FoxitReader'; Name = 'Foxit PDF Reader'; Method = 'Winget'; WingetId = 'Foxit.FoxitReader'
            Match = @('Foxit PDF Reader', 'Foxit Reader')
        }
        # Phase 1 — high-volume / completely safe winget targets
        [pscustomobject]@{
            Id = 'SevenZip'; Name = '7-Zip'; Method = 'Winget'; WingetId = '7zip.7zip'
            Match = @('^7-Zip(\s+\d|\s*\(|$)')
            Notes = 'Lists every 7-Zip copy, updates 7zip.7zip, then removes all but the latest (x64 preferred)'
        }
        [pscustomobject]@{
            Id = 'NotepadPlusPlus'; Name = 'Notepad++'; Method = 'Winget'; WingetId = 'Notepad++.Notepad++'
            Match = @('Notepad\+\+')
        }
        [pscustomobject]@{
            Id = 'VcRedistX64'; Name = 'Visual C++ Redistributable (x64)'
            Method = 'Winget'; WingetId = 'Microsoft.VCRedist.2015+.x64'
            Match = @('Visual C\+\+.*Redistributable \(x64\)')
        }
        [pscustomobject]@{
            Id = 'VcRedistX86'; Name = 'Visual C++ Redistributable (x86)'
            Method = 'Winget'; WingetId = 'Microsoft.VCRedist.2015+.x86'
            Match = @('Visual C\+\+.*Redistributable \(x86\)')
        }
        [pscustomobject]@{
            Id = 'PuTTY'; Name = 'PuTTY'; Method = 'Winget'; WingetId = 'PuTTY.PuTTY'
            Match = @('^PuTTY', 'PuTTY release')
        }
        [pscustomobject]@{
            Id = 'WinSCP'; Name = 'WinSCP'; Method = 'Winget'; WingetId = 'WinSCP.WinSCP'
            Match = @('^WinSCP')
        }
        [pscustomobject]@{
            Id = 'VLC'; Name = 'VLC media player'; Method = 'Winget'; WingetId = 'VideoLAN.VLC'
            Match = @('VLC media player')
        }
        [pscustomobject]@{
            Id = 'WebView2'; Name = 'Microsoft Edge WebView2 Runtime'
            Method = 'Winget'; WingetId = 'Microsoft.EdgeWebView2Runtime'
            Match = @('WebView2 Runtime', 'Microsoft Edge WebView2')
        }
        [pscustomobject]@{
            Id = 'PowerShell7'; Name = 'PowerShell 7'; Method = 'Winget'; WingetId = 'Microsoft.PowerShell'
            Match = @('^PowerShell 7', 'PowerShell 7-')
            Notes = 'Does not replace Windows PowerShell 5.1'
        }
        [pscustomobject]@{
            Id = 'FileZilla'; Name = 'FileZilla'; Method = 'Winget'; WingetId = 'FileZilla.FileZilla'
            Match = @('^FileZilla')
        }
        # Phase 2 — safe mid-volume (password managers / PDF / admin CLIs)
        [pscustomobject]@{
            Id = 'KeePass'; Name = 'KeePass'; Method = 'Winget'; WingetId = 'DominikReichl.KeePass'
            Match = @('^KeePass$', '^KeePass 2')
        }
        [pscustomobject]@{
            Id = 'KeePassXC'; Name = 'KeePassXC'; Method = 'Winget'; WingetId = 'KeePassXCTeam.KeePassXC'
            Match = @('^KeePassXC')
        }
        [pscustomobject]@{
            Id = 'SumatraPDF'; Name = 'SumatraPDF'; Method = 'Winget'; WingetId = 'SumatraPDF.SumatraPDF'
            Match = @('^SumatraPDF')
        }
        [pscustomobject]@{
            Id = 'AzureCLI'; Name = 'Microsoft Azure CLI'; Method = 'Winget'; WingetId = 'Microsoft.AzureCLI'
            Match = @('Microsoft Azure CLI', '^Azure CLI')
        }
        [pscustomobject]@{
            Id = 'GitHubCli'; Name = 'GitHub CLI'; Method = 'Winget'; WingetId = 'GitHub.cli'
            Match = @('^GitHub CLI', '^gh$')
        }
        # Phase 3 — more safe workstation / IT tooling
        [pscustomobject]@{
            Id = 'TreeSizeFree'; Name = 'TreeSize Free'; Method = 'Winget'; WingetId = 'JAMSoftware.TreeSize.Free'
            Match = @('TreeSize Free')
        }
        [pscustomobject]@{
            Id = 'PowerToys'; Name = 'PowerToys'; Method = 'Winget'; WingetId = 'Microsoft.PowerToys'
            Match = @('^PowerToys', 'Microsoft PowerToys')
        }
        [pscustomobject]@{
            Id = 'WindowsTerminal'; Name = 'Windows Terminal'; Method = 'Winget'; WingetId = 'Microsoft.WindowsTerminal'
            Match = @('^Windows Terminal$', 'Windows Terminal ')
            Notes = 'Stable channel only (not Preview)'
        }
        [pscustomobject]@{
            Id = 'AwsCli'; Name = 'AWS Command Line Interface'; Method = 'Winget'; WingetId = 'Amazon.AWSCLI'
            Match = @('AWS Command Line Interface', '^AWS CLI')
        }
        [pscustomobject]@{
            Id = 'SysinternalsSuite'; Name = 'Sysinternals Suite'; Method = 'Winget'; WingetId = 'Microsoft.Sysinternals.Suite'
            Match = @('Sysinternals Suite')
        }
        [pscustomobject]@{
            Id = 'UltraVNC'; Name = 'UltraVNC'; Method = 'Winget'; WingetId = 'uvncbvba.UltraVNC'
            Match = @('^UltraVNC', '^UltraVnc')
            Notes = 'In-place winget upgrade. Does not change the VNC password.'
        }
        [pscustomobject]@{
            Id = 'Python313'; Name = 'Python 3.13'; Method = 'Winget'; WingetId = 'Python.Python.3.13'
            Match = @('Python 3\.13')
            Notes = 'Stays on 3.13. Does not install 3.14 or remove older majors.'
        }
        # Browsers — opt-in only (-IncludeBrowsers or explicit -Product); may close sessions
        [pscustomobject]@{
            Id = 'Chrome'; Name = 'Google Chrome'; Method = 'Winget'; WingetId = 'Google.Chrome'
            Match = @('^Google Chrome$')
            OptionalGroup = 'Browsers'
            Notes = 'Opt-in (-IncludeBrowsers). May close Chrome tabs/windows during upgrade'
        }
        [pscustomobject]@{
            Id = 'Edge'; Name = 'Microsoft Edge'; Method = 'Winget'; WingetId = 'Microsoft.Edge'
            Match = @('^Microsoft Edge$')
            OptionalGroup = 'Browsers'
            Notes = 'Opt-in (-IncludeBrowsers). Stable only; may close Edge sessions'
        }
        [pscustomobject]@{
            Id = 'Firefox'; Name = 'Mozilla Firefox'; Method = 'Winget'; WingetId = 'Mozilla.Firefox'
            Match = @('^Mozilla Firefox$', '^Mozilla Firefox \(', '^Firefox$')
            OptionalGroup = 'Browsers'
            Notes = 'Opt-in (-IncludeBrowsers). Stable only (skips ESR/Beta/Dev by name); may close sessions'
        }
    )
}

function Get-InstalledApps {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    # Per-user (common for VS Code User)
    try {
        $sidRoot = 'Registry::HKEY_USERS'
        Get-ChildItem $sidRoot -ErrorAction SilentlyContinue | Where-Object {
            $_.PSChildName -match '^S-1-5-21-\d+-\d+-\d+-\d+$'
        } | ForEach-Object {
            $paths += (Join-Path $_.PSPath 'Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
        }
    }
    catch { }

    $apps = foreach ($p in $paths) {
        Get-ItemProperty $p -ErrorAction SilentlyContinue | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.DisplayName)
        } | ForEach-Object {
            [pscustomobject]@{
                DisplayName    = [string]$_.DisplayName
                DisplayVersion = [string]$_.DisplayVersion
                Publisher      = [string]$_.Publisher
                InstallLocation = [string]$_.InstallLocation
                PSPath         = [string]$_.PSPath
            }
        }
    }
    $apps | Sort-Object DisplayName -Unique
}

function Test-NameMatch {
    param([string]$DisplayName, [string[]]$Patterns)
    foreach ($pat in @($Patterns)) {
        if ([string]::IsNullOrWhiteSpace($pat)) { continue }
        if ($DisplayName -match $pat) { return $true }
    }
    return $false
}

function Find-InstalledMatches {
    param($CatalogItem, $InstalledApps)
    @($InstalledApps | Where-Object { Test-NameMatch -DisplayName $_.DisplayName -Patterns $CatalogItem.Match })
}

function Get-WingetPath {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:LocalAppData 'Microsoft\WindowsApps\winget.exe')
        (Join-Path $env:ProgramFiles 'WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe')
    )
    foreach ($c in $candidates) {
        $resolved = Get-Item $c -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($resolved) { return $resolved.FullName }
    }
    return $null
}

function Invoke-Winget {
    param(
        [Parameter(Mandatory)][string]$WingetPath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [int]$TimeoutSec = 900,
        [switch]$QuietOutput
    )
    try { $env:WINGET_DISABLE_INTERACTIVITY = '1' } catch { }
    # Quote args that need it (e.g. Notepad++.Notepad++)
    $argLine = (
        $ArgumentList | ForEach-Object {
            if ($_ -match '[\s\+]') { '"{0}"' -f $_ } else { $_ }
        }
    ) -join ' '
    Write-VulnLog ("winget {0}" -f $argLine)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $WingetPath
    $psi.Arguments = $argLine
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch { }
        throw "winget timed out after ${TimeoutSec}s"
    }
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    # Keep ScreenConnect logs readable: only echo upgrade noise when not QuietOutput
    if (-not $QuietOutput) {
        if ($stdout) { Write-Host $stdout }
        if ($stderr) { Write-Host $stderr }
    }
    return [pscustomobject]@{ ExitCode = $p.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

function Get-WingetVersionFromLine {
    param([string]$Line, [string]$WingetId)
    # winget columns are often single-spaced; find Id token then Version [Available] Source
    $escaped = [regex]::Escape($WingetId)
    if ($Line -notmatch $escaped) { return $null }
    if ($Line -match ("{0}\s+(\S+)(?:\s+(\S+))?(?:\s+(\S+))?\s*$" -f $escaped)) {
        $v1 = $Matches[1]
        $v2 = $Matches[2]
        $v3 = $Matches[3]
        # Patterns: Id Version Source  OR  Id Version Available Source
        if ($v3 -and $v3 -match '^(winget|msstore)$' -and $v2 -notmatch '^(winget|msstore)$') {
            return [pscustomobject]@{ Installed = $v1; Available = $v2; HasUpgradeColumn = $true }
        }
        if ($v2 -match '^(winget|msstore)$') {
            return [pscustomobject]@{ Installed = $v1; Available = $null; HasUpgradeColumn = $false }
        }
        if ($v1 -notmatch '^(winget|msstore)$') {
            return [pscustomobject]@{ Installed = $v1; Available = $null; HasUpgradeColumn = $false }
        }
    }
    return $null
}

function Get-WingetPackageState {
    param([string]$WingetPath, [string]$WingetId)
    # IMPORTANT: never call `winget upgrade --id ...` here - that APPLIES updates.
    # Use `winget list` only (with --upgrade-available when supported).
    $list = Invoke-Winget -WingetPath $WingetPath -ArgumentList @(
        'list', '--id', $WingetId, '--exact',
        '--upgrade-available',
        '--accept-source-agreements', '--disable-interactivity'
    ) -TimeoutSec 180 -QuietOutput

    # Older winget may not support --upgrade-available; fall back to plain list
    if ($list.ExitCode -ne 0 -or ($list.StdErr -match 'upgrade-available|unrecognized')) {
        $list = Invoke-Winget -WingetPath $WingetPath -ArgumentList @(
            'list', '--id', $WingetId, '--exact',
            '--accept-source-agreements', '--disable-interactivity'
        ) -TimeoutSec 180 -QuietOutput
    }

    $installed = $null
    $available = $null
    $needsUpdate = $false
    foreach ($line in ($list.StdOut -split "`r?`n")) {
        $parsed = Get-WingetVersionFromLine -Line $line -WingetId $WingetId
        if (-not $parsed) { continue }
        $installed = $parsed.Installed
        if ($parsed.HasUpgradeColumn -and $parsed.Available) {
            $available = $parsed.Available
            $needsUpdate = $true
        }
    }

    # Fallback: full upgrade *listing* (no package id => does not apply updates)
    if ($installed -and -not $needsUpdate) {
        $upgradeList = Invoke-Winget -WingetPath $WingetPath -ArgumentList @(
            'upgrade', '--accept-source-agreements', '--disable-interactivity', '--include-unknown'
        ) -TimeoutSec 180 -QuietOutput
        foreach ($line in ($upgradeList.StdOut -split "`r?`n")) {
            $parsed = Get-WingetVersionFromLine -Line $line -WingetId $WingetId
            if (-not $parsed) { continue }
            $needsUpdate = $true
            if ($parsed.HasUpgradeColumn -and $parsed.Available) { $available = $parsed.Available }
            elseif ($parsed.Available) { $available = $parsed.Available }
            break
        }
    }

    if ($installed -or $needsUpdate) {
        return [pscustomobject]@{
            Present     = $true
            Installed   = $installed
            Available   = $available
            NeedsUpdate = [bool]$needsUpdate
        }
    }
    return [pscustomobject]@{ Present = $false; Installed = $null; Available = $null; NeedsUpdate = $false }
}

function Update-WingetPackage {
    param([string]$WingetPath, [string]$WingetId)
    $r = Invoke-Winget -WingetPath $WingetPath -ArgumentList @(
        'upgrade', '--id', $WingetId, '--exact',
        '--silent',
        '--disable-interactivity',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--include-unknown',
        '--scope', 'machine'
    ) -TimeoutSec 1200
    # Retry without --scope machine if package is user-scoped only
    if ($r.ExitCode -ne 0 -and ($r.StdOut + $r.StdErr) -match 'scope|installed in a different|different installer technology') {
        Write-VulnLog 'Retrying winget upgrade without --scope machine (likely user-scope install).' 'WARN'
        $r = Invoke-Winget -WingetPath $WingetPath -ArgumentList @(
            'upgrade', '--id', $WingetId, '--exact',
            '--silent',
            '--disable-interactivity',
            '--accept-package-agreements',
            '--accept-source-agreements',
            '--include-unknown'
        ) -TimeoutSec 1200
    }
    return $r
}

function Install-WingetPackage {
    param([string]$WingetPath, [string]$WingetId)
    return Invoke-Winget -WingetPath $WingetPath -ArgumentList @(
        'install', '--id', $WingetId, '--exact',
        '--silent',
        '--disable-interactivity',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--scope', 'machine'
    ) -TimeoutSec 1200
}

function Get-UninstallAppEntries {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    try {
        Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue | Where-Object {
            $_.PSChildName -match '^S-1-5-21-\d+-\d+-\d+-\d+$'
        } | ForEach-Object {
            $paths += (Join-Path $_.PSPath 'Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
        }
    }
    catch { }

    $apps = foreach ($p in $paths) {
        Get-ItemProperty $p -ErrorAction SilentlyContinue | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.DisplayName)
        } | ForEach-Object {
            $keyName = [string]$_.PSChildName
            [pscustomobject]@{
                DisplayName          = [string]$_.DisplayName
                DisplayVersion       = [string]$_.DisplayVersion
                Publisher            = [string]$_.Publisher
                InstallLocation      = [string]$_.InstallLocation
                UninstallString      = [string]$_.UninstallString
                QuietUninstallString = [string]$_.QuietUninstallString
                ProductCode          = $(if ($keyName -match '^\{[0-9A-Fa-f-]+\}$') { $keyName } else { '' })
                Hive                 = $(if ([string]$_.PSPath -match 'WOW6432Node') { 'x86' } else { 'native' })
            }
        }
    }
    # Do not use "return , $array": @( ) on PS 5.1 nests it and property access becomes System.Object[].
    return $apps
}

function ConvertTo-SevenZipVersion {
    param([string]$DisplayVersion, [string]$DisplayName)
    foreach ($text in @($DisplayVersion, $DisplayName)) {
        if ($text -match '(\d+\.\d+(?:\.\d+){0,2})') {
            try { return [version]$Matches[1] } catch { }
        }
    }
    return $null
}

function Get-SevenZipArch {
    param($Entry)
    if ($Entry.DisplayName -match '\(x64\)') { return 'x64' }
    if ($Entry.DisplayName -match '\(x86\)') { return 'x86' }
    if ($Entry.InstallLocation -match 'Program Files \(x86\)') { return 'x86' }
    if ($Entry.Hive -eq 'x86') { return 'x86' }
    return 'x64'
}

function Get-SevenZipInstalls {
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($app in (Get-UninstallAppEntries)) {
        if ($app.DisplayName -notmatch '^7-Zip(\s+\d|\s*\(|$)') { continue }
        if ($app.DisplayName -match '^7-Zip\s+(ZS|Extra)\b') { continue }
        [void]$rows.Add([pscustomobject]@{
                DisplayName          = $app.DisplayName
                DisplayVersion       = $app.DisplayVersion
                Version              = (ConvertTo-SevenZipVersion -DisplayVersion $app.DisplayVersion -DisplayName $app.DisplayName)
                Arch                 = (Get-SevenZipArch -Entry $app)
                ProductCode          = $app.ProductCode
                UninstallString      = $app.UninstallString
                QuietUninstallString = $app.QuietUninstallString
            })
    }
    return $rows.ToArray()
}

function Get-SevenZipKey {
    param($Entry)
    if ($Entry.ProductCode) { return $Entry.ProductCode }
    return '{0}|{1}|{2}|{3}' -f $Entry.DisplayName, $Entry.DisplayVersion, $Entry.Arch, $Entry.UninstallString
}

function Format-SevenZipList {
    param($Installs)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Installs)) {
        if ($null -eq $item -or $item -is [System.Array]) { continue }
        $ver = if ($item.Version) { [string]$item.Version } elseif ($item.DisplayVersion) { [string]$item.DisplayVersion } else { 'unknown' }
        $arch = if ($item.Arch) { [string]$item.Arch } else { 'unknown' }
        $name = if ($item.DisplayName) { [string]$item.DisplayName } else { '7-Zip' }
        [void]$parts.Add(('{0} {1} ({2})' -f $name, $ver, $arch))
    }
    if ($parts.Count -eq 0) { return 'none' }
    return ($parts.ToArray() -join ', ')
}

function Select-SevenZipKeeper {
    param($Installs)
    $known = @($Installs | Where-Object { $_.Version })
    if ($known.Count -eq 0) { return $null }
    $max = ($known | Sort-Object Version -Descending | Select-Object -First 1).Version
    $top = @($known | Where-Object { $_.Version -eq $max })
    $x64 = @($top | Where-Object { $_.Arch -eq 'x64' })
    if ($x64.Count -ge 1) { return $x64[0] }
    return $top[0]
}

function Get-MsiProductCodeFromText {
    param([string]$Text)
    if ($Text -match '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}') {
        return $Matches[0]
    }
    return $null
}

function Uninstall-SevenZipCopy {
    param($Entry)
    $code = $Entry.ProductCode
    if (-not $code) { $code = Get-MsiProductCodeFromText $Entry.QuietUninstallString }
    if (-not $code) { $code = Get-MsiProductCodeFromText $Entry.UninstallString }
    if ($code) {
        Write-VulnLog ("Removing 7-Zip {0} {1} ({2})" -f $Entry.DisplayVersion, $Entry.Arch, $code)
        $p = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList @('/X', $code, '/qn', '/norestart') -Wait -PassThru -WindowStyle Hidden
        return [int]$p.ExitCode
    }

    $src = if ($Entry.QuietUninstallString) { $Entry.QuietUninstallString } else { $Entry.UninstallString }
    $exe = $null
    if ($src -match '^"([^"]+\.exe)"') { $exe = $Matches[1] }
    elseif ($src -match '^(\S+\.exe)') { $exe = $Matches[1] }
    if ($exe -and (Test-Path -LiteralPath $exe)) {
        Write-VulnLog ("Removing 7-Zip {0} {1} via {2}" -f $Entry.DisplayVersion, $Entry.Arch, $exe)
        $p = Start-Process -FilePath $exe -ArgumentList '/S' -Wait -PassThru -WindowStyle Hidden
        return [int]$p.ExitCode
    }
    throw ("No quiet uninstall for {0} {1}" -f $Entry.DisplayName, $Entry.DisplayVersion)
}

function Invoke-SevenZipKeepLatest {
    param(
        [string]$WingetPath,
        [switch]$CheckOnly,
        [switch]$Force
    )

    $before = @(Get-SevenZipInstalls)
    if ($before.Count -eq 0) {
        Add-Result -Id 'SevenZip' -Name '7-Zip' -Status 'SKIPPED_NOT_INSTALLED' `
            -Detail 'Not detected in uninstall registry.'
        return
    }

    $listText = Format-SevenZipList -Installs $before
    Write-VulnLog ("7-Zip installs: {0}" -f $listText)
    $keeper = Select-SevenZipKeeper -Installs $before
    $keepKey = if ($keeper) { Get-SevenZipKey -Entry $keeper } else { '' }
    $extra = @($before | Where-Object { (Get-SevenZipKey -Entry $_) -ne $keepKey })

    $state = $null
    $needsWinget = $false
    if ($WingetPath) {
        $state = Get-WingetPackageState -WingetPath $WingetPath -WingetId '7zip.7zip'
        $needsWinget = [bool]($state.NeedsUpdate -or $Force -or -not $state.Present)
    }
    $stale = ($extra.Count -gt 0) -or (-not $keeper)

    if ($CheckOnly) {
        if (-not $WingetPath) {
            $detail = "Installed: $listText. winget is missing, so the kept copy cannot be upgraded."
            if ($keeper) { $detail += " Would keep $($keeper.Version) $($keeper.Arch)." }
            if ($extra.Count -gt 0) { $detail += " Would remove $($extra.Count) other install(s)." }
            Add-Result -Id 'SevenZip' -Name '7-Zip' -Status 'MANUAL' -Detail $detail -InstalledVersion $listText
            return
        }
        if ($stale -or $needsWinget) {
            $detail = "Installed: $listText."
            if ($keeper) { $detail += " Would keep $($keeper.Version) $($keeper.Arch)." }
            if ($extra.Count -gt 0) { $detail += " Would remove $($extra.Count) other install(s)." }
            if ($needsWinget -and $state.Available) { $detail += " winget target $($state.Available)." }
            elseif ($needsWinget -and -not $state.Present) { $detail += ' Not tracked by winget; would install 7zip.7zip, then remove older copies.' }
            Add-Result -Id 'SevenZip' -Name '7-Zip' -Status 'UPDATE_AVAILABLE' -Detail $detail `
                -InstalledVersion $listText -TargetVersion $state.Available
        }
        else {
            Add-Result -Id 'SevenZip' -Name '7-Zip' -Status 'UP_TO_DATE' `
                -Detail ("Single current install: {0}." -f $listText) -InstalledVersion $listText
        }
        return
    }

    if ($WingetPath -and $needsWinget) {
        if ($state.Present) {
            $up = Update-WingetPackage -WingetPath $WingetPath -WingetId '7zip.7zip'
            Write-VulnLog ("7-Zip winget upgrade exit {0}" -f $up.ExitCode)
        }
        else {
            $up = Install-WingetPackage -WingetPath $WingetPath -WingetId '7zip.7zip'
            Write-VulnLog ("7-Zip winget install exit {0}" -f $up.ExitCode)
        }
    }

    $current = @(Get-SevenZipInstalls)
    $keeper = Select-SevenZipKeeper -Installs $current
    if (-not $keeper) {
        Add-Result -Id 'SevenZip' -Name '7-Zip' -Status 'ERROR' `
            -Detail ("Could not identify a latest 7-Zip to keep. Installed: {0}" -f (Format-SevenZipList -Installs $current)) `
            -InstalledVersion (Format-SevenZipList -Installs $current)
        return
    }

    $keepKey = Get-SevenZipKey -Entry $keeper
    $removed = 0
    $failed = 0
    foreach ($copy in @($current)) {
        if ((Get-SevenZipKey -Entry $copy) -eq $keepKey) { continue }
        if (-not $copy.Version) {
            Write-VulnLog ("Skipping uninstall of {0}; version could not be parsed." -f $copy.DisplayName) 'WARN'
            $failed++
            continue
        }
        try {
            $code = Uninstall-SevenZipCopy -Entry $copy
            if ($code -in 0, 3010, 1641, 1605) { $removed++ }
            else {
                Write-VulnLog ("7-Zip uninstall exit {0} for {1} {2}" -f $code, $copy.DisplayVersion, $copy.Arch) 'WARN'
                $failed++
            }
        }
        catch {
            Write-VulnLog $_.Exception.Message 'WARN'
            $failed++
        }
    }

    $left = @(Get-SevenZipInstalls)
    $leftText = Format-SevenZipList -Installs $left
    $stillBehind = $false
    if ($WingetPath -and $needsWinget) {
        $after = Get-WingetPackageState -WingetPath $WingetPath -WingetId '7zip.7zip'
        $stillBehind = [bool]($after.NeedsUpdate -or -not $after.Present)
    }
    if ($failed -gt 0 -or $left.Count -gt 1 -or $stillBehind) {
        Add-Result -Id 'SevenZip' -Name '7-Zip' -Status 'UPDATE_AVAILABLE' `
            -Detail ("Removed {0} older install(s); {1} could not be removed. Remaining: {2}. Update pending: {3}" -f $removed, $failed, $leftText, $stillBehind) `
            -InstalledVersion $leftText
        return
    }

    if (-not $WingetPath) {
        Add-Result -Id 'SevenZip' -Name '7-Zip' -Status 'MANUAL' `
            -Detail ("winget is missing, so the kept copy was not upgraded. Remaining: {0}. Removed {1} older install(s)." -f $leftText, $removed) `
            -InstalledVersion $leftText
        return
    }

    $status = if ($needsWinget -or $removed -gt 0) { 'UPDATED' } else { 'UP_TO_DATE' }
    Add-Result -Id 'SevenZip' -Name '7-Zip' -Status $status `
        -Detail ("Remaining: {0}. Removed {1} older install(s)." -f $leftText, $removed) `
        -InstalledVersion $leftText
}

function Get-MyToolsScript {
    param([Parameter(Mandatory)][string]$RelativePath)
    $uri = "https://api.github.com/repos/$MyToolsRepo/contents/$RelativePath`?ref=$MyToolsRef"
    Write-VulnLog ("Fetching mytools script: {0}" -f $RelativePath)
    $wc = New-Object Net.WebClient
    $wc.Headers.Add('User-Agent', "VulnSoftwareUpdate/$ScriptVersion")
    $wc.Headers.Add('Accept', 'application/vnd.github.raw')
    return $wc.DownloadString($uri)
}

function Invoke-MyToolsScriptBlock {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [hashtable]$Arguments
    )
    $text = Get-MyToolsScript -RelativePath $RelativePath
    $sb = [scriptblock]::Create($text)
    # Never pass -Exit into nested tools (would kill this orchestrator).
    $args = @{}
    if ($Arguments) {
        foreach ($k in $Arguments.Keys) {
            if ($k -eq 'Exit') { continue }
            $args[$k] = $Arguments[$k]
        }
    }
    $args['NoExit'] = $true
    & $sb @args
}

function Test-M365Present {
    $cfg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    if (-not $cfg) {
        $cfg = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    }
    return [bool]$cfg
}

function Resolve-AdobeWingetId {
    param($Matches)
    $names = @($Matches | ForEach-Object { $_.DisplayName }) -join ' | '
    if ($names -match 'Reader') { return 'Adobe.Acrobat.Reader.64-bit' }
    if ($names -match 'Pro|Adobe Acrobat \(') { return 'Adobe.Acrobat.Pro' }
    # "Adobe Acrobat (64-bit)" often = Reader DC branding varies; prefer Reader 64-bit if unsure and Reader present
    if ($names -match 'Acrobat') { return 'Adobe.Acrobat.Reader.64-bit' }
    return 'Adobe.Acrobat.Reader.64-bit'
}

function Add-Result {
    param(
        [string]$Id,
        [string]$Name,
        [string]$Status,
        [string]$Detail,
        [string]$InstalledVersion,
        [string]$TargetVersion
    )
    $script:Results.Add([pscustomobject]@{
            Id               = $Id
            Name             = $Name
            Status           = $Status
            Detail           = $Detail
            InstalledVersion = $InstalledVersion
            TargetVersion    = $TargetVersion
        }) | Out-Null
    Write-VulnVerdict -ProductName $Name -Status $Status -Detail $Detail
}

# --- main ---
Write-VulnLog ("VulnSoftwareUpdate {0}" -f $ScriptVersion)
Write-VulnLog ("User: {0} | CheckOnly={1} Force={2} IncludeBrowsers={3}" -f `
        [Security.Principal.WindowsIdentity]::GetCurrent().Name, $CheckOnly, $Force, $IncludeBrowsers)

$catalog = @(Get-VulnCatalog)

if ($List) {
    Write-Host ''
    Write-Host 'Catalog IDs:'
    foreach ($c in $catalog) {
        $opt = if ($c.OptionalGroup) { (" [opt-in: -IncludeBrowsers or -Product {0}]" -f $c.Id) } else { '' }
        Write-Host ("  {0,-22} {1,-40} {2}{3}" -f $c.Id, $c.Name, $c.Method, $opt)
        if ($c.Notes) { Write-Host ("    notes: {0}" -f $c.Notes) }
    }
    Complete-Vuln -Code 0
    return
}

$selected = $catalog
if ($Product -and $Product.Count -gt 0) {
    # Support -Product A,B,C (single string) and -Product A -Product B
    # Explicit -Product Chrome/Edge/Firefox does not require -IncludeBrowsers.
    $wanted = @(
        $Product |
            ForEach-Object { $_ -split ',' } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
    $selected = @($catalog | Where-Object { $wanted -contains $_.Id })
    $missing = @($wanted | Where-Object { $id = $_; -not ($catalog | Where-Object { $_.Id -eq $id }) })
    foreach ($m in $missing) {
        Write-VulnLog ("Unknown catalog Id: {0} (use -List)" -f $m) 'WARN'
    }
    if ($selected.Count -eq 0) {
        Write-VulnLog 'No matching catalog products.' 'ERROR'
        Complete-Vuln -Code 1
        return
    }
}
elseif (-not $IncludeBrowsers) {
    $selected = @($catalog | Where-Object { $_.OptionalGroup -ne 'Browsers' })
    Write-VulnLog 'Browsers (Chrome/Edge/Firefox) skipped by default. Pass -IncludeBrowsers or -Product Chrome,Edge,Firefox to opt in.'
}
else {
    Write-VulnLog 'IncludeBrowsers enabled - Chrome/Edge/Firefox will be assessed (updates may close open browser sessions).' 'WARN'
}

$installedApps = @(Get-InstalledApps)
$winget = Get-WingetPath
if ($winget) {
    Write-VulnLog ("winget: {0}" -f $winget)
}
else {
    Write-VulnLog 'winget not found - winget-based products will be MANUAL/ERROR.' 'WARN'
}

foreach ($item in $selected) {
    Write-VulnLog ("--- {0} ({1}) ---" -f $item.Id, $item.Method)

    switch ($item.Method) {
        'M365C2R' {
            if (-not (Test-M365Present)) {
                Add-Result -Id $item.Id -Name $item.Name -Status 'SKIPPED_NOT_INSTALLED' `
                    -Detail 'Office Click-to-Run configuration not present on this host.'
                break
            }
            try {
                if ($CheckOnly) {
                    Invoke-MyToolsScriptBlock -RelativePath 'M365AppsUpdate/Update-M365Apps.ps1' -Arguments @{
                        CheckOnly = $true
                    }
                    $code = 0
                    try { $code = [int]$global:M365AppsUpdateResultCode } catch { }
                    $status = if ($code -eq 0) { 'UP_TO_DATE' } elseif ($code -eq 2) { 'UPDATE_AVAILABLE' } else { 'UNKNOWN' }
                    Add-Result -Id $item.Id -Name $item.Name -Status $status `
                        -Detail ("Delegated to M365AppsUpdate (result {0}). See log above." -f $code)
                }
                else {
                    $args = @{ }
                    if ($Force) { $args['Force'] = $true }
                    if ($ForceAppShutdown) { $args['ForceAppShutdown'] = $true }
                    Invoke-MyToolsScriptBlock -RelativePath 'M365AppsUpdate/Update-M365Apps.ps1' -Arguments $args
                    $code = 0
                    try { $code = [int]$global:M365AppsUpdateResultCode } catch { }
                    $status = if ($code -eq 0) { 'UP_TO_DATE' } elseif ($code -eq 2) { 'UPDATE_AVAILABLE' } else { 'ERROR' }
                    if ($code -eq 0) { $status = 'UPDATED_OR_CURRENT' }
                    Add-Result -Id $item.Id -Name $item.Name -Status $status `
                        -Detail ("Delegated to M365AppsUpdate (result {0}). Re-check if apps were open." -f $code)
                }
            }
            catch {
                Add-Result -Id $item.Id -Name $item.Name -Status 'ERROR' -Detail $_.Exception.Message
            }
        }

        'Delegate' {
            if (-not $item.AlwaysRun -and $item.Match -and -not $Force) {
                $hits = Find-InstalledMatches -CatalogItem $item -InstalledApps $installedApps
                if ($hits.Count -eq 0) {
                    Add-Result -Id $item.Id -Name $item.Name -Status 'SKIPPED_NOT_INSTALLED' `
                        -Detail ("{0} not detected." -f $item.Name)
                    break
                }
            }
            try {
                $args = @{ }
                # Safety: some delegates (HPSA) remediating by default is destructive - force check-only.
                if ($CheckOnly -or $item.CheckOnlyDelegate) { $args['CheckOnly'] = $true }
                if ($Force -and -not $item.CheckOnlyDelegate) { $args['Force'] = $true }
                if ($item.CheckOnlyDelegate -and -not $CheckOnly) {
                    Write-VulnLog ("{0}: orchestrator will not remediate this product (check-only). Use the dedicated tool to change the system." -f $item.Id) 'WARN'
                }
                # Clear prior nested result so we don't reuse a stale code
                $rv = if ($item.ResultVariable) { [string]$item.ResultVariable } else { 'DelegateResultCode' }
                try { Remove-Variable -Name $rv -Scope Global -ErrorAction SilentlyContinue } catch { }
                try { Set-Variable -Name $rv -Scope Global -Value $null } catch { }
                Invoke-MyToolsScriptBlock -RelativePath $item.DelegatePath -Arguments $args
                $code = 0
                try {
                    $raw = Get-Variable -Name $rv -Scope Global -ValueOnly -ErrorAction SilentlyContinue
                    if ($null -ne $raw) { $code = [int]$raw }
                }
                catch { }
                $status = switch ($code) {
                    0 { 'UP_TO_DATE' }
                    2 { 'UPDATE_AVAILABLE' }
                    3 { 'ERROR' }
                    1 { 'ERROR' }
                    default { 'UNKNOWN' }
                }
                Add-Result -Id $item.Id -Name $item.Name -Status $status `
                    -Detail ("Delegated to {0} (result {1}). See log above." -f $item.DelegatePath, $code)
            }
            catch {
                Add-Result -Id $item.Id -Name $item.Name -Status 'ERROR' -Detail $_.Exception.Message
            }
        }

        'Winget' {
            if ($item.Id -eq 'SevenZip') {
                Invoke-SevenZipKeepLatest -WingetPath $winget -CheckOnly:$CheckOnly -Force:$Force
                break
            }
            $hits = Find-InstalledMatches -CatalogItem $item -InstalledApps $installedApps
            if ($hits.Count -eq 0) {
                Add-Result -Id $item.Id -Name $item.Name -Status 'SKIPPED_NOT_INSTALLED' `
                    -Detail 'Not detected in uninstall registry.'
                break
            }
            $localVer = ($hits | Select-Object -First 1).DisplayVersion
            if (-not $winget) {
                Add-Result -Id $item.Id -Name $item.Name -Status 'MANUAL' `
                    -Detail ("Installed {0} but winget missing - update manually." -f $localVer) `
                    -InstalledVersion $localVer
                break
            }
            try {
                $state = Get-WingetPackageState -WingetPath $winget -WingetId $item.WingetId
                if (-not $state.Present -and $hits.Count -gt 0) {
                    # Registry says installed; winget may not track it
                    Add-Result -Id $item.Id -Name $item.Name -Status 'MANUAL' `
                        -Detail ("Installed locally ({0}) but not tracked by winget id {1}." -f $localVer, $item.WingetId) `
                        -InstalledVersion $localVer
                    break
                }
                if ($state.NeedsUpdate -or $Force) {
                    if ($CheckOnly) {
                        Add-Result -Id $item.Id -Name $item.Name -Status 'UPDATE_AVAILABLE' `
                            -Detail ("Local {0}; winget reports update available ({1})." -f $localVer, $state.Available) `
                            -InstalledVersion $localVer -TargetVersion $state.Available
                    }
                    else {
                        $up = Update-WingetPackage -WingetPath $winget -WingetId $item.WingetId
                        $after = Get-WingetPackageState -WingetPath $winget -WingetId $item.WingetId
                        if (-not $after.NeedsUpdate) {
                            Add-Result -Id $item.Id -Name $item.Name -Status 'UPDATED' `
                                -Detail ("winget upgrade exit {0}; now current." -f $up.ExitCode) `
                                -InstalledVersion $after.Installed
                        }
                        else {
                            Add-Result -Id $item.Id -Name $item.Name -Status 'UPDATE_AVAILABLE' `
                                -Detail ("winget upgrade exit {0}; update may still be pending." -f $up.ExitCode) `
                                -InstalledVersion $localVer -TargetVersion $state.Available
                        }
                    }
                }
                else {
                    Add-Result -Id $item.Id -Name $item.Name -Status 'UP_TO_DATE' `
                        -Detail ("No winget upgrade for {0} (installed {1})." -f $item.WingetId, $localVer) `
                        -InstalledVersion $localVer
                }
            }
            catch {
                Add-Result -Id $item.Id -Name $item.Name -Status 'ERROR' -Detail $_.Exception.Message `
                    -InstalledVersion $localVer
            }
        }

        'Adobe' {
            $hits = Find-InstalledMatches -CatalogItem $item -InstalledApps $installedApps
            if ($hits.Count -eq 0) {
                Add-Result -Id $item.Id -Name $item.Name -Status 'SKIPPED_NOT_INSTALLED' `
                    -Detail 'Adobe Acrobat / Reader not detected.'
                break
            }
            $wingetId = Resolve-AdobeWingetId -Matches $hits
            $localVer = ($hits | Select-Object -First 1).DisplayVersion
            if (-not $winget) {
                Add-Result -Id $item.Id -Name $item.Name -Status 'MANUAL' `
                    -Detail ("Installed {0}; winget missing." -f $localVer) -InstalledVersion $localVer
                break
            }
            try {
                $item2 = [pscustomobject]@{ WingetId = $wingetId; Match = $item.Match; Id = $item.Id; Name = "$($item.Name) [$wingetId]" }
                $state = Get-WingetPackageState -WingetPath $winget -WingetId $wingetId
                if (-not $state.Present) {
                    Add-Result -Id $item.Id -Name $item2.Name -Status 'MANUAL' `
                        -Detail ("Installed locally ({0}) but not tracked by winget id {1}." -f $localVer, $wingetId) `
                        -InstalledVersion $localVer
                    break
                }
                if ($state.NeedsUpdate -or $Force) {
                    if ($CheckOnly) {
                        Add-Result -Id $item.Id -Name $item2.Name -Status 'UPDATE_AVAILABLE' `
                            -Detail ("Local {0}; update available via {1}." -f $localVer, $wingetId) `
                            -InstalledVersion $localVer -TargetVersion $state.Available
                    }
                    else {
                        $up = Update-WingetPackage -WingetPath $winget -WingetId $wingetId
                        $after = Get-WingetPackageState -WingetPath $winget -WingetId $wingetId
                        if (-not $after.NeedsUpdate) {
                            Add-Result -Id $item.Id -Name $item2.Name -Status 'UPDATED' `
                                -Detail ("winget upgrade exit {0}; now current." -f $up.ExitCode) `
                                -InstalledVersion $after.Installed
                        }
                        else {
                            Add-Result -Id $item.Id -Name $item2.Name -Status 'UPDATE_AVAILABLE' `
                                -Detail ("winget upgrade exit {0}; update may still be pending." -f $up.ExitCode) `
                                -InstalledVersion $localVer -TargetVersion $state.Available
                        }
                    }
                }
                else {
                    Add-Result -Id $item.Id -Name $item2.Name -Status 'UP_TO_DATE' `
                        -Detail ("No winget upgrade ({0}). Local {1}." -f $wingetId, $localVer) `
                        -InstalledVersion $localVer
                }
            }
            catch {
                Add-Result -Id $item.Id -Name $item.Name -Status 'ERROR' -Detail $_.Exception.Message
            }
        }

        'Manual' {
            $hits = Find-InstalledMatches -CatalogItem $item -InstalledApps $installedApps
            if ($hits.Count -eq 0) {
                Add-Result -Id $item.Id -Name $item.Name -Status 'SKIPPED_NOT_INSTALLED' `
                    -Detail 'Not detected.'
            }
            else {
                $v = ($hits | Select-Object -First 1).DisplayVersion
                Add-Result -Id $item.Id -Name $item.Name -Status 'MANUAL' `
                    -Detail ("Installed {0}. {1}" -f $v, $item.Notes) -InstalledVersion $v
            }
        }

        default {
            Add-Result -Id $item.Id -Name $item.Name -Status 'ERROR' -Detail ("Unknown method {0}" -f $item.Method)
        }
    }
}

Write-Host ''
Write-VulnLog '===== SUMMARY ====='
foreach ($r in $script:Results) {
    Write-VulnLog ("{0,-22} {1,-22} {2}" -f $r.Id, $r.Status, $r.Detail)
}

$needs = @($script:Results | Where-Object { $_.Status -in @('UPDATE_AVAILABLE', 'MANUAL', 'ERROR', 'UNKNOWN') })
$hard = @($script:Results | Where-Object { $_.Status -eq 'ERROR' })

if ($hard.Count -gt 0) {
    Complete-Vuln -Code 1
    return
}
if ($needs.Count -gt 0) {
    Complete-Vuln -Code 2
    return
}
Complete-Vuln -Code 0
return
