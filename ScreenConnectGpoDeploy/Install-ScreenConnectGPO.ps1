#Requires -Version 5.1
<#
.SYNOPSIS
    Stage a ScreenConnect client MSI on NETLOGON and deploy it with a workstation GPO.

.DESCRIPTION
    Run elevated as a Domain Admin on a DC or RSAT box. The MSI is the Access
    client installer downloaded from your ScreenConnect instance (already
    configured for that instance). This script does not build or transform it.

    An Immediate Task runs as SYSTEM at the next Group Policy refresh. It
    installs only when no "ScreenConnect Client*" service exists. A reboot is
    not required to start the task.

.PARAMETER MsiPath
    Local path to the ScreenConnect client .msi.

.PARAMETER ClientName
    Used in the GPO name and the NETLOGON folder. Not a live customer name in git.

.PARAMETER Domain
    AD DNS name. Default: current domain.

.PARAMETER TargetOU
    Distinguished name to link. Overrides -LinkToDomain.

.PARAMETER LinkToDomain
    Link at the domain root and attach the workstation WMI filter.

.EXAMPLE
    .\Install-ScreenConnectGPO.ps1 -MsiPath 'C:\Support\ScreenConnect.ClientSetup.msi' -ClientName 'Contoso' -LinkToDomain
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MsiPath,
    [string]$ClientName = 'ScreenConnect',
    [string]$Domain,
    [string]$TargetOU,
    [switch]$LinkToDomain,
    [switch]$SkipWmiFilter,
    [switch]$SkipLink,
    [string]$GpoName,
    [switch]$DryRun
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$script:WmiFilterName = 'Windows Workstations (ProductType=1)'
$script:GppSchedCse = '[{AADCED64-746C-4633-A97C-D80500FC4251}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}]'
$script:TaskUid = '{8F3C1A70-6B24-4E19-9C55-2D7A0E4B91F6}'

function Write-Step { param([string]$Message) Write-Host $Message }

function ConvertTo-SecuritySid {
    param($Identity)
    if (-not $Identity) { return $null }
    if ($Identity -is [System.Security.Principal.SecurityIdentifier]) { return $Identity }
    $text = [string]$Identity
    if ($text -match '^S-1-') { return New-Object System.Security.Principal.SecurityIdentifier $text }
    try { return (New-Object System.Security.Principal.NTAccount $text).Translate([System.Security.Principal.SecurityIdentifier]) }
    catch { return $null }
}

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
    param([string]$Existing, [string]$Add)
    $pairs = @()
    if ($Existing) {
        $pairs += [regex]::Matches($Existing, '\[\{[0-9A-Fa-f-]+\}\{[0-9A-Fa-f-]+\}\]') | ForEach-Object { $_.Value }
    }
    if ($pairs -notcontains $Add) { $pairs += $Add }
    return (($pairs | Sort-Object) -join '')
}

function Set-GpoImmediateTask {
    param($Gpo, [string]$DnsRoot, [string]$DomainDN, [string]$CmdName, [string]$CmdText)
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
	<ImmediateTaskV2 clsid="{9756B581-76EC-451C-9E12-DFF9B5CA5C32}" name="Install ScreenConnect" image="2" changed="$changed" uid="$($script:TaskUid)" userContext="0" removePolicy="0">
		<Properties action="U" name="Install ScreenConnect" runAs="NT AUTHORITY\System" logonType="S4U">
			<Task version="1.3">
				<RegistrationInfo>
					<Author>NT AUTHORITY\System</Author>
					<Description>Install ScreenConnect when the client service is missing</Description>
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
    $merged = Merge-GpoExtensionNames -Existing ([string]$obj.gPCMachineExtensionNames) -Add $script:GppSchedCse
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

function ConvertTo-LdapFilterLiteral {
    param([string]$Value)
    return ($Value -replace '\\', '\5c' -replace '\*', '\2a' -replace '\(', '\28' -replace '\)', '\29')
}

function Grant-WmiFilterRead {
    param([string]$FilterDn)
    $rights = [System.DirectoryServices.ActiveDirectoryRights]::GenericRead
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    $none = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::None
    $sidType = [System.Security.Principal.SecurityIdentifier]
    $identities = @(
        (New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-11'),
        (Get-ADGroup -Identity 'Domain Computers').SID
    )
    $entry = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$FilterDn")
    $sd = $entry.ObjectSecurity
    $existing = @($sd.GetAccessRules($true, $true, $sidType))
    foreach ($id in $identities) {
        $hasRead = $false
        foreach ($ace in $existing) {
            if ($ace.IdentityReference.Value -eq $id.Value -and $ace.AccessControlType -eq $allow -and (($ace.ActiveDirectoryRights -band $rights) -eq $rights)) {
                $hasRead = $true
                break
            }
        }
        if (-not $hasRead) {
            $sd.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($id, $rights, $allow, $none)))
        }
    }
    $entry.CommitChanges()
}

