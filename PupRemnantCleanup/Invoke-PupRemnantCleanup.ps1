#Requires -Version 5.1
<#
.SYNOPSIS
    Scan and remove leftover PUP remnants. Catalog covers Ask Toolbar, MediaArena converters, AppSuite PDF Editor, Wave/OneLaunch, fake PDF installers, and Browser Assistant.

.DESCRIPTION
    Definition-driven remnant sweep for toolbars / search hijackers. Default is a dry-run report.
    Pass -Remove (or -Remediate) to delete matched folders, tasks, services, ARP keys, and
    registry roots. Chromium / Firefox preference files are reported only — never rewritten.

    Default scans every catalog family and reports whatever is actually on the host.
    -Name limits the job to one or more families. -Remove deletes every finding for the
    selected families (browser prefs stay report-only).

    Matches stay specific (Ask Toolbar / Ask.com / APN). A bare "Ask" is not used so Copilot
    and other help UI are not flagged.

    Prefer elevated / Backstage so every profile folder is visible.

    Exit 0 = clean. Exit 2 = remnants still present. Exit 1 = error.

.PARAMETER Name
    Limit to one or more catalog ids (comma-separated ok). Omit to scan every family
    and act on whatever is present. Use -List to see ids.

.PARAMETER All
    Explicitly scan every catalog family (same as omitting -Name).

.PARAMETER List
    Print catalog ids and exit.

.PARAMETER Remove
    Delete removable findings for the selected families, then re-scan.

.PARAMETER Remediate
    Same as -Remove (ScToolLauncher / McAfee-style alias).

.PARAMETER CheckOnly
    Force dry-run even if -Remove is also passed.

.PARAMETER Json
    Emit a JSON summary after the log lines.

.PARAMETER NoExit
    Keep the PowerShell host open (Backstage).

.PARAMETER Exit
    Always call exit with the result code (Commands / automation).
