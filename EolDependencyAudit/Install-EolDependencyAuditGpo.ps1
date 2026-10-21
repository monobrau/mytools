#Requires -Version 5.1
<#
.SYNOPSIS
    Stage the EOL dependency script on NETLOGON and run it from a GPO.

.DESCRIPTION
    Run elevated as a Domain Admin on a DC or RSAT box. The Immediate Task
    runs the same Invoke-EolDependencyAudit.ps1 switches this script receives.
    Watch and Enable also set Audit File System success in the GPO. Measure
    does not. A repeating sample is refused; run -SampleMinutes on one PC.

.PARAMETER Action
    Measure, Enable, Collect, Disable, or Watch. Default Watch.

.PARAMETER Dependency
    Same names as the endpoint script. Omit for the built-in EOL set.

.PARAMETER MaxDailyLogMB
    Passed through. Default 64.

.PARAMETER SinceHours
    Passed through. Default 24.

.PARAMETER TargetOU
    Distinguished name to link.

.PARAMETER LinkToDomain
    Link at the domain root. Prefer a pilot OU.

.EXAMPLE
    .\Install-EolDependencyAuditGpo.ps1 -Action Watch -Dependency VC2012 -TargetOU 'OU=Workstations,DC=contoso,DC=com' -DryRun
#>
[CmdletBinding()]
param(
    [ValidateSet('Measure', 'Enable', 'Collect', 'Disable', 'Watch')]
    [string]$Action = 'Watch',
    [string[]]$Dependency,
    [int]$MaxDailyLogMB = 64,
    [int]$SinceHours = 24,
    [switch]$Force,
    [string]$Domain,
    [string]$TargetOU,
    [switch]$LinkToDomain,
    [switch]$SkipLink,
    [string]$GpoName,
    [string]$ScriptPath,
    [switch]$DryRun
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$script:GppSchedCse = '[{AADCED64-746C-4633-A97C-D80500FC4251}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}]'
$script:AuditCse = '[{F3CCC681-B74C-4060-9F26-CD84525DCA2A}{0F3F3735-573D-9804-99E4-AB2A69BA5FD4}]'
$script:TaskUid = '{C4E8A1B2-7D35-4F90-8A16-6E2B9D04C7A1}'

function Write-Step { param([string]$Message) Write-Host $Message }

function Grant-DeployNtfs {
    param([string]$Path, [string]$Netbios)
    $grants = @(
        "$Netbios\Domain Computers:(OI)(CI)RX"
        'Authenticated Users:(OI)(CI)RX'
        "$Netbios\Domain Admins:(OI)(CI)F"
        'SYSTEM:(OI)(CI)F'
    )
    foreach ($grant in $grants) {
        & icacls.exe $Path '/grant' $grant '/T' '/C' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "icacls failed on $Path for $grant (exit $LASTEXITCODE)" }
    }
}

function Merge-GpoExtensionNames {
    param([string]$Existing, [string[]]$Add)
    $pairs = @()
    if ($Existing) {
        $pairs += [regex]::Matches($Existing, '\[\{[0-9A-Fa-f-]+\}\{[0-9A-Fa-f-]+\}\]') | ForEach-Object { $_.Value }
    }
    foreach ($item in $Add) {
        if ($pairs -notcontains $item) { $pairs += $item }
    }
    return (($pairs | Sort-Object) -join '')
}

