#Requires -Version 5.1
<#
.SYNOPSIS
    Silent-install Huntress Windows agent (download + /ACCT_KEY /ORG_KEY /S).

.DESCRIPTION
    Downloads HuntressInstaller.exe from update.huntress.io using the account key,
    then runs a silent install. Uses the official flag name /ACCT_KEY (not
    /ACCOUNT_KEY — the latter is ignored and commonly yields a non-zero exit such
    as 53).

    Skips download and install when HuntressAgent is already present (service
    or HuntressAgent.exe under Program Files). Never hardcode real keys.

.PARAMETER AccountKey
    Huntress account key (32 chars). Used for download URL and /ACCT_KEY=.

.PARAMETER OrgKey
    Huntress organization key (client short name). Spaces become dashes.

.PARAMETER Tags
    Optional comma-separated agent tags (/TAGS=).

.PARAMETER InstallerPath
    Destination path for the downloaded EXE.

.PARAMETER DownloadTimeoutSec
    Max seconds to wait for download (default 120).

.PARAMETER InstallTimeoutSec
    Max seconds to wait for installer (default 180).

.PARAMETER Exit
    Call exit with a status code (ScreenConnect Commands). Omit in Backstage.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AccountKey,

    [Parameter(Mandatory = $true)]
    [string]$OrgKey,

    [string]$Tags,

    [string]$InstallerPath = '',

    [int]$DownloadTimeoutSec = 120,

    [int]$InstallTimeoutSec = 180,

    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$script:ExitCode = 0

function Write-Section([string]$Message) {
    Write-Output "=== $Message ==="
}

