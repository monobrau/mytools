#Requires -Version 5.1
<#
.SYNOPSIS
    Silently checks / updates Microsoft 365 Apps (Click-to-Run) without disrupting the user.

.DESCRIPTION
    Vuln-scan remediation for Microsoft 365 Apps. Uses OfficeC2RClient.exe (Click-to-Run),
    not winget.

    Default:
      - Compare installed VersionToReport to the channel's latest from Microsoft
      - If already current: print a clear "no updates needed" verdict and exit (no app impact)
      - If behind: start a silent background update that does NOT close Office apps

    -CheckOnly: report verdict only (never starts an update).

.PARAMETER CheckOnly
    Verify only. Clear up-to-date / updates-needed message. Does not start C2R update.

.PARAMETER ForceAppShutdown
    Opt-in: close running Office apps so an update can finish immediately.
    Default is off (non-disruptive; update may apply after apps are closed later).

.PARAMETER Force
    Start a silent update even when the host already looks current.

.PARAMETER ShowUi
    Show the Office update UI (displaylevel=true). Default is silent.

.PARAMETER UpdateToVersion
    Optional specific Click-to-Run build (e.g. 16.0.xxxxx.xxxxx).

.PARAMETER WaitSeconds
    Seconds to poll after starting an update (default 90).

.PARAMETER NoExit
    Keep the PowerShell host open (Backstage).

.PARAMETER Exit
    Always call exit with the result code (Commands / automation).
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$ForceAppShutdown,
    [switch]$Force,
    [switch]$ShowUi,
    [string]$UpdateToVersion,
    [int]$WaitSeconds = 90,
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptVersion = '1.1.0'
$OfficeReleasesUri = 'https://clients.config.office.net/releases/v1.0/OfficeReleases'

try {
    [Net.ServicePointManager]::SecurityProtocol = (
        [Net.ServicePointManager]::SecurityProtocol -bor
        [Net.SecurityProtocolType]::Tls12
    )
}
catch {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
}

function Write-M365Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts][$Level] $Message"
}

function Write-M365Verdict {
    param(
        [Parameter(Mandatory)][string]$Status,
        [string]$Detail
    )
    Write-Host ''
    Write-Host ('======== M365 APPS UPDATE STATUS: {0} ========' -f $Status)
    if ($Detail) { Write-Host $Detail }
    Write-Host '================================================'
    Write-Host ''
}