function Set-GpoImmediateTask {
    param($Gpo, [string]$DnsRoot, [string]$DomainDN, [string]$CmdName, [string]$CmdText, [string[]]$Extensions)
    $policyRoot = "\\$DnsRoot\SYSVOL\$DnsRoot\Policies\{$($Gpo.Id)}"
    $scriptDir = Join-Path $policyRoot 'Machine\Scripts'
    $prefDir = Join-Path $policyRoot 'Machine\Preferences\ScheduledTasks'
    New-Item -ItemType Directory -Path $scriptDir, $prefDir -Force | Out-Null
    Set-Content -Path (Join-Path $scriptDir $CmdName) -Value $CmdText -Encoding Ascii

    $cmdUnc = "\\$DnsRoot\SYSVOL\$DnsRoot\Policies\{$($Gpo.Id)}\Machine\Scripts\$CmdName"
    $cmdEsc = [System.Security.SecurityElement]::Escape($cmdUnc)
    $changed = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<ScheduledTasks clsid="{CC63F200-7309-4ba0-B154-A71CD118DBCC}">
	<ImmediateTaskV2 clsid="{9756B581-76EC-451C-9E12-DFF9B5CA5C32}" name="EOL dependency audit" image="2" changed="$changed" uid="$($script:TaskUid)" userContext="0" removePolicy="0">
		<Properties action="U" name="EOL dependency audit" runAs="NT AUTHORITY\System" logonType="S4U">
			<Task version="1.3">
				<RegistrationInfo>
					<Author>NT AUTHORITY\System</Author>
					<Description>Measure Security-log pace and audit EOL runtime sentinel DLLs. Hit counts only.</Description>
				</RegistrationInfo>
				<Principals>
					<Principal id="Author">
						<UserId>S-1-5-18</UserId>
						<RunLevel>HighestAvailable</RunLevel>
					</Principal>
				</Principals>
				<Settings>
					<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
					<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
					<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
					<AllowHardTerminate>false</AllowHardTerminate>
					<StartWhenAvailable>true</StartWhenAvailable>
					<RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>
					<AllowStartOnDemand>true</AllowStartOnDemand>
					<Enabled>true</Enabled>
					<Hidden>true</Hidden>
					<RunOnlyIfIdle>false</RunOnlyIfIdle>
					<WakeToRun>false</WakeToRun>
					<ExecutionTimeLimit>PT30M</ExecutionTimeLimit>
					<Priority>7</Priority>
				</Settings>
				<Actions Context="Author">
					<Exec>
						<Command>C:\Windows\System32\cmd.exe</Command>
						<Arguments>/c &quot;$cmdEsc&quot;</Arguments>
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
    $ver = [int]$obj.versionNumber
    $userVer = $ver -shr 16
    $machineVer = ($ver -band 0xFFFF) + 1
    if ($machineVer -gt 65535) { $machineVer = 1 }
    $newVer = ($userVer -shl 16) + $machineVer
    $merged = Merge-GpoExtensionNames -Existing ([string]$obj.gPCMachineExtensionNames) -Add $Extensions
    Set-ADObject -Identity $adPath -Replace @{
        versionNumber            = $newVer
        gPCMachineExtensionNames = $merged
    }
    $gptPath = Join-Path $policyRoot 'GPT.INI'
    if (Test-Path -LiteralPath $gptPath) {
        $gpt = Get-Content -LiteralPath $gptPath -Raw
        if ($gpt -match 'Version=\d+') { $gpt = $gpt -replace 'Version=\d+', "Version=$newVer" }
        else { $gpt = "[General]`r`nVersion=$newVer`r`n" }
        Set-Content -LiteralPath $gptPath -Value $gpt.TrimEnd() -Encoding Ascii
    }
}

function Set-GpoFileSystemAudit {
    param($Gpo, [string]$DnsRoot, [bool]$Enable)
    $auditDir = "\\$DnsRoot\SYSVOL\$DnsRoot\Policies\{$($Gpo.Id)}\Machine\Microsoft\Windows NT\Audit"
    $auditFile = Join-Path $auditDir 'audit.csv'
    if (-not $Enable) {
        if (Test-Path -LiteralPath $auditFile) { Remove-Item -LiteralPath $auditFile -Force }
        return
    }
    New-Item -ItemType Directory -Path $auditDir -Force | Out-Null
    $csv = "Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value`r`n,System,File System,{0cce921d-69ae-11d9-bed3-505054503030},Success,,1`r`n"
    $utf16 = New-Object System.Text.UnicodeEncoding $false, $true
    [System.IO.File]::WriteAllText($auditFile, $csv, $utf16)
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script elevated as a Domain Admin.'
}

$names = @()
foreach ($item in $Dependency) {
    foreach ($part in ([string]$item -split '[,\s;]+')) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $token = $part.Trim()
        if ($token -notmatch '^[A-Za-z][A-Za-z0-9]{0,31}$') { throw "Dependency name is not valid: $token" }
        $names += $token
    }
}
if ($MaxDailyLogMB -lt 1) { throw '-MaxDailyLogMB must be at least 1.' }
if ($SinceHours -lt 1) { throw '-SinceHours must be at least 1.' }

if (-not $ScriptPath) { $ScriptPath = Join-Path $PSScriptRoot 'Invoke-EolDependencyAudit.ps1' }
if (-not (Test-Path -LiteralPath $ScriptPath)) { throw "Endpoint script not found: $ScriptPath" }
$catalogSource = Join-Path (Split-Path -Parent $ScriptPath) 'dependencies.csv'
$hasCatalog = Test-Path -LiteralPath $catalogSource

foreach ($mod in @('ActiveDirectory', 'GroupPolicy')) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        throw "Required module '$mod' is missing. Install RSAT or run this on a domain controller."
    }
    Import-Module $mod -ErrorAction Stop
}

if (-not $Domain) {
    $Domain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name
}
$adDomain = Get-ADDomain -Identity $Domain
$dnsRoot = $adDomain.DNSRoot
$domainDN = $adDomain.DistinguishedName
if (-not $GpoName) { $GpoName = 'EOL dependency audit' }
$packageUnc = "\\$dnsRoot\NETLOGON\EolDependencyAudit"
$stagedScript = Join-Path $packageUnc 'Invoke-EolDependencyAudit.ps1'
$stagedCatalog = Join-Path $packageUnc 'dependencies.csv'