#>
[CmdletBinding()]
param(
    [Alias('Id', 'Product')]
    [string[]]$Name,

    [switch]$All,
    [switch]$List,
    [switch]$Remove,
    [switch]$Remediate,
    [switch]$CheckOnly,
    [switch]$Json,
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$ScriptVersion = '1.3.1'
$script:ExitCode = 0
$script:Findings = New-Object System.Collections.Generic.List[object]
$script:Seen = New-Object 'System.Collections.Generic.HashSet[string]'
$script:LogPath = Join-Path $env:TEMP ("PupRemnantCleanup_{0}_{1}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'), $env:COMPUTERNAME)

# ---------------------------------------------------------------------------
# Catalog — copy an entry and change Id / paths / match strings to add a PUP.
# Keep regexes specific. Do not use a bare "Ask" / "Update" / vendor-generic word.
# Domain matches need a lookbehind, e.g. (?<![A-Za-z0-9])ask\.com, so hydroflask.com does not hit.
# ---------------------------------------------------------------------------
function Get-PupCatalog {
    [ordered]@{
        AskToolbar = @{
            Id          = 'AskToolbar'
            DisplayName = 'Ask Toolbar / Ask.com'
            Notes       = 'Huntress often already removed "Scheduled Update for Ask Toolbar" and updatetask.exe. This finishes leftover folders, ARP, registry, browser hijacks, and leftover tasks/services.'
            Folders     = @(
                '%ProgramFiles%\Ask.com'
                '%ProgramFiles(x86)%\Ask.com'
                '%ProgramFiles%\AskToolbar'
                '%ProgramFiles(x86)%\AskToolbar'
                '%ProgramData%\Ask.com'
                '%ProgramData%\AskToolbar'
            )
            UserFolders = @(
                'AppData\Local\Ask.com'
                'AppData\Roaming\Ask.com'
                'AppData\Local\AskToolbar'
                'AppData\Roaming\AskToolbar'
                'AppData\Local\Apn'
                'AppData\Roaming\Apn'
            )
            RegistryKeys = @(
                'HKLM:\SOFTWARE\AskToolbar'
                'HKLM:\SOFTWARE\WOW6432Node\AskToolbar'
                'HKLM:\SOFTWARE\Ask.com'
                'HKLM:\SOFTWARE\WOW6432Node\Ask.com'
                'HKLM:\SOFTWARE\APN'
                'HKLM:\SOFTWARE\WOW6432Node\APN'
            )
            UserRegistryKeys = @(
                'SOFTWARE\AskToolbar'
                'SOFTWARE\Ask.com'
                'SOFTWARE\APN'
            )
            RegistryValueRoots = @(
                'HKLM:\SOFTWARE\Microsoft\Internet Explorer\Main'
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Internet Explorer\Main'
                'HKLM:\SOFTWARE\Microsoft\Internet Explorer\Toolbar'
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Internet Explorer\Toolbar'
                'HKLM:\SOFTWARE\Policies\Google\Chrome'
                'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
                'HKCU:\Software\Microsoft\Internet Explorer\Main'
                'HKCU:\Software\Microsoft\Internet Explorer\Toolbar'
            )
            TaskMatch                  = '(?i)Ask Toolbar|Ask\.com|AskToolbar|Scheduled Update for Ask'
            ServiceMatch               = '(?i)Ask Toolbar|Ask\.com|AskToolbar'
            UninstallDisplayNameMatch  = '(?i)Ask Toolbar|Ask\.com Toolbar|AskToolbar|Ask Search'
            UninstallPublisherMatch    = '(?i)^Ask(\.com)?$|^APN( LLC)?$|^IAC Search'
            SearchUrlMatch             = '(?i)(?<![A-Za-z0-9])ask\.com'
            SearchDisplayNameMatch     = '(?i)Ask Toolbar|Ask\.com'
            RunValueMatch              = '(?i)(?<![A-Za-z0-9])ask\.com|AskToolbar|Ask Toolbar|\\Ask\.com\\'
            BrowserContentMatch        = '(?i)(?<![A-Za-z0-9])ask\.com'
            ProcessMatch               = '(?i)^updatetask$|AskToolbar|Ask\.com'
            SkipRemoveTypes            = @('ChromiumPrefs', 'FirefoxPrefs')
        }

        MediaArena = @{
            Id          = 'MediaArena'
            DisplayName = 'MediaArena (PdfPower / PdfMagic / search hijack converters)'
            Notes       = 'BrowserModifier:Win32/MediaArena. Fake PDF/GIF/zip converters from malvertising. Uninstaller often only deletes a desktop shortcut. Huntress/Defender may already quarantine the exe.'
            Folders     = @(
                '%ProgramFiles%\MediaArena'
                '%ProgramFiles(x86)%\MediaArena'
                '%ProgramData%\MediaArena'
            )
            FolderNameMatch = '(?i)^MediaArena$|^Gifsearchutils$|^Gifsmakerpro$|^PdfHub$|^PdfMagic(App)?$|^PdfPower$|^PdfShark$|^Screensearchutils$|^Screensrecorder$|^Searcharchiver$|^Searchpoweronline$|^Searchtoolshub$|^Sharksearchonline$|^Ziplikeapro(app)?$|^Ziprararchiver$|^GiveMeRecipe$|^FoodFormula$|^KitchenCanvas$'
            LooseFileMatch  = '(?i)^(MediaArena(E|Service)?|Gifsearchutils|Gifsmakerpro|PdfHub|PdfMagic(App)?|PdfPower|PdfShark|Screensearchutils|Screensrecorder|Searcharchiver|Searchpoweronline|Searchtoolshub|Sharksearchonline|Ziplikeapro(app)?|Ziprararchiver|GiveMeRecipe|FoodFormula|KitchenCanvas)(\s*\(\d+\))?(\.exe|\.msi|\.lnk)$'
            RegistryKeys = @(
                'HKLM:\SOFTWARE\MediaArena'
                'HKLM:\SOFTWARE\WOW6432Node\MediaArena'
            )
            UserRegistryKeys = @(
                'SOFTWARE\MediaArena'
            )
            TaskMatch                 = '(?i)MediaArena|PdfPower|PdfMagic|Searchpoweronline|Searcharchiver|Ziprararchiver'
            ServiceMatch              = '(?i)MediaArena'
            UninstallDisplayNameMatch = '(?i)^(MediaArena|Gifsearchutils|Gifsmakerpro|PdfHub|PdfMagic(App)?|PdfPower|PdfShark|Screensearchutils|Screensrecorder|Searcharchiver|Searchpoweronline|Searchtoolshub|Sharksearchonline|Ziplikeapro(app)?|Ziprararchiver|GiveMeRecipe|FoodFormula|KitchenCanvas)$'
            UninstallPublisherMatch   = '(?i)^Media ?Arena$|^PdfPower$|^PdfMagic$|^Searchpoweronline$'
            SearchUrlMatch            = '(?i)(?<![A-Za-z0-9])(searchpoweronline|searchtoolshub|sharksearchonline)\.com'
            SearchDisplayNameMatch    = '(?i)AASearchpoweronline|Searchpoweronline|MediaArena'
            RunValueMatch             = '(?i)MediaArena|PdfPower|PdfMagic|Searchpoweronline|\\MediaArena\\'
            BrowserContentMatch       = '(?i)(?<![A-Za-z0-9])(searchpoweronline|searchtoolshub|sharksearchonline)\.com'
            ProcessMatch              = '(?i)^MediaArena(E|Service)?$|^PdfPower$|^PdfMagic(App)?$|^PdfHub$|^PdfShark$|^Ziprararchiver$|^Ziplikeapro(app)?$'
            SkipRemoveTypes           = @('ChromiumPrefs', 'FirefoxPrefs')
        }

        AppSuitePdf = @{
            Id          = 'AppSuitePdf'
            DisplayName = 'AppSuite / TamperedChef PDF Editor'
            Notes       = 'Malvertising MSI AppSuite-PDF.msi / PDF Editor.exe / ManualFinderApp. Persistence: PDFEditorScheduledTask, PDFEditorUScheduledTask, Run PDFEditorUpdater. Do not match Foxit/Adobe PDF Editor.'
            UserFolders = @(
                'PDF Editor'
                'AppData\Local\AppSuite'
                'AppData\Roaming\AppSuite'
                'AppData\Local\PDF Editor'
                'AppData\Roaming\PDF Editor'
                'AppData\Local\ManualFinder'
                'AppData\Roaming\ManualFinder'
            )
            FolderNameMatch = '(?i)^AppSuite$|^ManualFinder$'
            LooseFileMatch  = '(?i)^(AppSuite-PDF|AppSuite|PDFEditorSetup|ManualFinderApp|PDF Editor)(\s*\(\d+\))?(\.exe|\.msi|\.lnk)$'
            RegistryKeys = @(
                'HKLM:\SOFTWARE\AppSuite'
                'HKLM:\SOFTWARE\WOW6432Node\AppSuite'
            )
            UserRegistryKeys = @(
                'SOFTWARE\AppSuite'
                'SOFTWARE\PDF Editor'
            )
            TaskMatch                 = '(?i)PDFEditorScheduledTask|PDFEditorUScheduledTask|ManualFinder'
            ServiceMatch              = '(?i)AppSuite PDF|PDFEditor'
            UninstallDisplayNameMatch = '(?i)^PDF Editor$|^AppSuite|ManualFinder'
            UninstallPublisherMatch   = '(?i)^AppSuite(s)?$|^PDF Editor$'
            SearchUrlMatch            = '(?i)(?<![A-Za-z0-9])appsuites?\.ai'
            SearchDisplayNameMatch    = '(?i)AppSuite|ManualFinder'
            RunValueMatch             = '(?i)PDFEditorUpdater|AppSuite|ManualFinderApp|\\PDF Editor\\'
            BrowserContentMatch       = '(?i)(?<![A-Za-z0-9])appsuites?\.ai'
            ProcessMatch              = '(?i)^PDF Editor$|^ManualFinderApp$|^PDFEditorSetup$'
            SkipRemoveTypes           = @('ChromiumPrefs', 'FirefoxPrefs')
        }

        WaveBrowser = @{
            Id          = 'WaveBrowser'
            DisplayName = 'Wave Browser (Wavesor)'
            Notes       = 'Chromium PUP often bundled with MediaArena/AppSuite-style converters. Task WaveBrowser-StartAtLogin; vendor Wavesor Software.'
            FolderNameMatch = '(?i)^Wavesor Software$|^WaveBrowser$'
            LooseFileMatch  = '(?i)^(WaveBrowser|Wave Browser)(\s*\(\d+\))?(\.exe|\.msi|\.lnk)$'
            RegistryKeys = @(
                'HKLM:\SOFTWARE\Wavesor'
                'HKLM:\SOFTWARE\WOW6432Node\Wavesor'
            )
            UserRegistryKeys = @(
                'SOFTWARE\Wavesor'
                'SOFTWARE\WaveBrowser'
            )
            TaskMatch                 = '(?i)WaveBrowser-StartAtLogin|Wavesor|WaveBrowser'
            ServiceMatch              = '(?i)WaveBrowser|Wavesor'
            UninstallDisplayNameMatch = '(?i)Wave Browser|WaveBrowser'
            UninstallPublisherMatch   = '(?i)^Wavesor'
            SearchUrlMatch            = '(?i)(?<![A-Za-z0-9])(wavebrowser|wavesor)\.com'
            SearchDisplayNameMatch    = '(?i)Wave Browser|WaveBrowser'
            RunValueMatch             = '(?i)WaveBrowser|Wavesor|swupdater'
            BrowserContentMatch       = '(?i)(?<![A-Za-z0-9])(wavebrowser|wavesor)\.com'
            ProcessMatch              = '(?i)^WaveBrowser$|^swupdater$'
            SkipRemoveTypes           = @('ChromiumPrefs', 'FirefoxPrefs')
        }

        OneLaunch = @{
            Id          = 'OneLaunch'
            DisplayName = 'OneLaunch / OneStart'
            Notes       = 'Launcher/adware browser often dropped with AppSuite PDF Editor (OneLaunchLaunchTask).'
            FolderNameMatch = '(?i)^OneLaunch$|^OneStart$'
            LooseFileMatch  = '(?i)^(OneLaunch|OneStart)(\s*\(\d+\))?(\.exe|\.msi|\.lnk)$'
            RegistryKeys = @(
                'HKLM:\SOFTWARE\OneLaunch'
                'HKLM:\SOFTWARE\WOW6432Node\OneLaunch'
                'HKLM:\SOFTWARE\OneStart'
                'HKLM:\SOFTWARE\WOW6432Node\OneStart'
            )
            UserRegistryKeys = @(
                'SOFTWARE\OneLaunch'
                'SOFTWARE\OneStart'
            )
            TaskMatch                 = '(?i)OneLaunchLaunchTask|OneStart|OneLaunch'
            ServiceMatch              = '(?i)OneLaunch|OneStart'
            UninstallDisplayNameMatch = '(?i)^OneLaunch$|^OneStart$'
            UninstallPublisherMatch   = '(?i)^OneLaunch$|^OneStart$'
            SearchUrlMatch            = '(?i)(?<![A-Za-z0-9])(onelaunch|onestart)\.com'
            SearchDisplayNameMatch    = '(?i)OneLaunch|OneStart'
            RunValueMatch             = '(?i)OneLaunch|OneStart'
            BrowserContentMatch       = '(?i)(?<![A-Za-z0-9])(onelaunch|onestart)\.com'
            ProcessMatch              = '(?i)^OneLaunch$|^OneStart$'
            SkipRemoveTypes           = @('ChromiumPrefs', 'FirefoxPrefs')
        }

        FakePdfConverter = @{
            Id          = 'FakePdfConverter'
            DisplayName = 'Fake PDF/file converter installers (ConvertMate / Easy2Convert / PDFConvertSetup)'
            Notes       = 'Malvertising converters that drop UpdateRetriever.exe or PDFConvertSetup under LocalAppData, Downloads, or Desktop, plus a +1 day scheduled task. Not Adobe, Foxit, Nitro, or PDF24.'
            FolderNameMatch = '(?i)^ConvertMate$|^Easy2Convert$|^InfiniteDocs$|^PowerDoc$|^PdfSkills$|^PdfClick$|^ZapPdf$|^OneZip$|^ZipMate(Pro)?$|^NotaWord$|^CrystalPdf$|^PdfSpark$|^ConvertMaster$|^PDFConvertSetup$'
            LooseFileMatch  = '(?i)^(ConvertMate|Easy2Convert|InfiniteDocs|PowerDoc|PdfSkills|PdfClick|ZapPdf|OneZip|ZipMate(Pro)?|NotaWord|CrystalPdf|PdfSpark|ConvertMaster|UpdateRetriever|PDFConvertSetup)(\s*\(\d+\))?(\.exe|\.msi|\.lnk)$'
            TaskMatch                 = '(?i)Easy2ConvertTask|Crystal_updater|PDC_Update|ConvertMate|UpdateRetriever|PDFConvertSetup'
            ServiceMatch              = '(?i)ConvertMate|Easy2Convert|PDFConvertSetup'
            UninstallDisplayNameMatch = '(?i)^ConvertMate$|^Easy2Convert$|^InfiniteDocs$|^PowerDoc$|^PdfSkills$|^PdfClick$|^ZapPdf$|^OneZip$|^ZipMate(Pro)?$|^NotaWord$|^CrystalPdf$|^PdfSpark$|^ConvertMaster$|^PDFConvertSetup$'
            UninstallPublisherMatch   = '(?i)^BLUE TAKIN|^ConvertMate$|^Easy2Convert$'
            SearchUrlMatch            = '(?i)(?<![A-Za-z0-9])(conmateapp|convertyfileapp|ez2convertapp|powerdocapp|infinitedocsapp|convertmasterapp|pdfskillsapp|pdfclickapp|zappdfapp|onezipapp|crystalpdf|pdfsparkware|zipmatepro|notawordapp)\.com'
            SearchDisplayNameMatch    = '(?i)ConvertMate|Easy2Convert'
            RunValueMatch             = '(?i)ConvertMate|Easy2Convert|UpdateRetriever|PDFConvertSetup|\\ConvertMate\\'
            BrowserContentMatch       = '(?i)(?<![A-Za-z0-9])(conmateapp|convertyfileapp|ez2convertapp|powerdocapp|infinitedocsapp|convertmasterapp|pdfskillsapp|pdfclickapp|zappdfapp|onezipapp|crystalpdf|pdfsparkware|zipmatepro|notawordapp)\.com'
            ProcessMatch              = '(?i)^ConvertMate$|^Easy2Convert$|^UpdateRetriever$|^InfiniteDocs$|^PowerDoc$|^PDFConvertSetup$'
            SkipRemoveTypes           = @('ChromiumPrefs', 'FirefoxPrefs')
        }

        BrowserAssistant = @{
            Id          = 'BrowserAssistant'
            DisplayName = 'Browser Assistant (Blaze Media / browser-helper PUP)'
            Notes       = 'Per-user AppData\Roaming\Browser Assistant leftover. Huntress/Defender often flag it as PUA and leave the folder. Related: Browser Extension (Blaze Media), Browser Assistant Updater, NetTwoUpdater, BAv*.msi. Do not match a bare Browser or Assistant.'
            UserFolders = @(
                'AppData\Roaming\Browser Assistant'
                'AppData\Local\Browser Assistant'
                'AppData\Roaming\Browser Extension'
                'AppData\Local\Browser Extension'
            )
            FolderNameMatch = '(?i)^Browser Assistant$|^Browser Assistant Updater$|^Browser Extension$'
            LooseFileMatch  = '(?i)^(Browser Assistant( Updater)?|BAv\d+)(\s*\(\d+\))?(\.exe|\.msi|\.lnk)$'
            RegistryKeys = @(
                'HKLM:\SOFTWARE\Browser Assistant'
                'HKLM:\SOFTWARE\WOW6432Node\Browser Assistant'
            )
            UserRegistryKeys = @(
                'SOFTWARE\Browser Assistant'
            )
            TaskMatch                 = '(?i)Browser Assistant|BrowserAssistant|NetTwoUpdater|Browser Extension'
            ServiceMatch              = '(?i)Browser Assistant|BrowserAssistant'
            UninstallDisplayNameMatch = '(?i)^Browser Assistant( Updater)?$|^Browser Extension$'
            UninstallPublisherMatch   = '(?i)^Blaze Media$'
            RunValueMatch             = '(?i)Browser Assistant|BrowserAssistant|\\Browser Assistant\\'
            ProcessMatch              = '(?i)^Browser Assistant$|^BrowserAssistant$|^Browser Assistant Updater$'
            SkipRemoveTypes           = @('ChromiumPrefs', 'FirefoxPrefs')
        }
    }
}

function Write-PupLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '[{0}][{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    try { Add-Content -LiteralPath $script:LogPath -Value $line -ErrorAction SilentlyContinue } catch { }
}

function Test-PupShouldExitProcess {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-PupRun {
    param([Parameter(Mandatory)][int]$Code)
    $script:ExitCode = $Code
    $global:LASTEXITCODE = $Code
    Write-PupLog ("Log saved to: {0}" -f $script:LogPath)
    if (Test-PupShouldExitProcess) { exit $Code }
}

function Get-PupDefList {
    param($Value)
    @($Value) | Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) }
}

