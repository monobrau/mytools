#Requires -Version 5.1
<#
.SYNOPSIS
    Scan or install Windows Update quality (non-feature) or feature updates.

.DESCRIPTION
    Uses the Windows Update Agent COM API (no PSWindowsUpdate module).
    Quality: cumulative / security / SSU / .NET  -  excludes Feature Update titles.
    Feature: Feature Update and Enablement Package only.

    Always runs a pre-check (disk space, recovery partition, WU services,
    policy, pending reboot). Default install does not reboot. -Reboot
    restarts when the installer reports RebootRequired.

.PARAMETER CheckOnly
    Search and report only. No download or install.

.PARAMETER Quality
    Target non-feature Windows Updates (default if neither switch is set).

.PARAMETER Feature
    Target feature updates / enablement packages only.

.PARAMETER Reboot
    Restart automatically when the install reports a reboot is required.

.PARAMETER Force
    Include Preview updates. Continue Apply after non-critical pre-check
    Fail. Still stops on critical disk (under 5 GB quality / 10 GB feature).

.PARAMETER Exit
    Call exit with a status code (ScreenConnect Commands). Omit in Backstage.
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Quality,
    [switch]$Feature,
    [switch]$Reboot,
    [switch]$Force,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$script:ExitCode = 0
$script:PreCheckFails = 0
$script:PreCheckWarns = 0

if ($Quality -and $Feature) {
    Write-Error 'Specify only one of -Quality or -Feature.'
    if ($Exit) { exit 2 }
    return
}
if (-not $Quality -and -not $Feature) { $Quality = $true }
$script:Channel = $(if ($Feature) { 'Feature' } else { 'Quality' })

function Write-Line([string]$Message) {
    Write-Host $Message
    try { [Console]::Out.Flush() } catch { }
}

function Write-Section([string]$Message) {
    Write-Line "=== $Message ==="
}

function Write-Check {
    param(
        [ValidateSet('Pass', 'Warn', 'Fail')]
        [string]$Level,
        [string]$Name,
        [string]$Detail
    )
    Write-Line ("PreCheck {0}: {1}  -  {2}" -f $Level, $Name, $Detail)
    if ($Level -eq 'Fail') { $script:PreCheckFails++ }
    if ($Level -eq 'Warn') { $script:PreCheckWarns++ }
}

function Get-KbList($Update) {
    try {
        $ids = @($Update.KBArticleIDs)
        if ($ids.Count -gt 0) { return ($ids | ForEach-Object { "KB$_" }) -join ',' }
    } catch { }
    return '-'
}

function Test-IsFeatureUpdate($Update) {
    $title = [string]$Update.Title
    if ($title -match '(?i)feature update|enablement package') { return $true }
    try {
        foreach ($c in @($Update.Categories)) {
            if ([string]$c.Name -match '(?i)^Upgrades$|Feature Packs') { return $true }
        }
    } catch { }
    return $false
}

function Get-SystemDriveInfo {
    $letter = $env:SystemDrive
    if ([string]::IsNullOrWhiteSpace($letter)) { $letter = 'C:' }
    $vol = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $letter) -ErrorAction SilentlyContinue
    if (-not $vol) { return $null }
    [pscustomobject]@{
        DeviceID = $vol.DeviceID
        FreeGB   = [math]::Round($vol.FreeSpace / 1GB, 1)
        SizeGB   = [math]::Round($vol.Size / 1GB, 1)
    }
}

function Get-RecoveryPartitions {
    $out = @()
    $parts = @()
    try { $parts = @(Get-Partition -ErrorAction Stop) } catch { $parts = @() }
    if ($parts.Count -eq 0) {
        try {
            $parts = @(Get-CimInstance -Namespace root\Microsoft\Windows\Storage -ClassName MSFT_Partition -ErrorAction Stop)
        } catch { $parts = @() }
    }
    foreach ($p in $parts) {
        $gpt = ''
        try { $gpt = [string]$p.GptType } catch { }
        $type = ''
        try { $type = [string]$p.Type } catch { }
        $isRec = ($gpt -eq '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}') -or ($type -eq 'Recovery')
        if (-not $isRec) { continue }
        $mb = 0
        try { $mb = [math]::Round([double]$p.Size / 1MB, 0) } catch { }
        $disk = $null
        try { $disk = $p.DiskNumber } catch { }
        $num = $null
        try { $num = $p.PartitionNumber } catch { }
        $out += [pscustomobject]@{ Disk = $disk; Partition = $num; SizeMB = $mb }
    }
    return $out
}

