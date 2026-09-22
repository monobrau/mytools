<#
.SYNOPSIS
    Download a ConnectWise Automate location installer, bake the MST into the MSI,
    stage it on SYSVOL, and create a computer startup-script GPO.

.DESCRIPTION
    Run as Domain Admin from a DC or RSAT box joined to the client domain.

    The token URL returns MSI_Install_Package.zip (Agent_Install.msi + Agent_Install.mst).
    This script applies the MST with msi_transform.ps1 (local copy, or downloaded from
    mytools when this file is invoked via irm), copies the baked MSI to NETLOGON, and
    creates a GPO whose startup script installs that MSI when LTService is missing.

    Native GPO Software Installation packages cannot be created from PowerShell (no
    public API for .aas advertisement files). The startup script calls msiexec on the
    already-transformed MSI, which is the same silent install.

.PARAMETER Server
    Automate server hostname, e.g. river-run.hostedrmm.com

.PARAMETER LocationID
    Automate location ID.

.PARAMETER Token
    Windows MSI installer token from the location deployment ticket.

.PARAMETER Domain
    AD DNS name. Defaults to the current domain.

.PARAMETER ClientName
    Used in the GPO name and package folder.

.PARAMETER LocationName
    Used in the GPO name and package folder. Default: Main

.PARAMETER TargetOU
    Distinguished name of the OU to link. Example: OU=Workstations,DC=contoso,DC=com

.PARAMETER LinkToDomain
    Link the GPO at the domain root. Adds a workstation-only WMI filter unless
    -SkipWmiFilter is set.

.PARAMETER SkipWmiFilter
    Do not create or attach the workstation WMI filter.

.PARAMETER SkipGpo
    Download, transform, and stage the MSI only.

.PARAMETER SkipLink
    Create the GPO but do not link it.

.PARAMETER GpoName
    Override the generated GPO name.

.PARAMETER Repo
    GitHub owner/name used to fetch msi_transform.ps1 when it is not beside this script.

.PARAMETER RepoPath
    Folder inside the repo that contains msi_transform.ps1.

.PARAMETER DryRun
    Download and transform in %TEMP%. Do not write SYSVOL or create a GPO.

.EXAMPLE
    # On the client DC (download from mytools and run):
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object Net.WebClient
    $wc.Headers.Add('User-Agent', 'AutomateGpoDeploy-bootstrap/1.0')
    $wc.Headers.Add('Accept', 'application/vnd.github.raw')
    $script = $wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/AutomateGpoDeploy/Install-AutomateGPO.ps1?ref=main')
    & ([ScriptBlock]::Create($script)) -Server 'river-run.hostedrmm.com' -LocationID 1 -Token '<token>' -Domain 'contoso.com' -ClientName 'Contoso' -LocationName 'Main' -LinkToDomain
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Server,

    [Parameter(Mandatory)]
    [int]$LocationID,

    [Parameter(Mandatory)]
    [string]$Token,

    [string]$Domain,

    [string]$ClientName = 'Automate',

    [string]$LocationName = 'Main',

    [string]$TargetOU,

    [switch]$LinkToDomain,

    [switch]$SkipWmiFilter,

    [switch]$SkipGpo,

    [switch]$SkipLink,

    [string]$GpoName,

    [string]$Repo = 'monobrau/mytools',

    [string]$RepoPath = 'AutomateGpoDeploy',

    [switch]$DryRun,

    [switch]$Exit,

    [switch]$NoExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:WmiFilterName = 'Windows Workstations (ProductType=1)'
# Scripts CSE + scripts snap-in. 42B5FA4A is the real CSE; 42B5FAAE was a typo and clients ignore it.
$script:ScriptsCse = '[{42B5FA4A-6536-11D2-AE5A-0000F87571E3}{40B6664F-4972-11D1-A7CA-0000F87571E3}]'
$script:BadScriptsCse = '42B5FAAE-6536-11D2-AE5A-0000F87571E3'
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

