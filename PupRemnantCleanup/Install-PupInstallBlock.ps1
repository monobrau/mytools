#Requires -Version 5.1
<#
.SYNOPSIS
    Stop catalog PUP installers from running, and tell the user why.

.DESCRIPTION
    Reads Get-PupCatalog from Invoke-PupRemnantCleanup.ps1. Literal program
    names in LooseFileMatch and ProcessMatch become Image File Execution
    Options entries. When someone starts one of those .exe names, Windows
    runs a warning instead of the program. The program does not start.

    Re-run -Enable after a family is added to the catalog. A renamed
    installer, an MSI started by msiexec, or a browser extension is not
    covered. A legitimate program with the same .exe name is also stopped.

.PARAMETER Enable
    Arm the block for the selected families.

.PARAMETER Disable
    Remove only the block entries this script created.

.PARAMETER CheckOnly
    List the program names. Do not change the computer.

.PARAMETER Name
    Catalog ids. Omit for every family. Same -Name the cleanup script uses.

.NOTES
    Exit 0: check passed, or the block is armed.
    Exit 1: error.
    Exit 2: disable finished.
#>
[CmdletBinding()]
param(
    [switch]$Enable,
    [switch]$Disable,
    [switch]$CheckOnly,
    [Alias('Id', 'Product')]
    [string[]]$Name,
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$script:ExitCode = 0
$script:IfeoPath = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
$script:Marker = 'PupInstallBlock'
$script:Root = Join-Path $env:ProgramData 'PupInstallBlock'
$script:Warner = Join-Path $script:Root 'Show-PupBlock.ps1'
$script:ListPath = Join-Path $script:Root 'blocklist.csv'
$script:Deny = @(
    'powershell.exe', 'powershell_ise.exe', 'pwsh.exe', 'cmd.exe', 'msiexec.exe',
    'explorer.exe', 'svchost.exe', 'dllhost.exe', 'rundll32.exe', 'regsvr32.exe',
    'wscript.exe', 'cscript.exe', 'mshta.exe', 'install.exe', 'setup.exe',
    'update.exe', 'updater.exe', 'runtimebroker.exe'
)

function Write-Line([string]$Message) {
    Write-Host $Message
    try { [Console]::Out.Flush() } catch { }
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CleanupScriptText {
    $local = $null
    if ($PSScriptRoot) { $local = Join-Path $PSScriptRoot 'Invoke-PupRemnantCleanup.ps1' }
    if ($local -and (Test-Path -LiteralPath $local)) {
        Write-Line "Catalog: $local"
        return [IO.File]::ReadAllText($local)
    }
    $url = 'https://api.github.com/repos/monobrau/mytools/contents/PupRemnantCleanup/Invoke-PupRemnantCleanup.ps1?ref=main'
    Write-Line 'Catalog: downloading Invoke-PupRemnantCleanup.ps1'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object Net.WebClient
    $wc.Headers.Add('User-Agent', 'PupInstallBlock-bootstrap/1.0.0')
    $wc.Headers.Add('Accept', 'application/vnd.github.raw')
    $text = $wc.DownloadString($url)
    if ($text -notmatch 'function Get-PupCatalog') { throw 'The cleanup script download did not contain Get-PupCatalog.' }
    return $text
}

function Get-PupCatalogFromText {
    param([string]$Text)
    $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$errs)
    $fn = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-PupCatalog'
    }, $false)
    if (-not $fn) { throw 'Get-PupCatalog was not found in the cleanup script.' }
    $sb = [scriptblock]::Create($fn.Extent.Text)
    . $sb
    return Get-PupCatalog
}

function Split-TopLevel {
    param([string]$Text)
    $parts = New-Object System.Collections.Generic.List[string]
    $cur = New-Object System.Text.StringBuilder
    $depth = 0
    foreach ($ch in $Text.ToCharArray()) {
        if ($ch -eq '(') { $depth++; [void]$cur.Append($ch) }
        elseif ($ch -eq ')') { if ($depth -gt 0) { $depth-- }; [void]$cur.Append($ch) }
        elseif ($ch -eq '|' -and $depth -eq 0) {
            $parts.Add($cur.ToString())
            $cur.Length = 0
        }
        else { [void]$cur.Append($ch) }
    }
    if ($cur.Length -gt 0) { $parts.Add($cur.ToString()) }
    return @($parts)
}

function Expand-ImageStem {
    param([string]$Token)
    $token = $Token.Trim().Trim('^').Trim('$').Trim()
    if (-not $token) { return @() }
    $pending = @($token)
    $done = @()
    foreach ($item in $pending) {
        if ($item -match '^(?<base>.+?)\((?<alts>[^()]+)\)\?$') {
            $base = $Matches.base.Trim()
            if ($base) { $done += $base }
            foreach ($alt in ($Matches.alts -split '\|')) {
                $alt = $alt.TrimEnd()
                if ($base -and $alt) { $done += ($base + $alt) }
            }
        }
        else { $done += $item }
    }
    $clean = @()
    foreach ($item in $done) {
        $item = $item.Trim()
        if (-not $item) { continue }
        if ($item -match '[\\\[\]\*\+\?\(\)]|\\d') { continue }
        $clean += $item
    }
    return $clean
}