function Get-WinReStatus {
    $text = ''
    try {
        $text = (& reagentc.exe /info 2>&1 | Out-String)
    } catch {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $enabled = $null
    if ($text -match '(?i)Windows RE status:\s+(Enabled|Disabled)') {
        $enabled = $Matches[1]
    }
    $loc = ''
    if ($text -match '(?i)Windows RE location:\s+(\S+)') {
        $loc = $Matches[1]
    }
    [pscustomobject]@{ Enabled = $enabled; Location = $loc; Raw = $text.Trim() }
}

function Test-PendingReboot {
    $reasons = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $reasons += 'CBS RebootPending'
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $reasons += 'WU RebootRequired'
    }
    try {
        $pf = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction Stop).PendingFileRenameOperations
        if ($pf) { $reasons += 'PendingFileRenameOperations' }
    } catch { }
    return $reasons
}

function Invoke-UpdatePreCheck {
    Write-Section ("Pre-check ({0})" -f $script:Channel)

    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        Write-Line ("OS: {0} ({1}.{2})" -f $os.Caption.Trim(), $os.Version, $os.BuildNumber)
    }
    Write-Line ("ComputerName: {0}" -f $env:COMPUTERNAME)
    Write-Line ("Channel: {0}" -f $script:Channel)
    Write-Line ("RebootIfRequired: {0}" -f $(if ($Reboot) { 'Yes' } else { 'No' }))

    $disk = Get-SystemDriveInfo
    if (-not $disk) {
        Write-Check Fail 'SystemDrive' 'Could not read system volume free space.'
    } else {
        Write-Line ("SystemDrive: {0} {1} GB free / {2} GB" -f $disk.DeviceID, $disk.FreeGB, $disk.SizeGB)
        if ($Feature) {
            if ($disk.FreeGB -lt 10) { Write-Check Fail 'DiskSpace' ("{0} GB free; feature update needs at least 20 GB (critical below 10 GB)." -f $disk.FreeGB) }
            elseif ($disk.FreeGB -lt 20) { Write-Check Fail 'DiskSpace' ("{0} GB free; feature update typically needs 20+ GB." -f $disk.FreeGB) }
            elseif ($disk.FreeGB -lt 30) { Write-Check Warn 'DiskSpace' ("{0} GB free; 30+ GB recommended for feature update." -f $disk.FreeGB) }
            else { Write-Check Pass 'DiskSpace' ("{0} GB free." -f $disk.FreeGB) }
        } else {
            if ($disk.FreeGB -lt 5) { Write-Check Fail 'DiskSpace' ("{0} GB free; quality updates need at least 8 GB (critical below 5 GB)." -f $disk.FreeGB) }
            elseif ($disk.FreeGB -lt 8) { Write-Check Fail 'DiskSpace' ("{0} GB free; quality updates typically need 8+ GB." -f $disk.FreeGB) }
            elseif ($disk.FreeGB -lt 15) { Write-Check Warn 'DiskSpace' ("{0} GB free; 15+ GB recommended." -f $disk.FreeGB) }
            else { Write-Check Pass 'DiskSpace' ("{0} GB free." -f $disk.FreeGB) }
        }
    }

    $recs = @(Get-RecoveryPartitions)
    if ($recs.Count -eq 0) {
        Write-Check Warn 'RecoveryPartition' 'No GPT Recovery / WinRE partition found. Feature updates and some CUs can fail if WinRE cannot be updated.'
    } else {
        foreach ($r in $recs) {
            $label = 'disk{0}p{1} {2} MB' -f $r.Disk, $r.Partition, $r.SizeMB
            if ($r.SizeMB -gt 0 -and $r.SizeMB -lt 250) {
                Write-Check Fail 'RecoveryPartition' ("{0}  -  too small (need 250+ MB; 500+ MB safer). Common CU/WinRE failure." -f $label)
            } elseif ($Feature -and $r.SizeMB -lt 750) {
                Write-Check Warn 'RecoveryPartition' ("{0}  -  under 750 MB; feature updates often fail until WinRE is resized." -f $label)
            } elseif ($r.SizeMB -lt 500) {
                Write-Check Warn 'RecoveryPartition' ("{0}  -  under 500 MB; some cumulative updates fail (resize WinRE)." -f $label)
            } else {
                Write-Check Pass 'RecoveryPartition' $label
            }
        }
    }

    $winre = Get-WinReStatus
    if (-not $winre) {
        Write-Check Warn 'WinRE' 'Could not read reagentc /info (need elevation, or WinRE tools missing).'
    } elseif ($winre.Enabled -eq 'Disabled') {
        if ($Feature) {
            Write-Check Fail 'WinRE' 'Windows RE is Disabled  -  feature updates often fail until WinRE is enabled/resized.'
        } else {
            Write-Check Warn 'WinRE' 'Windows RE is Disabled  -  some cumulative updates fail when WinRE cannot be patched.'
        }
    } elseif ($winre.Enabled -eq 'Enabled') {
        $loc = $winre.Location
        if ([string]::IsNullOrWhiteSpace($loc)) { $loc = 'location not reported' }
        Write-Check Pass 'WinRE' ("Enabled ({0})" -f $loc)
    } else {
        Write-Check Warn 'WinRE' 'reagentc did not report Enabled/Disabled.'
    }

    foreach ($svcName in @('wuauserv', 'bits', 'TrustedInstaller', 'cryptsvc')) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-Check Fail $svcName 'Service not installed.'
            continue
        }
        if ($svc.StartType -eq 'Disabled') {
            Write-Check Fail $svcName 'StartType is Disabled  -  Windows Update cannot run.'
        } else {
            Write-Check Pass $svcName ("{0} ({1})" -f $svc.Status, $svc.StartType)
        }
    }
    $medic = Get-Service -Name 'WaaSMedicSvc' -ErrorAction SilentlyContinue
    if ($medic) {
        if ($medic.StartType -eq 'Disabled') {
            Write-Check Warn 'WaaSMedicSvc' 'Disabled  -  Windows Update Medic cannot repair the agent.'
        } else {
            Write-Check Pass 'WaaSMedicSvc' ("{0} ({1})" -f $medic.Status, $medic.StartType)
        }
    }

    $polWu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $polAu = Join-Path $polWu 'AU'
    $disableAccess = $null
    try { $disableAccess = (Get-ItemProperty -LiteralPath $polWu -ErrorAction Stop).DisableWindowsUpdateAccess } catch { }
    if ($disableAccess -eq 1) {
        Write-Check Fail 'WUPolicy' 'DisableWindowsUpdateAccess=1  -  policy blocks Windows Update.'
    } else {
        Write-Check Pass 'WUPolicy' 'DisableWindowsUpdateAccess is not set to 1.'
    }
    $useWsus = $null
    $wsus = $null
    try { $useWsus = (Get-ItemProperty -LiteralPath $polAu -ErrorAction Stop).UseWUServer } catch { }
    try { $wsus = (Get-ItemProperty -LiteralPath $polWu -ErrorAction Stop).WUServer } catch { }
    if ($useWsus -eq 1) {
        if ([string]::IsNullOrWhiteSpace([string]$wsus)) {
            Write-Check Fail 'WSUS' 'UseWUServer=1 but WUServer is empty.'
        } else {
            Write-Check Warn 'WSUS' ("UseWUServer=1; WUServer={0}  -  scan/install uses WSUS, not Microsoft Update." -f $wsus)
        }
    } else {
        Write-Check Pass 'WSUS' 'Not forced to WSUS (or AU policy missing).'
    }

    $pending = @(Test-PendingReboot)
    if ($pending.Count -gt 0) {
        Write-Check Warn 'PendingReboot' (($pending -join ', ') + '  -  finish the reboot before a reliable install.')
    } else {
        Write-Check Pass 'PendingReboot' 'No CBS/WU pending-reboot keys.'
    }

    if ($Feature -and $os) {
        $ramGB = 0
        try { $ramGB = [math]::Round([double]$os.TotalVisibleMemorySize / 1MB, 1) } catch { }
        if ($ramGB -gt 0 -and $ramGB -lt 4) {
            Write-Check Fail 'RAM' ("{0} GB RAM  -  feature updates to current Windows need 4+ GB." -f $ramGB)
        } elseif ($ramGB -gt 0) {
            Write-Check Pass 'RAM' ("{0} GB." -f $ramGB)
        }
    }

    Write-Line ("PreCheckSummary: Fail={0} Warn={1}" -f $script:PreCheckFails, $script:PreCheckWarns)
}

