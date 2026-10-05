#Requires -Version 5.1
<#
.SYNOPSIS
    Scan or remove the ConnectWise Automate (LabTech) remote agent.

.DESCRIPTION
    Targets the RMM agent only: LTService, LTSvcMon, LabVNC, and %windir%\LTSvc.
    ScreenConnect / ConnectWise Control and the Automate Control Center are left
    installed. Apply runs a matching MSI uninstall, then ConnectWise Agent_Uninstall.exe
    (from the server recorded on the agent, then the public ConnectWise copy), then
    scrubs leftover services, files, and agent registry keys.

    A probe agent (registry Probe=1) is reported and left in place unless -Force.

    -Reinstall reads the server and location already on the PC, keeps a copy of the
    installed agent MSI (or downloads one from that server), uninstalls, then installs
    again with those same settings. No installer token is required. The new agent
    checks in under the same location with a new agent ID.

.PARAMETER CheckOnly
    Report only.

.PARAMETER Remediate
    Uninstall the agent and scrub leftovers.

.PARAMETER Reinstall
    Uninstall, then install again from the MSI and server/location already on this PC.

.PARAMETER Force
    Allow uninstall or reinstall when the agent is a probe.

.PARAMETER Exit
    Call exit with a status code (ScreenConnect Commands).
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Remediate,
    [switch]$Reinstall,
    [switch]$Force,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$script:ExitCode = 0

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
} catch {}

$script:AgentServiceNames = @('LTSvcMon', 'LabVNC', 'LTService')
$script:AgentImageNames = @('ltsvc.exe', 'ltsvcmon.exe', 'lttray.exe')
$script:KnownProductCodes = @(
    '{58A3001D-B675-4D67-A5A1-0FA9F08CF7CA}',
    '{3426921D-9AD5-4237-9145-F15DEE7E3004}',
    '{40BF8C82-ED0D-4F66-B73E-58A3D7AB6582}',
    '{3F460D4C-D217-46B4-80B6-B5ED50BD7CF5}'
)

function Test-IsAdmin {
    $p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-AgentBase {
    return (Join-Path $env:windir 'LTSvc')
}

function Test-UnderAgentRoot {
    param([string]$Path)
    if (-not $Path) { return $false }
    $clean = ($Path -replace '^"', '' -replace '"$', '').Trim()
    $root = (Get-AgentBase).TrimEnd('\')
    $prefix = $root + '\'
    if ($clean.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($clean.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return ($clean -match '(?i)\\LTSvc(\\|"|$)')
}

function Get-LabTechProps {
    $hits = @()
    foreach ($path in @(
            'HKLM:\SOFTWARE\LabTech\Service',
            'HKLM:\SOFTWARE\WOW6432Node\LabTech\Service'
        )) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $item = Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        $server = [string]$item.'Server Address'
        if (-not $server) { $server = [string]$item.ServerAddress }
        $hits += [pscustomobject]@{
            KeyPath  = $path
            Server   = $server
            Version  = [string]$item.Version
            Id       = [string]$item.ID
            Location = [string]$item.LocationID
            Probe    = [string]$item.Probe
        }
    }
    if ($hits.Count -eq 0) { return $null }
    $best = $hits | Where-Object { $_.Server } | Select-Object -First 1
    if (-not $best) { $best = $hits[0] }
    foreach ($hit in $hits) {
        if ($hit.Probe -eq '1') { $best.Probe = '1' }
    }
    return $best
}

function Get-UninstallEntries {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -or $_.PSChildName }
}

function Test-AgentArpEntry {
    param($Entry)
    $name = [string]$Entry.DisplayName
    if ($name -match '(?i)ScreenConnect|ConnectWise Control|Control Center') { return $false }
    if ($name -match '(?i)(LabTech|ConnectWise Automate)\s+Remote Agent') { return $true }
    $guid = ([string]$Entry.PSChildName).ToUpper()
    if ($script:KnownProductCodes -contains $guid) { return $true }
    $blob = ([string]$Entry.UninstallString) + ' ' + ([string]$Entry.InstallLocation) + ' ' + ([string]$Entry.DisplayIcon)
    if ($blob -match '(?i)ScreenConnect|ConnectWise Control') { return $false }
    return [bool]($blob -match '(?i)\\LTSvc\\')
}

function Get-AgentArp {
    @(Get-UninstallEntries | Where-Object { Test-AgentArpEntry $_ })
}

function Get-KeptRemoteTools {
    @(Get-UninstallEntries | Where-Object {
        $n = [string]$_.DisplayName
        $n -match '(?i)ScreenConnect|ConnectWise Control|Control Center' -and $n -notmatch '(?i)Remote Agent'
    })
}

function Get-AgentServices {
    $found = @()
    foreach ($name in $script:AgentServiceNames) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) { $found += $svc }
    }
    $extra = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notin $script:AgentServiceNames -and
        $_.Name -notmatch '(?i)ScreenConnect|ConnectWise' -and
        (Test-UnderAgentRoot ([string]$_.PathName))
    })
    foreach ($svc in $extra) {
        $live = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($live) { $found += $live }
    }
    @($found | Sort-Object Name -Unique)
}