function Test-PupRegex {
    param(
        [string]$Text,
        [string]$Pattern
    )
    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Pattern)) {
        return $false
    }
    return [bool]($Text -match $Pattern)
}

function Test-PupIsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $prin = [Security.Principal.WindowsPrincipal]$id
        return $prin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Initialize-PupRegistryDrives {
    if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
    }
}

function Expand-PupPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $expanded = $Path
    if ($expanded -match '%ProgramFiles\(x86\)%') {
        $pf86 = ${env:ProgramFiles(x86)}
        if ($pf86) { $expanded = $expanded.Replace('%ProgramFiles(x86)%', $pf86) }
    }
    return [Environment]::ExpandEnvironmentVariables($expanded)
}

function Add-PupFinding {
    param(
        [string]$Pup,
        [string]$Type,
        [string]$Item,
        [string]$Detail = '',
        [hashtable]$Meta = $null
    )
    if ([string]::IsNullOrWhiteSpace($Item)) { return }
    $key = '{0}|{1}|{2}' -f $Pup, $Type, $Item
    if (-not $script:Seen.Add($key)) { return }
    $obj = [pscustomobject]@{
        Pup    = $Pup
        Type   = $Type
        Item   = $Item
        Detail = $Detail
        Meta   = $Meta
    }
    $script:Findings.Add($obj)
    $suffix = $(if ($Detail) { " ($Detail)" } else { '' })
    Write-PupLog ("FOUND [{0}] {1}: {2}{3}" -f $Pup, $Type, $Item, $suffix)
}

