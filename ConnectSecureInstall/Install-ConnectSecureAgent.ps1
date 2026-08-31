#Requires -Version 5.1
<#
.SYNOPSIS
    Silent-install ConnectSecure (CyberCNS) Windows agent.

.DESCRIPTION
    Downloads the current Windows agent from the ConnectSecure agentlink API and
    installs with -c / -e / -j / -i.

    Leftover (not Running) CyberCNS services are removed with the same
    uninstall.bat sequence the vendor ships, so install does not fail with
    "service CyberCNSAgent already exists".

    Never hardcode real company/env/token values. Pass them at run time.

.PARAMETER CompanyId
    Installer -c value (company id).

.PARAMETER EnvironmentId
    Installer -e value (environment id).

.PARAMETER InstallToken
    Installer -j value (install JWT / token). Never commit real tokens to git.

.PARAMETER Exit
    Call exit with a status code (ScreenConnect Commands). Omit in Backstage.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CompanyId,

    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [Parameter(Mandatory = $true)]
    [string]$InstallToken,

    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$script:ExitCode = 0

function Write-Section([string]$Message) {
    Write-Output "=== $Message ==="
}

function Get-CyberCnsServices {
    $byCim = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.PathName -like '*cybercns*' -or $_.Name -like 'CyberCNS*' -or $_.Name -like 'ConnectSecure*' })
    $names = @('CyberCNSAgent', 'CyberCNSAgentMonitor', 'ConnectSecureAgentMonitor')
    $byName = foreach ($n in $names) {
        Get-Service -Name $n -ErrorAction SilentlyContinue
    }
    @($byCim + $byName) | Sort-Object Name -Unique
}

function Invoke-Sc([string[]]$ScArgs) {
    $out = & sc.exe @ScArgs 2>&1 | Out-String
    $out = $out.Trim()
    if ($out) { Write-Output $out }
}

function Invoke-CyberCnsUninstallBat {
    $pf86 = ${env:ProgramFiles(x86)}
    if (-not $pf86) { $pf86 = 'C:\Program Files (x86)' }
    $folder = Join-Path $pf86 'CyberCNSAgent'
    $exe = Join-Path $folder 'cybercnsagent.exe'

    Write-Section 'Vendor uninstall.bat sequence'
    Write-Output 'Wait 5 seconds'
    Start-Sleep -Seconds 5

    Invoke-Sc @('stop', 'CyberCNSAgentMonitor')
    Start-Sleep -Seconds 5
    Invoke-Sc @('delete', 'CyberCNSAgentMonitor')

    Start-Sleep -Seconds 5
    Invoke-Sc @('stop', 'CyberCNSAgent')
    Start-Sleep -Seconds 5
    Invoke-Sc @('delete', 'CyberCNSAgent')
    Start-Sleep -Seconds 5

    foreach ($im in @('osqueryi.exe', 'nmap.exe', 'cyberutilities.exe')) {
        Write-Output ("taskkill /IM {0} /F" -f $im)
        $tk = & taskkill.exe /IM $im /F 2>&1 | Out-String
        if ($tk.Trim()) { Write-Output $tk.Trim() }
    }

    if (Test-Path -LiteralPath $exe) {
        Write-Output 'cybercnsagent.exe --internalAssetArgument uninstallservice'
        Push-Location $pf86
        try {
            & $exe --internalAssetArgument uninstallservice
        }
        finally {
            Pop-Location
        }
    }
    else {
        Write-Output ("Agent exe not found at {0}; skipping uninstallservice" -f $exe)
    }

    if (Test-Path -LiteralPath $folder) {
        Write-Output ("rmdir {0} /s /q" -f $folder)
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    }

    Remove-CyberCnsGhostServices
}

function Remove-CyberCnsGhostServices {
    Write-Section 'Removing leftover CyberCNS service records (ghost / Failed to Read Description)'
    $names = @('CyberCNSAgent', 'CyberCNSAgentMonitor', 'ConnectSecureAgentMonitor')
    foreach ($n in $names) {
        Invoke-Sc @('stop', $n)
        Invoke-Sc @('delete', $n)
        $cim = Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue
        if ($cim) {
            try { $cim | Invoke-CimMethod -MethodName Delete -ErrorAction Stop | Out-Null } catch { }
        }
        foreach ($set in @('CurrentControlSet', 'ControlSet001', 'ControlSet002')) {
            $reg = "HKLM:\SYSTEM\$set\Services\$n"
            if (Test-Path -LiteralPath $reg) {
                Write-Output ("Removing {0}" -f $reg)
                Remove-Item -LiteralPath $reg -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Start-Sleep -Seconds 2
}

if ([string]::IsNullOrWhiteSpace($CompanyId) -or
    [string]::IsNullOrWhiteSpace($EnvironmentId) -or
    [string]::IsNullOrWhiteSpace($InstallToken)) {
    Write-Output 'ERROR: -CompanyId, -EnvironmentId, and -InstallToken are required.'
    $script:ExitCode = 2
    if ($Exit) { exit $script:ExitCode }
    return
}

$existing = @(Get-CyberCnsServices)
$running = @($existing | Where-Object { $_.State -eq 'Running' })
if ($running.Count -gt 0) {
    Write-Output 'CyberCNS service already Running. Use ConnectSecure agent repair to wipe + reinstall.'
    $existing | Format-Table Name, State, StartMode, PathName -AutoSize | Out-String | Write-Output
    $script:ExitCode = 0
    if ($Exit) { exit $script:ExitCode }
    return
}

if ($existing.Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $(if (${env:ProgramFiles(x86)}) { ${env:ProgramFiles(x86)} } else { $env:ProgramFiles }) 'CyberCNSAgent'))) {
    Write-Section 'Leftover CyberCNS install found (not running). Running uninstall.bat steps first'
    $existing | Format-Table Name, State, StartMode, PathName -AutoSize | Out-String | Write-Output
    Invoke-CyberCnsUninstallBat
    $left = @(Get-CyberCnsServices)
    if ($left.Count -gt 0) {
        Write-Output 'ERROR: leftover CyberCNS service still registered. Reboot, then run ConnectSecure agent repair.'
        $left | Format-Table Name, State, PathName -AutoSize | Out-String | Write-Output
        $script:ExitCode = 3
        if ($Exit) { exit $script:ExitCode }
        return
    }
}

$installerPath = 'C:\cybercnsagent.exe'

Write-Section 'Downloading Windows agent from ConnectSecure agentlink'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    $source = Invoke-RestMethod -Method Get -Uri 'https://configuration.myconnectsecure.com/api/v4/configuration/agentlink?ostype=windows'
    Invoke-WebRequest -Uri $source -OutFile $installerPath -UseBasicParsing
}
catch {
    Write-Output ("ERROR: download failed: {0}" -f $_.Exception.Message)
    $script:ExitCode = 4
    if ($Exit) { exit $script:ExitCode }
    return
}

Write-Section 'Installing agent (-c / -e / -j / -i)'
& $installerPath -c $CompanyId -e $EnvironmentId -j $InstallToken -i
$installExit = $LASTEXITCODE

Write-Section 'Done. Checking CyberCNS services'
Get-CyberCnsServices |
    Format-Table Name, State, StartMode, PathName -AutoSize |
    Out-String |
    Write-Output

if ($installExit -and $installExit -ne 0) {
    $script:ExitCode = $installExit
}
else {
    $script:ExitCode = 0
}

if ($Exit) { exit $script:ExitCode }