function Search-WindowsUpdates {
    Write-Section 'Windows Update search'
    foreach ($n in @('wuauserv', 'bits')) {
        $s = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($s -and $s.Status -ne 'Running' -and $s.StartType -ne 'Disabled') {
            try { Start-Service -Name $n -ErrorAction Stop } catch { Write-Line ("Start-Service {0}: {1}" -f $n, $_.Exception.Message) }
        }
    }

    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = 'mytools-WindowsUpdate'
    $searcher = $session.CreateUpdateSearcher()
    Write-Line 'Searching (IsInstalled=0 IsHidden=0 Type=Software)...'
    $result = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
    $all = @()
    for ($i = 0; $i -lt $result.Updates.Count; $i++) {
        $all += $result.Updates.Item($i)
    }

    $picked = @()
    foreach ($u in $all) {
        $isFeat = Test-IsFeatureUpdate $u
        if ($Feature -and -not $isFeat) { continue }
        if ($Quality -and $isFeat) { continue }
        $title = [string]$u.Title
        if (-not $Force -and $title -match '(?i)\bPreview\b') {
            Write-Line ("Skip (Preview; use -Force): {0}" -f $title)
            continue
        }
        $picked += $u
    }

    Write-Line ("UpdatesFound: {0}" -f $picked.Count)
    foreach ($u in $picked) {
        $mb = 0
        try { $mb = [math]::Round($u.MaxDownloadSize / 1MB, 0) } catch { }
        $dl = $false
        try { $dl = [bool]$u.IsDownloaded } catch { }
        Write-Line ("Update: {0} | {1} | {2} MB | Downloaded={3}" -f $u.Title, (Get-KbList $u), $mb, $dl)
    }
    if ($picked.Count -eq 0) {
        Write-Line ("Result: No {0} updates waiting." -f $script:Channel.ToLower())
    }
    return @{ Session = $session; Updates = $picked }
}

