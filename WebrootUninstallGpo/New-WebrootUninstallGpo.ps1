<#
.SYNOPSIS
    Create a GPO Immediate Task that silently uninstalls Webroot
    (OpenText Core Endpoint Protection) when WRSA.exe is present.

.DESCRIPTION
    Run as Domain Admin from a DC or RSAT box joined to the client domain.

    Native GPO Software Installation cannot uninstall Webroot unless that same
    MSI was originally assigned by GPO. This publishes a Group Policy
    Preferences Immediate Task (Windows 7+) that runs as SYSTEM at the next
    gpupdate — no reboot required to start. WRSA.exe -uninstall -silent.

    The script skips hosts that no longer have WRSA.exe. After a successful
    uninstall it removes leftover ProgramData\WRData and WRCore. It does not
    reboot and does not do a full remnant sweep (use windows-av-cleanup for
    leftovers).

    Do not put a live client DNS name or keycode in git. Pass -Domain at run
    time. A keycode written into the cmd on SYSVOL is readable by domain
    computers.

.PARAMETER Domain
    AD DNS name. Defaults to the current domain.

.PARAMETER TargetOU
    Distinguished name of the OU to link. Example: OU=Workstations,DC=contoso,DC=com

.PARAMETER LinkToDomain
    Link the GPO at the domain root. Adds a workstation-only WMI filter unless
    -SkipWmiFilter is set.

.PARAMETER SkipWmiFilter
    Do not create or attach the workstation WMI filter.

.PARAMETER SkipLink
    Create the GPO but do not link it.

.PARAMETER GpoName
    Override the GPO name. Default: Uninstall Webroot

.PARAMETER KeyCode
    Optional Webroot keycode. When set, the Immediate Task cmd also tries
    -uninstall -silent -keycode. SYSVOL is readable by domain computers —
    leave blank unless uninstall fails without it.

.PARAMETER DryRun
    Print the planned GPO and uninstall cmd. Do not write AD or SYSVOL.

.PARAMETER Exit
    Accepted for ScToolLauncher Commands pastes. Ignored.

.PARAMETER NoExit
    Accepted for ScToolLauncher PowerShell pastes. Ignored.

.EXAMPLE
    # On the client DC (download from mytools and run):
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object Net.WebClient
    $wc.Headers.Add('User-Agent', 'WebrootUninstallGpo-bootstrap/1.0')
    $wc.Headers.Add('Accept', 'application/vnd.github.raw')
    $script = $wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WebrootUninstallGpo/New-WebrootUninstallGpo.ps1?ref=main')
    & ([ScriptBlock]::Create($script)) -Domain 'contoso.com' -LinkToDomain
#>