function ConvertTo-SecuritySid {
    param($Identity)
    if ($Identity -is [System.Security.Principal.SecurityIdentifier]) { return $Identity }
    $name = [string]$Identity
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    if ($name -match '^S-\d-\d+(-\d+)+$') {
        return [System.Security.Principal.SecurityIdentifier]$name
    }
    try {
        return ([System.Security.Principal.NTAccount]$name).Translate([System.Security.Principal.SecurityIdentifier])
    }
    catch {
        return $null
    }
}

function Grant-DeployNtfs {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Netbios
    )
    if (-not (Test-Path -LiteralPath $Path)) { throw "Cannot set permissions. Path not found: $Path" }
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

    $computers = ConvertTo-SecuritySid "$Netbios\Domain Computers"
    $authUsers = ConvertTo-SecuritySid 'Authenticated Users'
    $required = @($computers, $authUsers)
    Assert-NtfsRead -Path $Path -RequiredSids $required
    Get-ChildItem -LiteralPath $Path -Recurse -File | ForEach-Object {
        Assert-NtfsRead -Path $_.FullName -RequiredSids $required
    }
}

function Assert-NtfsRead {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Security.Principal.SecurityIdentifier[]]$RequiredSids
    )
    $need = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
    $acl = Get-Acl -LiteralPath $Path
    foreach ($required in $RequiredSids) {
        $found = $false
        foreach ($ace in $acl.Access) {
            if ($ace.AccessControlType -ne 'Allow') { continue }
            $sid = ConvertTo-SecuritySid $ace.IdentityReference
            if (-not $sid -or $sid.Value -ne $required.Value) { continue }
            if (($ace.FileSystemRights -band $need) -eq $need) { $found = $true; break }
        }
        if (-not $found) { throw "Missing Allow ReadAndExecute for $($required.Value) on $Path" }
    }
}

function Assert-NetlogonShareRead {
    param(
        [Parameter(Mandatory)][string]$Domain,
        [Parameter(Mandatory)][string]$Netbios
    )
    $computers = ConvertTo-SecuritySid "$Netbios\Domain Computers"
    $allowed = @('S-1-1-0', 'S-1-5-11', $computers.Value)
    $dcs = @(Get-ADDomainController -Filter * -Server $Domain)
    foreach ($dc in $dcs) {
        $session = New-CimSession -ComputerName $dc.HostName
        try {
            $aces = @(Get-SmbShareAccess -Name 'NETLOGON' -CimSession $session)
            $ok = $false
            foreach ($ace in $aces) {
                if ([string]$ace.AccessControlType -eq 'Deny') { continue }
                if ([string]$ace.AccessRight -notin @('Read', 'Change', 'Full')) { continue }
                $sid = ConvertTo-SecuritySid $ace.AccountName
                if ($sid -and ($allowed -contains $sid.Value)) { $ok = $true; break }
            }
            if (-not $ok) {
                Write-Step "       Granting Domain Computers Read on \\$($dc.HostName)\NETLOGON"
                Grant-SmbShareAccess -Name 'NETLOGON' -CimSession $session -AccountName "$Netbios\Domain Computers" -AccessRight Read -Force | Out-Null
                $aces = @(Get-SmbShareAccess -Name 'NETLOGON' -CimSession $session)
                $ok = $false
                foreach ($ace in $aces) {
                    if ([string]$ace.AccessControlType -eq 'Deny') { continue }
                    if ([string]$ace.AccessRight -notin @('Read', 'Change', 'Full')) { continue }
                    $sid = ConvertTo-SecuritySid $ace.AccountName
                    if ($sid -and ($allowed -contains $sid.Value)) { $ok = $true; break }
                }
            }
            if (-not $ok) { throw "NETLOGON on $($dc.HostName) does not allow domain computers to read." }
        }
        finally {
            Remove-CimSession $session -ErrorAction SilentlyContinue
        }
    }
}

