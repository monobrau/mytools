#Requires -Version 2.0
<#
.SYNOPSIS
    Report whether this workstation or Windows Server is using PHP.

.DESCRIPTION
    Read-only. The same check runs on workstations and servers. Nothing is
    skipped because the computer is a server. It is using PHP when a PHP
    process is running, or when IIS, Apache, nginx, Caddy, a Windows service,
    or a scheduled task is set up to start it.

    Installed means php.exe was found on a machine or user PATH, in the
    installed-programs list, or in a usual install folder. The check reads
    both 32-bit and 64-bit uninstall views.

    Commented sample blocks are ignored. A location whose only action is
    deny all or return 403/404 is ignored. fastcgi_pass and proxy:fcgi://
    count only in a block that also references .php or a PHP executable.

    PHP inside WSL distributions and Docker containers is not checked.
    The check does not search every folder on the disk.
    It runs on Windows PowerShell 2.0 and later.

    Exit 0: not installed and not in use.
    Exit 1: installed, but nothing is set up to run it.
    Exit 2: PHP is in use.

.PARAMETER NoExit
    Keep the PowerShell host open (Backstage).

.PARAMETER Exit
    Always call exit with the result code (Commands / automation).
#>
[CmdletBinding()]
param(
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$script:PhpEntryPath = $MyInvocation.MyCommand.Path

$script:Running = New-Object System.Collections.Generic.List[string]
$script:Use = New-Object System.Collections.Generic.List[string]
$script:Bins = New-Object System.Collections.Generic.List[string]
$script:Info = New-Object System.Collections.Generic.List[string]
$script:SeenUse = @{}
$script:SeenBin = @{}
$script:SeenInfo = @{}
$script:PhpRef = '(?i)\bphp(-cgi|-win)?(\.exe)?\b|\.php\b'
$script:PhpStrong = '(?i)LoadModule\s+php|PHPIniDir|x-httpd-php|php-cgi\.exe|php-win\.exe|php\.exe|php\d*apache'
$script:UninstallName = '(?i)^(PHP\s+[0-9]|XAMPP\b|WampServer\b|Zend Server\b|Laragon\b|Bitnami\b|AMPPS\b)'

function Test-PhpShouldExit {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    $commandPath = $script:PhpEntryPath
    if (-not $commandPath) { $commandPath = $PSCommandPath }
    if (-not [string]::IsNullOrEmpty($commandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function New-PhpObject {
    param([hashtable]$Values)
    return New-Object PSObject -Property $Values
}

function Complete-PhpReport {
    param([Parameter(Mandatory = $true)][int]$Code)
    $global:LASTEXITCODE = $Code
    if (Test-PhpShouldExit) { exit $Code }
}

function Add-PhpUse {
    param([string]$Message)
    if (-not $Message) { return }
    $key = $Message.ToLowerInvariant()
    if ($script:SeenUse.ContainsKey($key)) { return }
    $script:SeenUse[$key] = $true
    [void]$script:Use.Add($Message)
}

function Add-PhpBin {
    param([string]$Message)
    if (-not $Message) { return }
    $key = $Message.ToLowerInvariant()
    if ($script:SeenBin.ContainsKey($key)) { return }
    $script:SeenBin[$key] = $true
    [void]$script:Bins.Add($Message)
}

function Add-PhpInfo {
    param([string]$Message)
    if (-not $Message) { return }
    $key = $Message.ToLowerInvariant()
    if ($script:SeenInfo.ContainsKey($key)) { return }
    $script:SeenInfo[$key] = $true
    [void]$script:Info.Add($Message)
}

function Remove-PhpConfigComment {
    param([string]$Text)
    if (-not $Text) { return '' }
    $clean = [regex]::Replace($Text, '(?s)<!--.*?-->', '')
    $kept = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($clean -split '\r?\n')) {
        if ($line.Trim().StartsWith('#')) { continue }
        [void]$kept.Add($line)
    }
    return ($kept.ToArray() -join "`n")
}

function Test-PhpDenyAction {
    param([string]$Body)
    $actions = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($Body -split '\r?\n')) {
        $trim = $line.Trim()
        if (-not $trim -or $trim.StartsWith('#') -or $trim -eq '{' -or $trim -eq '}') { continue }
        [void]$actions.Add($trim)
    }
    if ($actions.Count -eq 0) { return $false }
    foreach ($action in $actions) {
        if ($action -notmatch '(?i)^(deny(\s+from)?\s+all|return\s+403|return\s+404)\s*;?\s*$') { return $false }
    }
    return $true
}

function Get-PhpBraceBlocks {
    param([string]$Text)
    $blocks = New-Object System.Collections.Generic.List[object]
    $start = -1
    $depth = 0
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($ch -eq '{') {
            if ($depth -eq 0) { $start = $i }
            $depth++
        } elseif ($ch -eq '}' -and $depth -gt 0) {
            $depth--
            if ($depth -eq 0 -and $start -ge 0) {
                $headerStart = [Math]::Max(0, $start - 240)
                $blocks.Add((New-PhpObject @{
                    Start  = $headerStart
                    Open   = $start
                    End    = $i
                    Header = $Text.Substring($headerStart, $start - $headerStart)
                    Body   = $Text.Substring($start + 1, $i - $start - 1)
                })) | Out-Null
            }
        }
    }
    return $blocks
}

function Remove-PhpDeniedLocation {
    param([string]$Text)
    if (-not $Text) { return '' }
    $spans = New-Object System.Collections.Generic.List[object]
    foreach ($block in (Get-PhpBraceBlocks -Text $Text)) {
        if ($block.Header -match '(?i)\blocation\b' -and (Test-PhpDenyAction -Body $block.Body)) {
            $lineBreak = $block.Header.LastIndexOf("`n")
            $spanStart = $block.Start
            if ($lineBreak -ge 0) { $spanStart = $block.Start + $lineBreak + 1 }
            $spans.Add((New-PhpObject @{ Start = $spanStart; End = $block.End })) | Out-Null
        }
    }
    $tagRx = '(?is)<Location(Match)?\b[^>]*>.*?</Location(Match)?>'
    foreach ($match in [regex]::Matches($Text, $tagRx)) {
        $inner = $match.Value -replace '(?is)^<Location(Match)?\b[^>]*>', '' -replace '(?is)</Location(Match)?>$', ''
        if (Test-PhpDenyAction -Body $inner) {
            $spans.Add((New-PhpObject @{ Start = $match.Index; End = ($match.Index + $match.Length - 1) })) | Out-Null
        }
    }
    if ($spans.Count -eq 0) { return $Text }
    $ordered = @($spans | Sort-Object Start -Descending)
    $clean = $Text
    foreach ($span in $ordered) {
        if ($span.Start -lt 0 -or $span.End -ge $clean.Length -or $span.Start -gt $span.End) { continue }
        $clean = $clean.Remove($span.Start, ($span.End - $span.Start + 1))
    }
    return $clean
}

function Test-PhpWebText {
    param([string]$Text)
    $clean = Remove-PhpDeniedLocation -Text (Remove-PhpConfigComment -Text $Text)
    if ($clean -match $script:PhpStrong) { return $true }
    foreach ($block in (Get-PhpBraceBlocks -Text $clean)) {
        $chunk = $block.Header + "`n" + $block.Body
        $hasPhp = $chunk -match '(?i)\.php\b|php(-cgi|-win)?\.exe'
        $hasPass = $chunk -match '(?i)fastcgi_pass|proxy:fcgi://'
        if ($hasPhp -and $hasPass) { return $true }
    }
    return $false
}

function Add-PhpBinFromText {
    param([string]$Text)
    if (-not $Text) { return }
    $pathRx = '(?i)[A-Za-z]:\\[^"''<>|\s]*(?:php(?:-cgi|-win)?\.exe|php\d*apache[^"''<>|\s]*)'
    foreach ($match in [regex]::Matches($Text, $pathRx)) {
        if (Test-Path -LiteralPath $match.Value) { Add-PhpBin $match.Value }
    }
}

function Add-PhpConfigFile {
    param(
        [string]$Path,
        [string]$Label,
        [string]$Kind
    )
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    $raw = ''
    try { $raw = [IO.File]::ReadAllText($Path) } catch { Write-Debug $_.Exception.Message; return }
    $clean = Remove-PhpConfigComment -Text $raw
    $hit = $false
    if ($Kind -eq 'iis') {
        $hit = $clean -match '(?i)php-cgi\.exe|php-win\.exe|php\.exe'
    } elseif ($Kind -eq 'caddy') {
        $hit = $clean -match '(?i)\bphp_fastcgi\b'
    } else {
        $hit = Test-PhpWebText -Text $raw
    }
    if (-not $hit) { return }
    Add-PhpUse ("{0} is set to run PHP: {1}" -f $Label, $Path)
    Add-PhpBinFromText -Text $clean
}

function Resolve-PhpIncludePath {
    param(
        [string]$Token,
        [string]$ServerRoot,
        [string]$CurrentFile
    )
    $token = $Token.Trim().Trim('"').Trim("'").TrimEnd(';').Trim()
    if (-not $token) { return $null }
    if ($token -match '^[A-Za-z]:\\' -or $token -match '^\\\\') { return $token }
    $token = $token -replace '/', '\'
    $fromRoot = $null
    if ($ServerRoot) { $fromRoot = Join-Path $ServerRoot $token }
    if ($fromRoot -and ((Test-Path -LiteralPath $fromRoot) -or $fromRoot.Contains('*'))) { return $fromRoot }
    $currentDir = Split-Path -Parent $CurrentFile
    if ($currentDir) { return Join-Path $currentDir $token }
    return $fromRoot
}

function Add-PhpFollowFile {
    param(
        [string]$Path,
        [string]$Label,
        [string]$Kind,
        [string]$ServerRoot,
        [string]$Style,
        [int]$Depth = 0,
        [hashtable]$Visited
    )
    if ($Depth -gt 3 -or -not $Path) { return }
    if (-not $Visited) { $Visited = @{} }
    $targets = @()
    if ($Path.Contains('*') -or $Path.Contains('?')) {
        $targets = @(Get-ChildItem -Path $Path -ErrorAction SilentlyContinue | Where-Object { $_ -and -not $_.PSIsContainer } | ForEach-Object { $_.FullName })
    } elseif ([IO.File]::Exists($Path)) {
        $targets = @([IO.Path]::GetFullPath($Path))
    }
    foreach ($full in $targets) {
        if (-not $full) { continue }
        $key = $full.ToLowerInvariant()
        if ($Visited.ContainsKey($key)) { continue }
        $Visited[$key] = $true
        Add-PhpConfigFile -Path $full -Label $Label -Kind $Kind
        if ($Depth -ge 3) { continue }
        $raw = ''
        try { $raw = [IO.File]::ReadAllText($full) } catch { Write-Debug $_.Exception.Message; continue }
        $clean = Remove-PhpConfigComment -Text $raw
        if (-not $ServerRoot) {
            $fallback = Split-Path -Parent $full
            $parent = Split-Path -Parent $fallback
            if ($Style -eq 'apache' -and $parent) { $fallback = $parent }
            $ServerRoot = $fallback
            if ($clean -match '(?im)^\s*ServerRoot\s+"([^"]+)"') { $ServerRoot = $Matches[1] }
            elseif ($clean -match "(?im)^\s*ServerRoot\s+'([^']+)'") { $ServerRoot = $Matches[1] }
            elseif ($clean -match '(?im)^\s*ServerRoot\s+(\S+)') { $ServerRoot = $Matches[1].Trim('"').Trim("'") }
        }
        $includeRx = if ($Style -eq 'apache') { '(?im)^\s*Include(?:Optional)?\s+(.+)$' } else { '(?im)^\s*include\s+(.+?)\s*;\s*$' }
        foreach ($include in [regex]::Matches($clean, $includeRx)) {
            $token = $include.Groups[1].Value.Trim()
            $next = Resolve-PhpIncludePath -Token $token -ServerRoot $ServerRoot -CurrentFile $full
            if ($next) {
                Add-PhpFollowFile -Path $next -Label $Label -Kind $Kind -ServerRoot $ServerRoot -Style $Style -Depth ($Depth + 1) -Visited $Visited
            }
        }
    }
}

function Get-PhpFlagValue {
    param(
        [string]$CommandLine,
        [string]$Flag
    )
    if (-not $CommandLine -or -not $Flag) { return $null }
    $escaped = [regex]::Escape($Flag)
    $pattern = '(?i)(?:^|\s)' + $escaped + '(?:=|\s+)(?:"([^"]+)"|''([^'']+)''|(\S+))'
    $match = [regex]::Match($CommandLine, $pattern)
    if (-not $match.Success) { return $null }
    foreach ($group in @($match.Groups[1].Value, $match.Groups[2].Value, $match.Groups[3].Value)) {
        if ($group) { return $group }
    }
    return $null
}

function Get-PhpExeFromCommand {
    param([string]$CommandLine)
    if (-not $CommandLine) { return $null }
    if ($CommandLine -match '^"([^"]+\.exe)"') { return $Matches[1] }
    if ($CommandLine -match "(?i)^'([^']+\.exe)'") { return $Matches[1] }
    if ($CommandLine -match '(?i)^([A-Za-z]:\\[^\s]+\.exe)') { return $Matches[1] }
    return $null
}

function Add-PhpServerCommand {
    param(
        [string]$ExePath,
        [string]$CommandLine
    )
    if (-not $ExePath -or -not (Test-Path -LiteralPath $ExePath)) { return }
    $base = [IO.Path]::GetFileName($ExePath)
    if ($base -match '(?i)^php(-cgi|-win)?\.exe$') {
        Add-PhpBin $ExePath
        return
    }
    $dir = Split-Path -Parent $ExePath
    if ($base -match '(?i)^httpd\.exe$') {
        $explicit = Get-PhpFlagValue -CommandLine $CommandLine -Flag '-f'
        if ($explicit) {
            Add-PhpFollowFile -Path $explicit -Label 'Apache' -Kind 'web' -Style 'apache' -Visited @{}
        }
        $apacheRoot = Split-Path -Parent $dir
        $conf = Join-Path $apacheRoot 'httpd.conf'
        $confDir = Join-Path $apacheRoot 'conf'
        if (Test-Path -LiteralPath (Join-Path $confDir 'httpd.conf')) { $conf = Join-Path $confDir 'httpd.conf' }
        if (Test-Path -LiteralPath $conf) {
            Add-PhpFollowFile -Path $conf -Label 'Apache' -Kind 'web' -Style 'apache' -Visited @{}
        }
    }
    if ($base -match '(?i)^nginx\.exe$') {
        $explicit = Get-PhpFlagValue -CommandLine $CommandLine -Flag '-c'
        if ($explicit) {
            Add-PhpFollowFile -Path $explicit -Label 'nginx' -Kind 'web' -Style 'nginx' -Visited @{}
        }
        $conf = Join-Path $dir 'conf\nginx.conf'
        if (Test-Path -LiteralPath $conf) {
            Add-PhpFollowFile -Path $conf -Label 'nginx' -Kind 'web' -Style 'nginx' -ServerRoot $dir -Visited @{}
        }
    }
    if ($base -match '(?i)^caddy\.exe$') {
        $explicit = Get-PhpFlagValue -CommandLine $CommandLine -Flag '--config'
        if (-not $explicit) { $explicit = Join-Path $dir 'Caddyfile' }
        Add-PhpConfigFile -Path $explicit -Label 'Caddy' -Kind 'caddy'
    }
}

function Get-PhpSystemPath {
    param([string]$Relative)
    $root = Join-Path $env:windir 'System32'
    if ($env:PROCESSOR_ARCHITEW6432) {
        $native = Join-Path $env:windir 'Sysnative'
        if (Test-Path -LiteralPath $native) { $root = $native }
    }
    return Join-Path $root $Relative
}

function Get-PhpXmlDocument {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = [IO.File]::ReadAllText($Path)
        $raw = [regex]::Replace($raw, '(?s)<!--.*?-->', '')
        $xml = New-Object System.Xml.XmlDocument
        $xml.LoadXml($raw)
        return $xml
    } catch {
        Write-Debug $_.Exception.Message
        return $null
    }
}