function Get-PupUserProfiles {
    $rows = @()
    try {
        $rows = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
            Where-Object {
                $_.LocalPath -and
                -not $_.Special -and
                $_.LocalPath -notmatch '\\(Default|Default User|Public|All Users)$'
            })
    }
    catch {
        Write-PupLog ("Could not enumerate user profiles: {0}" -f $_.Exception.Message) 'WARN'
    }
    $rows
}

function Get-PupUserHiveRoots {
    Initialize-PupRegistryDrives
    $roots = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -Path 'HKU:\' -ErrorAction SilentlyContinue | ForEach-Object {
        $name = $_.PSChildName
        if ($name -match '^S-1-5-21-\d+-\d+-\d+-\d+$') {
            $roots.Add(('HKU:\{0}' -f $name))
        }
    }
    $currentSid = $null
    try { $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { }
    $hasCurrent = $currentSid -and ($roots | Where-Object { $_ -eq ('HKU:\{0}' -f $currentSid) })
    if (-not $hasCurrent) { $roots.Insert(0, 'HKCU:') }
    $roots | Select-Object -Unique
}

function Get-PupUninstallPaths {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($root in Get-PupUserHiveRoots) {
        $paths += (Join-Path $root 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')
    }
    $paths
}

function Find-PupFolders {
    param($Def)
    foreach ($raw in Get-PupDefList $Def.Folders) {
        $path = Expand-PupPath $raw
        if ($path -and (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue)) {
            Add-PupFinding -Pup $Def.Id -Type 'Folder' -Item $path
        }
    }
    foreach ($profile in Get-PupUserProfiles) {
        foreach ($rel in Get-PupDefList $Def.UserFolders) {
            $path = Join-Path $profile.LocalPath $rel
            if (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue) {
                Add-PupFinding -Pup $Def.Id -Type 'Folder' -Item $path -Detail $profile.LocalPath
            }
        }
    }
}

function Find-PupNamedFolders {
    param($Def)
    if (-not $Def.FolderNameMatch) { return }
    $machineRoots = @(
        $env:ProgramFiles
        ${env:ProgramFiles(x86)}
        $env:ProgramData
    ) | Where-Object { $_ }
    foreach ($root in $machineRoots) {
        if (-not (Test-Path -LiteralPath $root -ErrorAction SilentlyContinue)) { continue }
        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-PupRegex $_.Name $Def.FolderNameMatch } |
            ForEach-Object {
                Add-PupFinding -Pup $Def.Id -Type 'Folder' -Item $_.FullName
            }
    }
    foreach ($profile in Get-PupUserProfiles) {
        foreach ($rel in @('AppData\Local', 'AppData\Roaming')) {
            $root = Join-Path $profile.LocalPath $rel
            if (-not (Test-Path -LiteralPath $root -ErrorAction SilentlyContinue)) { continue }
            Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-PupRegex $_.Name $Def.FolderNameMatch } |
                ForEach-Object {
                    Add-PupFinding -Pup $Def.Id -Type 'Folder' -Item $_.FullName -Detail $profile.LocalPath
                }
        }
    }
}