function Set-DeployGpoSecurity {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Domain
    )
    $wanted = @(
        @{ Target = 'Authenticated Users'; Level = 'GpoApply' }
        @{ Target = 'Domain Computers'; Level = 'GpoRead' }
    )
    $canReplace = (Get-Command Set-GPPermission).Parameters.ContainsKey('Replace')
    foreach ($item in $wanted) {
        $params = @{
            Name            = $Name
            Domain          = $Domain
            TargetName      = $item.Target
            TargetType      = 'Group'
            PermissionLevel = $item.Level
            Confirm         = $false
        }
        if ($canReplace) { $params.Replace = $true }
        Set-GPPermission @params | Out-Null
    }

    $perms = @(Get-GPPermission -Name $Name -Domain $Domain -All)
    $authSid = (ConvertTo-SecuritySid 'Authenticated Users').Value
    $computersSid = (Get-ADGroup -Identity 'Domain Computers' -Server $Domain).SID.Value
    $rank = @{
        'GpoRead' = 1
        'GpoApply' = 2
        'GpoEdit' = 3
        'GpoEditDeleteModifySecurity' = 4
    }
    $need = @{ $authSid = 2; $computersSid = 1 }
    foreach ($sid in @($authSid, $computersSid)) {
        $best = 0
        foreach ($perm in $perms) {
            $raw = $null
            if ($perm.Trustee.PSObject.Properties['Sid']) { $raw = $perm.Trustee.Sid }
            if (-not $raw -and $perm.Trustee.PSObject.Properties['Name']) { $raw = $perm.Trustee.Name }
            $trusteeSid = ConvertTo-SecuritySid $raw
            if (-not $trusteeSid -or $trusteeSid.Value -ne $sid) { continue }
            $level = [string]$perm.Permission
            if ($rank.ContainsKey($level) -and $rank[$level] -gt $best) { $best = $rank[$level] }
        }
        if ($best -lt $need[$sid]) { throw "GPO '$Name' is missing the required permission for $sid." }
    }
}

function ConvertTo-FolderName {
    param([string]$Client, [string]$Location, [int]$Id)
    $clientPart = ($Client -replace '[^A-Za-z0-9]+', '')
    if ($clientPart.Length -gt 24) { $clientPart = $clientPart.Substring(0, 24) }
    $locPart = ($Location -replace '[^A-Za-z0-9]+', '')
    if (-not $locPart) { $locPart = 'Location' }
    return "$clientPart-$locPart-$Id"
}

function Save-RepoFile {
    param(
        [string]$GitHubRepo,
        [string]$Folder,
        [string]$Name,
        [string]$Destination
    )
    $rel = if ($Folder) { "$Folder/$Name" } else { $Name }
    $api = "https://api.github.com/repos/$GitHubRepo/contents/${rel}?ref=main"
    try {
        $wc = New-Object Net.WebClient
        $wc.Headers.Add('User-Agent', 'AutomateGpoDeploy-bootstrap/1.0')
        $wc.Headers.Add('Accept', 'application/vnd.github.raw')
        $bytes = $wc.DownloadData($api)
        if (-not $bytes -or $bytes.Length -lt 10) { throw 'empty download' }
        [System.IO.File]::WriteAllBytes($Destination, $bytes)
        return
    }
    catch {
        $raw = "https://raw.githubusercontent.com/$GitHubRepo/main/$rel"
        Invoke-WebRequest -Uri $raw -UseBasicParsing -OutFile $Destination
    }
}

function Get-TransformScriptPath {
    param([string]$GitHubRepo, [string]$Folder)
    $candidates = @()
    if ($PSScriptRoot) { $candidates += (Join-Path $PSScriptRoot 'msi_transform.ps1') }
    $candidates += 'C:\git\mytools\AutomateGpoDeploy\msi_transform.ps1'
    foreach ($path in $candidates) {
        if ($path -and (Test-Path -LiteralPath $path)) { return $path }
    }

    $dest = Join-Path $env:TEMP 'msi_transform.ps1'
    Write-Step "  Downloading msi_transform.ps1 from $GitHubRepo/$Folder"
    Save-RepoFile -GitHubRepo $GitHubRepo -Folder $Folder -Name 'msi_transform.ps1' -Destination $dest
    return $dest
}