function Get-AgentProcesses {
    $names = $script:AgentImageNames
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $n = [string]$_.Name
        if ($n -match '(?i)ScreenConnect') { return $false }
        ($names -contains $n.ToLower()) -or (Test-UnderAgentRoot ([string]$_.ExecutablePath))
    })
}

function Get-AgentTasks {
    @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
        $hit = $false
        foreach ($action in @($_.Actions)) {
            $exe = [string]$action.Execute
            if ($exe -and (Test-UnderAgentRoot $exe)) { $hit = $true }
        }
        $hit
    })
}

function Get-ControlCenterRoots {
    $roots = @()
    foreach ($envName in @('ProgramFiles(x86)', 'ProgramFiles')) {
        $base = [Environment]::GetEnvironmentVariable($envName)
        if (-not $base) { continue }
        $roots += (Join-Path $base 'LabTech Client')
        $roots += (Join-Path $base 'ConnectWise\Automate')
    }
    return $roots
}

function Test-ControlCenterInstalled {
    foreach ($root in (Get-ControlCenterRoots)) {
        if ($root -and (Test-Path -LiteralPath $root)) { return $true }
    }
    $hit = @(Get-UninstallEntries | Where-Object {
        [string]$_.DisplayName -match '(?i)Control Center|LabTech Client'
    })
    return [bool]($hit.Count -gt 0)
}

function Get-MachineAgentRegKeys {
    @(
        'HKLM:\SOFTWARE\LabTech\Service',
        'HKLM:\SOFTWARE\LabTech\LabVNC',
        'HKLM:\SOFTWARE\WOW6432Node\LabTech\Service',
        'HKLM:\SOFTWARE\WOW6432Node\LabTech\LabVNC',
        'HKLM:\SOFTWARE\LabTechMSP'
    ) | Where-Object { Test-Path -LiteralPath $_ }
}

function Get-UserAgentRegKeys {
    # Control Center stores its own config here. Only scrub when the console is absent.
    if (Test-ControlCenterInstalled) { return @() }
    @(
        'HKCU:\SOFTWARE\LabTech\Service',
        'HKCU:\SOFTWARE\LabTech\LabVNC'
    ) | Where-Object { Test-Path -LiteralPath $_ }
}

function Get-AgentRegKeys {
    foreach ($key in @((Get-MachineAgentRegKeys) + (Get-UserAgentRegKeys))) {
        if ($key) { $key }
    }
}

function Stop-AgentHolders {
    foreach ($name in $script:AgentServiceNames) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        Write-Output ("Stop-Service " + $name + " " + [string]$svc.Status)
        & "$env:SystemRoot\System32\sc.exe" stop $name 2>&1 | ForEach-Object { Write-Output ("  " + $_) }
    }
    Start-Sleep -Seconds 3
    foreach ($proc in @(Get-AgentProcesses)) {
        Write-Output ("taskkill PID " + [string]$proc.ProcessId + " " + $proc.Name)
        & "$env:SystemRoot\System32\taskkill.exe" /F /T /PID $proc.ProcessId 2>$null | Out-Null
    }
    $dll = Join-Path (Get-AgentBase) 'wodVPN.dll'
    if (Test-Path -LiteralPath $dll) {
        Write-Output ("regsvr32 /u " + $dll)
        & "$env:SystemRoot\System32\regsvr32.exe" /u /s $dll 2>$null | Out-Null
    }
}