function Get-HuntressInstallState {
    $svc = Get-Service -Name 'HuntressAgent' -ErrorAction SilentlyContinue
    $exePaths = @(
        (Join-Path ${env:ProgramFiles} 'Huntress\HuntressAgent.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'Huntress\HuntressAgent.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    [pscustomobject]@{
        Service     = $svc
        ExePaths    = @($exePaths)
        IsPresent   = [bool]($svc -or $exePaths.Count -gt 0)
    }
}

$AccountKey = $AccountKey.Trim()
$OrgKey = $OrgKey.Trim()
$Tags = if ($null -eq $Tags) { '' } else { $Tags.Trim() }

if ([string]::IsNullOrWhiteSpace($AccountKey) -or [string]::IsNullOrWhiteSpace($OrgKey)) {
    Write-Output 'ERROR: -AccountKey and -OrgKey are required.'
    $script:ExitCode = 2
    if ($Exit) { exit $script:ExitCode }
    return
}

if ($AccountKey.Length -ne 32) {
    Write-Output ("WARNING: Account key length is {0} (Huntress expects 32). Continuing anyway." -f $AccountKey.Length)
}

if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
    $InstallerPath = Join-Path $env:TEMP 'HuntressInstaller.exe'
}

Write-Section 'Checking for existing Huntress agent'
$existing = Get-HuntressInstallState
if ($existing.Service) {
    Write-Output ("Service HuntressAgent: {0} (StartType={1})" -f $existing.Service.Status, $existing.Service.StartType)
} else {
    Write-Output 'Service HuntressAgent: not found'
}
if ($existing.ExePaths.Count -gt 0) {
    foreach ($p in $existing.ExePaths) {
        Write-Output ("Found {0}" -f $p)
    }
} else {
    Write-Output 'HuntressAgent.exe: not found under Program Files'
}

if ($existing.IsPresent) {
    Write-Output 'Huntress agent already present. Skipping download and install.'
    $script:ExitCode = 0
    if ($Exit) { exit $script:ExitCode }
    return
}

$InstallerUrl = "https://update.huntress.io/download/$AccountKey/HuntressInstaller.exe"
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Section 'Downloading Huntress installer'
Write-Output ("URL host: update.huntress.io (account key used in path; not printed)")
try {
    $job = Start-Job -ScriptBlock {
        param($url, $path)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing -ErrorAction Stop
    } -ArgumentList $InstallerUrl, $InstallerPath

    if (-not (Wait-Job $job -Timeout $DownloadTimeoutSec)) {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        Write-Output ("ERROR: Download timed out after {0} seconds." -f $DownloadTimeoutSec)
        $script:ExitCode = 4
        if ($Exit) { exit $script:ExitCode }
        return
    }

    if ($job.State -eq 'Failed') {
        $jobError = Receive-Job $job 2>&1 | Out-String
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        Write-Output ("ERROR: Download job failed: {0}" -f $jobError.Trim())
        $script:ExitCode = 4
        if ($Exit) { exit $script:ExitCode }
        return
    }

    Receive-Job $job -ErrorAction Stop | Out-Null
    Remove-Job $job -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Output ("ERROR: Download failed: {0}" -f $_.Exception.Message)
    $script:ExitCode = 4
    if ($Exit) { exit $script:ExitCode }
    return
}

if (-not (Test-Path -LiteralPath $InstallerPath)) {
    Write-Output 'ERROR: Installer file not found after download.'
    $script:ExitCode = 3
    if ($Exit) { exit $script:ExitCode }
    return
}

$fileSize = (Get-Item -LiteralPath $InstallerPath).Length
if ($fileSize -eq 0) {
    Write-Output 'ERROR: Installer file is 0 bytes.'
    Remove-Item -LiteralPath $InstallerPath -Force -ErrorAction SilentlyContinue
    $script:ExitCode = 3
    if ($Exit) { exit $script:ExitCode }
    return
}
Write-Output ("Downloaded installer ({0} bytes)." -f $fileSize)

# Official silent flags: /ACCT_KEY (not /ACCOUNT_KEY), /ORG_KEY, optional /TAGS, /S
$argList = @(
    ('/ACCT_KEY={0}' -f $AccountKey),
    ('/ORG_KEY={0}' -f $OrgKey)
)
if (-not [string]::IsNullOrWhiteSpace($Tags)) {
    $argList += ('/TAGS={0}' -f $Tags)
}
$argList += '/S'

Write-Section 'Installing Huntress agent'
Write-Output 'Flags: /ACCT_KEY=... /ORG_KEY=... /S  (official names; /ACCOUNT_KEY is invalid)'
Write-Output 'Installer log (if present): C:\Windows\Temp\HuntressInstaller.log'

try {
    $proc = Start-Process -FilePath $InstallerPath -ArgumentList $argList -PassThru -Wait:$false
    if (-not $proc.WaitForExit($InstallTimeoutSec * 1000)) {
        Write-Output ("ERROR: Install timed out after {0} seconds. Killing process." -f $InstallTimeoutSec)
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        $script:ExitCode = 5
        if ($Exit) { exit $script:ExitCode }
        return
    }
    $script:ExitCode = [int]$proc.ExitCode
}
catch {
    Write-Output ("ERROR: Install failed to start: {0}" -f $_.Exception.Message)
    $script:ExitCode = 1
    if ($Exit) { exit $script:ExitCode }
    return
}

if ($script:ExitCode -eq 0) {
    Write-Output 'Huntress installation complete (exit 0).'
}
else {
    Write-Output ("WARNING: Installer exited with code {0}." -f $script:ExitCode)
    if ($script:ExitCode -eq 53) {
        Write-Output 'NOTE: Exit 53 was commonly seen when /ACCOUNT_KEY= was used instead of /ACCT_KEY=. This script uses /ACCT_KEY=. If it still fails, check C:\Windows\Temp\HuntressInstaller.log and account/org keys.'
    }
    Write-Output 'Also verify elevation, outbound access to Huntress, and EDR allowlisting.'
}

Remove-Item -LiteralPath $InstallerPath -Force -ErrorAction SilentlyContinue

if ($Exit) { exit $script:ExitCode }