function Install-WindowsUpdates {
    param($Session, $Updates)
    if (-not $Updates -or $Updates.Count -eq 0) {
        Write-Line 'Nothing to install.'
        return
    }

    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $Updates) {
        $title = [string]$u.Title
        try {
            if ($u.InstallationBehavior.CanRequestUserInput -and -not $Force) {
                Write-Line ("Skip (may prompt; use -Force): {0}" -f $title)
                continue
            }
        } catch { }
        try {
            if (-not $u.EulaAccepted) {
                $u.AcceptEula()
                Write-Line ("EULA accepted: {0}" -f $title)
            }
        } catch {
            Write-Line ("EULA accept failed: {0}  -  {1}" -f $title, $_.Exception.Message)
        }
        [void]$coll.Add($u)
    }
    if ($coll.Count -eq 0) {
        Write-Line 'Result: No updates left to install after skips.'
        $script:ExitCode = 1
        return
    }

    Write-Section 'Download'
    $downloader = $Session.CreateUpdateDownloader()
    $downloader.Updates = $coll
    $dlResult = $downloader.Download()
    Write-Line ("Download ResultCode: {0} (2=Succeeded)" -f $dlResult.ResultCode)
    if ($dlResult.ResultCode -notin 2, 3) {
        Write-Line 'Result: Download failed.'
        $script:ExitCode = 2
        return
    }

    Write-Section 'Install'
    $installer = $Session.CreateUpdateInstaller()
    $installer.Updates = $coll
    $inst = $installer.Install()
    Write-Line ("Install ResultCode: {0} (2=Succeeded 3=SucceededWithErrors)" -f $inst.ResultCode)
    Write-Line ("RebootRequired: {0}" -f $inst.RebootRequired)
    if ($inst.ResultCode -eq 4 -or $inst.ResultCode -eq 5) {
        Write-Line 'Result: Install failed or aborted.'
        $script:ExitCode = 2
        return
    }
    if ($inst.RebootRequired) {
        Write-Line 'PENDING_REBOOT'
        if ($Reboot) {
            Write-Line 'Reboot: restarting now (ScreenConnect session will drop).'
            $script:ExitCode = 3
            Restart-Computer -Force
            return
        }
        Write-Line 'Result: Installed. Reboot required (not rebooting).'
        $script:ExitCode = 1
        return
    }
    if ($inst.ResultCode -eq 3) {
        Write-Line 'Result: Installed with errors. No reboot reported.'
        $script:ExitCode = 2
        return
    }
    Write-Line 'Result: Installed. No reboot required.'
    $script:ExitCode = 0
}