function Invoke-AgentMsiUninstall {
    param($Entry)
    $name = [string]$Entry.DisplayName
    $guid = [string]$Entry.PSChildName
    if ($guid -notmatch '^\{[0-9A-Fa-f-]{36}\}$') {
        Write-Output ("No MSI product code: " + $name)
        return
    }
    Write-Output ("msiexec /x " + $guid + " " + $name)
    $p = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru
    Write-Output ("msiexec exit " + [string]$p.ExitCode)
}

function Get-AgentUninstaller {
    param([string]$Server)
    $destDir = Join-Path $env:windir 'Temp\AutomateAgentUninstall'
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $dest = Join-Path $destDir 'Agent_Uninstall.exe'
    $urls = @()
    if ($Server) {
        $s = $Server.Trim().TrimEnd('/')
        $s = $s -replace '(?i)/LabTech$', ''
        if ($s -notmatch '^https?://') { $s = "https://$s" }
        $urls += ($s + '/LabTech/Service/LabUninstall.exe')
    }
    $urls += 'https://s3.amazonaws.com/assets-cp/assets/Agent_Uninstall.exe'

    foreach ($url in $urls) {
        try {
            Write-Output ("Download " + $url)
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue }
            $wc = New-Object Net.WebClient
            $wc.Headers.Add('User-Agent', 'AutomateUninstall/1.0.0')
            $wc.DownloadFile($url, $dest)
            $len = (Get-Item -LiteralPath $dest -ErrorAction SilentlyContinue).Length
            if ($len -gt 80KB) {
                Write-Output ("Uninstaller bytes " + [string]$len)
                return $dest
            }
            Write-Output ("Uninstaller too small (" + [string]$len + ")")
            Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Output ("Download failed: " + $_.Exception.Message)
        }
    }
    return $null
}

function Invoke-AgentUninstaller {
    param([string]$ExePath)
    $work = Split-Path -Parent $ExePath
    Write-Output ("Run " + $ExePath)
    $p = Start-Process -FilePath $ExePath -WorkingDirectory $work -Wait -PassThru
    Write-Output ("Agent_Uninstall.exe exit " + [string]$p.ExitCode)
    $extracted = Join-Path $work 'Uninstall.exe'
    if (Test-Path -LiteralPath $extracted) {
        Write-Output ("Run " + $extracted)
        $p2 = Start-Process -FilePath $extracted -WorkingDirectory $work -Wait -PassThru
        Write-Output ("Uninstall.exe exit " + [string]$p2.ExitCode)
    }
}

function Get-PrimaryServer {
    param([string]$Raw)
    if (-not $Raw) { return $null }
    $s = ([string](($Raw -split '\|')[0])).Trim() -replace '~', ''
    $s = $s.TrimEnd('/')
    if (-not $s) { return $null }
    if ($s -notmatch '^https?://') { $s = "https://$s" }
    return $s
}

function Test-IsMsiFile {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $item -or $item.Length -lt 1234KB) { return $false }
    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        $b = New-Object byte[] 4
        if ($fs.Read($b, 0, 4) -lt 4) { return $false }
        return ($b[0] -eq 0xD0 -and $b[1] -eq 0xCF -and $b[2] -eq 0x11 -and $b[3] -eq 0xE0)
    } catch {
        return $false
    } finally {
        if ($fs) { $fs.Dispose() }
    }
}

function Get-ReinstallDir {
    return (Join-Path $env:windir 'Temp\AutomateReinstall')
}

function Get-SavedReinstallMsi {
    $msi = Join-Path (Get-ReinstallDir) 'Agent_Install.msi'
    if (Test-IsMsiFile $msi) { return $msi }
    return $null
}