function Merge-GpoExtensionNames {
    param([string]$Existing, [string]$Add)
    $pairs = @()
    if ($Existing) {
        $pairs += [regex]::Matches($Existing, '\[\{[0-9A-Fa-f-]+\}\{[0-9A-Fa-f-]+\}\]') | ForEach-Object { $_.Value }
    }
    $pairs = @($pairs | Where-Object { $_ -notmatch $script:BadScriptsCse })
    if ($pairs -notcontains $Add) { $pairs += $Add }
    return (($pairs | Sort-Object) -join '')
}

function ConvertTo-LdapFilterLiteral {
    param([string]$Value)
    return ($Value -replace '\\', '\5c' -replace '\*', '\2a' -replace '\(', '\28' -replace '\)', '\29')
}

function Set-GpoStartupScript {
    param(
        $Gpo,
        [string]$DnsRoot,
        [string]$DomainDN,
        [string]$CmdName,
        [string]$CmdText
    )

    $policyRoot = "\\$DnsRoot\SYSVOL\$DnsRoot\Policies\{$($Gpo.Id)}"
    $startupDir = Join-Path $policyRoot 'Machine\Scripts\Startup'
    New-Item -ItemType Directory -Path $startupDir -Force | Out-Null
    Set-Content -Path (Join-Path $startupDir $CmdName) -Value $CmdText -Encoding Ascii

    $ini = "[Startup]`r`n0CmdLine=$CmdName`r`n0Parameters=`r`n"
    $iniPath = Join-Path $policyRoot 'Machine\Scripts\scripts.ini'
    [System.IO.File]::WriteAllText($iniPath, $ini, [System.Text.UnicodeEncoding]::new($false, $true))

    $adPath = "CN={$($Gpo.Id)},CN=Policies,CN=System,$DomainDN"
    $obj = Get-ADObject -Identity $adPath -Properties versionNumber, gPCMachineExtensionNames
    $ver = [int]($obj.versionNumber)
    $userVer = $ver -shr 16
    $machineVer = ($ver -band 0xFFFF) + 1
    if ($machineVer -gt 65535) { $machineVer = 1 }
    $newVer = ($userVer -shl 16) + $machineVer
    $merged = Merge-GpoExtensionNames -Existing ([string]$obj.gPCMachineExtensionNames) -Add $script:ScriptsCse

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
    $ldapName = ConvertTo-LdapFilterLiteral -Value $Name
    $existing = Get-ADObject -SearchBase $searchBase -LDAPFilter "(msWMI-Name=$ldapName)" -Properties 'msWMI-Name', 'msWMI-ID' -ErrorAction SilentlyContinue
    if ($existing) { return @($existing)[0] }

    $guid = [guid]::NewGuid()
    $guidBrace = "{$guid}"
    $now = (Get-Date).ToUniversalTime()
    $frac = [int](($now.Ticks % 10000000) / 10)
    $stamp = $now.ToString('yyyyMMddHHmmss') + '.' + $frac.ToString('000000') + '-000'
    $author = "$env:USERDOMAIN\$env:USERNAME"
    $query = 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1'
    $parm2 = "1;3;10;$($query.Length);WQL;root\CIMv2;$query;"

    New-ADObject -Name $guidBrace -Type 'msWMI-Som' -Path $searchBase -OtherAttributes @{
        'msWMI-Name'             = $Name
        'msWMI-Parm1'            = 'Computer is a workstation (not a server or DC). '
        'msWMI-Parm2'            = $parm2
        'msWMI-Author'           = $author
        'msWMI-ID'               = $guidBrace
        'showInAdvancedViewOnly' = $true
        'msWMI-ChangeDate'       = $stamp
        'msWMI-CreationDate'     = $stamp
    } | Out-Null

    return Get-ADObject -SearchBase $searchBase -LDAPFilter "(msWMI-Name=$ldapName)" -Properties 'msWMI-Name', 'msWMI-ID'
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Test-IsAdministrator)) {
    throw 'Run this script elevated as a Domain Admin (or equivalent GPO/SYSVOL rights).'
}

$Server = $Server -replace '^https?://', '' -replace '/$', ''
$Token = $Token.Trim()

