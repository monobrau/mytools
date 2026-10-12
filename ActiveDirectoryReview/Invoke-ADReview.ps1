#Requires -Version 5.1
<#
.SYNOPSIS
    Read-only Active Directory review of a client domain, run from this PC over a RemoteOps tunnel.

.DESCRIPTION
    Connects over WinRM to a domain-joined host that is enrolled in RemoteOps (its
    10.88.88.x tunnel address), runs read-only AD queries there, and writes CSVs plus
    a summary on this PC.

    Covers the domain and forest, domain controllers, privileged group membership
    (nested), stale users and computers, enabled accounts whose password never
    expires, krbtgt password age, and trusts.

    The target needs the ActiveDirectory module. A domain controller has it. On a
    member server: Install-WindowsFeature RSAT-AD-PowerShell.

    Run elevated on this PC. Connecting by IP address needs a WinRM TrustedHosts
    entry. The script adds the address for the run and puts the original list back
    when it finishes. If it had to start the local WinRM service, it stops it again.

    The credential is passed to every AD query on the target, so a member server
    can reach its domain controller without CredSSP.

.PARAMETER ComputerName
    Tunnel address of the enrolled host (Peer IP on the RemoteOps portal).

.PARAMETER Credential
    Domain account, DOMAIN\user. Prompted for when omitted.

.PARAMETER InactiveDays
    An enabled account with no logon in this many days is stale. Default 90.

.PARAMETER OutputPath
    Folder for the results. Default is Documents\ADReview\<domain>_<timestamp>.

.EXAMPLE
    .\Invoke-ADReview.ps1 -ComputerName 10.88.88.2

.EXAMPLE
    .\Invoke-ADReview.ps1 -ComputerName 10.88.88.2 -InactiveDays 60
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ComputerName,

    [pscredential]$Credential,

    [ValidateRange(1, 3650)]
    [int]$InactiveDays = 90,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

