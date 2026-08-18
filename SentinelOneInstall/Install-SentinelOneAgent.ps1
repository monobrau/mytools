#Requires -Version 5.1
<#
.SYNOPSIS
    Silent-install SentinelOne Windows agent with a site/group token.

.DESCRIPTION
    Runs an EXE installer with -t (and optional -q), or an MSI with msiexec
    SITE_TOKEN= /qn /norestart. Optional -InstallerUrl downloads the package
    to -InstallerPath first.

    Never hardcode real tokens. Pass -SiteToken at run time (ScToolLauncher).

.PARAMETER SiteToken
    SentinelOne site or group token.

.PARAMETER InstallerPath
    Full path to the EXE or MSI on the endpoint.

.PARAMETER InstallerUrl
    Optional HTTPS URL to download into InstallerPath before install.

.PARAMETER Quiet
    For EXE installs, pass -q (needed on older agent lines).

.PARAMETER Exit
    Call exit with a status code (ScreenConnect Commands). Omit in Backstage.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SiteToken,

    [string]$InstallerPath = 'C:\Windows\Temp\SentinelOneInstaller.exe',

    [string]$InstallerUrl,

    [switch]$Quiet,

    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$script:ExitCode = 0

function Write-Section([string]$Message) {
    Write-Output "=== $Message ==="
}

if ([string]::IsNullOrWhiteSpace($SiteToken)) {
    Write-Output 'ERROR: -SiteToken is required.'
    $script:ExitCode = 2
    if ($Exit) { exit $script:ExitCode }
    return
}

if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
    Write-Output 'ERROR: -InstallerPath is required.'
    $script:ExitCode = 2
    if ($Exit) { exit $script:ExitCode }
    return
}

$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not [string]::IsNullOrWhiteSpace($InstallerUrl)) {
    Write-Section 'Downloading installer'
    $parent = Split-Path -Parent $InstallerPath
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    try {
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing
    }
    catch {
        Write-Output ("ERROR: download failed: {0}" -f $_.Exception.Message)
        $script:ExitCode = 4
        if ($Exit) { exit $script:ExitCode }
        return
    }
}

if (-not (Test-Path -LiteralPath $InstallerPath)) {
    Write-Output ("ERROR: installer not found: {0}" -f $InstallerPath)
    $script:ExitCode = 3
    if ($Exit) { exit $script:ExitCode }
    return
}

Write-Section ("Installing from {0}" -f $InstallerPath)

try {
    if ($InstallerPath -like '*.msi') {
        $args = @(
            '/i', $InstallerPath,
            '/qn',
            '/norestart',
            ('SITE_TOKEN={0}' -f $SiteToken)
        )
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -PassThru -NoNewWindow
        $script:ExitCode = $p.ExitCode
    }
    else {
        $args = @('-t', $SiteToken)
        if ($Quiet) { $args += '-q' }
        $p = Start-Process -FilePath $InstallerPath -ArgumentList $args -Wait -PassThru -NoNewWindow
        $script:ExitCode = $p.ExitCode
    }
}
catch {
    Write-Output ("ERROR: install failed: {0}" -f $_.Exception.Message)
    $script:ExitCode = 1
}

Write-Section ("Done. ExitCode={0}" -f $script:ExitCode)
if ($Exit) { exit $script:ExitCode }
