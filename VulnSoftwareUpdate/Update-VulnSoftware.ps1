#Requires -Version 5.1
<#
.SYNOPSIS
    Detect and silently update common vulnerability-scan software findings.

.DESCRIPTION
    ScreenConnect-oriented orchestrator for ConnectSecure-style
    "Vulnerability Remediation - <Product> - Update Required" tickets.

    Reuses mytools handlers where they exist (M365 Click-to-Run, HP Support Assistant)
    and uses winget / vendor silent installers for other common products.

    Default: check all catalog products that are installed; update those that are behind.
    -CheckOnly: verdicts only.
    -Product Id1,Id2: limit to specific catalog IDs (see -List).
    -List: print catalog and exit.

.PARAMETER CheckOnly
    Do not change the system; print per-product status only.

.PARAMETER Product
    One or more catalog IDs (e.g. M365Apps, ShareX, Git). Default: all.

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
    [switch]$List,
    [switch]$Force,
    [switch]$ForceAppShutdown,
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptVersion = '1.4.0'
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
            Notes = 'Win11 update / Win10 uninstall via existing tool'
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
            Id = 'GIMP'; Name = 'GIMP'; Method = 'Winget'; WingetId = 'GIMP.GIMP'
            Match = @('^GIMP', 'GIMP ')
            Notes = 'May resolve to GIMP 2.x or 3.x channel depending on install'
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
            Match = @('^7-Zip', '7-Zip ')
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
        # Browsers — high ticket volume; upgrades may close open browser sessions
        [pscustomobject]@{
            Id = 'Chrome'; Name = 'Google Chrome'; Method = 'Winget'; WingetId = 'Google.Chrome'
            Match = @('^Google Chrome$')
            Notes = 'May close Chrome tabs/windows during upgrade; prefer off-hours or warn the user'
        }
        [pscustomobject]@{
            Id = 'Edge'; Name = 'Microsoft Edge'; Method = 'Winget'; WingetId = 'Microsoft.Edge'
            Match = @('^Microsoft Edge$')
            Notes = 'Stable channel only. May close Edge sessions; WU/Intune is preferred when healthy'
        }
        [pscustomobject]@{
            Id = 'Firefox'; Name = 'Mozilla Firefox'; Method = 'Winget'; WingetId = 'Mozilla.Firefox'
            Match = @('^Mozilla Firefox', '^Firefox$')
            Notes = 'Stable channel only (not Beta/Dev). May close Firefox sessions during upgrade'
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
        [int]$TimeoutSec = 900
    )
    $argLine = ($ArgumentList -join ' ')
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
    if ($stdout) { Write-Host $stdout }
    if ($stderr) { Write-Host $stderr }
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
    # Installed version (list only - never upgrades)
    $list = Invoke-Winget -WingetPath $WingetPath -ArgumentList @(
        'list', '--id', $WingetId, '--exact', '--accept-source-agreements', '--disable-interactivity'
    ) -TimeoutSec 180
    $installed = $null
    foreach ($line in ($list.StdOut -split "`r?`n")) {
        $parsed = Get-WingetVersionFromLine -Line $line -WingetId $WingetId
        if (-not $parsed) { continue }
        $installed = $parsed.Installed
        if ($parsed.HasUpgradeColumn -and $parsed.Available) {
            return [pscustomobject]@{
                Present     = $true
                Installed   = $installed
                Available   = $parsed.Available
                NeedsUpdate = $true
            }
        }
    }

    # Available upgrades table (no package id => list only, does not apply updates)
    $upgrade = Invoke-Winget -WingetPath $WingetPath -ArgumentList @(
        'upgrade', '--accept-source-agreements', '--disable-interactivity', '--include-unknown'
    ) -TimeoutSec 180
    $available = $null
    $needsUpdate = $false
    foreach ($line in ($upgrade.StdOut -split "`r?`n")) {
        $parsed = Get-WingetVersionFromLine -Line $line -WingetId $WingetId
        if (-not $parsed) { continue }
        $needsUpdate = $true
        if (-not $installed) { $installed = $parsed.Installed }
        if ($parsed.HasUpgradeColumn -and $parsed.Available) { $available = $parsed.Available }
        elseif ($parsed.Available) { $available = $parsed.Available }
        break
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
        'upgrade', '--id', $WingetId,
        '--silent',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity',
        '--include-unknown'
    ) -TimeoutSec 1200
    return $r
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
Write-VulnLog ("User: {0} | CheckOnly={1} Force={2}" -f `
        [Security.Principal.WindowsIdentity]::GetCurrent().Name, $CheckOnly, $Force)

$catalog = @(Get-VulnCatalog)

if ($List) {
    Write-Host ''
    Write-Host 'Catalog IDs:'
    foreach ($c in $catalog) {
        Write-Host ("  {0,-22} {1,-40} {2}" -f $c.Id, $c.Name, $c.Method)
        if ($c.Notes) { Write-Host ("    notes: {0}" -f $c.Notes) }
    }
    Complete-Vuln -Code 0
    return
}

$selected = $catalog
if ($Product -and $Product.Count -gt 0) {
    # Support -Product A,B,C (single string) and -Product A -Product B
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
                if ($CheckOnly) { $args['CheckOnly'] = $true }
                if ($Force) { $args['Force'] = $true }
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
                if ($state.NeedsUpdate -or $Force) {
                    if ($CheckOnly) {
                        Add-Result -Id $item.Id -Name $item2.Name -Status 'UPDATE_AVAILABLE' `
                            -Detail ("Local {0}; update available via {1}." -f $localVer, $wingetId) `
                            -InstalledVersion $localVer -TargetVersion $state.Available
                    }
                    else {
                        $up = Update-WingetPackage -WingetPath $winget -WingetId $wingetId
                        Add-Result -Id $item.Id -Name $item2.Name -Status 'UPDATED' `
                            -Detail ("winget upgrade exit {0}." -f $up.ExitCode) -InstalledVersion $localVer
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