[CmdletBinding()]
param(
    [string]$Domain,

    [string]$TargetOU,

    [switch]$LinkToDomain,

    [switch]$SkipWmiFilter,

    [switch]$SkipLink,

    [string]$GpoName = 'Uninstall Webroot',

    [string]$KeyCode,

    [switch]$DryRun,

    [switch]$Exit,

    [switch]$NoExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:WmiFilterName = 'Windows Workstations (ProductType=1)'
$script:GppSchedCse = '[{AADCED64-746C-4633-A97C-D80500FC4251}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}]'
$script:TaskUid = '{B7E2C41A-6F3D-4A91-9C18-2E8A0D5B4F11}'
$null = $Exit
$null = $NoExit

function Write-Step {
    param([string]$Message)
    Write-Host $Message
}

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$id
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-WebrootUninstallCmd {
    param([string]$UninstallKeyCode)

    $keyLine = ''
    if ($UninstallKeyCode) {
        $esc = $UninstallKeyCode.Replace('"', '')
        $keyLine = @"
if exist "%WRSA%" (
  echo %DATE% %TIME% retry with keycode>>"%LOG%"
  "%WRSA%" -uninstall -silent -keycode $esc
  echo %DATE% %TIME% keycode uninstall exit %ERRORLEVEL%>>"%LOG%"
)

"@
    }

    return @"
@echo off
set LOG=%SystemRoot%\Temp\Webroot-GPO-Uninstall.log
echo %DATE% %TIME% startup script began>>"%LOG%"

set WRSA=
if exist "%ProgramFiles(x86)%\Webroot\WRSA.exe" set WRSA=%ProgramFiles(x86)%\Webroot\WRSA.exe
if not defined WRSA if exist "%ProgramFiles%\Webroot\WRSA.exe" set WRSA=%ProgramFiles%\Webroot\WRSA.exe

if not defined WRSA (
  echo %DATE% %TIME% WRSA.exe not found. Nothing to do.>>"%LOG%"
  exit /b 0
)

echo %DATE% %TIME% Uninstalling "%WRSA%">>"%LOG%"
"%WRSA%" -uninstall -silent
echo %DATE% %TIME% uninstall exit %ERRORLEVEL%>>"%LOG%"
$keyLine
if exist "%WRSA%" (
  echo %DATE% %TIME% WRSA.exe still present. Reboot and/or run windows-av-cleanup.>>"%LOG%"
  exit /b 1
)

if exist "%ProgramData%\WRData" rd /s /q "%ProgramData%\WRData"
if exist "%ProgramData%\WRCore" rd /s /q "%ProgramData%\WRCore"
echo %DATE% %TIME% Webroot uninstalled. Reboot recommended.>>"%LOG%"
exit /b 0
"@
}

function Merge-GpoExtensionNames {
    param([string]$Existing, [string]$Add)
    $pairs = @()
    if ($Existing) {
        $pairs += [regex]::Matches($Existing, '\[\{[0-9A-Fa-f-]+\}\{[0-9A-Fa-f-]+\}\]') | ForEach-Object { $_.Value }
    }
    if ($pairs -notcontains $Add) { $pairs += $Add }
    return (($pairs | Sort-Object) -join '')
}

function Set-GpoImmediateTask {
    param(
        $Gpo,
        [string]$DnsRoot,
        [string]$DomainDN,
        [string]$CmdName,
        [string]$CmdText
    )

    $policyRoot = "\\$DnsRoot\SYSVOL\$DnsRoot\Policies\{$($Gpo.Id)}"
    $scriptDir = Join-Path $policyRoot 'Machine\Scripts'
    $prefDir = Join-Path $policyRoot 'Machine\Preferences\ScheduledTasks'
    New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
    New-Item -ItemType Directory -Path $prefDir -Force | Out-Null
    Set-Content -Path (Join-Path $scriptDir $CmdName) -Value $CmdText -Encoding Ascii

    $startupIni = Join-Path $scriptDir 'scripts.ini'
    if (Test-Path -LiteralPath $startupIni) {
        Remove-Item -LiteralPath $startupIni -Force
    }

    $cmdUnc = "\\$DnsRoot\SYSVOL\$DnsRoot\Policies\{$($Gpo.Id)}\Machine\Scripts\$CmdName"
    $cmdEsc = [System.Security.SecurityElement]::Escape($cmdUnc)
    $changed = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<ScheduledTasks clsid="{CC63F200-7309-4ba0-B154-A71CD118DBCC}">
	<ImmediateTaskV2 clsid="{9756B581-76EC-451C-9E12-DFF9B5CA5C32}" name="Uninstall Webroot" image="2" changed="$changed" uid="$($script:TaskUid)" userContext="0" removePolicy="0">
		<Properties action="C" name="Uninstall Webroot" runAs="NT AUTHORITY\System" logonType="S4U">
			<Task version="1.3">
				<RegistrationInfo>
					<Author>NT AUTHORITY\System</Author>
					<Description>Silent Webroot / OpenText CEP uninstall when WRSA.exe is present</Description>
				</RegistrationInfo>
				<Principals>
					<Principal id="Author">
						<UserId>S-1-5-18</UserId>
						<RunLevel>HighestAvailable</RunLevel>
					</Principal>
				</Principals>
				<Settings>
					<IdleSettings>
						<Duration>PT10M</Duration>
						<WaitTimeout>PT1H</WaitTimeout>
						<StopOnIdleEnd>false</StopOnIdleEnd>
						<RestartOnIdle>false</RestartOnIdle>
					</IdleSettings>
					<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
					<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
					<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
					<AllowHardTerminate>false</AllowHardTerminate>
					<StartWhenAvailable>true</StartWhenAvailable>
					<RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
					<AllowStartOnDemand>true</AllowStartOnDemand>
					<Enabled>true</Enabled>
					<Hidden>false</Hidden>
					<RunOnlyIfIdle>false</RunOnlyIfIdle>
					<WakeToRun>false</WakeToRun>
					<ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
					<Priority>7</Priority>
					<DeleteExpiredTaskAfter>PT0S</DeleteExpiredTaskAfter>
				</Settings>
				<Actions Context="Author">
					<Exec>
						<Command>cmd.exe</Command>
						<Arguments>/c "$cmdEsc"</Arguments>
					</Exec>
				</Actions>
			</Task>
		</Properties>
	</ImmediateTaskV2>
</ScheduledTasks>
"@
    $utf8 = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText((Join-Path $prefDir 'ScheduledTasks.xml'), $xml, $utf8)

    $adPath = "CN={$($Gpo.Id)},CN=Policies,CN=System,$DomainDN"
    $obj = Get-ADObject -Identity $adPath -Properties versionNumber, gPCMachineExtensionNames
    $ver = [int]($obj.versionNumber)
    $userVer = $ver -shr 16
    $machineVer = ($ver -band 0xFFFF) + 1
    if ($machineVer -gt 65535) { $machineVer = 1 }
    $newVer = ($userVer -shl 16) + $machineVer
    $merged = Merge-GpoExtensionNames -Existing ([string]$obj.gPCMachineExtensionNames) -Add $script:GppSchedCse

    Set-ADObject -Identity $adPath -Replace @{
        versionNumber            = $newVer
        gPCMachineExtensionNames = $merged
    }

    $gptPath = Join-Path $policyRoot 'GPT.INI'
    if (Test-Path -LiteralPath $gptPath) {
        $gpt = Get-Content -LiteralPath $gptPath -Raw
        if ($gpt -match 'Version=\d+') {
            $gpt = $gpt -replace 'Version=\d+', "Version=$newVer"
        }
        else {
            $gpt = "[General]`r`nVersion=$newVer`r`n"
        }
        Set-Content -LiteralPath $gptPath -Value $gpt.TrimEnd() -Encoding Ascii
    }
}

function Resolve-WmiFilter {
    param([string]$DomainDN, [string]$Name)

    $searchBase = "CN=SOM,CN=WMIPolicy,CN=System,$DomainDN"
    $existing = Get-ADObject -SearchBase $searchBase -LDAPFilter "(msWMI-Name=$Name)" -Properties 'msWMI-Name', 'msWMI-ID' -ErrorAction SilentlyContinue
    if ($existing) { return $existing }

    $guid = [guid]::NewGuid()
    $guidBrace = "{$guid}"
    $now = (Get-Date).ToUniversalTime()
    $stamp = $now.ToString('yyyyMMddHHmmss.ffffff') + '-000'
    $author = "$env:USERDOMAIN\$env:USERNAME"
    $query = 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1'
    $parm2 = "1;3;10;$($query.Length);WQL;root\CIMv2;$query;"

    New-ADObject -Name $guidBrace -Type 'msWMI-Som' -Path $searchBase -OtherAttributes @{
        'msWMI-Name'             = $Name
        'msWMI-Parm1'            = 'Computer is a workstation (not a server or DC). '
        'msWMI-Parm2'            = $parm2
        'msWMI-Author'           = $author
        'msWMI-ID'               = $guidBrace
        'instanceType'           = 4
        'showInAdvancedViewOnly' = $true
        'msWMI-ChangeDate'       = $stamp
        'msWMI-CreationDate'     = $stamp
    } | Out-Null

    return Get-ADObject -SearchBase $searchBase -LDAPFilter "(msWMI-Name=$Name)" -Properties 'msWMI-Name', 'msWMI-ID'
}

if (-not (Test-IsAdministrator)) {
    throw 'Run this script elevated as a Domain Admin (or equivalent GPO/SYSVOL rights).'
}

$KeyCode = if ($KeyCode) { $KeyCode.Trim() } else { '' }
$cmdName = 'Uninstall-Webroot.cmd'
$cmdText = New-WebrootUninstallCmd -UninstallKeyCode $KeyCode

Write-Step '=== Webroot uninstall GPO ==='
if ($DryRun) { Write-Step 'Mode: DRY-RUN (no AD/SYSVOL writes)' }

if (-not $Domain) {
    $Domain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name
}

if (-not $DryRun) {
    foreach ($mod in @('ActiveDirectory', 'GroupPolicy')) {
        if (-not (Get-Module -ListAvailable -Name $mod)) {
            throw "Required module '$mod' is missing. Install RSAT or run this on a domain controller."
        }
        Import-Module $mod -ErrorAction Stop
    }
    $adDomain = Get-ADDomain -Identity $Domain
    $dnsRoot = $adDomain.DNSRoot
    $domainDN = $adDomain.DistinguishedName
}
else {
    $dnsRoot = $Domain
    $domainDN = ($Domain -split '\.' | ForEach-Object { "DC=$_" }) -join ','
}

Write-Step "  Domain:  $dnsRoot"
Write-Step "  GPO:     $GpoName"
if ($KeyCode) {
    Write-Step '  Keycode: set (will be written to SYSVOL — readable by domain computers)'
}
else {
    Write-Step '  Keycode: not set (SYSTEM -uninstall -silent only)'
}
Write-Step ''

if ($DryRun) {
    Write-Step '[DRY RUN] Immediate Task cmd that would be published:'
    Write-Host $cmdText
    Write-Step '          Re-run without -DryRun to create the GPO.'
    return
}

Write-Step "[1/3] Creating or updating GPO '$GpoName'..."
$gpo = Get-GPO -Name $GpoName -Domain $dnsRoot -ErrorAction SilentlyContinue
if (-not $gpo) {
    $gpo = New-GPO -Name $GpoName -Domain $dnsRoot -Comment 'Silent Webroot / OpenText CEP uninstall (WRSA.exe -uninstall -silent) when present'
}

Set-GPRegistryValue -Name $GpoName -Domain $dnsRoot -Key 'HKLM\Software\Policies\Microsoft\Windows NT\CurrentVersion\Winlogon' -ValueName 'SyncForegroundPolicy' -Type DWord -Value 1 | Out-Null

Set-GpoImmediateTask -Gpo $gpo -DnsRoot $dnsRoot -DomainDN $domainDN -CmdName $cmdName -CmdText $cmdText

$linkTarget = $null
if ($TargetOU) {
    $linkTarget = $TargetOU
}
elseif ($LinkToDomain) {
    $linkTarget = $domainDN
}

if ($linkTarget -and -not $SkipLink) {
    if ($LinkToDomain -and -not $TargetOU -and -not $SkipWmiFilter) {
        Write-Step "       Attaching WMI filter '$($script:WmiFilterName)'..."
        try {
            $wmi = Resolve-WmiFilter -DomainDN $domainDN -Name $script:WmiFilterName
            $wmiId = [string]$wmi.'msWMI-ID'
            if (-not $wmiId) { $wmiId = $wmi.Name }
            if ($wmiId -notmatch '^\{') { $wmiId = "{$wmiId}" }
            $gpoDn = "CN={$($gpo.Id)},CN=Policies,CN=System,$domainDN"
            Set-ADObject -Identity $gpoDn -Replace @{ gPCWQLFilter = "[$dnsRoot;$wmiId]" }
        }
        catch {
            Write-Warning "WMI filter was not attached: $($_.Exception.Message)"
        }
    }

    Write-Step "[2/3] Linking GPO to $linkTarget"
    try {
        New-GPLink -Name $GpoName -Domain $dnsRoot -Target $linkTarget -LinkEnabled Yes -ErrorAction Stop | Out-Null
    }
    catch {
        if ($_.Exception.Message -match 'already linked|already exists') {
            Write-Step '       Link already exists.'
        }
        else {
            throw
        }
    }
}
else {
    Write-Step '[2/3] GPO created but not linked. Pass -TargetOU or -LinkToDomain.'
}

Write-Step '[3/3] Done'
Write-Step ''
Write-Step "[OK] $GpoName"
Write-Step '     Immediate Task runs WRSA.exe -uninstall -silent when present (SYSTEM, next gpupdate).'
Write-Step '     On a test PC: gpupdate /force — no reboot required to start. Webroot may still need a reboot to finish.'
Write-Step '     Log: C:\Windows\Temp\Webroot-GPO-Uninstall.log'
Write-Step '     Pilot: security-filter the GPO to a test computer group before a wide link.'
Write-Step '     Leftovers: windows-av-cleanup -Delete -Vendor Webroot'