function Resolve-WmiFilter {
    param([string]$DomainDN, [string]$Name)
    $searchBase = "CN=SOM,CN=WMIPolicy,CN=System,$DomainDN"
    $ldapName = ConvertTo-LdapFilterLiteral -Value $Name
    $existing = Get-ADObject -SearchBase $searchBase -LDAPFilter "(msWMI-Name=$ldapName)" -Properties 'msWMI-Name', 'msWMI-ID' -ErrorAction SilentlyContinue
    if ($existing) {
        $filter = @($existing)[0]
        Grant-WmiFilterRead -FilterDn $filter.DistinguishedName
        return $filter
    }
    $guid = [guid]::NewGuid()
    $guidBrace = "{$guid}"
    $now = (Get-Date).ToUniversalTime()
    $frac = [int](($now.Ticks % 10000000) / 10)
    $stamp = $now.ToString('yyyyMMddHHmmss') + '.' + $frac.ToString('000000') + '-000'
    $query = 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1'
    $parm2 = "1;3;10;$($query.Length);WQL;root\CIMv2;$query;"
    New-ADObject -Name $guidBrace -Type 'msWMI-Som' -Path $searchBase -OtherAttributes @{
        'msWMI-Name'             = $Name
        'msWMI-Parm1'            = 'Computer is a workstation (not a server or DC). '
        'msWMI-Parm2'            = $parm2
        'msWMI-Author'           = "$env:USERDOMAIN\$env:USERNAME"
        'msWMI-ID'               = $guidBrace
        'showInAdvancedViewOnly' = $true
        'msWMI-ChangeDate'       = $stamp
        'msWMI-CreationDate'     = $stamp
    } | Out-Null
    $created = Get-ADObject -SearchBase $searchBase -LDAPFilter "(msWMI-Name=$ldapName)" -Properties 'msWMI-Name', 'msWMI-ID'
    Grant-WmiFilterRead -FilterDn $created.DistinguishedName
    return $created
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script elevated as a Domain Admin.'
}

foreach ($mod in @('ActiveDirectory', 'GroupPolicy')) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        throw "Required module '$mod' is missing. Install RSAT or run this on a domain controller."
    }
    Import-Module $mod -ErrorAction Stop
}

$MsiPath = $MsiPath.Trim().Trim('"')
if (-not (Test-Path -LiteralPath $MsiPath)) { throw "MSI not found: $MsiPath" }
$msiItem = Get-Item -LiteralPath $MsiPath
if ($msiItem.Extension -ne '.msi') { throw "Expected a .msi file: $MsiPath" }
if ($msiItem.Length -lt 1MB) { throw "MSI looks too small ($($msiItem.Length) bytes): $MsiPath" }

if (-not $Domain) {
    $Domain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name
}
$adDomain = Get-ADDomain -Identity $Domain
$dnsRoot = $adDomain.DNSRoot
$domainDN = $adDomain.DistinguishedName
$folder = ($ClientName -replace '[^A-Za-z0-9]+', '')
if (-not $folder) { $folder = 'ScreenConnect' }
if ($folder.Length -gt 32) { $folder = $folder.Substring(0, 32) }
if (-not $GpoName) { $GpoName = "Deploy ScreenConnect - $ClientName" }
$packageUnc = "\\$dnsRoot\NETLOGON\ScreenConnect\$folder"
$stagedMsi = Join-Path $packageUnc $msiItem.Name