function Get-PupLooseFileRoots {
    param($Def)
    $rels = @(Get-PupDefList $Def.LooseFileRoots)
    if ($rels.Count -eq 0) {
        $rels = @(
            'Downloads'
            'Desktop'
            'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
            'AppData\Roaming\Microsoft\Windows\Start Menu\Programs'
        )
    }
    $rels
}

function Find-PupLooseFiles {
    param($Def)
    if (-not $Def.LooseFileMatch) { return }
    foreach ($profile in Get-PupUserProfiles) {
        foreach ($rel in Get-PupLooseFileRoots -Def $Def) {
            $root = Join-Path $profile.LocalPath $rel
            if (-not (Test-Path -LiteralPath $root -ErrorAction SilentlyContinue)) { continue }
            Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue |
                Where-Object { Test-PupRegex $_.Name $Def.LooseFileMatch } |
                ForEach-Object {
                    Add-PupFinding -Pup $Def.Id -Type 'LooseFile' -Item $_.FullName -Detail $rel
                }
        }
    }
    $publicDesktop = Join-Path $env:PUBLIC 'Desktop'
    if (Test-Path -LiteralPath $publicDesktop -ErrorAction SilentlyContinue) {
        Get-ChildItem -LiteralPath $publicDesktop -File -ErrorAction SilentlyContinue |
            Where-Object { Test-PupRegex $_.Name $Def.LooseFileMatch } |
            ForEach-Object {
                Add-PupFinding -Pup $Def.Id -Type 'LooseFile' -Item $_.FullName -Detail 'Public Desktop'
            }
    }
}

