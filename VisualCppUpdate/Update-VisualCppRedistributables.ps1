#Requires -Version 5.1
<#
.SYNOPSIS
    Patch installed Visual C++ 2005-2013 redistributables to their final security builds.

.DESCRIPTION
    Detects Microsoft Visual C++ 2005, 2008, 2010, 2012, and 2013 redistributables
    already on the host (x86 and x64) and silently installs the last Microsoft
    security update for each year that is present.

    Does not install a year that is not already installed.
    Visual C++ 2015-2022 stays on winget (VulnSoftwareUpdate VcRedistX64 / VcRedistX86).

.PARAMETER CheckOnly
    Report status only; do not download or install.

.PARAMETER Force
    Re-run installers even when DisplayVersion already meets the target.

.PARAMETER Year
    Limit to specific years (2005, 2008, 2010, 2012, 2013). Default: all detected.

.PARAMETER NoExit
    Keep the PowerShell host open (Backstage / nested orchestrator).

.PARAMETER Exit
    Always exit with a result code (Commands tab).
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Force,
    [int[]]$Year,
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptVersion = '1.0.0'

try {
    [Net.ServicePointManager]::SecurityProtocol = (
        [Net.ServicePointManager]::SecurityProtocol -bor
        [Net.SecurityProtocolType]::Tls12
    )
}
catch {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
}

function Write-VcLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts][$Level] $Message"
}

function Write-VcVerdict {
    param([string]$Status, [string]$Detail)
    Write-Host ''
    Write-Host ("======== VISUAL C++ LEGACY STATUS: {0} ========" -f $Status)
    if ($Detail) { Write-Host $Detail }
    Write-Host '================================================'
    Write-Host ''
}

function Test-VcShouldExitProcess {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-Vc {
    param([Parameter(Mandatory)][int]$Code)
    $global:LASTEXITCODE = $Code
    try { $global:VisualCppUpdateResultCode = $Code } catch { }
    if (Test-VcShouldExitProcess) { exit $Code }
    Write-VcLog ("Done. ResultCode={0} (PowerShell host kept open)." -f $Code)
}

function ConvertTo-VcVersion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $clean = ($Text -replace '[^\d\.].*$', '')
    if ([string]::IsNullOrWhiteSpace($clean)) { return $null }
    try { return [version]$clean } catch {
        $parts = @($clean -split '\.')
        while ($parts.Count -lt 2) { $parts += '0' }
        try { return [version](($parts[0..([Math]::Min(3, $parts.Count - 1))] -join '.')) } catch { return $null }
    }
}

function Test-VcVersionAtLeast {
    param([string]$Current, [string]$Target)
    $c = ConvertTo-VcVersion $Current
    $t = ConvertTo-VcVersion $Target
    if (-not $c -or -not $t) { return $false }
    return ($c -ge $t)
}

function Get-VcCatalog {
    @(
        [pscustomobject]@{
            Year = 2005
            Name = 'Visual C++ 2005'
            Kb = 'KB2538242'
            Target = '8.0.50727.6195'
            Pattern = 'Microsoft Visual C\+\+ 2005.*Redistributable'
            SilentArgs = @('/Q')
            DownloadPage = 'https://www.microsoft.com/download/details.aspx?id=26347'
            ConfirmationPage = 'https://www.microsoft.com/download/confirmation.aspx?id=26347'
            FileName = @{ x86 = 'vcredist_x86.exe'; x64 = 'vcredist_x64.exe' }
            Url = @{
                x86 = $null
                x64 = $null
            }
        }
        [pscustomobject]@{
            Year = 2008
            Name = 'Visual C++ 2008'
            Kb = 'KB2538243'
            Target = '9.0.30729.5677'
            Pattern = 'Microsoft Visual C\+\+ 2008.*Redistributable'
            SilentArgs = @('/quiet', '/norestart')
            DownloadPage = 'https://www.microsoft.com/download/details.aspx?id=26368'
            ConfirmationPage = $null
            FileName = $null
            Url = @{
                x86 = 'https://download.windowsupdate.com/msdownload/update/software/secu/2011/05/vcredist_x86_470640aa4bb7db8e69196b5edb0010933569e98d.exe'
                x64 = 'https://download.windowsupdate.com/msdownload/update/software/secu/2011/05/vcredist_x64_a7c83077b8a28d409e36316d2d7321fa0ccdb7e8.exe'
            }
        }
        [pscustomobject]@{
            Year = 2010
            Name = 'Visual C++ 2010'
            Kb = 'KB2565063'
            Target = '10.0.40219'
            Pattern = 'Microsoft Visual C\+\+ 2010.*Redistributable'
            SilentArgs = @('/quiet', '/norestart')
            DownloadPage = 'https://www.microsoft.com/download/details.aspx?id=26999'
            ConfirmationPage = $null
            FileName = $null
            Url = @{
                x86 = 'https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x86.exe'
                x64 = 'https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x64.exe'
            }
        }
        [pscustomobject]@{
            Year = 2012
            Name = 'Visual C++ 2012'
            Kb = 'Update 4'
            Target = '11.0.61030.0'
            Pattern = 'Microsoft Visual C\+\+ 2012.*Redistributable'
            SilentArgs = @('/install', '/quiet', '/norestart')
            DownloadPage = 'https://www.microsoft.com/download/details.aspx?id=30679'
            ConfirmationPage = $null
            FileName = $null
            Url = @{
                x86 = 'https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x86.exe'
                x64 = 'https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x64.exe'
            }
        }
        [pscustomobject]@{
            Year = 2013
            Name = 'Visual C++ 2013'
            Kb = 'Latest'
            Target = '12.0.40649.5'
            Pattern = 'Microsoft Visual C\+\+ 2013.*Redistributable'
            SilentArgs = @('/install', '/quiet', '/norestart')
            DownloadPage = 'https://www.microsoft.com/download/details.aspx?id=40784'
            ConfirmationPage = $null
            FileName = $null
            Url = @{
                x86 = 'https://download.microsoft.com/download/c/c/2/cc2df5f8-4454-44b4-802d-5ea68d086676/vcredist_x86.exe'
                x64 = 'https://download.microsoft.com/download/c/c/2/cc2df5f8-4454-44b4-802d-5ea68d086676/vcredist_x64.exe'
            }
        }
    )
}