Write-Step '=== ScreenConnect GPO deploy ==='
if ($DryRun) { Write-Step 'Mode: DRY-RUN (no SYSVOL/GPO writes)' }
Write-Step "  Domain:  $dnsRoot"
Write-Step "  MSI:     $($msiItem.FullName)"
Write-Step "  Package: $stagedMsi"
Write-Step "  GPO:     $GpoName"

if ($DryRun) {
    Write-Step ''
    Write-Step '[DRY RUN] Would copy the MSI to NETLOGON and create an Immediate Task GPO.'
    Write-Step '          The task installs only when no ScreenConnect Client service exists.'
    return
}

Write-Step '[1/3] Staging MSI'
New-Item -ItemType Directory -Path $packageUnc -Force | Out-Null
Copy-Item -LiteralPath $msiItem.FullName -Destination $stagedMsi -Force
Grant-DeployNtfs -Path $packageUnc -Netbios $adDomain.NetBIOSName

Write-Step "[2/3] Creating or updating GPO '$GpoName'"
$gpo = Get-GPO -Name $GpoName -Domain $dnsRoot -ErrorAction SilentlyContinue
if (-not $gpo) {
    $gpo = New-GPO -Name $GpoName -Domain $dnsRoot -Comment "ScreenConnect client for $ClientName"
}
Set-GPPermission -Name $GpoName -Domain $dnsRoot -TargetName 'Authenticated Users' -TargetType Group -PermissionLevel GpoApply -Confirm:$false | Out-Null
Set-GPPermission -Name $GpoName -Domain $dnsRoot -TargetName 'Domain Computers' -TargetType Group -PermissionLevel GpoApply -Confirm:$false | Out-Null

$cmdText = @"
@echo off
set LOG=%SystemRoot%\Temp\ScreenConnect-GPO-Install.log
echo %DATE% %TIME% immediate task began>>"%LOG%"
powershell.exe -NoProfile -Command "if (Get-Service -Name 'ScreenConnect Client*' -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if not errorlevel 1 (
  echo %DATE% %TIME% ScreenConnect Client already present>>"%LOG%"
  exit /b 0
)
echo %DATE% %TIME% Installing $stagedMsi>>"%LOG%"
msiexec /i "$stagedMsi" /qn /norestart /l*v "%SystemRoot%\Temp\ScreenConnect-GPO-Install.msi.log"
echo %DATE% %TIME% msiexec exit %ERRORLEVEL%>>"%LOG%"
"@
Set-GpoImmediateTask -Gpo $gpo -DnsRoot $dnsRoot -DomainDN $domainDN -CmdName 'Install-ScreenConnect.cmd' -CmdText $cmdText
$policyRoot = "\\$dnsRoot\SYSVOL\$dnsRoot\Policies\{$($gpo.Id)}"
Grant-DeployNtfs -Path $policyRoot -Netbios $adDomain.NetBIOSName

$linkTarget = $null
if ($TargetOU) { $linkTarget = $TargetOU }
elseif ($LinkToDomain) { $linkTarget = $domainDN }

if ($linkTarget -and -not $SkipLink) {
    if ($LinkToDomain -and -not $TargetOU -and -not $SkipWmiFilter) {
        Write-Step "       Attaching WMI filter '$($script:WmiFilterName)'"
        $wmi = Resolve-WmiFilter -DomainDN $domainDN -Name $script:WmiFilterName
        $wmiId = [string]$wmi.'msWMI-ID'
        if (-not $wmiId) { throw 'WMI filter has no msWMI-ID. Refusing to link at the domain root.' }
        if ($wmiId -notmatch '^\{') { $wmiId = "{$wmiId}" }
        Set-ADObject -Identity "CN={$($gpo.Id)},CN=Policies,CN=System,$domainDN" -Replace @{ gPCWQLFilter = "[$dnsRoot;$wmiId;0]" }
    }
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
Write-Step "     MSI: $stagedMsi"
Write-Step '     Workstations install at the next Group Policy refresh when the ScreenConnect Client service is missing.'
Write-Step '     Log: C:\Windows\Temp\ScreenConnect-GPO-Install.log'