function Find-PupTasks {
    param($Def)
    if (-not $Def.TaskMatch) { return }
    try {
        Get-ScheduledTask -ErrorAction Stop | ForEach-Object {
            $action = ''
            try { $action = @($_.Actions | ForEach-Object { $_.Execute }) -join ';' } catch { }
            if (
                (Test-PupRegex $_.TaskName $Def.TaskMatch) -or
                (Test-PupRegex $_.TaskPath $Def.TaskMatch) -or
                (Test-PupRegex $action $Def.TaskMatch)
            ) {
                Add-PupFinding -Pup $Def.Id -Type 'ScheduledTask' -Item ("{0}{1}" -f $_.TaskPath, $_.TaskName) `
                    -Detail $action -Meta @{ TaskName = $_.TaskName; TaskPath = $_.TaskPath }
            }
        }
    }
    catch {
        Write-PupLog ("Scheduled task query failed: {0}" -f $_.Exception.Message) 'WARN'
    }

    $taskRoot = Join-Path $env:SystemRoot 'System32\Tasks'
    if (Test-Path -LiteralPath $taskRoot) {
        Get-ChildItem -LiteralPath $taskRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { Test-PupRegex $_.Name $Def.TaskMatch -or Test-PupRegex $_.FullName $Def.TaskMatch } |
            ForEach-Object {
                Add-PupFinding -Pup $Def.Id -Type 'TaskFile' -Item $_.FullName
            }
    }
}

function Find-PupServices {
    param($Def)
    if (-not $Def.ServiceMatch) { return }
    try {
        Get-CimInstance -ClassName Win32_Service -ErrorAction Stop | ForEach-Object {
            if (
                (Test-PupRegex $_.Name $Def.ServiceMatch) -or
                (Test-PupRegex $_.DisplayName $Def.ServiceMatch) -or
                (Test-PupRegex $_.PathName $Def.ServiceMatch)
            ) {
                Add-PupFinding -Pup $Def.Id -Type 'Service' -Item $_.Name -Detail $_.DisplayName
            }
        }
    }
    catch {
        Write-PupLog ("Service query failed: {0}" -f $_.Exception.Message) 'WARN'
    }
}

function Find-PupUninstallKeys {
    param($Def)
    foreach ($keyPath in Get-PupUninstallPaths) {
        Get-ItemProperty -Path $keyPath -ErrorAction SilentlyContinue | ForEach-Object {
            $display = [string]$_.DisplayName
            $publisher = [string]$_.Publisher
            if (
                (Test-PupRegex $display $Def.UninstallDisplayNameMatch) -or
                (Test-PupRegex $publisher $Def.UninstallPublisherMatch)
            ) {
                Add-PupFinding -Pup $Def.Id -Type 'UninstallRegKey' -Item $_.PSPath -Detail $display
            }
        }
    }
}

function Find-PupRegistryKeys {
    param($Def)
    foreach ($root in Get-PupDefList $Def.RegistryKeys) {
        $path = Expand-PupPath $root
        if ($path -and (Test-Path -LiteralPath $path)) {
            Add-PupFinding -Pup $Def.Id -Type 'RegistryKey' -Item $path
        }
    }
    foreach ($hive in Get-PupUserHiveRoots) {
        foreach ($rel in Get-PupDefList $Def.UserRegistryKeys) {
            $path = Join-Path $hive $rel
            if (Test-Path -LiteralPath $path) {
                Add-PupFinding -Pup $Def.Id -Type 'RegistryKey' -Item $path
            }
        }
    }
}

function Find-PupRegistryValues {
    param($Def)
    $pattern = $Def.SearchUrlMatch
    if (-not $pattern) { $pattern = $Def.BrowserContentMatch }
    if (-not $pattern) { return }

    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($raw in Get-PupDefList $Def.RegistryValueRoots) {
        if ($raw -like 'HKCU:\*') {
            $rel = $raw.Substring(6)
            foreach ($hive in Get-PupUserHiveRoots) {
                $roots.Add((Join-Path $hive $rel))
            }
        }
        else {
            $roots.Add($raw)
        }
    }

    foreach ($root in ($roots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $props = Get-ItemProperty -LiteralPath $root -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -match '^PS') { continue }
            $val = [string]$p.Value
            if (Test-PupRegex $val $pattern) {
                Add-PupFinding -Pup $Def.Id -Type 'RegistryValue' -Item ("{0}\{1}" -f $root, $p.Name) -Detail $val `
                    -Meta @{ Path = $root; Name = $p.Name }
            }
        }
    }
}

function Find-PupSearchScopes {
    param($Def)
    $scopes = New-Object System.Collections.Generic.List[string]
    foreach ($hive in @('HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node')) {
        $scopes.Add((Join-Path $hive 'Microsoft\Internet Explorer\SearchScopes'))
    }
    foreach ($hive in Get-PupUserHiveRoots) {
        $scopes.Add((Join-Path $hive 'SOFTWARE\Microsoft\Internet Explorer\SearchScopes'))
    }

    foreach ($scope in $scopes) {
        if (-not (Test-Path -LiteralPath $scope)) { continue }
        Get-ChildItem -LiteralPath $scope -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            if (-not $props) { return }
            $display = [string]$props.DisplayName
            $url = [string]$props.URL
            if (
                (Test-PupRegex $display $Def.SearchDisplayNameMatch) -or
                (Test-PupRegex $url $Def.SearchUrlMatch)
            ) {
                Add-PupFinding -Pup $Def.Id -Type 'IESearchScope' -Item $_.PSPath -Detail $display
            }
        }
    }
}

