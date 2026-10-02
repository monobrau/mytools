#Requires -Version 5.1
<#
.SYNOPSIS
    Report whether a Windows feature download or setup is actually moving.

.DESCRIPTION
    Safe to run in a second window while Invoke-WindowsUpdate.ps1 is sitting
    on Download(). Does not start a download, does not stop services, and does
    not walk the download tree. BITS and Delivery Optimization queries are
    skipped because those calls hang while a feature download is stuck.

    The feature plan is C:\Windows\SoftwareDistribution\Download\<id>\windlp.state.xml.
    OSDownloadSize 0 and TaskCount 0 mean the OS image is not downloading, even
    when ActionList.xml keeps getting a new timestamp.

.PARAMETER WatchSeconds
    Wait this long and take a second sample. 0 prints one sample and returns.

.PARAMETER NoExit
    Keep the PowerShell host open (Backstage). Does not call exit.

.PARAMETER Exit
    Call exit with a status code (ScreenConnect Commands). Omit in Backstage.

.NOTES
    Exit 0: setup is running, or the OS download grew during the watch.
    Exit 1: a feature folder exists and the OS download has not started.
    Exit 2: no feature download and no setup.
#>
[CmdletBinding()]
param(
    [int]$WatchSeconds = 0,

    [switch]$NoExit,

    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

function Write-Line([string]$Message) {
    Write-Host $Message
    try { [Console]::Out.Flush() } catch { }
}

function Write-Section([string]$Message) {
    Write-Line "=== $Message ==="
}

function Convert-WindlpNumber([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $text = $Value.Trim()
    $n = 0L
    if ($text -match '^[0-9]+$') {
        [void][int64]::TryParse($text, [ref]$n)
        return $n
    }
    if ($text -match '^[0-9A-Fa-f]+$') {
        return [Convert]::ToInt64($text, 16)
    }
    return $null
}

function Read-WindlpFile {
    param([string]$Path)
    $result = [ordered]@{
        Path                       = $Path
        LastWriteTime              = $null
        TaskCount                  = $null
        WorkingPath                = ''
        OsDownloadComplete         = $null
        OSDownloadSize             = $null
        RecreatePackageFileList    = $null
        PreDownloadCheckComplete   = $null
    }
    try { $result.LastWriteTime = (Get-Item -LiteralPath $Path).LastWriteTime } catch { return $null }
    try { [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop } catch { return $null }
    $root = $xml.WINDLP
    if (-not $root) { return $null }
    $result.TaskCount = $root.TaskCount
    $result.WorkingPath = [string]$root.WorkingPath
    foreach ($prop in @($root.DwordProperty) + @($root.QuadwordProperty)) {
        if (-not $prop) { continue }
        $name = [string]$prop.Name
        switch ($name) {
            'OsDownloadComplete' { $result.OsDownloadComplete = $prop.Value }
            'RecreatePackageFileList' { $result.RecreatePackageFileList = $prop.Value }
            'PreDownloadCheckComplete' { $result.PreDownloadCheckComplete = $prop.Value }
            'OSDownloadSize' { $result.OSDownloadSize = Convert-WindlpNumber ([string]$prop.Value) }
        }
    }
    return [pscustomobject]$result
}

function Get-WindlpFiles {
    $root = 'C:\Windows\SoftwareDistribution\Download'
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($dir in @(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer })) {
        $candidate = Join-Path $dir.FullName 'windlp.state.xml'
        if (Test-Path -LiteralPath $candidate) { $found.Add($candidate) }
    }
    return @($found.ToArray())
}

function Get-TopFiles {
    param([string]$Folder)
    if (-not $Folder -or -not (Test-Path -LiteralPath $Folder)) { return @() }
    return @(Get-ChildItem -LiteralPath $Folder -Force -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 5)
}

function Get-ProgressSample {
    $os = $null
    try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop } catch { }
    $free = $null
    try { $free = (Get-PSDrive -Name C -ErrorAction Stop).Free } catch { }

    $procs = @(Get-Process -Name SetupHost, SetupPrep, MoUsoCoreWorker, TiWorker, TrustedInstaller, Windows10UpgraderApp -ErrorAction SilentlyContinue)
    $services = @(Get-Service -Name bits, dosvc, wuauserv, UsoSvc -ErrorAction SilentlyContinue)

    $windlpPaths = @(Get-WindlpFiles)
    $states = New-Object System.Collections.Generic.List[object]
    foreach ($path in $windlpPaths) {
        $state = Read-WindlpFile -Path $path
        if ($state) { $states.Add($state) }
    }

    $bt = 'C:\$WINDOWS.~BT'
    $btItems = @()
    if (Test-Path -LiteralPath $bt) { $btItems = @(Get-TopFiles -Folder $bt) }

    return [pscustomobject]@{
        When       = Get-Date
        Caption    = $(if ($os) { $os.Caption } else { '' })
        Build      = $(if ($os) { $os.BuildNumber } else { '' })
        FreeBytes  = $free
        Processes  = $procs
        Services   = $services
        States     = @($states.ToArray())
        BtItems    = $btItems
        BtExists   = (Test-Path -LiteralPath $bt)
    }
}

function Format-Bytes([object]$Value) {
    if ($null -eq $Value -or $Value -eq '') { return '' }
    $n = 0L
    if (-not [int64]::TryParse([string]$Value, [ref]$n)) { return [string]$Value }
    if ($n -ge 1GB) { return ('{0:N2} GB' -f ($n / 1GB)) }
    if ($n -ge 1MB) { return ('{0:N0} MB' -f ($n / 1MB)) }
    return ('{0:N0} bytes' -f $n)
}

function Write-ProgressSample {
    param($Sample)
    Write-Line ("Time: {0}" -f $Sample.When.ToString('yyyy-MM-dd HH:mm:ss'))
    if ($Sample.Caption) { Write-Line ("OS: {0} (build {1})" -f $Sample.Caption, $Sample.Build) }
    if ($null -ne $Sample.FreeBytes) { Write-Line ("FreeSpace: {0}" -f (Format-Bytes $Sample.FreeBytes)) }

    Write-Line 'Services:'
    foreach ($svc in @($Sample.Services)) {
        Write-Line ("  {0}  {1}" -f $svc.Name, $svc.Status)
    }
    if (-not $Sample.Services -or @($Sample.Services).Count -eq 0) { Write-Line '  (none found)' }

    Write-Line 'Processes:'
    $procs = @($Sample.Processes)
    if ($procs.Count -eq 0) {
        Write-Line '  (no SetupHost, MoUsoCoreWorker, or TiWorker)'
    } else {
        foreach ($proc in $procs) {
            $started = ''
            try { if ($proc.StartTime) { $started = $proc.StartTime.ToString('HH:mm:ss') } } catch { }
            $cpu = ''
            if ($null -ne $proc.CPU) { $cpu = '  cpu {0:N1}s' -f $proc.CPU }
            $at = ''
            if ($started) { $at = "  started $started" }
            Write-Line ("  {0}  pid {1}{2}{3}" -f $proc.Name, $proc.Id, $cpu, $at)
        }
    }

    $states = @($Sample.States)
    if ($states.Count -eq 0) {
        Write-Line 'Windlp: no feature plan file under SoftwareDistribution\Download'
    }
    foreach ($state in $states) {
        Write-Line ("Windlp: {0}" -f $state.Path)
        Write-Line ("  LastWrite: {0}" -f $state.LastWriteTime)
        Write-Line ("  TaskCount: {0}" -f $state.TaskCount)
        Write-Line ("  OsDownloadComplete: {0}" -f $state.OsDownloadComplete)
        Write-Line ("  OSDownloadSize: {0}" -f (Format-Bytes $state.OSDownloadSize))
        Write-Line ("  RecreatePackageFileList: {0}" -f $state.RecreatePackageFileList)
        Write-Line ("  PreDownloadCheckComplete: {0}" -f $state.PreDownloadCheckComplete)
        foreach ($item in @(Get-TopFiles -Folder $state.WorkingPath)) {
            Write-Line ("  File: {0:N0} MB  {1}  {2}" -f ($item.Length / 1MB), $item.LastWriteTime.ToString('HH:mm:ss'), $item.Name)
        }
    }

    if ($Sample.BtExists) {
        Write-Line 'SetupFolder: C:\$WINDOWS.~BT'
        foreach ($item in @($Sample.BtItems)) {
            Write-Line ("  {0}  {1}" -f $item.LastWriteTime.ToString('HH:mm:ss'), $item.Name)
        }
    } else {
        Write-Line 'SetupFolder: C:\$WINDOWS.~BT is not present'
    }
}

function Test-SetupRunning($Sample) {
    return @($Sample.Processes | Where-Object { $_.Name -match '^(SetupHost|SetupPrep|Windows10UpgraderApp)$' }).Count -gt 0
}

function Get-ProgressVerdict($Sample) {
    if (Test-SetupRunning $Sample) { return 'Setup is running.' }
    $states = @($Sample.States)
    if ($states.Count -eq 0) { return 'No feature download is in progress.' }
    $busy = @($states | Where-Object {
        $size = 0L
        [void][int64]::TryParse([string]$_.OSDownloadSize, [ref]$size)
        $tasks = 0
        [void][int]::TryParse([string]$_.TaskCount, [ref]$tasks)
        $recent = @((Get-TopFiles -Folder $_.WorkingPath) | Where-Object {
            $_.Name -notmatch '^(ActionList\.xml|windlp\.state(-old)?\.xml)$' -and
            $_.LastWriteTime -gt (Get-Date).AddMinutes(-15) -and
            $_.Length -gt 1MB
        })
        ($_.OsDownloadComplete -eq '1') -or ($size -gt 0) -or ($tasks -gt 0) -or ($recent.Count -gt 0)
    })
    if ($busy.Count -gt 0) {
        $done = @($busy | Where-Object { $_.OsDownloadComplete -eq '1' })
        if ($done.Count -eq $busy.Count) { return 'The OS download is complete. Setup has not started.' }
        return 'The OS download is in progress.'
    }
    return 'Planner only. The OS image is not downloading.'
}

if ($MyInvocation.InvocationName -eq '.') { return }

if ($WatchSeconds -lt 0) { $WatchSeconds = 0 }

Write-Section 'Windows Update progress'
$first = Get-ProgressSample
Write-ProgressSample $first
$verdict = Get-ProgressVerdict $first
$exitCode = 2
if ($verdict -eq 'Setup is running.' -or $verdict -eq 'The OS download is in progress.' -or $verdict -eq 'The OS download is complete. Setup has not started.') {
    $exitCode = 0
} elseif ($verdict -eq 'Planner only. The OS image is not downloading.') {
    $exitCode = 1
}

if ($WatchSeconds -gt 0) {
    Write-Line ("Waiting {0} seconds for a second sample..." -f $WatchSeconds)
    Start-Sleep -Seconds $WatchSeconds
    Write-Section 'Second sample'
    $second = Get-ProgressSample
    Write-ProgressSample $second
    $verdict = Get-ProgressVerdict $second
    if ($verdict -eq 'Setup is running.' -or $verdict -eq 'The OS download is in progress.' -or $verdict -eq 'The OS download is complete. Setup has not started.') {
        $exitCode = 0
    } elseif ($verdict -eq 'Planner only. The OS image is not downloading.') {
        $exitCode = 1
    } else {
        $exitCode = 2
    }

    $freeDelta = $null
    if ($null -ne $first.FreeBytes -and $null -ne $second.FreeBytes) {
        $freeDelta = [int64]$first.FreeBytes - [int64]$second.FreeBytes
        Write-Line ("FreeSpaceChange: {0} (positive means space was used)" -f (Format-Bytes $freeDelta))
    }
    $grew = $false
    foreach ($state in @($second.States)) {
        $before = @($first.States | Where-Object { $_.Path -eq $state.Path } | Select-Object -First 1)
        if (-not $before) { continue }
        $sizeNow = 0L
        $sizeThen = 0L
        [void][int64]::TryParse([string]$state.OSDownloadSize, [ref]$sizeNow)
        [void][int64]::TryParse([string]$before.OSDownloadSize, [ref]$sizeThen)
        if ($sizeNow -gt $sizeThen) { $grew = $true }
        $tasksNow = 0
        $tasksThen = 0
        [void][int]::TryParse([string]$state.TaskCount, [ref]$tasksNow)
        [void][int]::TryParse([string]$before.TaskCount, [ref]$tasksThen)
        if ($tasksNow -gt $tasksThen) { $grew = $true }
    }
    if ($grew) {
        Write-Line 'Change: OSDownloadSize or TaskCount increased.'
        $exitCode = 0
        $verdict = 'The OS download is in progress.'
    } elseif ($freeDelta -gt 50MB) {
        Write-Line 'Change: free space fell, and the OS download counters did not increase.'
    } else {
        Write-Line 'Change: the OS download counters did not increase.'
    }
}

Write-Line ("Verdict: {0}" -f $verdict)
if ($Exit -and -not $NoExit) { exit $exitCode }
