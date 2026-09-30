#Requires -Version 5.1
<#
.SYNOPSIS
    Export Entra authorized users, likely service accounts, and Intune BitLocker status per workstation.

.DESCRIPTION
    Writes three CSVs for an evidence request that asks for an Active Directory
    authorized-user list and a service-account list, including Microsoft 365 / Entra,
    plus proof that BitLocker is deployed on each workstation.

    The directory source is Entra ID. That is the Microsoft 365 directory, and it
    includes users synced from on-premises Active Directory. Accounts that exist
    only on a domain controller and are not synced are not in this export.

    BitLocker rows come from the Intune encryption report
    (Graph beta deviceManagement/managedDeviceEncryptionStates). Recovery keys
    are not exported.

    Entra has no service-account object class. ServiceAccounts.csv is the subset
    whose name, job title, department, or on-premises OU looks like a service
    account. PasswordNeverExpires is a column, not the reason a row is included.

.PARAMETER TenantId
    Passed to Connect-MgGraph when a new sign-in is required.

.PARAMETER OutputPath
    Folder for the CSVs. Default is OneDrive\EntraIntuneEvidence\<tenant>\<timestamp>.

.PARAMETER ServiceAccountPattern
    Extra regular expression matched against display name, UPN, and mail nickname.
    Use this when a tenant's service accounts do not follow svc / sa- / service account.

.EXAMPLE
    .\Get-EntraIntuneEvidence.ps1

.EXAMPLE
    .\Get-EntraIntuneEvidence.ps1 -ServiceAccountPattern 'backup|sql'
#>
[CmdletBinding()]
param(
    [string]$TenantId,

    [string]$OutputPath,

    [string]$ServiceAccountPattern
)

$ErrorActionPreference = 'Stop'

function Get-EvidenceProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $prop = $Object.PSObject.Properties[$Name]
    if (-not $prop) { return $null }
    return $prop.Value
}

