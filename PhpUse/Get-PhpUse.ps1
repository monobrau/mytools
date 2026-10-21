#Requires -Version 5.1
<#
.SYNOPSIS
    Report whether this Windows PC is using PHP.

.DESCRIPTION
    Read-only. A PC is using PHP when a PHP process is running, or when IIS,
    Apache, nginx, a Windows service, or a scheduled task is set up to start it.
    Installed means php.exe was found on PATH, in the installed-programs list,
    or in the usual PHP, XAMPP, WampServer, Laragon, Plesk, and Chocolatey folders.

    Commented sample blocks, such as the PHP example in a default nginx.conf,
    are ignored. The check does not search every folder on the disk.

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

$script:Running = New-Object System.Collections.Generic.List[string]
$script:Use = New-Object System.Collections.Generic.List[string]
$script:Bins = New-Object System.Collections.Generic.List[string]
$script:SeenUse = @{}
$script:SeenBin = @{}

function Test-PhpShouldExit {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-PhpReport {
    param([Parameter(Mandatory)][int]$Code)
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

function Add-PhpConfigFile {
    param(
        [string]$Path,
        [string]$Label,
        [string]$Kind
    )
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    $pattern = '(?i)php|fastcgi_pass|proxy:fcgi://'
    foreach ($hit in @(Select-String -LiteralPath $Path -Pattern $pattern -ErrorAction SilentlyContinue)) {
        $line = $hit.Line.Trim()
        if ($line -match '^\s*#' -or $line -match '^\s*<!--') { continue }
        $ok = $false
        if ($Kind -eq 'iis') {
            $ok = $line -match '(?i)php-cgi\.exe|php-win\.exe|php\.exe'
        } else {
            $ok = $line -match '(?i)LoadModule\s+php|PHPIniDir|x-httpd-php|php-cgi\.exe|php-win\.exe|php\.exe|php\d*apache|fastcgi_pass|proxy:fcgi://|\.php'
        }
        if (-not $ok) { continue }
        Add-PhpUse ("{0} is set to run PHP: {1}" -f $Label, $Path)
        $pathRx = '(?i)[A-Za-z]:\\[^"''<>|\s]*(?:php(?:-cgi|-win)?\.exe|php\d*apache[^"''<>|\s]*)'
        foreach ($match in [regex]::Matches($line, $pathRx)) {
            Add-PhpBin $match.Value
        }
        break
    }
}

function Add-PhpServerExe {
    param([string]$ExePath)
    if (-not $ExePath -or -not (Test-Path -LiteralPath $ExePath)) { return }
    $base = [IO.Path]::GetFileName($ExePath)
    if ($base -match '(?i)^php(-cgi|-win)?\.exe$') {
        Add-PhpBin $ExePath
        return
    }
    $dir = Split-Path -Parent $ExePath
    if ($base -match '(?i)^httpd\.exe$') {
        $apacheRoot = Split-Path -Parent $dir
        $conf = Join-Path $apacheRoot 'conf'
        if (Test-Path -LiteralPath $conf) {
            Get-ChildItem -LiteralPath $conf -Filter *.conf -Recurse -Depth 2 -File -ErrorAction SilentlyContinue |
                ForEach-Object { Add-PhpConfigFile -Path $_.FullName -Label 'Apache' -Kind 'web' }
        }
    }
    if ($base -match '(?i)^nginx\.exe$') {
        $conf = Join-Path $dir 'conf'
        if (Test-Path -LiteralPath $conf) {
            Get-ChildItem -LiteralPath $conf -Filter *.conf -Recurse -Depth 2 -File -ErrorAction SilentlyContinue |
                ForEach-Object { Add-PhpConfigFile -Path $_.FullName -Label 'nginx' -Kind 'web' }
        }
    }
}

function Add-PhpExeUnder {
    param([string]$Root)
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return }
    Get-ChildItem -LiteralPath $Root -Filter php.exe -Recurse -Depth 4 -File -ErrorAction SilentlyContinue |
        ForEach-Object { Add-PhpBin $_.FullName }
}

Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(php|php-cgi|php-win|httpd|nginx)\.exe$' } |
    ForEach-Object {
        if ($_.Name -match '^(php|php-cgi|php-win)\.exe$') {
            [void]$script:Running.Add("Running now: $($_.Name) process $($_.ProcessId)")
            if ($_.ExecutablePath) { Add-PhpBin $_.ExecutablePath }
        }
        $exe = $_.ExecutablePath
        if (-not $exe -and $_.CommandLine -match '(?i)([A-Za-z]:\\[^"]*?\.exe)') {
            $exe = $Matches[1]
        }
        Add-PhpServerExe -ExePath $exe
    }

Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | ForEach-Object {
    $serviceRx = '(?i)([A-Za-z]:\\[^"]*?\\(?:php-cgi|php-win|php|httpd|nginx)\.exe)'
    if ($_.PathName -match $serviceRx) {
        $exe = $Matches[1]
        if ($exe -match '(?i)\\php(-cgi|-win)?\.exe$') {
            Add-PhpUse ("Windows service {0} is {1} and starts {2}" -f $_.Name, $_.State, $exe)
            Add-PhpBin $exe
        } else {
            Add-PhpServerExe -ExePath $exe
        }
    }
}

try {
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
            $taskName = $_.TaskName
            foreach ($action in @($_.Actions)) {
                if (-not $action) { continue }
                $blob = ((@($action.Execute, $action.Arguments) | Where-Object { $_ }) -join ' ')
                if ($blob -match '(?i)php(-cgi|-win)?\.exe') {
                    Add-PhpUse ("Scheduled task {0} starts PHP" -f $taskName)
                    if ($blob -match '(?i)([A-Za-z]:\\[^"\s]*php(?:-cgi|-win)?\.exe)') {
                        Add-PhpBin $Matches[1]
                    }
                }
            }
        }
    }
} catch { }