function Test-M365ShouldExitProcess {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-M365 {
    param([Parameter(Mandatory)][int]$Code)
    $global:LASTEXITCODE = $Code
    try { $global:M365AppsUpdateResultCode = $Code } catch { }
    if (Test-M365ShouldExitProcess) { exit $Code }
    Write-M365Log ("Done. ResultCode={0} (PowerShell host kept open)." -f $Code)
}

function Test-IsWindowsHost {
    if ($null -ne (Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue)) {
        return [bool]$IsWindows
    }
    return ($env:OS -like 'Windows*')
}

function Get-OfficeC2RClientPath {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe')
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Get-CdnGuid {
    param([string]$Url)
    if ($Url -match '/pr/([0-9a-fA-F-]{36})') {
        return $Matches[1].ToLowerInvariant()
    }
    return $null
}

function ConvertTo-M365Version {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try { return [version]$Text } catch { return $null }
}

function Get-M365ClickToRunInfo {
    $cfgPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $cfg = Get-ItemProperty -Path $cfgPath -ErrorAction SilentlyContinue
    if (-not $cfg) {
        $cfgPath = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration'
        $cfg = Get-ItemProperty -Path $cfgPath -ErrorAction SilentlyContinue
    }

    # Fallback names when API is unreachable (GUIDs match Microsoft channel CDNs)
    $channelByGuid = @{
        '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' = 'Current'
        '64256afe-f5d9-4f86-8936-8840a6a4f5be' = 'CurrentPreview'
        '55336b82-a18d-4dd6-b5f6-9e5095b9167b' = 'MonthlyEnterprise'
        '55336b82-a18d-4dd6-b5f6-9e5095c314a6' = 'MonthlyEnterprise'
        '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' = 'SemiAnnual'
        'b8f9b850-328d-4355-9145-c59439a0c4cf' = 'SemiAnnualPreview'
        '5440fd1f-7ecb-4221-8110-145efaa6372f' = 'BetaChannel'
    }

    $cdn = $null
    $version = $null
    $clientVersion = $null
    $products = $null
    $updatesEnabled = $null
    $channelName = $null
    $updateChannel = $null
    $platform = $null
    $cdnGuid = $null

    if ($cfg) {
        try { $cdn = [string]$cfg.CDNBaseUrl } catch { }
        try { $version = [string]$cfg.VersionToReport } catch { }
        try { $clientVersion = [string]$cfg.ClientVersionToReport } catch { }
        try { $products = [string]$cfg.ProductReleaseIds } catch { }
        try { $updatesEnabled = [string]$cfg.UpdatesEnabled } catch { }
        try { $updateChannel = [string]$cfg.UpdateChannel } catch { }
        try { $platform = [string]$cfg.Platform } catch { }

        $cdnGuid = Get-CdnGuid -Url $cdn
        if ($cdnGuid -and $channelByGuid.ContainsKey($cdnGuid)) {
            $channelName = $channelByGuid[$cdnGuid]
        }
        elseif ($updateChannel) {
            $channelName = $updateChannel
        }
    }

    if ([string]::IsNullOrWhiteSpace($products)) {
        try {
            $prodKey = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\ProductReleaseIDs'
            if (Test-Path $prodKey) {
                $products = (Get-ChildItem $prodKey -ErrorAction SilentlyContinue | ForEach-Object { $_.PSChildName }) -join ','
            }
        }
        catch { }
    }

    return [pscustomobject]@{
        ConfigPath        = $cfgPath
        VersionToReport   = $version
        ClientVersion     = $clientVersion
        ChannelName       = $channelName
        CDNBaseUrl        = $cdn
        CDNGuid           = $cdnGuid
        UpdateChannel     = $updateChannel
        ProductReleaseIds = $products
        UpdatesEnabled    = $updatesEnabled
        Platform          = $platform
        C2RClientPath     = (Get-OfficeC2RClientPath)
        Present           = [bool]$cfg -or [bool](Get-OfficeC2RClientPath)
    }
}

function Get-M365ChannelReleaseInfo {
    param(
        [string]$CDNGuid,
        [string]$ChannelName
    )

    $result = [pscustomobject]@{
        Ok            = $false
        ChannelId     = $null
        ChannelLabel  = $null
        LatestVersion = $null
        Error         = $null
    }

    try {
        $json = Invoke-RestMethod -Uri $OfficeReleasesUri -Method Get -TimeoutSec 45
    }
    catch {
        $result.Error = $_.Exception.Message
        return $result
    }

    $match = $null
    if ($CDNGuid) {
        foreach ($ch in @($json)) {
            $urls = @()
            if ($ch.cdnBaseUrl) { $urls += [string]$ch.cdnBaseUrl }
            foreach ($ov in @($ch.officeVersions)) {
                if ($ov.cdnBaseUrl) { $urls += [string]$ov.cdnBaseUrl }
            }
            foreach ($u in $urls) {
                if ((Get-CdnGuid -Url $u) -eq $CDNGuid) {
                    $match = $ch
                    break
                }
            }
            if ($match) { break }
        }
    }

    if (-not $match -and $ChannelName) {
        $want = $ChannelName.Trim()
        $match = @($json) | Where-Object {
            $_.channelId -eq $want -or
            $_.channel -eq $want -or
            ($_.alternateNames -and ($_.alternateNames -contains $want))
        } | Select-Object -First 1

        # Friendly aliases used in registry / docs
        if (-not $match) {
            $aliasMap = @{
                'Current'              = 'Current'
                'Monthly'              = 'Current'
                'CurrentPreview'       = 'CurrentPreview'
                'MonthlyPreview'       = 'CurrentPreview'
                'MonthlyEnterprise'    = 'MonthlyEnterprise'
                'MEC'                  = 'MonthlyEnterprise'
                'SemiAnnual'           = 'SemiAnnual'
                'Deferred'             = 'SemiAnnual'
                'SemiAnnualPreview'    = 'SemiAnnualPreview'
                'SemiAnnualEnterprise' = 'SemiAnnual'
            }
            if ($aliasMap.ContainsKey($want)) {
                $id = $aliasMap[$want]
                $match = @($json) | Where-Object { $_.channelId -eq $id } | Select-Object -First 1
            }
        }
    }

    if (-not $match) {
        $result.Error = 'Could not match this host channel in Microsoft OfficeReleases.'
        return $result
    }

    $result.Ok = $true
    $result.ChannelId = [string]$match.channelId
    $result.ChannelLabel = [string]$match.channel
    $result.LatestVersion = [string]$match.latestVersion
    return $result
}

function Get-M365UpdateAssessment {
    param($LocalInfo)

    $release = Get-M365ChannelReleaseInfo -CDNGuid $LocalInfo.CDNGuid -ChannelName $LocalInfo.ChannelName
    $localVer = ConvertTo-M365Version $LocalInfo.VersionToReport
    $latestVer = $null
    if ($release.Ok) { $latestVer = ConvertTo-M365Version $release.LatestVersion }

    $status = 'UNKNOWN'
    $summary = $null

    if (-not $localVer) {
        $status = 'UNKNOWN'
        $summary = 'Installed VersionToReport is missing or unreadable.'
    }
    elseif (-not $release.Ok) {
        $status = 'UNKNOWN'
        $summary = ("Could not verify against Microsoft channel releases: {0}" -f $release.Error)
    }
    elseif (-not $latestVer) {
        $status = 'UNKNOWN'
        $summary = 'Microsoft latestVersion was missing for this channel.'
    }
    elseif ($localVer -ge $latestVer) {
        $status = 'UP_TO_DATE'
        $summary = ("No updates needed. Local {0} >= channel latest {1} ({2})." -f `
                $LocalInfo.VersionToReport, $release.LatestVersion, $release.ChannelId)
    }
    else {
        $status = 'UPDATE_AVAILABLE'
        $summary = ("Updates needed. Local {0} < channel latest {1} ({2})." -f `
                $LocalInfo.VersionToReport, $release.LatestVersion, $release.ChannelId)
    }

    return [pscustomobject]@{
        Status          = $status
        Summary         = $summary
        LocalVersion    = $LocalInfo.VersionToReport
        ChannelLatest   = $release.LatestVersion
        ChannelId       = $release.ChannelId
        ChannelLabel    = $release.ChannelLabel
        ReleaseOk       = [bool]$release.Ok
        ReleaseError    = $release.Error
    }
}

function Write-M365Info {
    param($Info)
    if (-not $Info.Present) {
        Write-M365Log 'Microsoft 365 Apps / Office Click-to-Run not detected.' 'WARN'
        return
    }
    Write-M365Log ("VersionToReport:  {0}" -f $(if ($Info.VersionToReport) { $Info.VersionToReport } else { '(unknown)' }))
    Write-M365Log ("ClientVersion:    {0}" -f $(if ($Info.ClientVersion) { $Info.ClientVersion } else { '(unknown)' }))
    Write-M365Log ("Channel:          {0}" -f $(if ($Info.ChannelName) { $Info.ChannelName } else { '(unknown)' }))
    Write-M365Log ("CDN GUID:         {0}" -f $(if ($Info.CDNGuid) { $Info.CDNGuid } else { '(unknown)' }))
    Write-M365Log ("UpdatesEnabled:   {0}" -f $(if ($Info.UpdatesEnabled) { $Info.UpdatesEnabled } else { '(unknown)' }))
    Write-M365Log ("Products:         {0}" -f $(if ($Info.ProductReleaseIds) { $Info.ProductReleaseIds } else { '(unknown)' }))
    Write-M365Log ("Platform:         {0}" -f $(if ($Info.Platform) { $Info.Platform } else { '(unknown)' }))
    Write-M365Log ("OfficeC2RClient:  {0}" -f $(if ($Info.C2RClientPath) { $Info.C2RClientPath } else { '(missing)' }))
}

function Write-M365Assessment {
    param($Assessment)
    Write-M365Log ("Channel latest:   {0}" -f $(if ($Assessment.ChannelLatest) { $Assessment.ChannelLatest } else { '(unknown)' }))
    if ($Assessment.ChannelId) {
        Write-M365Log ("Matched channel:  {0} ({1})" -f $Assessment.ChannelId, $Assessment.ChannelLabel)
    }

    switch ($Assessment.Status) {
        'UP_TO_DATE' {
            Write-M365Verdict -Status 'UP TO DATE — NO UPDATES NEEDED' -Detail $Assessment.Summary
        }
        'UPDATE_AVAILABLE' {
            Write-M365Verdict -Status 'UPDATE AVAILABLE — UPDATES NEEDED' -Detail $Assessment.Summary
        }
        default {
            Write-M365Verdict -Status 'UNKNOWN — COULD NOT VERIFY' -Detail $Assessment.Summary
        }
    }
}

function Start-M365ClickToRunUpdate {
    param(
        [Parameter(Mandatory)][string]$ClientPath,
        [bool]$ForceShutdown,
        [bool]$Ui,
        [string]$ToVersion
    )

    $args = New-Object System.Collections.Generic.List[string]
    [void]$args.Add('/update')
    [void]$args.Add('user')
    [void]$args.Add(('displaylevel={0}' -f ($(if ($Ui) { 'true' } else { 'false' }))))
    [void]$args.Add('updatepromptuser=false')
    [void]$args.Add(('forceappshutdown={0}' -f ($(if ($ForceShutdown) { 'true' } else { 'false' }))))
    if (-not [string]::IsNullOrWhiteSpace($ToVersion)) {
        [void]$args.Add(('updatetoversion={0}' -f $ToVersion))
    }

    $argLine = ($args -join ' ')
    Write-M365Log ("Starting silent Click-to-Run update: `"{0}`" {1}" -f $ClientPath, $argLine)
    if (-not $ForceShutdown) {
        Write-M365Log 'Non-disruptive mode: Office apps will NOT be closed. Update may finish after apps exit.'
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ClientPath
    $psi.Arguments = $argLine
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = (-not $Ui)
    $psi.WindowStyle = if ($Ui) {
        [System.Diagnostics.ProcessWindowStyle]::Normal
    }
    else {
        [System.Diagnostics.ProcessWindowStyle]::Hidden
    }

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    Write-M365Log ("OfficeC2RClient started PID={0}" -f $proc.Id)
    return $proc
}

# --- main ---
$hostEdition = if ($PSVersionTable.PSEdition) { [string]$PSVersionTable.PSEdition } else { 'Desktop' }
Write-M365Log ("M365AppsUpdate {0}" -f $ScriptVersion)
Write-M365Log ("Host: PowerShell {0} ({1})" -f $PSVersionTable.PSVersion, $hostEdition)
Write-M365Log ("User: {0} | CheckOnly={1} ForceAppShutdown={2} Force={3} ShowUi={4}" -f `
        [Security.Principal.WindowsIdentity]::GetCurrent().Name, $CheckOnly, $ForceAppShutdown, $Force, $ShowUi)
Write-M365Log 'Mode: silent / non-disruptive by default (will not close Word/Excel/Outlook/etc.).'

if (-not (Test-IsWindowsHost)) {
    Write-M365Log 'Windows only.' 'ERROR'
    Complete-M365 -Code 1
    return
}

$before = Get-M365ClickToRunInfo
Write-M365Info -Info $before

if (-not $before.Present -or -not $before.C2RClientPath) {
    Write-M365Log 'Cannot continue: Click-to-Run client not found (is M365 Apps / Office C2R installed?).' 'ERROR'
    Write-M365Verdict -Status 'ERROR — M365 APPS / C2R NOT FOUND' -Detail 'Install or repair Microsoft 365 Apps first.'
    Complete-M365 -Code 1
    return
}

if ($before.UpdatesEnabled -and $before.UpdatesEnabled -match '^(False|0)$') {
    Write-M365Log 'UpdatesEnabled is False in ClickToRun configuration - updates may be blocked by policy.' 'WARN'
}

$assessment = Get-M365UpdateAssessment -LocalInfo $before
Write-M365Assessment -Assessment $assessment

if ($CheckOnly) {
    switch ($assessment.Status) {
        'UP_TO_DATE' { Complete-M365 -Code 0; return }
        'UPDATE_AVAILABLE' { Complete-M365 -Code 2; return }
        default { Complete-M365 -Code 1; return }
    }
}

# Default / update path: skip C2R when already current (unless -Force)
if ($assessment.Status -eq 'UP_TO_DATE' -and -not $Force -and [string]::IsNullOrWhiteSpace($UpdateToVersion)) {
    Write-M365Log 'Skipping update start — host is already on/above channel latest. Nothing for the user to notice.'
    Complete-M365 -Code 0
    return
}

if ($assessment.Status -eq 'UNKNOWN' -and -not $Force) {
    Write-M365Log 'Verification inconclusive. Starting silent non-disruptive update attempt anyway (use -CheckOnly to assess only).' 'WARN'
}

try {
    $proc = Start-M365ClickToRunUpdate -ClientPath $before.C2RClientPath `
        -ForceShutdown ([bool]$ForceAppShutdown) -Ui ([bool]$ShowUi) -ToVersion $UpdateToVersion
}
catch {
    Write-M365Log ("Failed to start OfficeC2RClient: {0}" -f $_.Exception.Message) 'ERROR'
    Complete-M365 -Code 1
    return
}

Write-M365Log ("Waiting up to {0}s for version change (apps stay open unless -ForceAppShutdown)..." -f $WaitSeconds)
$deadline = (Get-Date).AddSeconds([Math]::Max(15, $WaitSeconds))
$sawClickToRun = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $ctr = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessName -match '^(OfficeClickToRun|OfficeC2RClient)$'
        })
    if ($ctr.Count -gt 0) {
        $sawClickToRun = $true
        Write-M365Log ("Click-to-Run activity: {0}" -f (($ctr | ForEach-Object { $_.ProcessName + ':' + $_.Id }) -join ', '))
    }
    $now = Get-M365ClickToRunInfo
    if ($now.VersionToReport -and $before.VersionToReport -and ($now.VersionToReport -ne $before.VersionToReport)) {
        Write-M365Log ("Version changed during wait: {0} -> {1}" -f $before.VersionToReport, $now.VersionToReport)
        break
    }
}

if (-not $proc.HasExited) {
    Write-M365Log 'OfficeC2RClient still running; leaving it to finish in background (non-disruptive).'
}
else {
    Write-M365Log ("OfficeC2RClient exit code: {0}" -f $proc.ExitCode)
}

$after = Get-M365ClickToRunInfo
Write-M365Log '--- After update attempt ---'
Write-M365Info -Info $after
$afterAssessment = Get-M365UpdateAssessment -LocalInfo $after
Write-M365Assessment -Assessment $afterAssessment

if ($afterAssessment.Status -eq 'UP_TO_DATE') {
    Write-M365Log 'SUCCESS: host reports no updates needed after the update attempt.'
    Complete-M365 -Code 0
    return
}

if ($after.VersionToReport -and $before.VersionToReport -and ($after.VersionToReport -ne $before.VersionToReport)) {
    Write-M365Log ("Version moved {0} -> {1}, but still below channel latest (or verify deferred)." -f `
            $before.VersionToReport, $after.VersionToReport) 'WARN'
    Complete-M365 -Code 2
    return
}

if ($sawClickToRun -or (-not $proc.HasExited) -or ($proc.HasExited -and $proc.ExitCode -eq 0)) {
    Write-M365Log 'Silent update was started. Version may apply after Office apps are closed by the user.' 'WARN'
    Write-M365Log 'Re-run with -CheckOnly in a few minutes (or after apps restart) to confirm UP TO DATE.' 'WARN'
    Complete-M365 -Code 2
    return
}

Write-M365Log 'Update may not have started successfully (no version change, no C2R activity observed).' 'ERROR'
Complete-M365 -Code 1
return
