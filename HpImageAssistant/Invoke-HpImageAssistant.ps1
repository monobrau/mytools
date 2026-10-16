#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads HP Image Assistant and installs only unattended SoftPaqs on HP PCs.

.DESCRIPTION
    ScreenConnect Backstage (SYSTEM) and Commands (#!ps). Non-HP PCs exit
    without downloading or changing anything.

    Apply runs:
      /Operation:Analyze /Action:Install /Category:All /InstallType:AutoInstallable /Silent
    HPIA then installs only SSM-compliant SoftPaqs (the ones that can install
    with no person at the keyboard). Updates that need a click are skipped.

    Default does not reboot. -Reboot restarts only when HPIA returns 3010.
    A BIOS SoftPaq can still restart on its own.

.PARAMETER CheckOnly
    Download HPIA if needed, analyze, and list unattended recommendations. No install.

.PARAMETER Reboot
    Restart when HPIA reports 3010 (install succeeded and a reboot is required).

.PARAMETER Force
    Download and extract HPIA again even when this copy is already on disk.

.PARAMETER InstallerUrl
    HPIA SoftPaq URL. Default is the 5.3.7 build published on the HP Image Assistant page.

.PARAMETER WorkingDirectory
    Cache, report, and SoftPaq folders. Default: %ProgramData%\HpImageAssistant

.PARAMETER NoExit
    Do not call exit (keeps ScreenConnect Backstage PowerShell open).

.PARAMETER Exit
    Always call exit with the result code (ScreenConnect Commands).
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Reboot,
    [switch]$Force,
    [string]$InstallerUrl = 'https://hpia.hpcloud.hp.com/downloads/hpia/hp-hpia-5.3.7.exe',
    [string]$WorkingDirectory = (Join-Path $env:ProgramData 'HpImageAssistant'),
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ScriptVersion = '1.0.0'

try {
    [Net.ServicePointManager]::SecurityProtocol = (
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    )
}
catch {
    try { [Net.ServicePointManager]::SecurityProtocol = 3072 } catch { }
}

function Write-HpiaLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts][$Level] $Message"
}

function Test-HpiaElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Test-HpiaShouldExitProcess {
    if ($NoExit) { return $false }
    if ($Exit) { return $true }
    if (-not [string]::IsNullOrEmpty($PSCommandPath)) { return $true }
    if ([Environment]::UserInteractive) { return $false }
    return $true
}

function Complete-Hpia {
    param([Parameter(Mandatory)][int]$Code)
    $global:LASTEXITCODE = $Code
    try { $global:HpImageAssistantResultCode = $Code } catch { }
    if (Test-HpiaShouldExitProcess) { exit $Code }
    Write-HpiaLog ("Done. ResultCode={0} (PowerShell host kept open)." -f $Code)
}

function Get-HpiaComputer {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
    $mfg = ''
    $model = ''
    if ($cs) {
        $mfg = [string]$cs.Manufacturer
        $model = [string]$cs.Model
    }
    $biosMfg = ''
    if ($bios) { $biosMfg = [string]$bios.Manufacturer }
    $isHp = ($mfg -match '^(HP|Hewlett-Packard|HP Inc\.?)$') -or ($mfg -like 'HP *') -or ($mfg -like 'Hewlett*') -or ($biosMfg -match '^(HP|Hewlett-Packard|HP Inc\.?)$')
    return [pscustomobject]@{
        Manufacturer = $mfg
        Model        = $model
        BiosVendor   = $biosMfg
        IsHp         = [bool]$isHp
    }
}

function Get-HpiaExitMeaning {
    param([int]$Code)
    switch ($Code) {
        0 { return 'No error.' }
        256 { return 'No recommendations.' }
        257 { return 'No recommendations matched the unattended filter.' }
        3010 { return 'Install succeeded. At least one SoftPaq needs a restart.' }
        3011 { return 'A SoftPaq was skipped because it cannot install without a person.' }
        3020 { return 'One or more SoftPaq installs failed.' }
        4096 { return 'This platform is not supported by HPIA.' }
        4097 { return 'HPIA rejected the command line.' }
        4098 { return 'No internet connection.' }
        4102 { return 'TLS 1.2 or higher is required.' }
        4103 { return 'The request to HP did not complete.' }
        4104 { return 'HPIA used a generic OS reference file.' }
        8192 { return 'The operation failed.' }
        default { return 'See the HPIA log in the report folder.' }
    }
}

function Invoke-HpiaProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$Arguments,
        [string]$WorkingDirectory
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $psi.WorkingDirectory = $WorkingDirectory
    }
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    if (-not $proc.Start()) { throw "Failed to start $FilePath" }
    $proc.WaitForExit()
    return [int]$proc.ExitCode
}