$appHost = Join-Path $env:windir 'System32\inetsrv\config\applicationHost.config'
Add-PhpConfigFile -Path $appHost -Label 'IIS' -Kind 'iis'

$users = Join-Path $env:SystemDrive 'Users'
if (Test-Path -LiteralPath $users) {
    Get-ChildItem -LiteralPath $users -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $express = Join-Path $_.FullName 'Documents\IISExpress\config\applicationHost.config'
        Add-PhpConfigFile -Path $express -Label 'IIS Express' -Kind 'iis'
    }
}

$inetpub = Join-Path $env:SystemDrive 'inetpub'
if (Test-Path -LiteralPath $inetpub) {
    Get-ChildItem -LiteralPath $inetpub -Filter web.config -Recurse -Depth 5 -File -ErrorAction SilentlyContinue |
        ForEach-Object { Add-PhpConfigFile -Path $_.FullName -Label 'IIS site' -Kind 'iis' }
}

$drives = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue | ForEach-Object { $_.DeviceID })
if (-not $drives) { $drives = @($env:SystemDrive) }

foreach ($drive in $drives) {
    foreach ($rel in @('php', 'xampp\php', 'wamp\bin\php', 'wamp64\bin\php', 'laragon\bin\php', 'UniServerZ', 'EasyPHP', 'tools\php')) {
        Add-PhpExeUnder -Root (Join-Path ($drive + '\') $rel)
    }
    foreach ($pair in @(
            @{ Path = "$drive\xampp\apache\conf\httpd.conf"; Label = 'Apache' },
            @{ Path = "$drive\xampp\apache\conf\extra\httpd-xampp.conf"; Label = 'Apache' },
            @{ Path = "$drive\Apache24\conf\httpd.conf"; Label = 'Apache' },
            @{ Path = "$drive\nginx\conf\nginx.conf"; Label = 'nginx' }
        )) {
        Add-PhpConfigFile -Path $pair.Path -Label $pair.Label -Kind 'web'
    }
    foreach ($root in @(
            "$drive\wamp\bin\apache",
            "$drive\wamp64\bin\apache",
            "$drive\laragon\bin\apache",
            "$drive\laragon\bin\nginx",
            "$drive\wamp\bin\nginx",
            "$drive\wamp64\bin\nginx"
        )) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $label = 'Apache'
        if ($root -match 'nginx') { $label = 'nginx' }
        Get-ChildItem -LiteralPath $root -Filter *.conf -Recurse -Depth 4 -File -ErrorAction SilentlyContinue |
            ForEach-Object { Add-PhpConfigFile -Path $_.FullName -Label $label -Kind 'web' }
    }
}

$pf64 = $env:ProgramW6432
if (-not $pf64) { $pf64 = $env:ProgramFiles }
foreach ($root in @(
        (Join-Path $env:ProgramFiles 'PHP'),
        (Join-Path $pf64 'PHP'),
        (Join-Path ${env:ProgramFiles(x86)} 'PHP'),
        (Join-Path ${env:ProgramFiles(x86)} 'Plesk\Additional'),
        (Join-Path $env:ProgramData 'chocolatey\lib\php'),
        (Join-Path $env:ProgramData 'chocolatey\bin')
    )) {
    Add-PhpExeUnder -Root $root
}

Get-Command php.exe, php-cgi.exe -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Source) { Add-PhpBin $_.Source }
}

$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
Get-ItemProperty -Path $uninstallRoots -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match '(?i)^PHP\s+[0-9]' } |
    ForEach-Object {
        $loc = [string]$_.InstallLocation
        $exe = $null
        if ($loc) { $exe = Join-Path $loc.TrimEnd('\') 'php.exe' }
        if ($exe -and (Test-Path -LiteralPath $exe)) {
            Add-PhpBin $exe
        } else {
            Add-PhpBin ("Installed program entry: {0}" -f $_.DisplayName)
        }
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
    Write-Host 'NOT INSTALLED - PHP is set up, as shown above, but php.exe was not found on PATH, in the installed-programs list, or in the usual folders. The server may point at a removed copy, or the program may be stored somewhere else.'
} else {
    Write-Host 'NOT INSTALLED - The PHP program was not found on PATH, in the installed-programs list, or in the usual PHP, XAMPP, WampServer, Laragon, Plesk, and Chocolatey folders.'
}

Write-Host 'Note - This does not search every folder. A copy saved somewhere else, or a web server in an unusual folder that is not running and is not a Windows service, would not show up.'

if ($inUse) {
    Complete-PhpReport -Code 2
} elseif ($script:Bins.Count -gt 0) {
    Complete-PhpReport -Code 1
} else {
    Complete-PhpReport -Code 0
}