function Add-PhpIisFile {
    param([string]$Path)
    $xml = Get-PhpXmlDocument -Path $Path
    if (-not $xml) { return }
    Add-PhpConfigFile -Path $Path -Label 'IIS' -Kind 'iis'
    $seen = @{}
    foreach ($node in @($xml.SelectNodes('//virtualDirectory'))) {
        $physical = [Environment]::ExpandEnvironmentVariables([string]$node.GetAttribute('physicalPath'))
        if (-not $physical -or $physical -match '%') { continue }
        $physical = $physical -replace '/', '\'
        $key = $physical.TrimEnd('\').ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        Add-PhpConfigFile -Path (Join-Path $physical 'web.config') -Label 'IIS site' -Kind 'iis'
    }
}

function Add-PhpIisRedirection {
    param([string]$Path)
    $xml = Get-PhpXmlDocument -Path $Path
    if (-not $xml) { return }
    $node = $xml.SelectSingleNode('//configurationRedirection')
    if (-not $node) { return }
    if ([string]$node.GetAttribute('enabled') -ne 'true') { return }
    $target = [string]$node.GetAttribute('path')
    Add-PhpInfo ("IIS configuration redirection: {0}" -f $target)
    if (-not $target) { return }
    $remote = Join-Path $target 'applicationHost.config'
    if (Test-Path -LiteralPath $remote) {
        Add-PhpIisFile -Path $remote
    } else {
        Add-PhpInfo ("IIS redirected configuration could not be reached: {0}" -f $remote)
    }
}

function Open-PhpRegistryKey {
    param(
        [Microsoft.Win32.RegistryHive]$Hive,
        [string]$View,
        [string]$SubKey
    )
    if (-not $SubKey) { return $null }
    $viewType = 'Microsoft.Win32.RegistryView' -as [type]
    if ($viewType) {
        $base = $null
        try {
            $viewEnum = [Enum]::Parse($viewType, $View)
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, $viewEnum)
            if (-not $base) { return $null }
            return $base.OpenSubKey($SubKey)
        } catch {
            Write-Debug $_.Exception.Message
            return $null
        } finally {
            if ($base) { $base.Close() }
        }
    }
    $root = $null
    if ($Hive -eq [Microsoft.Win32.RegistryHive]::LocalMachine) { $root = [Microsoft.Win32.Registry]::LocalMachine }
    elseif ($Hive -eq [Microsoft.Win32.RegistryHive]::Users) { $root = [Microsoft.Win32.Registry]::Users }
    if (-not $root) { return $null }
    $effective = $SubKey
    $os64 = ($env:PROCESSOR_ARCHITECTURE -match '^(AMD64|ARM64)$' -or [string]$env:PROCESSOR_ARCHITEW6432)
    if ($View -eq 'Registry32' -and $os64) {
        if ($effective -match '(?i)^SOFTWARE\\') {
            $effective = 'SOFTWARE\Wow6432Node\' + $effective.Substring(9)
        } elseif ($effective -match '(?i)\\SOFTWARE\\') {
            $effective = [regex]::Replace($effective, '(?i)\\SOFTWARE\\', '\SOFTWARE\Wow6432Node\', 1)
        }
    }
    try { return $root.OpenSubKey($effective) } catch { Write-Debug $_.Exception.Message; return $null }
}

function Add-PhpUninstallKey {
    param($Key)
    if (-not $Key) { return }
    try {
        foreach ($name in @($Key.GetSubKeyNames())) {
            $sub = $null
            try {
                $sub = $Key.OpenSubKey($name)
                if (-not $sub) { continue }
                $display = [string]$sub.GetValue('DisplayName')
                if ($display -notmatch $script:UninstallName) { continue }
                $loc = [string]$sub.GetValue('InstallLocation')
                $exe = $null
                if ($loc) { $exe = Join-Path $loc.TrimEnd('\') 'php.exe' }
                if ($exe -and (Test-Path -LiteralPath $exe)) { Add-PhpBin $exe }
                else { Add-PhpBin ("Installed program entry: {0}" -f $display) }
            } catch {
                Write-Debug $_.Exception.Message
            } finally {
                if ($sub) { $sub.Close() }
            }
        }
    } finally {
        $Key.Close()
    }
}

function Add-PhpComposerKey {
    param($Key)
    if (-not $Key) { return }
    try {
        foreach ($name in @($Key.GetValueNames())) {
            $data = [string]$Key.GetValue($name)
            if (-not $data) { continue }
            try {
                if ($data -match '(?i)php(-cgi|-win)?\.exe$' -and (Test-Path -LiteralPath $data)) {
                    Add-PhpBin $data
                } elseif (Test-Path -LiteralPath (Join-Path $data 'php.exe')) {
                    Add-PhpBin (Join-Path $data 'php.exe')
                }
            } catch {
                Write-Debug $_.Exception.Message
            }
        }
    } catch {
        Write-Debug $_.Exception.Message
    } finally {
        $Key.Close()
    }
}

function Add-PhpPathValue {
    param([string]$PathValue)
    if (-not $PathValue) { return }
    $expanded = [Environment]::ExpandEnvironmentVariables($PathValue)
    foreach ($dir in ($expanded -split ';')) {
        $dir = $dir.Trim().Trim('"')
        if (-not $dir) { continue }
        foreach ($name in @('php.exe', 'php-cgi.exe')) {
            $candidate = Join-Path $dir $name
            if (Test-Path -LiteralPath $candidate) { Add-PhpBin $candidate }
        }
    }
}

function Add-PhpEnvValue {
    param(
        [string]$Scope,
        [string]$Name,
        [string]$Value
    )
    if (-not $Value) { return }
    Add-PhpInfo ("{0} ({1}): {2}" -f $Name, $Scope, $Value)
}

function Add-PhpEnvironmentKey {
    param(
        $Key,
        [string]$Scope
    )
    if (-not $Key) { return }
    try {
        Add-PhpPathValue -PathValue ([string]$Key.GetValue('Path'))
        Add-PhpEnvValue -Scope $Scope -Name 'PHPRC' -Value ([string]$Key.GetValue('PHPRC'))
        Add-PhpEnvValue -Scope $Scope -Name 'PHP_INI_SCAN_DIR' -Value ([string]$Key.GetValue('PHP_INI_SCAN_DIR'))
    } catch {
        Write-Debug $_.Exception.Message
    } finally {
        $Key.Close()
    }
}

function Get-PhpServiceParameters {
    param([string]$ServiceName)
    $sub = 'SYSTEM\CurrentControlSet\Services\' + $ServiceName + '\Parameters'
    $key = Open-PhpRegistryKey -Hive ([Microsoft.Win32.RegistryHive]::LocalMachine) -View 'Registry64' -SubKey $sub
    if (-not $key) { return $null }
    try {
        return New-PhpObject @{
            Application   = [string]$key.GetValue('Application')
            AppParameters = [string]$key.GetValue('AppParameters')
        }
    } finally {
        $key.Close()
    }
}

function Get-PhpWinSwCommand {
    param([string]$ExePath)
    if (-not $ExePath) { return $null }
    $xmlPath = [IO.Path]::ChangeExtension($ExePath, '.xml')
    $xml = Get-PhpXmlDocument -Path $xmlPath
    if (-not $xml -or -not $xml.service) { return $null }
    $executable = [string]$xml.service.executable
    $arguments = [string]$xml.service.arguments
    if (-not $executable) { return $null }
    return New-PhpObject @{ Exe = $executable; Arguments = $arguments }
}

function Add-PhpWrappedService {
    param(
        [string]$ServiceName,
        [string]$State,
        [string]$ExePath,
        [string]$Arguments
    )
    $base = [IO.Path]::GetFileName($ExePath)
    $command = (($ExePath, $Arguments) -join ' ').Trim()
    if ($base -match '(?i)^php(-cgi|-win)?\.exe$') {
        Add-PhpUse ("Windows service {0} is {1} and starts {2}" -f $ServiceName, $State, $ExePath)
        Add-PhpBin $ExePath
        return
    }
    if ($base -match '(?i)^(httpd|nginx|caddy)\.exe$') {
        Add-PhpServerCommand -ExePath $ExePath -CommandLine $command
    }
}

function Add-PhpUserProfiles {
    $profiles = New-Object System.Collections.Generic.List[string]
    $list = Open-PhpRegistryKey -Hive ([Microsoft.Win32.RegistryHive]::LocalMachine) -View 'Registry64' -SubKey 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    if ($list) {
        try {
            foreach ($sid in @($list.GetSubKeyNames())) {
                $sub = $null
                try {
                    $sub = $list.OpenSubKey($sid)
                    $path = [Environment]::ExpandEnvironmentVariables([string]$sub.GetValue('ProfileImagePath'))
                    if ($path) { [void]$profiles.Add($path) }
                } catch {
                    Write-Debug $_.Exception.Message
                } finally {
                    if ($sub) { $sub.Close() }
                }
            }
        } finally {
            $list.Close()
        }
    }
    $users = Join-Path $env:SystemDrive 'Users'
    foreach ($dir in @(Get-PhpDirectory -Root $users)) {
        if ($dir) { [void]$profiles.Add($dir) }
    }
    $seen = @{}
    foreach ($profilePath in $profiles) {
        if (-not $profilePath) { continue }
        $key = $profilePath.TrimEnd('\').ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        Add-PhpExeUnder -Root (Join-Path $profilePath 'scoop\apps\php')
        $herd = Join-Path $profilePath '.config\herd\bin'
        Add-PhpExeUnder -Root $herd
        $herdExe = Join-Path $herd 'php.exe'
        if (Test-Path -LiteralPath $herdExe) { Add-PhpBin $herdExe }
        $winget = Join-Path $profilePath 'AppData\Local\Microsoft\WinGet\Packages'
        foreach ($dir in @(Get-PhpDirectory -Root $winget -Filter 'PHP.PHP*')) {
            if ($dir) { Add-PhpExeUnder -Root $dir }
        }
        $express = Join-Path $profilePath 'Documents\IISExpress\config\applicationHost.config'
        Add-PhpIisFile -Path $express
    }
}

function Get-PhpDirectory {
    param(
        [string]$Root,
        [string]$Filter
    )
    if (-not $Root -or -not [IO.Directory]::Exists($Root)) { return }
    $info = $null
    try { $info = New-Object IO.DirectoryInfo $Root } catch { Write-Debug $_.Exception.Message; return }
    try {
        if ($Filter) { $dirs = @($info.GetDirectories($Filter)) }
        else { $dirs = @($info.GetDirectories()) }
    } catch {
        Write-Debug $_.Exception.Message
        return
    }
    foreach ($dir in $dirs) {
        if (-not $dir) { continue }
        if (($dir.Attributes -band [IO.FileAttributes]::Hidden) -ne 0) { continue }
        $dir.FullName
    }
}

function Get-PhpFilesUnder {
    param(
        [string]$Root,
        [string]$Filter,
        [int]$MaxDepth
    )
    if (-not $Root -or -not [IO.Directory]::Exists($Root)) { return }
    $pending = New-Object System.Collections.Generic.Queue[string]
    $pending.Enqueue(('0|' + $Root))
    $seen = @{}
    while ($pending.Count -gt 0) {
        $raw = [string]$pending.Dequeue()
        $split = $raw.IndexOf('|')
        if ($split -lt 1) { continue }
        $depth = [int]$raw.Substring(0, $split)
        $dir = $raw.Substring($split + 1)
        $key = $dir.TrimEnd('\').ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $info = $null
        try { $info = New-Object IO.DirectoryInfo $dir } catch { Write-Debug $_.Exception.Message; continue }
        try {
            foreach ($file in @($info.GetFiles($Filter))) {
                if (-not $file) { continue }
                if (($file.Attributes -band [IO.FileAttributes]::Hidden) -ne 0) { continue }
                $file.FullName
            }
        } catch { Write-Debug $_.Exception.Message }
        if ($depth -ge $MaxDepth) { continue }
        try {
            foreach ($child in @($info.GetDirectories())) {
                if (-not $child) { continue }
                if (($child.Attributes -band [IO.FileAttributes]::Hidden) -ne 0) { continue }
                $pending.Enqueue((([string]($depth + 1)) + '|' + $child.FullName))
            }
        } catch { Write-Debug $_.Exception.Message }
    }
}

function Add-PhpExeUnder {
    param([string]$Root)
    foreach ($exe in @(Get-PhpFilesUnder -Root $Root -Filter 'php.exe' -MaxDepth 4)) {
        if ($exe) { Add-PhpBin $exe }
    }
}

function Get-PhpCim {
    param(
        [string]$Class,
        [string]$Filter
    )
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            if ($Filter) { return @(Get-CimInstance -ClassName $Class -Filter $Filter -ErrorAction SilentlyContinue) }
            return @(Get-CimInstance -ClassName $Class -ErrorAction SilentlyContinue)
        }
        if ($Filter) { return @(Get-WmiObject -Class $Class -Filter $Filter -ErrorAction SilentlyContinue) }
        return @(Get-WmiObject -Class $Class -ErrorAction SilentlyContinue)
    } catch {
        Write-Debug $_.Exception.Message
        return @()
    }
}

function Add-PhpTaskCommand {
    param(
        [string]$TaskName,
        [string]$Execute,
        [string]$Arguments
    )
    $blob = ((@($Execute, $Arguments) | Where-Object { $_ }) -join ' ')
    $referenced = $blob -match $script:PhpRef
    if (-not $referenced -and $blob -match '(?i)(?:"([^"]+\.(?:bat|cmd|ps1))"|([A-Za-z]:\\[^"\s]+\.(?:bat|cmd|ps1)))') {
        $scriptFile = $Matches[1]
        if (-not $scriptFile) { $scriptFile = $Matches[2] }
        if ($scriptFile -and (Test-Path -LiteralPath $scriptFile)) {
            try {
                $fileText = [IO.File]::ReadAllText($scriptFile)
                if ($fileText.Length -le 512000 -and $fileText -match $script:PhpRef) { $referenced = $true }
            } catch {
                Write-Debug $_.Exception.Message
            }
        }
    }
    if (-not $referenced) { return }
    Add-PhpUse ("Scheduled task {0} starts PHP" -f $TaskName)
    if ($blob -match '(?i)([A-Za-z]:\\[^"\s]*php(?:-cgi|-win)?\.exe)') { Add-PhpBin $Matches[1] }
}

function Add-PhpScheduledTasks {
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
            $taskName = $_.TaskName
            foreach ($action in @($_.Actions)) {
                if (-not $action) { continue }
                Add-PhpTaskCommand -TaskName $taskName -Execute $action.Execute -Arguments $action.Arguments
            }
        }
        return
    }
    $svc = New-Object -ComObject 'Schedule.Service'
    $svc.Connect()
    $folders = New-Object System.Collections.Generic.Queue[string]
    $folders.Enqueue('\')
    while ($folders.Count -gt 0) {
        $folderPath = [string]$folders.Dequeue()
        $folder = $null
        try { $folder = $svc.GetFolder($folderPath) } catch { Write-Debug $_.Exception.Message; continue }
        try {
            foreach ($sub in $folder.GetFolders(0)) {
                if ($sub -and $sub.Path) { $folders.Enqueue([string]$sub.Path) }
            }
        } catch { Write-Debug $_.Exception.Message }
        try {
            foreach ($task in $folder.GetTasks(0)) {
                if (-not $task) { continue }
                $taskName = [string]$task.Name
                foreach ($action in $task.Definition.Actions) {
                    $execute = ''
                    $arguments = ''
                    try { $execute = [string]$action.Path } catch { $execute = '' }
                    try { $arguments = [string]$action.Arguments } catch { $arguments = '' }
                    Add-PhpTaskCommand -TaskName $taskName -Execute $execute -Arguments $arguments
                }
            }
        } catch { Write-Debug $_.Exception.Message }
    }
}

# --- main ---
Get-PhpCim -Class 'Win32_Process' |
    Where-Object { $_.Name -match '^(php|php-cgi|php-win|httpd|nginx|caddy)\.exe$' } |
    ForEach-Object {
        if ($_.Name -match '^(php|php-cgi|php-win)\.exe$') {
            [void]$script:Running.Add("Running now: $($_.Name) process $($_.ProcessId)")
            if ($_.ExecutablePath) { Add-PhpBin $_.ExecutablePath }
        }
        $exe = $_.ExecutablePath
        if (-not $exe) { $exe = Get-PhpExeFromCommand -CommandLine $_.CommandLine }
        Add-PhpServerCommand -ExePath $exe -CommandLine $_.CommandLine
    }

foreach ($proc in @(Get-Process -ErrorAction SilentlyContinue)) {
    try {
        foreach ($module in @($proc.Modules)) {
            $moduleName = [string]$module.ModuleName
            $isPhpDll = $moduleName -match '(?i)^php\d*(ts)?\.dll$'
            $isApacheDll = $moduleName -match '(?i)^php\d*apache'
            if (-not $isPhpDll -and -not $isApacheDll) { continue }
            [void]$script:Running.Add(("Running now: {0} {1} loads {2}" -f $proc.ProcessName, $proc.Id, $module.FileName))
            $dllDir = Split-Path -Parent ([string]$module.FileName)
            if ($dllDir) {
                $phpExe = Join-Path $dllDir 'php.exe'
                if (Test-Path -LiteralPath $phpExe) { Add-PhpBin $phpExe }
            }
        }
    } catch {
        Write-Debug $_.Exception.Message
    }
}

Get-PhpCim -Class 'Win32_Service' | ForEach-Object {
    $serviceName = [string]$_.Name
    $state = [string]$_.State
    $pathName = [string]$_.PathName
    $exe = Get-PhpExeFromCommand -CommandLine $pathName
    if (-not $exe) { return }
    $base = [IO.Path]::GetFileName($exe)
    if ($base -match '(?i)^nssm\.exe$') {
        $param = Get-PhpServiceParameters -ServiceName $serviceName
        if ($param -and $param.Application) {
            Add-PhpWrappedService -ServiceName $serviceName -State $state -ExePath $param.Application -Arguments $param.AppParameters
        }
        return
    }
    if ($base -match '(?i)^srvany\.exe$') {
        $param = Get-PhpServiceParameters -ServiceName $serviceName
        if ($param -and $param.Application) {
            Add-PhpWrappedService -ServiceName $serviceName -State $state -ExePath $param.Application -Arguments $param.AppParameters
        }
        return
    }
    $winsw = Get-PhpWinSwCommand -ExePath $exe
    if ($winsw -and $winsw.Exe) {
        Add-PhpWrappedService -ServiceName $serviceName -State $state -ExePath $winsw.Exe -Arguments $winsw.Arguments
        return
    }
    if ($base -match '(?i)^php(-cgi|-win)?\.exe$') {
        Add-PhpUse ("Windows service {0} is {1} and starts {2}" -f $serviceName, $state, $exe)
        Add-PhpBin $exe
        return
    }
    if ($base -match '(?i)^(httpd|nginx|caddy)\.exe$') {
        Add-PhpServerCommand -ExePath $exe -CommandLine $pathName
    }
}

try {
    Add-PhpScheduledTasks
} catch {
    Write-Debug $_.Exception.Message
}

$appHost = Get-PhpSystemPath -Relative 'inetsrv\config\applicationHost.config'
Add-PhpIisFile -Path $appHost
Add-PhpIisRedirection -Path (Get-PhpSystemPath -Relative 'inetsrv\config\redirection.config')

$inetpub = Join-Path $env:SystemDrive 'inetpub'
foreach ($file in @(Get-PhpFilesUnder -Root $inetpub -Filter 'web.config' -MaxDepth 5)) {
    if ($file) { Add-PhpConfigFile -Path $file -Label 'IIS site' -Kind 'iis' }
}

$drives = @(Get-PhpCim -Class 'Win32_LogicalDisk' -Filter 'DriveType=3' | ForEach-Object { $_.DeviceID })
if (-not $drives) { $drives = @($env:SystemDrive) }
$programRoots = @(
    (Join-Path $env:ProgramFiles 'PHP'),
    (Join-Path $env:ProgramFiles 'Ampps\php'),
    (Join-Path ${env:ProgramFiles(x86)} 'PHP'),
    (Join-Path ${env:ProgramFiles(x86)} 'Ampps\php'),
    (Join-Path ${env:ProgramFiles(x86)} 'Plesk\Additional'),
    (Join-Path ${env:ProgramFiles(x86)} 'Zend\ZendServer\bin'),
    (Join-Path $env:ProgramData 'chocolatey\lib\php'),
    (Join-Path $env:ProgramData 'chocolatey\bin')
)
$pf64 = $env:ProgramW6432
if ($pf64) {
    $programRoots += @(
        (Join-Path $pf64 'PHP'),
        (Join-Path $pf64 'Ampps\php'),
        (Join-Path $pf64 'Zend\ZendServer\bin')
    )
}

foreach ($drive in $drives) {
    $driveRoot = $drive + '\'
    foreach ($rel in @('php', 'xampp\php', 'wamp\bin\php', 'wamp64\bin\php', 'laragon\bin\php', 'UniServerZ', 'EasyPHP', 'tools\php', 'MAMP\bin\php')) {
        Add-PhpExeUnder -Root (Join-Path $driveRoot $rel)
    }
    $bitnami = Join-Path $driveRoot 'Bitnami'
    foreach ($dir in @(Get-PhpDirectory -Root $bitnami)) {
        if ($dir) { Add-PhpExeUnder -Root (Join-Path $dir 'php') }
    }
    foreach ($pair in @(
            @{ Path = "$drive\xampp\apache\conf\httpd.conf"; Label = 'Apache'; Style = 'apache' },
            @{ Path = "$drive\Apache24\conf\httpd.conf"; Label = 'Apache'; Style = 'apache' },
            @{ Path = "$drive\nginx\conf\nginx.conf"; Label = 'nginx'; Style = 'nginx' }
        )) {
        Add-PhpFollowFile -Path $pair.Path -Label $pair.Label -Kind 'web' -Style $pair.Style -Visited @{}
    }
    foreach ($root in @(
            "$drive\wamp\bin\apache", "$drive\wamp64\bin\apache", "$drive\laragon\bin\apache",
            "$drive\laragon\bin\nginx", "$drive\wamp\bin\nginx", "$drive\wamp64\bin\nginx"
        )) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $label = 'Apache'
        $style = 'apache'
        if ($root -match 'nginx') { $label = 'nginx'; $style = 'nginx' }
        foreach ($file in @(Get-PhpFilesUnder -Root $root -Filter '*.conf' -MaxDepth 4)) {
            if ($file) { Add-PhpFollowFile -Path $file -Label $label -Kind 'web' -Style $style -Visited @{} }
        }
    }
}

foreach ($root in $programRoots) { Add-PhpExeUnder -Root $root }
Add-PhpUserProfiles

Get-Command php.exe, php-cgi.exe -ErrorAction SilentlyContinue | ForEach-Object {
    $commandPath = $_.Path
    if (-not $commandPath) { $commandPath = $_.Definition }
    if ($commandPath) { Add-PhpBin $commandPath }
}

foreach ($viewName in @('Registry64', 'Registry32')) {
    Add-PhpUninstallKey -Key (Open-PhpRegistryKey -Hive ([Microsoft.Win32.RegistryHive]::LocalMachine) -View $viewName -SubKey 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
    Add-PhpComposerKey -Key (Open-PhpRegistryKey -Hive ([Microsoft.Win32.RegistryHive]::LocalMachine) -View $viewName -SubKey 'SOFTWARE\ComposerSetup')
}
Add-PhpEnvironmentKey -Key (Open-PhpRegistryKey -Hive ([Microsoft.Win32.RegistryHive]::LocalMachine) -View 'Registry64' -SubKey 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment') -Scope 'machine'

$sidNames = @()
$viewType = 'Microsoft.Win32.RegistryView' -as [type]
if ($viewType) {
    $usersHive = $null
    try {
        $viewEnum = [Enum]::Parse($viewType, 'Registry64')
        $usersHive = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::Users, $viewEnum)
        if ($usersHive) { $sidNames = @($usersHive.GetSubKeyNames()) }
    } catch {
        Write-Debug $_.Exception.Message
    } finally {
        if ($usersHive) { $usersHive.Close() }
    }
} else {
    try { $sidNames = @([Microsoft.Win32.Registry]::Users.GetSubKeyNames()) } catch { Write-Debug $_.Exception.Message }
}
foreach ($sid in $sidNames) {
    if ($sid -notmatch '^S-1-5-21-' -or $sid -match '_Classes$') { continue }
    foreach ($viewName in @('Registry64', 'Registry32')) {
        $uninstall = $sid + '\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        Add-PhpUninstallKey -Key (Open-PhpRegistryKey -Hive ([Microsoft.Win32.RegistryHive]::Users) -View $viewName -SubKey $uninstall)
        $composer = $sid + '\SOFTWARE\ComposerSetup'
        Add-PhpComposerKey -Key (Open-PhpRegistryKey -Hive ([Microsoft.Win32.RegistryHive]::Users) -View $viewName -SubKey $composer)
    }
    $envKey = $sid + '\Environment'
    Add-PhpEnvironmentKey -Key (Open-PhpRegistryKey -Hive ([Microsoft.Win32.RegistryHive]::Users) -View 'Registry64' -SubKey $envKey) -Scope $sid
}

$inUse = ($script:Running.Count -gt 0) -or ($script:Use.Count -gt 0)
if ($inUse) {
    Write-Host 'USING PHP - Something on this computer runs PHP. A PHP process is running now, or IIS, Apache, nginx, a Windows service, or a scheduled task is set up to start it.'
    foreach ($line in $script:Running) { Write-Host "  $line" }
    foreach ($line in $script:Use) { Write-Host "  $line" }
} else {
    Write-Host 'NOT USING PHP - Nothing found is set up to run PHP. No PHP process is running, and IIS, Apache, nginx, Windows services, and scheduled tasks are not set up to start it.'
}

if ($script:Bins.Count -gt 0) {
    Write-Host 'INSTALLED - The PHP program is on this computer. That only means the files are present. The line above says whether anything is set up to run them.'
    foreach ($line in $script:Bins) { Write-Host "  Found: $line" }
} elseif ($inUse) {
    Write-Host 'NOT INSTALLED - PHP is set up, as shown above, but php.exe was not found on PATH, in the installed-programs list, or in the usual folders. The web server may point at a removed copy, or the program may be stored somewhere else.'
} else {
    Write-Host 'NOT INSTALLED - The PHP program was not found on PATH, in the installed-programs list, or in the usual PHP, XAMPP, WampServer, Laragon, Plesk, and Chocolatey folders.'
}
foreach ($line in $script:Info) { Write-Host "  $line" }
Write-Host 'Note - Same check on a workstation or Windows Server. This does not search every folder. A copy saved somewhere else, or a web server in an unusual folder that is not running and is not a Windows service, would not show up. PHP inside WSL distributions and Docker containers is not checked.'

if ($inUse) { Complete-PhpReport -Code 2 }
elseif ($script:Bins.Count -gt 0) { Complete-PhpReport -Code 1 }
else { Complete-PhpReport -Code 0 }