function Get-BlockImages {
    param($Catalog, [string[]]$Only)
    $selected = @()
    if ($Only -and $Only.Count -gt 0) {
        foreach ($raw in $Only) {
            foreach ($part in ([string]$raw -split '[,\s;]+')) {
                if ($part) { $selected += $part.Trim() }
            }
        }
    }
    $rows = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($key in $Catalog.Keys) {
        $family = $Catalog[$key]
        $id = [string]$family.Id
        if (-not $id) { $id = [string]$key }
        if ($selected.Count -gt 0) {
            $want = $false
            foreach ($name in $selected) {
                if ($name -eq $id) { $want = $true }
            }
            if (-not $want) { continue }
        }
        $patterns = @([string]$family.LooseFileMatch, [string]$family.ProcessMatch)
        foreach ($pattern in $patterns) {
            if (-not $pattern) { continue }
            $work = $pattern -replace '\(\?[imsx]+\)', ''
            $work = $work.Replace('(\s*\(\d+\))?', '').Replace('(\.exe|\.msi|\.lnk)', '')
            $work = $work.Replace('^', '').Replace('$', '').Trim()
            if ($work.StartsWith('(') -and $work.EndsWith(')')) {
                $inner = $work.Substring(1, $work.Length - 2)
                $depth = 0
                $wrapped = $true
                foreach ($ch in $inner.ToCharArray()) {
                    if ($ch -eq '(') { $depth++ }
                    elseif ($ch -eq ')') { $depth--; if ($depth -lt 0) { $wrapped = $false; break } }
                }
                if ($wrapped -and $depth -eq 0) { $work = $inner }
            }
            foreach ($piece in (Split-TopLevel $work)) {
                foreach ($stem in (Expand-ImageStem $piece)) {
                    $stem = $stem.Trim()
                    if ($stem.Length -lt 4) { continue }
                    if ($stem -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{2,60}$') { continue }
                    $image = $stem
                    if ($image -notmatch '\.exe$') { $image = $image + '.exe' }
                    $imageKey = $image.ToLowerInvariant()
                    if ($seen.ContainsKey($imageKey)) { continue }
                    $seen[$imageKey] = $true
                    $rows.Add([pscustomobject]@{
                        Id          = $id
                        DisplayName = [string]$family.DisplayName
                        Image       = $image
                    }) | Out-Null
                }
            }
        }
    }
    if ($selected.Count -gt 0) {
        foreach ($name in $selected) {
            $known = $false
            foreach ($key in $Catalog.Keys) {
                $id = [string]$Catalog[$key].Id
                if (-not $id) { $id = [string]$key }
                if ($id -eq $name) { $known = $true }
            }
            if (-not $known) { throw "Unknown catalog id '$name'." }
        }
    }
    return @($rows.ToArray())
}

function Get-IfeoKey {
    param([bool]$Writable)
    $hive = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    $key = $hive.OpenSubKey($script:IfeoPath, $Writable)
    if (-not $key -and $Writable) { $key = $hive.CreateSubKey($script:IfeoPath) }
    return $key
}

function Get-DebuggerCommand {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    return "$ps -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($script:Warner)`""
}

function Write-Warner {
    $dir = $script:Root
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $scriptText = @'
# Installed by Install-PupInstallBlock.ps1. Windows starts this instead of a blocked program.
$image = ''
$path = ''
if ($args.Count -gt 0) {
    $path = [string]$args[0]
    try { $image = [IO.Path]::GetFileName($path) } catch { $image = $path }
}
$display = 'an unwanted program from the company block list'
$list = Join-Path $PSScriptRoot 'blocklist.csv'
if ($image -and (Test-Path -LiteralPath $list)) {
    foreach ($row in @(Import-Csv -LiteralPath $list)) {
        if ($row.Image -and ($row.Image -eq $image)) {
            if ($row.DisplayName) { $display = $row.DisplayName }
            break
        }
    }
}
$who = $image
if (-not $who) { $who = 'This program' }
$body = @"
Your organization blocked this program.

$who is $display. It was not installed.

These programs often show up as a free PDF tool, toolbar, or browser helper. They change search settings or install extra software.

If you need a tool like this for work, ask IT for the approved one.
"@
try {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($body, 'Program blocked', 'OK', 'Warning')
} catch { }
try {
    $log = Join-Path $PSScriptRoot 'blocks.log'
    Add-Content -LiteralPath $log -Value ("{0:o} user={1} image={2} path={3}" -f (Get-Date), $env:USERNAME, $image, $path) -Encoding ASCII
    $kept = @(Get-Content -LiteralPath $log -Tail 200 -ErrorAction SilentlyContinue)
    if ($kept.Count -gt 0) { Set-Content -LiteralPath $log -Value $kept -Encoding ASCII }
} catch { }
'@
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($script:Warner, $scriptText, $utf8)
}

if ($CheckOnly) { $Enable = $false; $Disable = $false }
if (-not $Enable -and -not $Disable) { $CheckOnly = $true }
if ($Enable -and $Disable) { throw 'Pass -Enable or -Disable, not both.' }

$catalog = Get-PupCatalogFromText -Text (Get-CleanupScriptText)
$images = @(Get-BlockImages -Catalog $catalog -Only $Name)
$images = @($images | Where-Object {
    $leaf = $_.Image.ToLowerInvariant()
    $script:Deny -notcontains $leaf
})

Write-Line '=== PUP install block ==='
Write-Line ("Program names from the catalog: {0}" -f $images.Count)
foreach ($row in ($images | Sort-Object Id, Image)) {
    Write-Line ("  {0}  {1}" -f $row.Id, $row.Image)
}
if ($images.Count -eq 0) {
    Write-Line 'Result: the selected families have no literal program names to block.'
    $script:ExitCode = 1
    if ($Exit) { exit $script:ExitCode }
    return
}

$ifeo = Get-IfeoKey -Writable $false
$armed = 0
foreach ($row in $images) {
    if (-not $ifeo) { break }
    $sub = $ifeo.OpenSubKey($row.Image)
    if (-not $sub) { continue }
    $marker = $sub.GetValue($script:Marker)
    $sub.Close()
    if ([string]$marker -eq '1') { $armed++ }
}
if ($ifeo) { $ifeo.Close() }
Write-Line "Already blocked by this script: $armed"
if (-not $CheckOnly -and -not (Test-IsAdmin)) {
    Write-Line 'Result: Run elevated. Blocking a program name requires an administrator.'
    $script:ExitCode = 1
    if ($Exit) { exit $script:ExitCode }
    return
}

if ($CheckOnly) {
    Write-Line 'Result: no changes. -Enable stops these programs and shows the warning.'
    if ($Exit) { exit 0 }
    return
}

if ($Disable) {
    $onlyThese = $null
    if ($Name) {
        $onlyThese = @{}
        foreach ($row in $images) { $onlyThese[$row.Image.ToLowerInvariant()] = $true }
    }
    $ifeoW = Get-IfeoKey -Writable $true
    $removed = 0
    foreach ($nameKey in @($ifeoW.GetSubKeyNames())) {
        if ($onlyThese -and -not $onlyThese.ContainsKey($nameKey.ToLowerInvariant())) { continue }
        $sub = $ifeoW.OpenSubKey($nameKey)
        $marker = $null
        if ($sub) { $marker = $sub.GetValue($script:Marker); $sub.Close() }
        if ([string]$marker -eq '1') {
            $ifeoW.DeleteSubKeyTree($nameKey)
            $removed++
        }
    }
    $left = 0
    foreach ($nameKey in @($ifeoW.GetSubKeyNames())) {
        $sub = $ifeoW.OpenSubKey($nameKey)
        $marker = $null
        if ($sub) { $marker = $sub.GetValue($script:Marker); $sub.Close() }
        if ([string]$marker -eq '1') { $left++ }
    }
    $ifeoW.Close()
    if ($left -eq 0) {
        if (Test-Path -LiteralPath $script:Warner) { Remove-Item -LiteralPath $script:Warner -Force }
        if (Test-Path -LiteralPath $script:ListPath) { Remove-Item -LiteralPath $script:ListPath -Force }
    }
    Write-Line "Removed $removed block entries. Still blocked: $left."
    if ($left -eq 0) { Write-Line 'Result: those programs can run again.' }
    else { Write-Line 'Result: the selected names can run again. Other catalog blocks are still on.' }
    $script:ExitCode = 2
    if ($Exit) { exit $script:ExitCode }
    return
}

Write-Warner
$images | Export-Csv -LiteralPath $script:ListPath -NoTypeInformation -Encoding ASCII
$cmd = Get-DebuggerCommand
$ifeoW = Get-IfeoKey -Writable $true
$added = 0
$skipped = 0
foreach ($row in $images) {
    $existing = $ifeoW.OpenSubKey($row.Image)
    if ($existing) {
        $marker = [string]$existing.GetValue($script:Marker)
        $debugger = [string]$existing.GetValue('Debugger')
        $existing.Close()
        if ($debugger -and $marker -ne '1') {
            Write-Line "Skip $($row.Image): another debugger is already set."
            $skipped++
            continue
        }
    }
    $sub = $ifeoW.CreateSubKey($row.Image)
    $sub.SetValue('Debugger', $cmd, [Microsoft.Win32.RegistryValueKind]::String)
    $sub.SetValue($script:Marker, 1, [Microsoft.Win32.RegistryValueKind]::DWord)
    $sub.SetValue('PupFamily', $row.Id, [Microsoft.Win32.RegistryValueKind]::String)
    $sub.Close()
    $added++
}
$ifeoW.Close()
Write-Line "Blocked: $added   left alone: $skipped"
Write-Line "Warning: $($script:Warner)"
Write-Line 'Result: those program names will not start. The person who opens one sees a warning. Re-run -Enable after the catalog changes.'
if ($Exit) { exit 0 }