Write-Section ("Windows Update {0}" -f $script:Channel)
Invoke-UpdatePreCheck

$blockApply = $false
if ($script:PreCheckFails -gt 0) {
    $disk = Get-SystemDriveInfo
    $criticalDisk = $false
    if ($disk) {
        if ($Feature -and $disk.FreeGB -lt 10) { $criticalDisk = $true }
        if ($Quality -and $disk.FreeGB -lt 5) { $criticalDisk = $true }
    }
    if ($criticalDisk) {
        Write-Line 'Result: Pre-check FAIL  -  not enough disk space. Search will still run; install is blocked.'
        $blockApply = $true
        $script:ExitCode = 4
    } elseif (-not $Force) {
        Write-Line 'Result: Pre-check FAIL  -  fix showstoppers (or re-run with -Force to try anyway, except critical disk).'
        $blockApply = $true
        $script:ExitCode = 4
    } else {
        Write-Line 'Warning: -Force continuing after pre-check FAIL (not critical disk).'
    }
}

try {
    $found = Search-WindowsUpdates
} catch {
    Write-Line ("ERROR: Windows Update search failed: {0}" -f $_.Exception.Message)
    Write-Line 'Exception: WU service/policy/WSUS may be blocking the agent. See pre-check.'
    $script:ExitCode = 2
    if ($Exit) { exit $script:ExitCode }
    return
}

if ($CheckOnly) {
    Write-Line 'Action: CheckOnly'
    if ($script:PreCheckFails -gt 0) {
        Write-Line 'Result: Pre-check FAIL  -  do not install until showstoppers are fixed.'
        $script:ExitCode = 4
    } elseif ($found.Updates.Count -gt 0) {
        Write-Line ("Result: {0} {1} update(s) available." -f $found.Updates.Count, $script:Channel.ToLower())
        $script:ExitCode = 1
    } else {
        Write-Line 'Result: Nothing to install.'
        $script:ExitCode = 0
    }
    if ($Exit) { exit $script:ExitCode }
    return
}

if ($blockApply) {
    Write-Line 'Action: Install skipped (pre-check FAIL).'
    if ($found.Updates.Count -gt 0) {
        Write-Line ("Pending (not installed): {0} {1} update(s)." -f $found.Updates.Count, $script:Channel.ToLower())
    }
    $script:ExitCode = 4
    if ($Exit) { exit $script:ExitCode }
    return
}

Write-Line 'Action: Install'
Install-WindowsUpdates -Session $found.Session -Updates $found.Updates
if ($Exit) { exit $script:ExitCode }