function Get-CachedAgentMsi {
    $saved = Get-SavedReinstallMsi
    if ($saved) { return $saved }

    $props = @(Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\*\Products\*\InstallProperties' -ErrorAction SilentlyContinue)
    foreach ($prop in $props) {
        $name = [string]$prop.DisplayName
        if ($name -match '(?i)ScreenConnect|ConnectWise Control|Control Center') { continue }
        if ($name -notmatch '(?i)(LabTech|ConnectWise Automate)\s+Remote Agent') { continue }
        $local = [string]$prop.LocalPackage
        if (Test-IsMsiFile $local) { return $local }
        $source = [string]$prop.InstallSource
        if ($source -match '^[A-Za-z]:\\') {
            $candidate = Join-Path $source 'Agent_Install.msi'
            if (Test-IsMsiFile $candidate) { return $candidate }
            $candidate = Join-Path $source 'LabTechRemoteAgent.msi'
            if (Test-IsMsiFile $candidate) { return $candidate }
        }
    }

    $base = Get-AgentBase
    if (Test-Path -LiteralPath $base) {
        $found = @(Get-ChildItem -LiteralPath $base -Recurse -Filter '*.msi' -ErrorAction SilentlyContinue |
            Where-Object { Test-IsMsiFile $_.FullName } |
            Select-Object -First 1)
        if ($found.Count -gt 0) { return $found[0].FullName }
    }
    return $null
}

function Copy-ReinstallMsi {
    param([string]$Source)
    if (-not (Test-IsMsiFile $Source)) { return $null }
    $dir = Get-ReinstallDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dest = Join-Path $dir 'Agent_Install.msi'
    $sourceFull = [System.IO.Path]::GetFullPath($Source)
    $destFull = [System.IO.Path]::GetFullPath($dest)
    if ($sourceFull -ne $destFull) {
        Copy-Item -LiteralPath $Source -Destination $dest -Force
    }
    $mst = Join-Path (Split-Path -Parent $Source) 'Agent_Install.mst'
    $destMst = Join-Path $dir 'Agent_Install.mst'
    if ((Test-Path -LiteralPath $mst) -and ($sourceFull -ne $destFull)) {
        Copy-Item -LiteralPath $mst -Destination $destMst -Force
    }
    if (Test-IsMsiFile $dest) { return $dest }
    return $null
}

function Save-ServerAgentMsi {
    param([string]$Server, [string]$LocationId)
    if (-not $Server) { return $null }
    $dir = Get-ReinstallDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $download = Join-Path $dir 'download.bin'
    $urls = @(
        ($Server + '/LabTech/Service/LabTechRemoteAgent.msi')
    )
    if ($LocationId -match '^\d+$') {
        $urls = @(
            ($Server + '/LabTech/Deployment.aspx?Probe=1&installType=msi&MSILocations=' + $LocationId)
        ) + $urls
    }
    foreach ($url in $urls) {
        try {
            Write-Output ("Download " + $url)
            if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue }
            $wc = New-Object Net.WebClient
            $wc.Headers.Add('User-Agent', 'AutomateUninstall/1.1.0')
            $wc.DownloadFile($url, $download)
            $len = (Get-Item -LiteralPath $download -ErrorAction SilentlyContinue).Length
            if ($len -lt 1234KB) {
                Write-Output ("Download too small (" + [string]$len + ")")
                continue
            }
            $fs = [System.IO.File]::Open($download, 'Open', 'Read', 'Read')
            $b = New-Object byte[] 2
            [void]$fs.Read($b, 0, 2)
            $fs.Dispose()
            $isZip = ($b[0] -eq 0x50 -and $b[1] -eq 0x4B)
            $isMsi = ($b[0] -eq 0xD0 -and $b[1] -eq 0xCF)
            if ($isMsi) {
                $dest = Join-Path $dir 'Agent_Install.msi'
                Copy-Item -LiteralPath $download -Destination $dest -Force
                if (Test-IsMsiFile $dest) { return $dest }
            } elseif ($isZip) {
                $extract = Join-Path $dir 'extract'
                if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue }
                Expand-Archive -LiteralPath $download -DestinationPath $extract -Force
                $msi = @(Get-ChildItem -LiteralPath $extract -Recurse -Filter '*.msi' -ErrorAction SilentlyContinue | Select-Object -First 1)
                $mst = @(Get-ChildItem -LiteralPath $extract -Recurse -Filter '*.mst' -ErrorAction SilentlyContinue | Select-Object -First 1)
                if ($msi.Count -gt 0) {
                    $copied = Copy-ReinstallMsi -Source $msi[0].FullName
                    if ($mst.Count -gt 0) {
                        Copy-Item -LiteralPath $mst[0].FullName -Destination (Join-Path $dir 'Agent_Install.mst') -Force
                    }
                    if ($copied) { return $copied }
                }
                Write-Output 'Download was a zip without a usable MSI.'
            } else {
                Write-Output 'Download was not an MSI or zip.'
            }
        } catch {
            Write-Output ("Download failed: " + $_.Exception.Message)
        }
    }
    return $null
}