Write-Step '=== Automate GPO installer ==='
if ($DryRun) { Write-Step 'Mode: DRY-RUN (no SYSVOL/GPO writes)' }

if (-not $SkipGpo) {
    foreach ($mod in @('ActiveDirectory', 'GroupPolicy')) {
        if (-not (Get-Module -ListAvailable -Name $mod)) {
            throw "Required module '$mod' is missing. Install RSAT or run this on a domain controller."
        }
        Import-Module $mod -ErrorAction Stop
    }
}

if (-not $Domain) {
    $Domain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name
}
$adDomain = Get-ADDomain -Identity $Domain
$dnsRoot = $adDomain.DNSRoot
$domainDN = $adDomain.DistinguishedName

$folderName = ConvertTo-FolderName -Client $ClientName -Location $LocationName -Id $LocationID
if (-not $GpoName) {
    $GpoName = "Deploy Automate - $ClientName $LocationName ($LocationID)"
}

$packageUnc = "\\$dnsRoot\NETLOGON\Automate\$folderName"
$msiName = 'Agent_Install.msi'
$stagedMsi = Join-Path $packageUnc $msiName

Write-Step "  Domain:  $dnsRoot"
Write-Step "  Server:  $Server"
Write-Step "  Location: $LocationName ($LocationID)"
Write-Step "  Package: $stagedMsi"
Write-Step "  GPO:     $GpoName"
Write-Step ''

# ---------------------------------------------------------------------------
# Download + transform
# ---------------------------------------------------------------------------