function Find-PupRunKeys {
    param($Def)
    if (-not $Def.RunValueMatch) { return }
    $keys = New-Object System.Collections.Generic.List[string]
    $keys.Add('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')
    $keys.Add('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce')
    $keys.Add('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')
    $keys.Add('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce')
    foreach ($hive in Get-PupUserHiveRoots) {
        $keys.Add((Join-Path $hive 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run'))
        $keys.Add((Join-Path $hive 'SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'))
    }

    foreach ($key in $keys) {
        if (-not (Test-Path -LiteralPath $key)) { continue }
        $props = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -match '^PS') { continue }
            $val = [string]$p.Value
            if (Test-PupRegex $val $Def.RunValueMatch -or Test-PupRegex $p.Name $Def.RunValueMatch) {
                Add-PupFinding -Pup $Def.Id -Type 'RunKey' -Item ("{0}\{1}" -f $key, $p.Name) -Detail $val `
                    -Meta @{ Path = $key; Name = $p.Name }
            }
        }
    }
}

function Get-PupBrowserProfiles {
    param([string]$UserDataRoot)
    if (-not (Test-Path -LiteralPath $UserDataRoot -ErrorAction SilentlyContinue)) { return @() }
    @(Get-ChildItem -LiteralPath $UserDataRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -match '^Profile \d+$' })
}

function Find-PupBrowserPrefs {
    param($Def)
    if (-not $Def.BrowserContentMatch) { return }

    foreach ($profile in Get-PupUserProfiles) {
        $chromiumRoots = @(
            (Join-Path $profile.LocalPath 'AppData\Local\Google\Chrome\User Data')
            (Join-Path $profile.LocalPath 'AppData\Local\Microsoft\Edge\User Data')
            (Join-Path $profile.LocalPath 'AppData\Local\BraveSoftware\Brave-Browser\User Data')
        )
        foreach ($root in $chromiumRoots) {
            foreach ($browserProfile in Get-PupBrowserProfiles -UserDataRoot $root) {
                $prefsFile = Join-Path $browserProfile.FullName 'Preferences'
                if (Test-Path -LiteralPath $prefsFile -ErrorAction SilentlyContinue) {
                    $content = Get-Content -LiteralPath $prefsFile -Raw -ErrorAction SilentlyContinue
                    if (Test-PupRegex $content $Def.BrowserContentMatch) {
                        Add-PupFinding -Pup $Def.Id -Type 'ChromiumPrefs' -Item $prefsFile
                    }
                }
            }
        }

        $ffRoot = Join-Path $profile.LocalPath 'AppData\Roaming\Mozilla\Firefox\Profiles'
        if (Test-Path -LiteralPath $ffRoot -ErrorAction SilentlyContinue) {
            Get-ChildItem -LiteralPath $ffRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                foreach ($name in @('prefs.js', 'user.js')) {
                    $prefsFile = Join-Path $_.FullName $name
                    if (Test-Path -LiteralPath $prefsFile -ErrorAction SilentlyContinue) {
                        $content = Get-Content -LiteralPath $prefsFile -Raw -ErrorAction SilentlyContinue
                        if (Test-PupRegex $content $Def.BrowserContentMatch) {
                            Add-PupFinding -Pup $Def.Id -Type 'FirefoxPrefs' -Item $prefsFile
                        }
                    }
                }
            }
        }
    }
}

function Find-PupProcesses {
    param($Def)
    if (-not $Def.ProcessMatch) { return }
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        $procPath = ''
        try { $procPath = [string]$_.Path } catch { }
        if (
            (Test-PupRegex $_.ProcessName $Def.ProcessMatch) -or
            (Test-PupRegex $procPath $Def.ProcessMatch)
        ) {
            Add-PupFinding -Pup $Def.Id -Type 'Process' -Item $_.ProcessName -Detail $procPath `
                -Meta @{ Id = $_.Id }
        }
    }
}

function Invoke-PupScan {
    param($Def)
    Write-PupLog ("--- Scanning {0} ({1}) ---" -f $Def.Id, $Def.DisplayName)
    if ($Def.Notes) { Write-PupLog $Def.Notes }
    Find-PupFolders -Def $Def
    Find-PupNamedFolders -Def $Def
    Find-PupLooseFiles -Def $Def
    Find-PupTasks -Def $Def
    Find-PupServices -Def $Def
    Find-PupUninstallKeys -Def $Def
    Find-PupRegistryKeys -Def $Def
    Find-PupRegistryValues -Def $Def
    Find-PupSearchScopes -Def $Def
    Find-PupRunKeys -Def $Def
    Find-PupBrowserPrefs -Def $Def
    Find-PupProcesses -Def $Def
}

function Test-PupRemovable {
    param($Def, [string]$Type)
    return @($Def.SkipRemoveTypes) -notcontains $Type
}

function Remove-PupFinding {
    param($Def, $Finding)
    $type = $Finding.Type
    $item = $Finding.Item
    if (-not (Test-PupRemovable -Def $Def -Type $type)) {
        Write-PupLog ("SKIPPED (manual review - live browser prefs): {0}" -f $item) 'WARN'
        return
    }

    switch ($type) {
        'Process' {
            $id = $Finding.Meta.Id
            if ($id) { Stop-Process -Id $id -Force -ErrorAction Stop }
            else { Stop-Process -Name $item -Force -ErrorAction Stop }
        }
        'Folder' { Remove-Item -LiteralPath $item -Recurse -Force -ErrorAction Stop }
        'LooseFile' { Remove-Item -LiteralPath $item -Force -ErrorAction Stop }
        'ScheduledTask' {
            $taskName = $Finding.Meta.TaskName
            $taskPath = $Finding.Meta.TaskPath
            if (-not $taskName) { throw "Missing TaskName for $item" }
            Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction Stop
        }
        'TaskFile' { Remove-Item -LiteralPath $item -Force -ErrorAction Stop }
        'Service' {
            Stop-Service -Name $item -Force -ErrorAction SilentlyContinue
            $svc = Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f ($item -replace "'", "''")) -ErrorAction Stop
            if ($svc) {
                $result = $svc | Invoke-CimMethod -MethodName Delete
                if ($result.ReturnValue -notin 0, 1) {
                    throw ("Service delete returned {0}" -f $result.ReturnValue)
                }
            }
        }
        'UninstallRegKey' { Remove-Item -LiteralPath $item -Recurse -Force -ErrorAction Stop }
        'RegistryKey' { Remove-Item -LiteralPath $item -Recurse -Force -ErrorAction Stop }
        'IESearchScope' { Remove-Item -LiteralPath $item -Force -ErrorAction Stop }
        'RegistryValue' {
            Remove-ItemProperty -LiteralPath $Finding.Meta.Path -Name $Finding.Meta.Name -Force -ErrorAction Stop
        }
        'RunKey' {
            Remove-ItemProperty -LiteralPath $Finding.Meta.Path -Name $Finding.Meta.Name -Force -ErrorAction Stop
        }
        default { throw "No remover for type $type" }
    }
    Write-PupLog ("REMOVED [{0}] {1}" -f $type, $item)
}

function Split-PupNameList {
    param([string[]]$Values)
    $ids = @()
    foreach ($value in @($Values)) {
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        $ids += ($value -split '[,;]') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }
    $ids
}

