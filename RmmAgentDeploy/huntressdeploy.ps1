#Requires -Version 5.1
<#
.SYNOPSIS
    Non-GPO deploy of Huntress only to online machines missing it.

.DESCRIPTION
    Run elevated as a domain admin on a machine that can reach C$ and create
    scheduled tasks on the targets. Reads a Huntress coverage CSV. For each
    online host with remote admin OK and Huntress missing, stages a SYSTEM task
    that runs the Huntress installer with /ACCT_KEY /ORG_KEY /S.

    Downloads the installer from Huntress CDN when -HuntressExe is missing
    (or when -ForceDownload is set). Pass keys on the command line; do not
    store them in this repo.

.PARAMETER Only
    Pilot: one or more computer names from the CSV Name column.

.PARAMETER HuntressAcctKey
    Huntress account key. Not stored in this repo.

.PARAMETER HuntressOrgKey
    Huntress organization key.

.PARAMETER HuntressExe
    Local path for HuntressInstaller.exe. Downloaded here if missing.

.PARAMETER InstallerUrl
    CDN URL for the Windows agent installer.

.PARAMETER ForceDownload
    Re-download even when HuntressExe already exists.

.PARAMETER CoverageCsv
    CSV with columns Name, Online, RemoteAdmin, Huntress.

.PARAMETER Exclude
    Computer names to skip.

.EXAMPLE
    .\huntressdeploy.ps1 -Only 'CONTOSO-PC01' -HuntressAcctKey '<acct>' -HuntressOrgKey 'contoso' -Exclude 'DC01','DC02'