function Resolve-HpiaExecutable {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$WorkDir,
        [switch]$Redownload
    )
    $appRoot = Join-Path $WorkDir 'app'
    $stampPath = Join-Path $appRoot 'source.txt'
    $want = [IO.Path]::GetFileName(($Url -split '\?')[0])
    if ([string]::IsNullOrWhiteSpace($want)) { $want = 'hp-hpia.exe' }

    $existing = $null
    if (Test-Path -LiteralPath $appRoot) {
        $existing = Get-ChildItem -LiteralPath $appRoot -Recurse -Filter 'HPImageAssistant.exe' -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
    $have = ''
    if (Test-Path -LiteralPath $stampPath) {
        $have = (Get-Content -LiteralPath $stampPath -Raw -ErrorAction SilentlyContinue).Trim()
    }
    if ($existing -and -not $Redownload -and $have -eq $want) {
        Write-HpiaLog ("Using cached HPIA: {0}" -f $existing.FullName)
        return $existing.FullName
    }

    if (-not (Test-Path -LiteralPath $WorkDir)) {
        New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    }
    $dest = Join-Path $WorkDir $want
    Write-HpiaLog ("Downloading {0}" -f $Url)
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', "HpImageAssistant/$ScriptVersion")
    $wc.DownloadFile($Url, $dest)
    $len = 0
    if (Test-Path -LiteralPath $dest) { $len = [int64](Get-Item -LiteralPath $dest).Length }
    if ($len -lt 1000000) {
        throw "HPIA download looks empty ($len bytes): $dest"
    }
    Write-HpiaLog ("Downloaded {0} bytes" -f $len)

    if (Test-Path -LiteralPath $appRoot) {
        Remove-Item -LiteralPath $appRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $appRoot -Force | Out-Null
    Write-HpiaLog ("Extracting to {0}" -f $appRoot)
    $extractCode = Invoke-HpiaProcess -FilePath $dest -Arguments "/s /e /f `"$appRoot`""
    $exe = Get-ChildItem -LiteralPath $appRoot -Recurse -Filter 'HPImageAssistant.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $exe) {
        throw "HPIA extract failed (exit $extractCode). HPImageAssistant.exe was not found under $appRoot"
    }
    if (@(0, 1168) -notcontains $extractCode) {
        Write-HpiaLog ("Extract exit code {0}. HPImageAssistant.exe is present, continuing." -f $extractCode) 'WARN'
    }
    Set-Content -LiteralPath $stampPath -Value $want -Encoding ASCII
    Write-HpiaLog ("HPIA ready: {0}" -f $exe.FullName)
    return $exe.FullName
}

function Write-HpiaRecommendations {
    param([Parameter(Mandatory)][string]$ReportFolder)
    $listed = 0
    if (-not (Test-Path -LiteralPath $ReportFolder)) { return 0 }

    $xmlFiles = @(Get-ChildItem -LiteralPath $ReportFolder -Recurse -Filter '*.xml' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    foreach ($file in $xmlFiles) {
        try { [xml]$xml = Get-Content -LiteralPath $file.FullName -ErrorAction Stop }
        catch { continue }
        $recs = $xml.HPIA.Recommendations
        if (-not $recs) { continue }
        Write-HpiaLog ("Recommendations: {0}" -f $file.FullName)
        foreach ($group in @($recs.ChildNodes)) {
            if ($group.NodeType -ne 'Element') { continue }
            $items = @()
            if ($group.LocalName -eq 'Recommendation') { $items = @($group) }
            else { $items = @($group.Recommendation) }
            foreach ($item in $items) {
                if (-not $item -or [string]::IsNullOrWhiteSpace([string]$item.TargetComponent)) { continue }
                $listed++
                $softpaq = ''
                if ($item.Solution -and $item.Solution.Softpaq) {
                    $id = [string]$item.Solution.Softpaq.Id
                    $spName = [string]$item.Solution.Softpaq.Name
                    $url = [string]$item.Solution.Softpaq.Url
                    $softpaq = (@($id, $spName, $url) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
                }
                $bucket = [string]$group.LocalName
                if ($bucket -eq 'Recommendation') { $bucket = 'item' }
                Write-HpiaLog ("  {0}: {1}  {2} -> {3}  {4}" -f $bucket, $item.TargetComponent, $item.TargetVersion, $item.ReferenceVersion, $softpaq)
            }
        }
        if ($listed -gt 0) { break }
    }

    $jsonFiles = @(Get-ChildItem -LiteralPath $ReportFolder -Recurse -Filter '*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    foreach ($file in $jsonFiles) {
        try { $json = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json }
        catch { continue }
        $root = $json.HPIA
        if (-not $root) { continue }
        Write-HpiaLog ("Install report: {0}" -f $file.FullName)
        if ($root.ExitCode) { Write-HpiaLog ("  HPIA exit: {0}" -f $root.ExitCode) }
        foreach ($item in @($root.Recommendations)) {
            if (-not $item) { continue }
            $name = [string]$item.Name
            if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]$item.TargetComponent }
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $status = ''
            $ret = ''
            if ($item.Remediation) {
                $status = [string]$item.Remediation.Status
                $ret = [string]$item.Remediation.ReturnCode
            }
            Write-HpiaLog ("  {0}  {1}  status={2} return={3}" -f $name, $item.SoftPaqID, $status, $ret)
        }
        break
    }

    if ($listed -eq 0) {
        Write-HpiaLog 'No unattended recommendations were listed in the report.'
    }
    return $listed
}

$computer = Get-HpiaComputer
Write-HpiaLog ("HpImageAssistant {0}" -f $ScriptVersion)
Write-HpiaLog ("Computer: {0} {1} | CheckOnly={2} Reboot={3} Force={4} Elevated={5}" -f $computer.Manufacturer, $computer.Model, $CheckOnly.IsPresent, $Reboot.IsPresent, $Force.IsPresent, (Test-HpiaElevated))

if (-not $computer.IsHp) {
    Write-HpiaLog 'Not an HP PC. Nothing downloaded or changed.'
    Complete-Hpia -Code 0
    return
}

if (-not (Test-HpiaElevated)) {
    Write-HpiaLog 'HPIA requires elevation.' 'ERROR'
    Complete-Hpia -Code 1
    return
}

try {
    $exe = Resolve-HpiaExecutable -Url $InstallerUrl -WorkDir $WorkingDirectory -Redownload:$Force
    $report = Join-Path $WorkingDirectory 'report'
    $softpaqs = Join-Path $WorkingDirectory 'softpaqs'
    if (Test-Path -LiteralPath $report) {
        Remove-Item -LiteralPath $report -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $report -Force | Out-Null
    if (-not $CheckOnly -and -not (Test-Path -LiteralPath $softpaqs)) {
        New-Item -ItemType Directory -Path $softpaqs -Force | Out-Null
    }

    $action = 'Install'
    if ($CheckOnly) { $action = 'List' }
    $hpiaArgs = "/Operation:Analyze /Action:$action /Category:All /InstallType:AutoInstallable /Silent /Debug /IgnoreGenericOsError /ReportFolder:`"$report`""
    if (-not $CheckOnly) {
        $hpiaArgs += " /SoftpaqDownloadFolder:`"$softpaqs`" /AutoCleanup"
    }
    Write-HpiaLog ("Running {0} {1}" -f $exe, $hpiaArgs)
    $hpiaCode = Invoke-HpiaProcess -FilePath $exe -Arguments $hpiaArgs -WorkingDirectory (Split-Path -Parent $exe)
    Write-HpiaLog ("HPIA exit {0}: {1}" -f $hpiaCode, (Get-HpiaExitMeaning -Code $hpiaCode))
    $listed = Write-HpiaRecommendations -ReportFolder $report
    Write-HpiaLog ("Report folder: {0}" -f $report)
}
catch {
    Write-HpiaLog $_.Exception.Message 'ERROR'
    Complete-Hpia -Code 1
    return
}

if ($CheckOnly) {
    if ($hpiaCode -eq 0 -and $listed -gt 0) {
        Write-HpiaLog ("Scan found {0} unattended recommendation(s). Nothing was installed." -f $listed)
        Complete-Hpia -Code 2
        return
    }
    if (@(0, 256, 257) -contains $hpiaCode) {
        Write-HpiaLog 'No unattended updates to install.'
        Complete-Hpia -Code 0
        return
    }
    Complete-Hpia -Code $hpiaCode
    return
}

if ($hpiaCode -eq 3010) {
    Write-HpiaLog 'Install finished. A restart is required before every SoftPaq is active.' 'WARN'
    if ($Reboot) {
        Write-HpiaLog 'Reboot: restarting now (ScreenConnect session will drop).'
        Restart-Computer -Force
        return
    }
    Write-HpiaLog 'Not rebooting. Run again with -Reboot, or restart the PC yourself.'
    Complete-Hpia -Code 3010
    return
}

if (@(0, 256, 257) -contains $hpiaCode) {
    if ($hpiaCode -eq 257) {
        Write-HpiaLog 'HPIA found nothing it can install unattended.'
    }
    Complete-Hpia -Code 0
    return
}

if ($hpiaCode -eq 3011) {
    Write-HpiaLog 'At least one SoftPaq was skipped because it is not unattended.' 'WARN'
    Complete-Hpia -Code 3011
    return
}

Write-HpiaLog ("HPIA did not finish cleanly ({0})." -f $hpiaCode) 'ERROR'
Complete-Hpia -Code $hpiaCode