function Get-VcUninstallApps {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($p in $paths) {
        Get-ItemProperty $p -ErrorAction SilentlyContinue | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.DisplayName)
        }
    }
}

function Get-VcArchFromName {
    param([string]$DisplayName)
    if ($DisplayName -match '(?i)x64|64-bit|64 bit') { return 'x64' }
    return 'x86'
}

function Resolve-VcDownloadUrl {
    param($Item, [string]$Arch)
    $direct = $Item.Url.$Arch
    if ($direct) { return $direct }
    if (-not $Item.ConfirmationPage -or -not $Item.FileName) { return $null }
    $fileName = $Item.FileName.$Arch
    if (-not $fileName) { return $null }
    try {
        $headers = @{ 'User-Agent' = "VisualCppUpdate/$ScriptVersion" }
        $resp = Invoke-WebRequest -Uri $Item.ConfirmationPage -UseBasicParsing -Headers $headers -ErrorAction Stop
        $escaped = [regex]::Escape($fileName)
        $m = [regex]::Match($resp.Content, "https://download\.microsoft\.com/[^`"']+$escaped", 'IgnoreCase')
        if ($m.Success) { return $m.Value }
    }
    catch {
        Write-VcLog ("Could not resolve {0} {1} download URL: {2}" -f $Item.Year, $Arch, $_.Exception.Message) 'WARN'
    }
    return $null
}

function Test-VcAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-VcInstaller {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutFile,
        [Parameter(Mandatory)][string[]]$SilentArgs
    )
    $wc = New-Object Net.WebClient
    $wc.Headers.Add('User-Agent', "VisualCppUpdate/$ScriptVersion")
    $wc.DownloadFile($Url, $OutFile)
    if (-not (Test-Path -LiteralPath $OutFile)) {
        throw "Download produced no file: $OutFile"
    }
    $p = Start-Process -FilePath $OutFile -ArgumentList $SilentArgs -Wait -PassThru -WindowStyle Hidden
    return [int]$p.ExitCode
}

# --- main ---
Write-VcLog ("VisualCppUpdate {0}" -f $ScriptVersion)
Write-VcLog ("User: {0} | CheckOnly={1} Force={2}" -f `
        [Security.Principal.WindowsIdentity]::GetCurrent().Name, $CheckOnly, $Force)

$wantedYears = @()
if ($Year -and $Year.Count -gt 0) { $wantedYears = @($Year) }

$catalog = @(Get-VcCatalog)
if ($wantedYears.Count -gt 0) {
    $unknown = @($wantedYears | Where-Object { $y = $_; -not ($catalog | Where-Object { $_.Year -eq $y }) })
    foreach ($u in $unknown) {
        Write-VcLog ("Unknown year {0} (supported: 2005 2008 2010 2012 2013)" -f $u) 'WARN'
    }
    $catalog = @($catalog | Where-Object { $wantedYears -contains $_.Year })
    if ($catalog.Count -eq 0) {
        Write-VcVerdict -Status 'ERROR' -Detail 'No matching Visual C++ years.'
        Complete-Vc -Code 1
        return
    }
}

$apps = @(Get-VcUninstallApps)
$work = New-Object System.Collections.Generic.List[object]
$tempFiles = New-Object System.Collections.Generic.List[string]
$reboot = $false
$errors = 0
$needed = 0
$updated = 0

foreach ($item in $catalog) {
    $hits = @($apps | Where-Object { $_.DisplayName -match $item.Pattern })
    if ($hits.Count -eq 0) {
        Write-VcLog ("{0}: not installed" -f $item.Name)
        continue
    }

    $byArch = @{}
    foreach ($h in $hits) {
        $arch = Get-VcArchFromName -DisplayName $h.DisplayName
        $ver = [string]$h.DisplayVersion
        if (-not $byArch.ContainsKey($arch)) {
            $byArch[$arch] = $h
            continue
        }
        $prev = ConvertTo-VcVersion $byArch[$arch].DisplayVersion
        $cur = ConvertTo-VcVersion $ver
        if ($cur -and ((-not $prev) -or ($cur -gt $prev))) {
            $byArch[$arch] = $h
        }
    }

    foreach ($arch in @($byArch.Keys | Sort-Object)) {
        $row = $byArch[$arch]
        $current = [string]$row.DisplayVersion
        $currentEnough = Test-VcVersionAtLeast -Current $current -Target $item.Target
        $status = if ($currentEnough) { 'UP_TO_DATE' } else { 'UPDATE_AVAILABLE' }
        Write-VcLog ("{0} {1}: installed {2} target {3} ({4}) [{5}]" -f `
                $item.Name, $arch, $current, $item.Target, $item.Kb, $status)
        $work.Add([pscustomobject]@{
                Item    = $item
                Arch    = $arch
                Current = $current
                CurrentEnough = $currentEnough
            }) | Out-Null
        if (-not $currentEnough) { $needed++ }
    }
}