function Install-SavedAgentMsi {
    param([string]$Msi, [string]$Server, [string]$LocationId)
    $log = Join-Path $env:windir 'Temp\Automate-Reinstall.msi.log'
    $argList = @('/i', $Msi, '/qn', '/norestart', '/l*v', $log)
    $mst = Join-Path (Split-Path -Parent $Msi) 'Agent_Install.mst'
    if (Test-Path -LiteralPath $mst) { $argList += ('TRANSFORMS="' + $mst + '"') }
    if ($Server) { $argList += ('SERVERADDRESS="' + $Server + '"') }
    if ($LocationId -match '^\d+$') { $argList += ('LOCATION=' + $LocationId) }
    Write-Output ("msiexec " + ($argList -join ' '))
    $p = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $argList -Wait -PassThru
    Write-Output ("msiexec exit " + [string]$p.ExitCode + " log " + $log)
    return [int]$p.ExitCode
}

function Wait-AgentService {
    $deadline = (Get-Date).AddMinutes(3)
    do {
        $svc = Get-Service -Name 'LTService' -ErrorAction SilentlyContinue
        if ($svc) { return $svc }
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)
    return $null
}

function Remove-AgentFolder {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    Write-Output ("Remove " + $Path)
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Path) {
        Write-Output ("LOCKED " + $Path)
        Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
            Select-Object -First 12 |
            ForEach-Object { Write-Output ("  " + $_.FullName) }
        Write-Output 'Reboot, then run this again.'
    }
}

Write-Output '=== ConnectWise Automate agent ==='
Write-Output 'ScreenConnect, ConnectWise Control, and Automate Control Center are not targets.'
if (Test-ControlCenterInstalled) {
    Write-Output 'Automate Control Center is installed. Its files and HKCU LabTech keys stay.'
}
if (-not (Test-IsAdmin)) {
    Write-Output 'WARNING: Not elevated. Scan may be incomplete; uninstall needs elevated PowerShell or SYSTEM.'
}

$info = Get-LabTechProps
$base = Get-AgentBase
$folderPresent = Test-Path -LiteralPath $base
$services = @(Get-AgentServices)
$procs = @(Get-AgentProcesses)
$arp = @(Get-AgentArp)
$tasks = @(Get-AgentTasks)
$regKeys = @(Get-AgentRegKeys)
$kept = @(Get-KeptRemoteTools)
$updateCache = Join-Path $env:windir 'Temp\_ltupdate'

if ($info) {
    Write-Output ("Registry: " + $info.KeyPath)
    Write-Output ("  Server " + $(if ($info.Server) { $info.Server } else { '(blank)' }))
    Write-Output ("  Version " + $(if ($info.Version) { $info.Version } else { '(blank)' }))
    Write-Output ("  ID " + $(if ($info.Id) { $info.Id } else { '(blank)' }))
    Write-Output ("  LocationID " + $(if ($info.Location) { $info.Location } else { '(blank)' }))
    Write-Output ("  Probe " + $(if ($info.Probe -eq '1') { 'yes' } else { 'no' }))
} else {
    Write-Output 'Registry HKLM\SOFTWARE\LabTech\Service: none'
}

if ($services.Count -eq 0) {
    Write-Output 'Agent services: none'
} else {
    Write-Output ("Agent services: " + [string]$services.Count)
    foreach ($svc in $services) {
        Write-Output ("  " + $svc.Name + " " + [string]$svc.Status)
    }
}

Write-Output ("Agent folder: " + $(if ($folderPresent) { $base } else { 'none' }))
Write-Output ("Update cache: " + $(if (Test-Path -LiteralPath $updateCache) { $updateCache } else { 'none' }))