function Get-SafeTenantFolderName {
    param([string]$Name)
    $safe = ($Name -replace '[^\w\-]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) { return 'tenant' }
    return $safe
}

function Get-EvidenceOneDriveRoot {
    foreach ($candidate in @($env:OneDriveCommercial, $env:OneDrive)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    $regPaths = @(
        'HKCU:\Software\Microsoft\OneDrive\Accounts\Business1'
        'HKCU:\Software\Microsoft\OneDrive\Accounts\Business2'
        'HKCU:\Software\Microsoft\OneDrive\Accounts\Personal'
    )
    foreach ($reg in $regPaths) {
        if (-not (Test-Path -LiteralPath $reg)) { continue }
        $item = Get-ItemProperty -LiteralPath $reg -ErrorAction SilentlyContinue
        $folder = $null
        if ($item -and $item.PSObject.Properties['UserFolder']) {
            $folder = [string]$item.UserFolder
        }
        if (-not [string]::IsNullOrWhiteSpace($folder) -and (Test-Path -LiteralPath $folder)) {
            return $folder
        }
    }

    return $null
}

function Get-EntraServiceAccountReasons {
    param(
        [string]$DisplayName,
        [string]$UserPrincipalName,
        [string]$MailNickname,
        [string]$JobTitle,
        [string]$Department,
        [string]$OnPremisesDistinguishedName,
        [string]$ExtraPattern
    )

    $reasons = New-Object System.Collections.Generic.List[string]
    $identity = (@($DisplayName, $UserPrincipalName, $MailNickname) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
    if ($identity -match '(?i)(^|[^a-z0-9])(svc|srv)([^a-z0-9]|$)') {
        $reasons.Add('Name')
    }
    elseif ($identity -match '(?i)service[._ -]?account') {
        $reasons.Add('Name')
    }
    elseif ($identity -match '(?i)(^|[^a-z0-9])sa[._-][a-z0-9]') {
        $reasons.Add('Name')
    }

    $roleText = (@($JobTitle, $Department) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
    if ($roleText -match '(?i)service account') {
        $reasons.Add('TitleOrDepartment')
    }
    if ($OnPremisesDistinguishedName -match '(?i)(^|,)\s*OU=[^,]*service') {
        $reasons.Add('OnPremisesOu')
    }
    if (-not [string]::IsNullOrWhiteSpace($ExtraPattern) -and $identity -match $ExtraPattern) {
        $reasons.Add('ExtraPattern')
    }

    $unique = New-Object System.Collections.Generic.List[string]
    foreach ($reason in $reasons) {
        if (-not $unique.Contains($reason)) { $unique.Add($reason) }
    }
    return $unique
}

function Test-IntuneWindowsWorkstation {
    param([string]$DeviceType)
    $kind = [string]$DeviceType
    if ([string]::IsNullOrWhiteSpace($kind)) { return $true }
    if ($kind -match '(?i)^(mac|macMDM|iPhone|iPad|iPod|android|androidForWork|androidEnterprise|blackberry|palm|nokia|unix|chromeOS|linux|winMO6|windowsPhone)$') {
        return $false
    }
    return $true
}

function Get-BitLockerDeployedVerdict {
    param(
        [string]$DeviceType,
        [string]$EncryptionState,
        $AdvancedBitLockerStates
    )

    if (-not (Test-IntuneWindowsWorkstation -DeviceType $DeviceType)) {
        return 'NotApplicable'
    }

    $flags = [string]$AdvancedBitLockerStates
    $osUnprotected = $false
    if ($flags -match 'osVolumeUnprotected') { $osUnprotected = $true }
    if ($flags -match '^\d+$') {
        $numeric = 0
        if ([int]::TryParse($flags, [ref]$numeric) -and (($numeric -band 2) -eq 2)) {
            $osUnprotected = $true
        }
    }
    if ($osUnprotected) { return 'No' }
    if ($EncryptionState -eq 'encrypted') { return 'Yes' }
    if ($flags -match '(^|[,\s])success($|[,\s])') { return 'Yes' }
    if ($flags -eq '0') { return 'Yes' }
    return 'No'
}

function ConvertTo-PolicyNameList {
    param($PolicyDetails)
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($policy in @($PolicyDetails)) {
        $name = Get-EvidenceProperty $policy 'policyName'
        if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
            [void]$names.Add([string]$name)
        }
    }
    return (($names | Select-Object -Unique) -join '; ')
}

function Export-EvidenceCsv {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        $Rows,
        [Parameter(Mandatory)]
        [string[]]$Headers
    )

    $list = @($Rows | Where-Object { $null -ne $_ })
    if ($list.Count -eq 0) {
        ($Headers -join ',') | Set-Content -LiteralPath $Path -Encoding utf8
        return
    }
    $list | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding utf8
}

function Invoke-EvidenceGraphGetAll {
    param([Parameter(Mandatory)][string]$Uri)

    $items = New-Object System.Collections.Generic.List[object]
    $next = $Uri
    while ($next) {
        $page = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject
        foreach ($row in @($page.value)) {
            if ($null -ne $row) { $items.Add($row) }
        }
        $next = [string](Get-EvidenceProperty $page '@odata.nextLink')
        if ([string]::IsNullOrWhiteSpace($next)) { $next = $null }
    }
    return $items.ToArray()
}

if ($MyInvocation.InvocationName -eq '.') { return }

if (-not [string]::IsNullOrWhiteSpace($ServiceAccountPattern)) {
    $null = [regex]::new($ServiceAccountPattern)
}

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    throw 'Microsoft.Graph is not installed. Run: Install-Module Microsoft.Graph -Scope CurrentUser'
}
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

$scopes = @(
    'User.Read.All'
    'Directory.Read.All'
    'AuditLog.Read.All'
    'DeviceManagementManagedDevices.Read.All'
    'DeviceManagementConfiguration.Read.All'
)

$context = Get-MgContext
$signedIn = $false
if ($context) {
    $have = @($context.Scopes)
    $signedIn = $true
    foreach ($scope in $scopes) {
        $found = $false
        foreach ($existing in $have) {
            if ([string]$existing -match [regex]::Escape($scope)) { $found = $true; break }
        }
        if (-not $found) { $signedIn = $false; break }
    }
}
if (-not $signedIn) {
    $connect = @{ Scopes = $scopes }
    if (-not [string]::IsNullOrWhiteSpace($TenantId)) { $connect['TenantId'] = $TenantId }
    Connect-MgGraph @connect
}

$org = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization?$select=displayName,id' -OutputType PSObject
$tenant = @($org.value) | Select-Object -First 1
$tenantName = [string](Get-EvidenceProperty $tenant 'displayName')
if ([string]::IsNullOrWhiteSpace($tenantName)) { $tenantName = 'tenant' }
Write-Host "Tenant: $tenantName"

if (-not $OutputPath) {
    $root = Get-EvidenceOneDriveRoot
    if (-not $root) {
        Write-Warning 'OneDrive folder was not found. Saving the export under Documents instead.'
        $root = [Environment]::GetFolderPath('MyDocuments')
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = Join-Path $root (Join-Path 'EntraIntuneEvidence' (Join-Path (Get-SafeTenantFolderName $tenantName) $stamp))
}
$null = New-Item -ItemType Directory -Path $OutputPath -Force
Write-Host "Export folder: $OutputPath"

$userSelect = 'id,displayName,userPrincipalName,mail,accountEnabled,userType,createdDateTime,department,jobTitle,mailNickname,onPremisesSyncEnabled,onPremisesDistinguishedName,onPremisesSamAccountName,passwordPolicies,assignedLicenses,signInActivity'
$userUri = "https://graph.microsoft.com/v1.0/users?`$select=$userSelect&`$top=999"
$users = $null
$signInIncluded = $true
try {
    $users = @(Invoke-EvidenceGraphGetAll -Uri $userUri)
}
catch {
    $signInIncluded = $false
    Write-Warning 'Sign-in activity was not readable. LastSignInDateTime will be blank. AuditLog.Read.All is required for that column.'
    $userSelect = $userSelect -replace ',signInActivity$', ''
    $userUri = "https://graph.microsoft.com/v1.0/users?`$select=$userSelect&`$top=999"
    $users = @(Invoke-EvidenceGraphGetAll -Uri $userUri)
}

$skuName = @{}
try {
    $skus = @(Invoke-EvidenceGraphGetAll -Uri 'https://graph.microsoft.com/v1.0/subscribedSkus?$select=skuId,skuPartNumber')
    foreach ($sku in $skus) {
        $id = [string](Get-EvidenceProperty $sku 'skuId')
        $part = [string](Get-EvidenceProperty $sku 'skuPartNumber')
        if ($id) { $skuName[$id] = $part }
    }
}
catch {
    Write-Warning 'Subscribed SKUs were not readable. LicenseSkus will be blank.'
}

$authorized = New-Object System.Collections.Generic.List[object]
$serviceAccounts = New-Object System.Collections.Generic.List[object]
foreach ($user in $users) {
    $displayName = [string](Get-EvidenceProperty $user 'displayName')
    $upn = [string](Get-EvidenceProperty $user 'userPrincipalName')
    $mailNick = [string](Get-EvidenceProperty $user 'mailNickname')
    $job = [string](Get-EvidenceProperty $user 'jobTitle')
    $dept = [string](Get-EvidenceProperty $user 'department')
    $dn = [string](Get-EvidenceProperty $user 'onPremisesDistinguishedName')
    $reasons = Get-EntraServiceAccountReasons -DisplayName $displayName -UserPrincipalName $upn -MailNickname $mailNick -JobTitle $job -Department $dept -OnPremisesDistinguishedName $dn -ExtraPattern $ServiceAccountPattern
    $likely = if ($reasons.Count -gt 0) { 'Yes' } else { 'No' }
    $enabled = Get-EvidenceProperty $user 'accountEnabled'
    $userType = [string](Get-EvidenceProperty $user 'userType')
    if ([string]::IsNullOrWhiteSpace($userType)) { $userType = 'Member' }
    $policies = [string](Get-EvidenceProperty $user 'passwordPolicies')
    $neverExpires = if ($policies -match 'DisablePasswordExpiration') { 'Yes' } else { 'No' }
    $licenses = @((Get-EvidenceProperty $user 'assignedLicenses'))
    $skuParts = New-Object System.Collections.Generic.List[string]
    foreach ($lic in $licenses) {
        $skuId = [string](Get-EvidenceProperty $lic 'skuId')
        if ($skuId -and $skuName.ContainsKey($skuId)) { [void]$skuParts.Add($skuName[$skuId]) }
        elseif ($skuId) { [void]$skuParts.Add($skuId) }
    }
    $lastSignIn = $null
    if ($signInIncluded) {
        $activity = Get-EvidenceProperty $user 'signInActivity'
        $lastSignIn = Get-EvidenceProperty $activity 'lastSignInDateTime'
    }
    $synced = Get-EvidenceProperty $user 'onPremisesSyncEnabled'
    $row = [pscustomobject][ordered]@{
        DisplayName              = $displayName
        UserPrincipalName        = $upn
        Mail                     = [string](Get-EvidenceProperty $user 'mail')
        SamAccountName           = [string](Get-EvidenceProperty $user 'onPremisesSamAccountName')
        AccountEnabled           = $enabled
        UserType                 = $userType
        OnPremisesSyncEnabled    = $synced
        Department               = $dept
        JobTitle                 = $job
        CreatedDateTime          = Get-EvidenceProperty $user 'createdDateTime'
        LastSignInDateTime       = $lastSignIn
        PasswordNeverExpires     = $neverExpires
        Licensed                 = $(if (@($licenses).Count -gt 0) { 'Yes' } else { 'No' })
        LicenseSkus              = ($skuParts -join '; ')
        LikelyServiceAccount     = $likely
        ServiceAccountReason     = ($reasons -join '; ')
        OnPremisesDistinguishedName = $dn
    }
    $isMember = $userType -eq 'Member'
    if ($enabled -eq $true -and $isMember) {
        $authorized.Add($row)
    }
    if ($likely -eq 'Yes') {
        $serviceAccounts.Add($row)
    }
}

$authorizedPath = Join-Path $OutputPath 'AuthorizedUsers.csv'
$servicePath = Join-Path $OutputPath 'ServiceAccounts.csv'
$userHeaders = @(
    'DisplayName', 'UserPrincipalName', 'Mail', 'SamAccountName', 'AccountEnabled', 'UserType',
    'OnPremisesSyncEnabled', 'Department', 'JobTitle', 'CreatedDateTime', 'LastSignInDateTime',
    'PasswordNeverExpires', 'Licensed', 'LicenseSkus', 'LikelyServiceAccount', 'ServiceAccountReason',
    'OnPremisesDistinguishedName'
)
Export-EvidenceCsv -Path $authorizedPath -Rows $authorized -Headers $userHeaders
Export-EvidenceCsv -Path $servicePath -Rows $serviceAccounts -Headers $userHeaders
Write-Host ("Authorized users (enabled members): {0}" -f $authorized.Count)
Write-Host ("Likely service accounts: {0}" -f $serviceAccounts.Count)

$encryptionUri = 'https://graph.microsoft.com/beta/deviceManagement/managedDeviceEncryptionStates'
$encryptionRows = @(Invoke-EvidenceGraphGetAll -Uri $encryptionUri)

$deviceById = @{}
$deviceByName = @{}
try {
    $deviceUri = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?$select=id,deviceName,lastSyncDateTime,serialNumber,model,complianceState,operatingSystem&$top=999'
    foreach ($device in @(Invoke-EvidenceGraphGetAll -Uri $deviceUri)) {
        $id = [string](Get-EvidenceProperty $device 'id')
        $name = [string](Get-EvidenceProperty $device 'deviceName')
        if ($id) { $deviceById[$id] = $device }
        if ($name -and -not $deviceByName.ContainsKey($name.ToLowerInvariant())) {
            $deviceByName[$name.ToLowerInvariant()] = $device
        }
    }
}
catch {
    Write-Warning 'Managed device details (last sync, serial) were not readable. BitLocker rows will still be written from the encryption report.'
}

$bitlocker = New-Object System.Collections.Generic.List[object]
$yes = 0
$no = 0
foreach ($state in $encryptionRows) {
    $deviceType = [string](Get-EvidenceProperty $state 'deviceType')
    if (-not (Test-IntuneWindowsWorkstation -DeviceType $deviceType)) { continue }
    $encryptionState = [string](Get-EvidenceProperty $state 'encryptionState')
    $advanced = Get-EvidenceProperty $state 'advancedBitLockerStates'
    $verdict = Get-BitLockerDeployedVerdict -DeviceType $deviceType -EncryptionState $encryptionState -AdvancedBitLockerStates $advanced
    if ($verdict -eq 'Yes') { $yes++ } else { $no++ }
    $id = [string](Get-EvidenceProperty $state 'id')
    $deviceName = [string](Get-EvidenceProperty $state 'deviceName')
    $managed = $null
    if ($id -and $deviceById.ContainsKey($id)) { $managed = $deviceById[$id] }
    elseif ($deviceName -and $deviceByName.ContainsKey($deviceName.ToLowerInvariant())) { $managed = $deviceByName[$deviceName.ToLowerInvariant()] }
    $bitlocker.Add([pscustomobject][ordered]@{
        DeviceName                   = $deviceName
        UserPrincipalName            = [string](Get-EvidenceProperty $state 'userPrincipalName')
        DeviceType                   = $deviceType
        OperatingSystem              = [string](Get-EvidenceProperty $managed 'operatingSystem')
        OsVersion                    = [string](Get-EvidenceProperty $state 'osVersion')
        SerialNumber                 = [string](Get-EvidenceProperty $managed 'serialNumber')
        Model                        = [string](Get-EvidenceProperty $managed 'model')
        LastSyncDateTime             = Get-EvidenceProperty $managed 'lastSyncDateTime'
        ComplianceState              = [string](Get-EvidenceProperty $managed 'complianceState')
        TpmSpecificationVersion      = [string](Get-EvidenceProperty $state 'tpmSpecificationVersion')
        EncryptionReadinessState     = [string](Get-EvidenceProperty $state 'encryptionReadinessState')
        EncryptionState              = $encryptionState
        EncryptionPolicySettingState = [string](Get-EvidenceProperty $state 'encryptionPolicySettingState')
        AdvancedBitLockerStates      = [string]$advanced
        BitLockerDeployed            = $verdict
        IntunePolicyNames            = ConvertTo-PolicyNameList (Get-EvidenceProperty $state 'policyDetails')
    })
}

$bitlockerPath = Join-Path $OutputPath 'BitLocker-Workstations.csv'
$bitlockerHeaders = @(
    'DeviceName', 'UserPrincipalName', 'DeviceType', 'OperatingSystem', 'OsVersion', 'SerialNumber',
    'Model', 'LastSyncDateTime', 'ComplianceState', 'TpmSpecificationVersion', 'EncryptionReadinessState',
    'EncryptionState', 'EncryptionPolicySettingState', 'AdvancedBitLockerStates', 'BitLockerDeployed',
    'IntunePolicyNames'
)
Export-EvidenceCsv -Path $bitlockerPath -Rows $bitlocker -Headers $bitlockerHeaders
Write-Host ("Windows workstations: {0}  BitLocker deployed: {1}  not deployed: {2}" -f $bitlocker.Count, $yes, $no)

$collected = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'
$notes = @(
    "Collected: $collected"
    "Tenant: $tenantName"
    ''
    'AuthorizedUsers.csv is every enabled Entra member. That is the Microsoft 365 directory.'
    'OnPremisesSyncEnabled = True means the account is synced from on-premises Active Directory.'
    'Accounts that exist only on a domain controller and are not synced to Entra are not in this file.'
    'Enabled guests are not in this file.'
    ''
    'ServiceAccounts.csv is not an official Entra object class. A row is included when the name'
    'looks like svc / srv / sa-, the title or department says service account, the on-premises OU'
    'contains "service", or -ServiceAccountPattern matches. PasswordNeverExpires is only a column.'
    'Review the list before sending it. A person named in a service OU will show up here.'
    ''
    'BitLocker-Workstations.csv is one row per Windows device in the Intune encryption report'
    '(Graph beta deviceManagement/managedDeviceEncryptionStates).'
    'BitLockerDeployed = Yes when Intune reports the device encrypted and the OS volume is not unprotected.'
    'IntunePolicyNames is the encryption policy Intune reports for that workstation.'
    'BitLocker recovery keys are not in this export.'
    ''
    "Authorized users: $($authorized.Count)"
    "Likely service accounts: $($serviceAccounts.Count)"
    "Windows workstations: $($bitlocker.Count)"
    "BitLocker deployed: $yes"
    "BitLocker not deployed: $no"
)
$notesPath = Join-Path $OutputPath 'Evidence-Notes.txt'
$notes -join [Environment]::NewLine | Set-Content -LiteralPath $notesPath -Encoding utf8
Write-Host "Notes: $notesPath"