if ($work.Count -eq 0) {
    Write-VcVerdict -Status 'SKIPPED_NOT_INSTALLED' -Detail 'No Visual C++ 2005-2013 redistributables detected.'
    Complete-Vc -Code 0
    return
}

if ($CheckOnly) {
    $detail = ($work | ForEach-Object {
            '{0} {1} {2} -> {3}' -f $_.Item.Name, $_.Arch, $_.Current, $_.Item.Target
        }) -join '; '
    if ($needed -gt 0) {
        Write-VcVerdict -Status 'UPDATE_AVAILABLE' -Detail $detail
        Complete-Vc -Code 2
        return
    }
    Write-VcVerdict -Status 'UP_TO_DATE' -Detail $detail
    Complete-Vc -Code 0
    return
}

if (-not (Test-VcAdmin)) {
    Write-VcVerdict -Status 'ERROR' -Detail 'Administrator / SYSTEM required to install redistributables.'
    Complete-Vc -Code 1
    return
}

$tempDir = Join-Path $env:TEMP 'VisualCppUpdate'
try {
    if (-not (Test-Path -LiteralPath $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }

    foreach ($job in $work) {
        $item = $job.Item
        $arch = $job.Arch
        if ($job.CurrentEnough -and -not $Force) {
            Write-VcLog ("{0} {1}: already at {2} - skip" -f $item.Name, $arch, $job.Current)
            continue
        }

        $url = Resolve-VcDownloadUrl -Item $item -Arch $arch
        if (-not $url) {
            Write-VcLog ("{0} {1}: no installer URL. Manual: {2}" -f $item.Name, $arch, $item.DownloadPage) 'WARN'
            $needed++
            $errors++
            continue
        }

        $safeYear = [string]$item.Year
        $out = Join-Path $tempDir ("vcredist_{0}_{1}.exe" -f $safeYear, $arch)
        $tempFiles.Add($out) | Out-Null
        try {
            Write-VcLog ("{0} {1}: downloading" -f $item.Name, $arch)
            $code = Invoke-VcInstaller -Url $url -OutFile $out -SilentArgs $item.SilentArgs
            # 0 ok; 1638 already installed; 1641/3010 reboot; 5100 already present
            if ($code -in 0, 1638, 1641, 3010, 5100) {
                Write-VcLog ("{0} {1}: installer exit {2}" -f $item.Name, $arch, $code)
                $updated++
                if ($code -in 1641, 3010) { $reboot = $true }
            }
            else {
                Write-VcLog ("{0} {1}: installer exit {2}" -f $item.Name, $arch, $code) 'WARN'
                $errors++
            }
        }
        catch {
            Write-VcLog ("{0} {1}: {2}" -f $item.Name, $arch, $_.Exception.Message) 'ERROR'
            $errors++
        }
    }
}
finally {
    foreach ($f in $tempFiles) {
        if (Test-Path -LiteralPath $f) {
            Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        }
    }
}

$summary = "Updated={0} Errors={1} RebootRequired={2}" -f $updated, $errors, $reboot
if ($errors -gt 0) {
    Write-VcVerdict -Status 'ERROR' -Detail $summary
    Complete-Vc -Code 1
    return
}
if ($reboot) {
    Write-VcVerdict -Status 'UPDATED' -Detail ($summary + '. Restart to finish.')
    Complete-Vc -Code 2
    return
}
Write-VcVerdict -Status 'UPDATED_OR_CURRENT' -Detail $summary
Complete-Vc -Code 0
return