$remoteReview = {
    param([pscredential]$Cred)
    $ErrorActionPreference = 'Stop'

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw "ActiveDirectory module is not installed on $env:COMPUTERNAME. On a server: Install-WindowsFeature RSAT-AD-PowerShell"
    }
    Import-Module ActiveDirectory -Verbose:$false

    # Discover before setting the defaults. -Discover has no -Credential parameter.
    $dc = [string](Get-ADDomainController -Discover).HostName
    $PSDefaultParameterValues = @{
        '*-AD*:Credential' = $Cred
        '*-AD*:Server'     = $dc
    }

    $domain = Get-ADDomain
    $forest = Get-ADForest

    $domainInfo = [pscustomobject]@{
        Target               = $env:COMPUTERNAME
        TargetIsDC           = ((Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4)
        QueriedDC            = $dc
        DNSRoot              = $domain.DNSRoot
        NetBIOSName          = $domain.NetBIOSName
        DomainMode           = [string]$domain.DomainMode
        ForestName           = $forest.Name
        ForestMode           = [string]$forest.ForestMode
        PDCEmulator          = $domain.PDCEmulator
        RIDMaster            = $domain.RIDMaster
        InfrastructureMaster = $domain.InfrastructureMaster
        SchemaMaster         = $forest.SchemaMaster
        DomainNamingMaster   = $forest.DomainNamingMaster
    }

    $dcs = @(Get-ADDomainController -Filter * | ForEach-Object {
        [pscustomobject]@{
            HostName        = $_.HostName
            Site            = $_.Site
            IPv4Address     = $_.IPv4Address
            OperatingSystem = $_.OperatingSystem
            OSVersion       = $_.OperatingSystemVersion
            IsGlobalCatalog = $_.IsGlobalCatalog
            IsReadOnly      = $_.IsReadOnly
            FsmoRoles       = (@($_.OperationMasterRoles) -join ', ')
        }
    })

    # Well-known SIDs keep this working on non-English domains.
    $sid = $domain.DomainSID.Value
    $groupIds = [ordered]@{
        'Domain Admins'               = "$sid-512"
        'Enterprise Admins'           = "$sid-519"
        'Schema Admins'               = "$sid-518"
        'Group Policy Creator Owners' = "$sid-520"
        'Administrators'              = 'S-1-5-32-544'
        'Account Operators'           = 'S-1-5-32-548'
        'Server Operators'            = 'S-1-5-32-549'
        'Print Operators'             = 'S-1-5-32-550'
        'Backup Operators'            = 'S-1-5-32-551'
        'DnsAdmins'                   = 'DnsAdmins'
    }
    $privileged = New-Object System.Collections.Generic.List[object]
    foreach ($label in $groupIds.Keys) {
        try { $group = Get-ADGroup -Identity $groupIds[$label] }
        catch {
            $privileged.Add([pscustomobject]@{
                Group = $label; Member = '(group not in this domain)'; ObjectClass = ''; Enabled = ''
                PasswordNeverExpires = ''; LastLogonDate = $null; PasswordLastSet = $null; DistinguishedName = ''
            })
            continue
        }
        # LDAP_MATCHING_RULE_IN_CHAIN returns nested members and does not fail on foreign principals.
        $members = @(Get-ADObject -LDAPFilter "(memberOf:1.2.840.113556.1.4.1941:=$($group.DistinguishedName))" `
            -Properties sAMAccountName, objectClass, userAccountControl, lastLogonTimestamp, pwdLastSet)
        if ($members.Count -eq 0) {
            $privileged.Add([pscustomobject]@{
                Group = $group.Name; Member = '(no members)'; ObjectClass = ''; Enabled = ''
                PasswordNeverExpires = ''; LastLogonDate = $null; PasswordLastSet = $null; DistinguishedName = ''
            })
            continue
        }
        foreach ($m in $members) {
            $uac = [int]$m.userAccountControl
            $isAccount = $m.objectClass -in @('user', 'computer')
            $privileged.Add([pscustomobject]@{
                Group                = $group.Name
                Member               = $(if ($m.sAMAccountName) { $m.sAMAccountName } else { $m.Name })
                ObjectClass          = $m.objectClass
                Enabled              = $(if ($isAccount) { -not ($uac -band 0x2) } else { '' })
                PasswordNeverExpires = $(if ($isAccount) { [bool]($uac -band 0x10000) } else { '' })
                LastLogonDate        = $(if ($m.lastLogonTimestamp) { [DateTime]::FromFileTime([int64]$m.lastLogonTimestamp) } else { $null })
                PasswordLastSet      = $(if ($m.pwdLastSet) { [DateTime]::FromFileTime([int64]$m.pwdLastSet) } else { $null })
                DistinguishedName    = $m.DistinguishedName
            })
        }
    }

    $users = @(Get-ADUser -Filter * -Properties LastLogonDate, PasswordLastSet, PasswordNeverExpires, WhenCreated |
        Select-Object SamAccountName, Name, Enabled, LastLogonDate, PasswordLastSet, PasswordNeverExpires, WhenCreated, DistinguishedName)

    $computers = @(Get-ADComputer -Filter * -Properties LastLogonDate, PasswordLastSet, OperatingSystem, OperatingSystemVersion, WhenCreated |
        Select-Object Name, Enabled, OperatingSystem, OperatingSystemVersion, LastLogonDate, PasswordLastSet, WhenCreated, DistinguishedName)

    $trusts = @(Get-ADTrust -Filter * |
        Select-Object Name, Direction, TrustType, ForestTransitive, IntraForest, SelectiveAuthentication, SIDFilteringQuarantined)

    [pscustomobject]@{
        Domain     = $domainInfo
        DCs        = $dcs
        Privileged = $privileged.ToArray()
        Users      = $users
        Computers  = $computers
        Trusts     = $trusts
    }
}

if (-not (Test-IsAdmin)) {
    throw 'Run this from an elevated PowerShell window. WinRM by IP address needs a TrustedHosts entry, and only an administrator can add it.'
}
if (-not $Credential) {
    $Credential = Get-Credential -Message "Domain account for $ComputerName (DOMAIN\user)"
}
if (-not $Credential) { throw 'No credential entered.' }

$startedWinRM = $false
$originalTrusted = $null
$changedTrusted = $false
$session = $null

try {
    $winrm = Get-Service -Name WinRM
    if ($winrm.Status -ne 'Running') {
        Start-Service -Name WinRM
        $startedWinRM = $true
    }

    $originalTrusted = [string](Get-Item -Path WSMan:\localhost\Client\TrustedHosts).Value
    $entries = @($originalTrusted -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($entries -notcontains '*' -and $entries -notcontains $ComputerName) {
        Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value $ComputerName -Concatenate -Force
        $changedTrusted = $true
    }

    Write-Host "Connecting to $ComputerName over WinRM (5985)..."
    try {
        $session = New-PSSession -ComputerName $ComputerName -Credential $Credential -Authentication Negotiate
    } catch {
        throw "Could not open a WinRM session to $ComputerName. Check the tunnel (ping), that WinRM listens on 5985 (Enable-PSRemoting -Force -SkipNetworkProfileCheck on the target), and the credential. $($_.Exception.Message)"
    }

    Write-Host 'Running read-only AD queries on the target...'
    $r = Invoke-Command -Session $session -ScriptBlock $remoteReview -ArgumentList $Credential

    $now = Get-Date
    $cutoff = $now.AddDays(-$InactiveDays)

    $staleUsers = @($r.Users | Where-Object {
        $_.Enabled -and $_.WhenCreated -lt $cutoff -and (-not $_.LastLogonDate -or $_.LastLogonDate -lt $cutoff)
    })
    $staleComputers = @($r.Computers | Where-Object {
        $_.Enabled -and $_.WhenCreated -lt $cutoff -and (-not $_.LastLogonDate -or $_.LastLogonDate -lt $cutoff)
    })
    $neverExpires = @($r.Users | Where-Object { $_.Enabled -and $_.PasswordNeverExpires })
    $krbtgt = $r.Users | Where-Object { $_.SamAccountName -eq 'krbtgt' } | Select-Object -First 1
    $krbtgtAge = $null
    if ($krbtgt -and $krbtgt.PasswordLastSet) { $krbtgtAge = [int]($now - $krbtgt.PasswordLastSet).TotalDays }

    if (-not $OutputPath) {
        $safeDomain = ($r.Domain.DNSRoot -replace '[^\w\.\-]+', '_')
        $OutputPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ("ADReview\{0}_{1}" -f $safeDomain, $now.ToString('yyyyMMdd-HHmmss'))
    }
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

    $csv = @{ NoTypeInformation = $true; Encoding = 'UTF8' }
    $r.Domain | Select-Object * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName |
        Export-Csv -Path (Join-Path $OutputPath 'Domain.csv') @csv
    $r.DCs | Select-Object * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName |
        Export-Csv -Path (Join-Path $OutputPath 'DomainControllers.csv') @csv
    $r.Privileged | Select-Object * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName |
        Export-Csv -Path (Join-Path $OutputPath 'PrivilegedGroupMembers.csv') @csv
    $r.Users | Select-Object * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName |
        Export-Csv -Path (Join-Path $OutputPath 'Users.csv') @csv
    $r.Computers | Select-Object * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName |
        Export-Csv -Path (Join-Path $OutputPath 'Computers.csv') @csv
    $staleUsers | Select-Object * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName |
        Export-Csv -Path (Join-Path $OutputPath 'StaleUsers.csv') @csv
    $staleComputers | Select-Object * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName |
        Export-Csv -Path (Join-Path $OutputPath 'StaleComputers.csv') @csv
    $neverExpires | Select-Object * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName |
        Export-Csv -Path (Join-Path $OutputPath 'PasswordNeverExpires.csv') @csv
    $r.Trusts | Select-Object * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName |
        Export-Csv -Path (Join-Path $OutputPath 'Trusts.csv') @csv

    $privCounts = $r.Privileged | Where-Object { $_.ObjectClass -in @('user', 'computer') } |
        Group-Object Group | ForEach-Object { '  {0}: {1}' -f $_.Name, $_.Count }

    $summary = @(
        "AD review  $($now.ToString('yyyy-MM-dd HH:mm'))"
        "Domain     $($r.Domain.DNSRoot) ($($r.Domain.NetBIOSName)), $($r.Domain.DomainMode)"
        "Forest     $($r.Domain.ForestName), $($r.Domain.ForestMode)"
        "Queried    $($r.Domain.QueriedDC) from $($r.Domain.Target) via $ComputerName"
        ''
        "Domain controllers: $(@($r.DCs).Count)"
        "Users: $(@($r.Users).Count) ($(@($r.Users | Where-Object Enabled).Count) enabled)"
        "Computers: $(@($r.Computers).Count) ($(@($r.Computers | Where-Object Enabled).Count) enabled)"
        "Trusts: $(@($r.Trusts).Count)"
        ''
        'Privileged accounts (nested, users and computers):'
    ) + @($privCounts) + @(
        ''
        "Stale enabled users (no logon in $InactiveDays days): $($staleUsers.Count)"
        "Stale enabled computers (no logon in $InactiveDays days): $($staleComputers.Count)"
        "Enabled users whose password never expires: $($neverExpires.Count)"
        $(if ($null -ne $krbtgtAge) { "krbtgt password age: $krbtgtAge days (last set $($krbtgt.PasswordLastSet.ToString('yyyy-MM-dd')))" } else { 'krbtgt password age: unknown' })
        ''
        'LastLogonDate is lastLogonTimestamp, which can lag up to 14 days behind the real last logon.'
        "Files: $OutputPath"
    )
    $summary | Set-Content -Path (Join-Path $OutputPath 'Summary.txt') -Encoding UTF8
    $summary | ForEach-Object { Write-Host $_ }
}
finally {
    if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
    if ($changedTrusted) {
        Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value $originalTrusted -Force -ErrorAction SilentlyContinue
    }
    if ($startedWinRM) { Stop-Service -Name WinRM -ErrorAction SilentlyContinue }
}