function Select-PupDefinitions {
    param($Catalog)
    $requested = @()
    if (-not $All) {
        $requested = @(Split-PupNameList -Values $Name)
    }
    if ($requested.Count -eq 0) {
        return @($Catalog.Values)
    }

    $defs = @()
    $unknown = @()
    foreach ($id in $requested) {
        $match = $Catalog.Keys | Where-Object { $_ -ieq $id } | Select-Object -First 1
        if ($match) {
            if (-not ($defs | Where-Object { $_.Id -eq $Catalog[$match].Id })) {
                $defs += $Catalog[$match]
            }
        }
        else {
            $unknown += $id
        }
    }
    if ($unknown.Count -gt 0) {
        throw ("Unknown PUP '{0}'. Use -List. Known: {1}" -f ($unknown -join ', '), ($Catalog.Keys -join ', '))
    }
    $defs
}

function Write-PupJsonSummary {
    param([int]$Code, $Defs, [string]$Mode)
    $payload = [pscustomobject]@{
        version  = $ScriptVersion
        computer = $env:COMPUTERNAME
        mode     = $Mode
        pups     = @($Defs | ForEach-Object { $_.Id })
        present  = @($script:Findings | Select-Object -ExpandProperty Pup -Unique)
        count    = $script:Findings.Count
        findings = @($script:Findings | Select-Object Pup, Type, Item, Detail)
        logPath  = $script:LogPath
        exitCode = $Code
    }
    $payload | ConvertTo-Json -Depth 6
}

try {
    Write-PupLog ("PupRemnantCleanup {0} on {1}" -f $ScriptVersion, $env:COMPUTERNAME)
    $catalog = Get-PupCatalog

    if ($List) {
        Write-PupLog 'Catalog:'
        foreach ($key in $catalog.Keys) {
            $d = $catalog[$key]
            Write-PupLog ("  {0}  -  {1}" -f $d.Id, $d.DisplayName)
        }
        if ($Json) { Write-PupJsonSummary -Code 0 -Defs @($catalog.Values) -Mode 'List' }
        Complete-PupRun -Code 0
        return
    }

    $defs = Select-PupDefinitions -Catalog $catalog
    $doRemove = ($Remove -or $Remediate) -and -not $CheckOnly
    $mode = $(if ($doRemove) { 'REMOVE' } else { 'DRY RUN (use -Remove to delete)' })
    $scope = $(if ($PSBoundParameters.ContainsKey('Name') -and -not $All -and $Name) { 'named' } else { 'catalog (whatever is present)' })
    Write-PupLog ("Mode: {0}" -f $mode)
    Write-PupLog ("Scope: {0}  -  {1}" -f $scope, (($defs | ForEach-Object { $_.Id }) -join ', '))

    if (-not (Test-PupIsAdmin)) {
        Write-PupLog 'Not elevated - HKLM / other-user hives may be incomplete. Prefer Backstage / admin.' 'WARN'
    }

    foreach ($def in $defs) { Invoke-PupScan -Def $def }

    $present = @($script:Findings | Select-Object -ExpandProperty Pup -Unique)
    $absent = @($defs | ForEach-Object { $_.Id } | Where-Object { $present -notcontains $_ })
    Write-PupLog ("=== Scan complete. {0} item(s) found. ===" -f $script:Findings.Count)
    if ($present.Count -gt 0) {
        Write-PupLog ("Present: {0}" -f ($present -join ', '))
    }
    if ($absent.Count -gt 0) {
        Write-PupLog ("Not found: {0}" -f ($absent -join ', '))
    }

    if ($script:Findings.Count -eq 0) {
        Write-PupLog 'No matching remnants found. Host appears clean for the selected PUP(s).'
        if ($Json) { Write-PupJsonSummary -Code 0 -Defs $defs -Mode $mode }
        Complete-PupRun -Code 0
        return
    }

    $script:Findings |
        Select-Object Pup, Type, Item, Detail |
        Format-Table -AutoSize |
        Out-String |
        ForEach-Object { $_.TrimEnd() } |
        Where-Object { $_ } |
        ForEach-Object { Write-PupLog $_ }

    if ($doRemove) {
        Write-PupLog '--- Removing found items ---'
        $byId = @{}
        foreach ($def in $defs) { $byId[$def.Id] = $def }
        $removeOrder = @{
            Process        = 0
            Service        = 1
            ScheduledTask  = 2
            TaskFile       = 3
            RunKey         = 4
            RegistryValue  = 5
            IESearchScope  = 6
            UninstallRegKey = 7
            RegistryKey    = 8
            Folder         = 9
            LooseFile      = 10
        }
        $ordered = @($script:Findings | Sort-Object { if ($removeOrder.ContainsKey($_.Type)) { $removeOrder[$_.Type] } else { 50 } }, Type, Item)
        foreach ($f in $ordered) {
            $def = $byId[$f.Pup]
            try {
                Remove-PupFinding -Def $def -Finding $f
            }
            catch {
                Write-PupLog ("FAILED [{0}] {1}: {2}" -f $f.Type, $f.Item, $_.Exception.Message) 'ERROR'
            }
        }

        $script:Findings.Clear()
        [void]$script:Seen.Clear()
        Write-PupLog '--- Re-scan after removal ---'
        foreach ($def in $defs) { Invoke-PupScan -Def $def }
        Write-PupLog ("=== Re-scan complete. {0} item(s) remain. ===" -f $script:Findings.Count)
    }
    else {
        Write-PupLog 'Dry run only - nothing removed. Re-run with -Remove to clean these items.'
    }

    $code = $(if ($script:Findings.Count -gt 0) { 2 } else { 0 })
    if ($code -eq 2) {
        Write-PupLog 'FAIL: remnants still present.' 'ERROR'
    }
    else {
        Write-PupLog 'PASS: selected PUP remnants removed or not present.'
    }
    if ($Json) { Write-PupJsonSummary -Code $code -Defs $defs -Mode $mode }
    Complete-PupRun -Code $code
}
catch {
    Write-PupLog $_.Exception.Message 'ERROR'
    if ($Json) {
        [pscustomobject]@{
            version  = $ScriptVersion
            error    = $_.Exception.Message
            exitCode = 1
        } | ConvertTo-Json -Depth 4
    }
    Complete-PupRun -Code 1
}
