#Requires -Version 5.1
<#
.SYNOPSIS
    Silent-install SentinelOne Windows agent with a site/group token.

.DESCRIPTION
    Runs an EXE installer with -t (and optional -q), or an MSI with msiexec
    SITE_TOKEN= /qn /norestart. Optional -InstallerUrl downloads the package
    to -InstallerPath first.

    If the URL or file is an MSI but -InstallerPath ends in .exe (common with
    Barracuda/XDR download links that use fileType=.msi), the path is corrected
    and msiexec is used. OLE/MSI magic bytes are checked as a fallback.

    Never hardcode real tokens. Pass -SiteToken at run time (ScToolLauncher).

.PARAMETER SiteToken
    SentinelOne site or group token.

.PARAMETER InstallerPath
    Full path to the EXE or MSI on the endpoint.

.PARAMETER InstallerUrl
    Optional HTTPS URL to download into InstallerPath before install.

.PARAMETER Quiet
    For EXE installs, pass -q (needed on older agent lines). Ignored for MSI.

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

function Test-UrlLooksLikeMsi([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    if ($Url -match '(?i)fileType=\.msi') { return $true }
    if ($Url -match '(?i)\.msi(\?|#|$)') { return $true }
    return $false
}

function Test-IsMsiPackage([string]$Path) {
    if ($Path -like '*.msi') { return $true }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        try {
            $buf = New-Object byte[] 8
            if ($fs.Read($buf, 0, 8) -lt 8) { return $false }
            # OLE compound document signature used by Windows Installer packages
            return ($buf[0] -eq 0xD0 -and $buf[1] -eq 0xCF -and $buf[2] -eq 0x11 -and $buf[3] -eq 0xE0)
        }
        finally { $fs.Close() }
    }
    catch {
        return $false
    }
}

function Set-PathExtension([string]$Path, [string]$Ext) {
    $dir = Split-Path -Parent $Path
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    if ([string]::IsNullOrWhiteSpace($base)) { $base = 'SentinelOneInstaller' }
    if ([string]::IsNullOrWhiteSpace($dir)) {
        return ($base + $Ext)
    }
    return (Join-Path $dir ($base + $Ext))
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

# Barracuda/XDR links often use fileType=.msi while the launcher default path is .exe
if (Test-UrlLooksLikeMsi $InstallerUrl) {
    $corrected = Set-PathExtension $InstallerPath '.msi'
    if ($corrected -ne $InstallerPath) {
        Write-Output ("URL looks like MSI; using path {0}" -f $corrected)
        $InstallerPath = $corrected
    }
}

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

# If someone saved an MSI as .exe, detect and rename so msiexec gets a .msi path
if ((-not ($InstallerPath -like '*.msi')) -and (Test-IsMsiPackage $InstallerPath)) {
    $msiPath = Set-PathExtension $InstallerPath '.msi'
    Write-Output ("Downloaded/local package is MSI (OLE signature); moving to {0}" -f $msiPath)
    if (Test-Path -LiteralPath $msiPath) {
        Remove-Item -LiteralPath $msiPath -Force -ErrorAction SilentlyContinue
    }
    Move-Item -LiteralPath $InstallerPath -Destination $msiPath -Force
    $InstallerPath = $msiPath
}

$isMsi = Test-IsMsiPackage $InstallerPath
Write-Section ("Installing from {0} ({1})" -f $InstallerPath, $(if ($isMsi) { 'MSI / msiexec' } else { 'EXE' }))

try {
    if ($isMsi) {
        $args = @(
            '/i', $InstallerPath,
            '/qn',
            '/norestart',
            ('SITE_TOKEN={0}' -f $SiteToken)
        )
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -PassThru -NoNewWindow
        $script:ExitCode = $p.ExitCode
        if ($script:ExitCode -eq 3010) {
            Write-Output 'msiexec 3010 = success, reboot required.'
            $script:ExitCode = 0
        }
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