$work = Join-Path $env:TEMP ("AutomateGPO-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$download = Join-Path $work 'installer.bin'
$uri = "https://$Server/LabTech/Deployment.aspx?InstallerToken=$Token"

try {
    Write-Step '[1/5] Downloading installer package...'
    Invoke-WebRequest -Uri $uri -UseBasicParsing -OutFile $download
    $bytes = [System.IO.File]::ReadAllBytes($download)
    if ($bytes.Length -lt 4) { throw "Download from $uri was empty." }

    $extractDir = Join-Path $work 'extract'
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

    $isZip = ($bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B)
    if ($isZip) {
        $zipPath = Join-Path $work 'MSI_Install_Package.zip'
        Copy-Item $download $zipPath -Force
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    }
    else {
        Copy-Item $download (Join-Path $extractDir 'Agent_Install.msi') -Force
    }

    $msi = Get-ChildItem -Path $extractDir -Recurse -Filter '*.msi' | Select-Object -First 1
    $mst = Get-ChildItem -Path $extractDir -Recurse -Filter '*.mst' | Select-Object -First 1
    if (-not $msi) { throw 'The installer package did not contain an MSI.' }
    if (-not $mst) { throw 'The installer package did not contain an MST. Refusing to stage an untransformed MSI.' }

    Write-Step "       $($msi.Name) + $($mst.Name)"

    Write-Step '[2/5] Baking MST into MSI...'
    $transformScript = Get-TransformScriptPath -GitHubRepo $Repo -Folder $RepoPath
    $bakedMsi = Join-Path $work $msiName
    & $transformScript -Msi $msi.FullName -Mst $mst.FullName -Output $bakedMsi
    if (-not (Test-Path -LiteralPath $bakedMsi)) {
        throw "Transform finished but output MSI was not created: $bakedMsi"
    }

    if ($DryRun) {
        Write-Step ''
        Write-Step "[DRY RUN] Transformed MSI is at $bakedMsi"
        Write-Step '          Would stage to SYSVOL and create the GPO. Re-run without -DryRun to apply.'
        return
    }

    Write-Step "[3/5] Staging baked MSI to $packageUnc"
    New-Item -ItemType Directory -Path $packageUnc -Force | Out-Null
    Copy-Item -LiteralPath $bakedMsi -Destination $stagedMsi -Force
    $info = @(
        "Client: $ClientName"
        "Location: $LocationName ($LocationID)"
        "Server: $Server"
        "Built: $((Get-Date).ToString('o'))"
        "MSI: $stagedMsi"
        "Transform: baked (no separate MST at install time)"
    ) -join [Environment]::NewLine
    Set-Content -Path (Join-Path $packageUnc 'BUILDINFO.txt') -Value $info -Encoding Ascii

    Write-Step '       Granting Domain Computers and Authenticated Users read on the MSI folder'
    Grant-DeployNtfs -Path $packageUnc -Netbios $adDomain.NetBIOSName
    Assert-NetlogonShareRead -Domain $dnsRoot -Netbios $adDomain.NetBIOSName

    if ($SkipGpo) {
        Write-Step ''
        Write-Step "[OK] Staged $stagedMsi"
        Write-Step '     -SkipGpo set; no GPO created.'
        return
    }

    Write-Step "[4/5] Creating or updating GPO '$GpoName'..."
    $gpo = Get-GPO -Name $GpoName -Domain $dnsRoot -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $GpoName -Domain $dnsRoot -Comment "ConnectWise Automate agent for $ClientName / $LocationName ($LocationID)"
    }

    Set-GPRegistryValue -Name $GpoName -Domain $dnsRoot -Key 'HKLM\Software\Policies\Microsoft\Windows NT\CurrentVersion\Winlogon' -ValueName 'SyncForegroundPolicy' -Type DWord -Value 1 | Out-Null
    Set-GPRegistryValue -Name $GpoName -Domain $dnsRoot -Key 'HKLM\Software\Policies\Microsoft\Windows\System' -ValueName 'MaxGPOScriptWait' -Type DWord -Value 900 | Out-Null

    $cmdName = 'Install-Automate.cmd'
    $cmdText = @"
@echo off
set LOG=%SystemRoot%\Temp\Automate-GPO-Install.log
echo %DATE% %TIME% startup script began>>"%LOG%"
sc query LTService >nul 2>&1
if not errorlevel 1 (
  echo %DATE% %TIME% LTService already present. Nothing to do.>>"%LOG%"
  exit /b 0
)
echo %DATE% %TIME% Installing Automate from $stagedMsi>>"%LOG%"
msiexec /i "$stagedMsi" /qn /norestart /l*v "%SystemRoot%\Temp\Automate-GPO-Install.msi.log"
echo %DATE% %TIME% msiexec exit %ERRORLEVEL%>>"%LOG%"
"@
    Set-GpoStartupScript -Gpo $gpo -DnsRoot $dnsRoot -DomainDN $domainDN -CmdName $cmdName -CmdText $cmdText
    $policyRoot = "\\$dnsRoot\SYSVOL\$dnsRoot\Policies\{$($gpo.Id)}"
    Write-Step '       Granting Domain Computers and Authenticated Users read on the GPO'
    Grant-DeployNtfs -Path $policyRoot -Netbios $adDomain.NetBIOSName
    Set-DeployGpoSecurity -Name $GpoName -Domain $dnsRoot

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
            $wmi = Resolve-WmiFilter -DomainDN $domainDN -Name $script:WmiFilterName
            $wmiId = [string]$wmi.'msWMI-ID'
            if (-not $wmiId) { throw "WMI filter '$($script:WmiFilterName)' was created but has no msWMI-ID. Refusing to link at the domain root." }
            if ($wmiId -notmatch '^\{') { $wmiId = "{$wmiId}" }
            $gpoDn = "CN={$($gpo.Id)},CN=Policies,CN=System,$domainDN"
            Set-ADObject -Identity $gpoDn -Replace @{ gPCWQLFilter = "[$dnsRoot;$wmiId;0]" }
        }

        Write-Step "[5/5] Linking GPO to $linkTarget"
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
        Write-Step '[5/5] GPO created but not linked. Pass -TargetOU or -LinkToDomain.'
    }

    Write-Step ''
    Write-Step "[OK] $GpoName"
    Write-Step "     MSI: $stagedMsi"
    Write-Step '     Startup script installs the baked MSI when LTService is missing.'
    Write-Step '     Clients need a reboot after gpupdate (startup scripts do not run at gpupdate).'
    Write-Step '     Pilot: security-filter the GPO to a test computer group before a wide link.'
}
finally {
    if (-not $DryRun -and (Test-Path -LiteralPath $work)) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