$depArg = ''
if ($names.Count -gt 0) { $depArg = " -Dependency $($names -join ',')" }
$forceArg = ''
if ($Force) { $forceArg = ' -Force' }
$catalogArg = ''
if ($hasCatalog) { $catalogArg = " -CatalogPath '$stagedCatalog'" }
$psArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$stagedScript`" -Action $Action$depArg -MaxDailyLogMB $MaxDailyLogMB -SinceHours $SinceHours$forceArg$catalogArg -Exit"
$armAudit = ($Action -eq 'Watch' -or $Action -eq 'Enable')

Write-Step '=== EOL dependency GPO ==='
Write-Step "  Domain: $dnsRoot"
Write-Step "  GPO:    $GpoName"
Write-Step "  Action: $Action"
Write-Step "  Cap:    $MaxDailyLogMB MB/day of current 4663 traffic"
if ($names.Count -eq 0) { Write-Step '  Families: built-in EOL set' }
else { Write-Step "  Families: $($names -join ', ')" }
Write-Step "  Script: $stagedScript"
if ($armAudit) { Write-Step '  Audit policy: File System success in this GPO' }
else { Write-Step '  Audit policy: not changed by this action' }
Write-Step '  The task stores process hit counts. It does not export event messages.'
if ($DryRun) { Write-Step 'Mode: DRY-RUN (no SYSVOL/GPO writes)' }

$cmdText = @"
@echo off
if not exist "%ProgramData%\EolDependencyAudit" mkdir "%ProgramData%\EolDependencyAudit"
echo %DATE% %TIME% $Action began>>"%ProgramData%\EolDependencyAudit\gpo-task.log"
powershell.exe $psArgs
echo %DATE% %TIME% exit %ERRORLEVEL%>>"%ProgramData%\EolDependencyAudit\gpo-task.log"
"@

if ($DryRun) {
    Write-Step ''
    Write-Step '[DRY RUN] Would stage the script and create the Immediate Task:'
    Write-Step "          powershell.exe $psArgs"
    return
}

Write-Step '[1/3] Staging script'
New-Item -ItemType Directory -Path $packageUnc -Force | Out-Null
Copy-Item -LiteralPath $ScriptPath -Destination $stagedScript -Force
if ($hasCatalog) { Copy-Item -LiteralPath $catalogSource -Destination $stagedCatalog -Force }
Grant-DeployNtfs -Path $packageUnc -Netbios $adDomain.NetBIOSName

Write-Step "[2/3] Creating or updating GPO '$GpoName'"
$gpo = Get-GPO -Name $GpoName -Domain $dnsRoot -ErrorAction SilentlyContinue
if (-not $gpo) {
    $gpo = New-GPO -Name $GpoName -Domain $dnsRoot -Comment 'EOL runtime sentinel audit. Hit counts only.'
}
Set-GPPermission -Name $GpoName -Domain $dnsRoot -TargetName 'Authenticated Users' -TargetType Group -PermissionLevel GpoApply -Confirm:$false | Out-Null
Set-GPPermission -Name $GpoName -Domain $dnsRoot -TargetName 'Domain Computers' -TargetType Group -PermissionLevel GpoApply -Confirm:$false | Out-Null
$extensions = @($script:GppSchedCse)
if ($armAudit) { $extensions += $script:AuditCse }
Set-GpoImmediateTask -Gpo $gpo -DnsRoot $dnsRoot -DomainDN $domainDN -CmdName 'Invoke-EolDependencyAudit.cmd' -CmdText $cmdText -Extensions $extensions
Set-GpoFileSystemAudit -Gpo $gpo -DnsRoot $dnsRoot -Enable $armAudit
$policyRoot = "\\$dnsRoot\SYSVOL\$dnsRoot\Policies\{$($gpo.Id)}"
Grant-DeployNtfs -Path $policyRoot -Netbios $adDomain.NetBIOSName

$linkTarget = $null
if ($TargetOU) { $linkTarget = $TargetOU }
elseif ($LinkToDomain) { $linkTarget = $domainDN }
if ($linkTarget -and -not $SkipLink) {
    Write-Step "[3/3] Linking GPO to $linkTarget"
    try {
        New-GPLink -Name $GpoName -Domain $dnsRoot -Target $linkTarget -LinkEnabled Yes -ErrorAction Stop | Out-Null
    }
    catch {
        if ($_.Exception.Message -match 'already linked|already exists') { Write-Step '       Link already exists.' }
        else { throw }
    }
}
else {
    Write-Step '[3/3] GPO created but not linked. Pass -TargetOU or -LinkToDomain.'
}

Write-Step ''
Write-Step "[OK] $GpoName"
Write-Step "     Script: $stagedScript"
Write-Step '     Runs as SYSTEM at the next Group Policy refresh.'
Write-Step '     Log: C:\ProgramData\EolDependencyAudit\gpo-task.log'
Write-Step '     Hits: C:\ProgramData\EolDependencyAudit\usage.csv'