Write-Output ("ARP agent entries: " + [string]$arp.Count)
foreach ($entry in $arp) {
    Write-Output ("  " + [string]$entry.DisplayName + " " + [string]$entry.DisplayVersion + " " + [string]$entry.PSChildName)
}

Write-Output ("Scheduled tasks under LTSvc: " + [string]$tasks.Count)
foreach ($task in $tasks) {
    Write-Output ("  " + $task.TaskPath + $task.TaskName)
}

if ($procs.Count -gt 0) {
    Write-Output ("Agent processes: " + [string]$procs.Count)
    foreach ($proc in $procs) {
        Write-Output ("  " + $proc.Name + " PID " + [string]$proc.ProcessId)
    }
}

Write-Output ("Left installed: " + [string]$kept.Count)
foreach ($entry in $kept) {
    Write-Output ("  " + [string]$entry.DisplayName)
}

$probe = [bool]($info -and $info.Probe -eq '1')
$present = [bool]($info -or $folderPresent -or $services.Count -gt 0 -or $arp.Count -gt 0 -or $regKeys.Count -gt 0 -or (Test-Path -LiteralPath $updateCache))
$primaryServer = $null
$locationId = $null
if ($info) {
    $primaryServer = Get-PrimaryServer $info.Server
    if ($info.Location -match '^\d+$') { $locationId = $info.Location }
}
$localMsi = Get-CachedAgentMsi
if ($localMsi) {
    Write-Output ("Cached installer: " + $localMsi)
} else {
    Write-Output 'Cached installer: none'
}

if (-not $present -and -not $localMsi) {
    Write-Output 'Automate agent not found.'
    if ($Exit) { exit 0 }
    return
}

if ($CheckOnly -or (-not $Remediate -and -not $Reinstall)) {
    if ($probe) {
        Write-Output 'Probe agent. Uninstall and reinstall stay blocked unless you pass -Force.'
    }
    if ($localMsi -and -not $present) {
        Write-Output 'Agent is gone. A saved installer remains. Re-run with -Reinstall to install it.'
    } else {
        Write-Output 'Uninstall with -Remediate. Reinstall from this PC with -Reinstall (same server and location, no token). ScreenConnect stays.'
    }
    $script:ExitCode = 1
    if ($Exit) { exit $script:ExitCode }
    return
}

if ($probe -and -not $Force) {
    Write-Output 'ERROR: Probe agent detected. Re-run with -Force if this probe should be removed.'
    $script:ExitCode = 3
    if ($Exit) { exit $script:ExitCode }
    return
}

if (-not (Test-IsAdmin)) {
    Write-Output 'ERROR: Uninstall needs elevated PowerShell or SYSTEM.'
    $script:ExitCode = 4
    if ($Exit) { exit $script:ExitCode }
    return
}

$installMsi = $null
if ($Reinstall) {
    Write-Output '=== Resolving installer from this PC ==='
    if ($primaryServer) { Write-Output ("Install server: " + $primaryServer) }
    if ($locationId) { Write-Output ("Install location: " + $locationId) }
    if ($localMsi) {
        $installMsi = Copy-ReinstallMsi -Source $localMsi
    }
    if (-not $installMsi -and $primaryServer) {
        Write-Output 'No cached MSI. Trying the Automate server recorded on this PC.'
        $installMsi = Save-ServerAgentMsi -Server $primaryServer -LocationId $locationId
    }
    if (-not $installMsi) {
        Write-Output 'ERROR: No installer on this PC, and the server download failed. Nothing was removed.'
        $script:ExitCode = 5
        if ($Exit) { exit $script:ExitCode }
        return
    }
    Write-Output ("Installer ready: " + $installMsi)
}