#>
[CmdletBinding()]
param(
    [string[]]$Only,
    [Parameter(Mandatory)][string]$HuntressAcctKey,
    [Parameter(Mandatory)][string]$HuntressOrgKey,
    [string]$HuntressExe = 'C:\Support\HuntressInstaller.exe',
    [string]$InstallerUrl = 'https://huntresscdn.com/huntress-installers/0.14.198.exe',
    [switch]$ForceDownload,
    [string]$CoverageCsv = 'C:\Support\huntress-coverage.csv',
    [string[]]$Exclude = @()
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

if ($HuntressAcctKey -match '__ACCT__|__ORG__' -or $HuntressOrgKey -match '__ACCT__|__ORG__') {
    throw 'Huntress key contains a script placeholder.'
}
if (-not (Test-Path -LiteralPath $CoverageCsv)) { throw "Missing $CoverageCsv" }

function Get-HuntressInstaller {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Url,
        [switch]$Force
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $need = $Force -or -not (Test-Path -LiteralPath $Path) -or ((Get-Item -LiteralPath $Path).Length -lt 1MB)
    if (-not $need) {
        Write-Host ("Using existing installer: {0}" -f $Path) -ForegroundColor Cyan
        return
    }
    Write-Host ("Downloading Huntress installer from {0}" -f $Url) -ForegroundColor Cyan
    $tmp = "$Path.download"
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    [Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
    $wc = New-Object System.Net.WebClient
    try {
        $wc.DownloadFile($Url, $tmp)
    }
    finally {
        $wc.Dispose()
    }
    if (-not (Test-Path -LiteralPath $tmp) -or (Get-Item -LiteralPath $tmp).Length -lt 1MB) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw "Download failed or file too small: $Url"
    }
    Move-Item -LiteralPath $tmp -Destination $Path -Force
    Write-Host ("Saved {0} ({1:N0} bytes)" -f $Path, (Get-Item -LiteralPath $Path).Length) -ForegroundColor Cyan
}

Get-HuntressInstaller -Path $HuntressExe -Url $InstallerUrl -Force:$ForceDownload

$endpointTemplate = @'
Start-Transcript -Path C:\Windows\Temp\huntress-deploy.log -Append | Out-Null
try {
    try {
        if (-not (Get-Service | Where-Object Name -like 'Huntress*') -and (Test-Path C:\Windows\Temp\HuntressInstaller.exe)) {
            $p = Start-Process C:\Windows\Temp\HuntressInstaller.exe -ArgumentList '/ACCT_KEY="__ACCT__" /ORG_KEY="__ORG__" /S' -Wait -PassThru
            "Huntress installer exit code: $($p.ExitCode)"
        } else { 'Huntress already installed or installer not staged' }
    }
    catch { "HUNTRESS ERROR: $($_.Exception.Message)" }
    "Huntress services after install step: $((Get-Service | Where-Object Name -like 'Huntress*').Name -join ', ')"
}
finally {
    Remove-Item C:\Windows\Temp\HuntressInstaller.exe, C:\Windows\Temp\huntress-deploy.ps1 -Force -ErrorAction SilentlyContinue
    schtasks.exe /delete /tn Huntress-AgentDeploy /f | Out-Null
    Stop-Transcript | Out-Null
}
'@

$endpoint = $endpointTemplate.
    Replace('__ACCT__', $HuntressAcctKey).
    Replace('__ORG__', $HuntressOrgKey)

function Test-HuntressMissing([string]$Value) {
    $v = if ($null -eq $Value) { '' } else { $Value.Trim() }
    # Blank means the scanner left the column empty; treat as missing for deploy.
    return ($v -eq '' -or $v -eq 'MISSING')
}

$rows = @(Import-Csv -LiteralPath $CoverageCsv)
$targets = @($rows | Where-Object {
    $_.Online -eq 'True' -and
    $_.RemoteAdmin -eq 'OK' -and
    (Test-HuntressMissing $_.Huntress) -and
    $Exclude -notcontains $_.Name
})
if ($Only) {
    $targets = @($targets | Where-Object { $Only -contains $_.Name })
}

if (-not $targets) {
    $onlineOk = @($rows | Where-Object { $_.Online -eq 'True' -and $_.RemoteAdmin -eq 'OK' }).Count
    $missing = @($rows | Where-Object { Test-HuntressMissing $_.Huntress }).Count
    Write-Warning ("No matching targets. Online+RemoteAdmin OK={0}; Huntress blank/MISSING={1}; CSV={2}" -f $onlineOk, $missing, $CoverageCsv)
    return
}
Write-Host ("Deploying Huntress to {0} machine(s)..." -f $targets.Count) -ForegroundColor Cyan

$results = foreach ($t in $targets) {
    $name = $t.Name
    $dest = "\\$name\C$\Windows\Temp"
    $status = 'Started'
    try {
        Set-Content -LiteralPath "$dest\huntress-deploy.ps1" -Value $endpoint -Encoding ASCII -ErrorAction Stop
        Copy-Item -LiteralPath $HuntressExe -Destination "$dest\HuntressInstaller.exe" -Force -ErrorAction Stop

        schtasks.exe /create /s $name /ru SYSTEM /sc once /st 23:59 /rl HIGHEST /f /tn Huntress-AgentDeploy /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Windows\Temp\huntress-deploy.ps1" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "task create failed (exit $LASTEXITCODE)" }

        schtasks.exe /run /s $name /tn Huntress-AgentDeploy 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "task run failed (exit $LASTEXITCODE)" }
    }
    catch {
        $status = "FAILED: $($_.Exception.Message)"
    }

    [pscustomobject]@{
        Name     = $name
        Huntress = $t.Huntress
        Status   = $status
    }
}

$results | Format-Table -AutoSize
$outCsv = Join-Path (Split-Path -Parent $CoverageCsv) 'huntress-deploy-results.csv'
$results | Export-Csv -LiteralPath $outCsv -NoTypeInformation
Write-Host "Results: $outCsv" -ForegroundColor Cyan
Write-Host 'Installs run in the background. Check C:\Windows\Temp\huntress-deploy.log on a target, then rerun coveragescan.ps1 in about 15 minutes.' -ForegroundColor Cyan