if (-not $present) {
    if (-not $Reinstall) {
        Write-Output 'Automate agent not found.'
        if ($Exit) { exit 0 }
        return
    }
    Write-Output 'Agent already absent. Skipping uninstall.'
} else {
Write-Output '=== Uninstalling Automate agent ==='
if ($probe) { Write-Output 'Probe override forced.' }

$server = $primaryServer
if (-not $server -and $info) { $server = $info.Server }

Stop-AgentHolders
foreach ($entry in @(Get-AgentArp)) { Invoke-AgentMsiUninstall -Entry $entry }

$uninstaller = Get-AgentUninstaller -Server $server
if ($uninstaller) {
    Invoke-AgentUninstaller -ExePath $uninstaller
} else {
    Write-Output 'Vendor uninstaller was not downloaded. Continuing with local service, file, and registry cleanup.'
}

Stop-AgentHolders

foreach ($svc in @(Get-AgentServices)) {
    Write-Output ("sc.exe delete " + $svc.Name)
    & "$env:SystemRoot\System32\sc.exe" delete $svc.Name 2>&1 | ForEach-Object { Write-Output ("  " + $_) }
}

foreach ($task in @(Get-AgentTasks)) {
    Write-Output ("Unregister-ScheduledTask " + $task.TaskPath + $task.TaskName)
    Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
}

Remove-AgentFolder -Path (Get-AgentBase)
Remove-AgentFolder -Path $updateCache
$work = Join-Path $env:windir 'Temp\AutomateAgentUninstall'
if (Test-Path -LiteralPath $work) {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

foreach ($key in @(Get-AgentRegKeys)) {
    Write-Output ("Remove " + $key)
    Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $key) { Write-Output ("  still present " + $key) }
}

$servicesLeft = @(Get-AgentServices)
$arpLeft = @(Get-AgentArp)
$regLeft = @(Get-AgentRegKeys)
$folderLeft = Test-Path -LiteralPath (Get-AgentBase)
$cacheLeft = Test-Path -LiteralPath $updateCache

Write-Output ("Services left: " + [string]$servicesLeft.Count)
foreach ($svc in $servicesLeft) { Write-Output ("  " + $svc.Name + " " + [string]$svc.Status) }
Write-Output ("ARP left: " + [string]$arpLeft.Count)
foreach ($entry in $arpLeft) { Write-Output ("  " + [string]$entry.DisplayName) }
Write-Output ("Registry keys left: " + [string]$regLeft.Count)
foreach ($key in $regLeft) { Write-Output ("  " + $key) }
Write-Output ("Folder left: " + $(if ($folderLeft) { Get-AgentBase } else { 'none' }))
Write-Output ("Update cache left: " + $(if ($cacheLeft) { $updateCache } else { 'none' }))

if (-not $Reinstall) {
    if ($servicesLeft.Count -gt 0 -or $arpLeft.Count -gt 0 -or $regLeft.Count -gt 0 -or $folderLeft -or $cacheLeft) {
        $script:ExitCode = 2
        Write-Output 'Automate leftovers remain. Reboot and run uninstall again.'
    } else {
        $script:ExitCode = 0
        Write-Output 'Automate agent removed. ScreenConnect was left installed.'
    }
    if ($Exit) { exit $script:ExitCode }
    return
}

if ($servicesLeft.Count -gt 0 -or $folderLeft) {
    Write-Output 'Uninstall left files or services behind. Install will still be attempted.'
}
}

if ($Reinstall) {
Write-Output '=== Installing Automate agent from this PC ==='
$installCode = Install-SavedAgentMsi -Msi $installMsi -Server $primaryServer -LocationId $locationId
if ($installCode -eq 3010) {
    Write-Output 'msiexec 3010 = success, reboot required.'
}
$svc = Wait-AgentService
if ($svc) {
    Write-Output ("LTService " + [string]$svc.Status)
    $after = Get-LabTechProps
    if ($after) {
        Write-Output ("  Server " + $(if ($after.Server) { $after.Server } else { '(blank)' }))
        Write-Output ("  ID " + $(if ($after.Id) { $after.Id } else { '(blank or not checked in yet)' }))
        Write-Output ("  LocationID " + $(if ($after.Location) { $after.Location } else { '(blank)' }))
    }
    Write-Output 'Automate agent reinstalled from this PC. The new check-in uses a new agent ID in the same location. ScreenConnect was left installed.'
    $script:ExitCode = 0
} else {
    Write-Output 'ERROR: LTService did not appear after install. The saved MSI is still in Temp\AutomateReinstall. Reboot and run -Reinstall again.'
    $script:ExitCode = 2
}

if ($Exit) { exit $script:ExitCode }
}
