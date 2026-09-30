#Requires -Version 5.1
<#
.SYNOPSIS
    Delete INKY, usecure, and Barracuda (Skout) enterprise apps from the signed-in Entra tenant.

.DESCRIPTION
    Finds service principals by display name. The app id and object id are different
    in each tenant, so the example IDs in the catalog are only an extra match when
    a vendor app was renamed. Shows a menu grouped by vendor, or selects with
    -Vendor, -AppId, or -All.

    Writes a JSON backup of each selected app, then deletes the service principal.
    -WhatIf writes the backup and does not delete. Restore from Entra deleted
    applications within 30 days; consents are not restored.

.PARAMETER Vendor
    Preselect every matching app for these vendors. Skips the menu.

.PARAMETER AppId
    Preselect by this tenant's app id or object id. Skips the menu.

.PARAMETER All
    Preselect every matching app in the tenant. Skips the menu.

.PARAMETER TenantId
    Passed to Connect-MgGraph when a new sign-in is required.

.PARAMETER OutputPath
    Backup folder. Default is Documents\EntraVendorAppRemoval\<tenant>\<timestamp>.

.PARAMETER CheckOnly
    List matching apps and stop. This is what the launcher sends for Scan.

.PARAMETER Delete
    Pick apps in the menu and delete them. This is what the launcher sends for Apply.

.PARAMETER Exit
    Exit the PowerShell process with a status code. The launcher sends this for Commands #!ps.

.PARAMETER NoExit
    Keep the PowerShell window open. Backstage omits -Exit, which already does this.

.PARAMETER Force
    Skip the typed DELETE confirmation. -WhatIf still does not delete.

.EXAMPLE
    .\Remove-VendorEnterpriseApps.ps1

.EXAMPLE
    .\Remove-VendorEnterpriseApps.ps1 -Vendor Inky,Usecure -WhatIf

.EXAMPLE
    .\Remove-VendorEnterpriseApps.ps1 -All
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Inky', 'Usecure', 'Barracuda')]
    [string[]]$Vendor,

    [string[]]$AppId,

    [switch]$All,

    [string]$TenantId,

    [string]$OutputPath,

    [switch]$CheckOnly,

    [switch]$Delete,

    [switch]$Exit,

    [switch]$NoExit,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# The launcher runs this file from a script block, so there is no script path
# and Private\ is not downloaded. These functions live in this file.

function Get-VendorEnterpriseAppCatalog {
    @(
        [pscustomobject]@{ Vendor = 'Inky'; VendorLabel = 'INKY'; Name = 'INKY Phish Fence - Installation'; ExampleId = '939be9d0-ed9f-48df-8867-f04004e7e460' }
        [pscustomobject]@{ Vendor = 'Inky'; VendorLabel = 'INKY'; Name = 'Inky Dashboard SSO'; ExampleId = '35343bd4-37f5-410b-bb69-fd23e9da03a6' }
        [pscustomobject]@{ Vendor = 'Inky'; VendorLabel = 'INKY'; Name = 'INKY Phish Fence - Directory Synchronization'; ExampleId = 'f02bffa3-76d9-41d3-8452-3d548c1290b7' }
        [pscustomobject]@{ Vendor = 'Inky'; VendorLabel = 'INKY'; Name = 'Inky Phish Fence Remediation'; ExampleId = 'dadbac07-d008-4b2d-b954-732074411c81' }
        [pscustomobject]@{ Vendor = 'Inky'; VendorLabel = 'INKY'; Name = 'INKY - Setup and Maintenance'; ExampleId = '0fdacf15-7cc1-4477-82df-b88e0ce107f3' }
        [pscustomobject]@{ Vendor = 'Usecure'; VendorLabel = 'usecure'; Name = 'usecure'; ExampleId = 'ccfeac09-c6ae-4dd7-b621-2f3c0bcf72d5' }
        [pscustomobject]@{ Vendor = 'Usecure'; VendorLabel = 'usecure'; Name = 'usecure - Message Injection'; ExampleId = '24decd76-8045-478f-b5d5-35b6b254d0d0' }
        [pscustomobject]@{ Vendor = 'Barracuda'; VendorLabel = 'Barracuda (Skout)'; Name = 'Skout Cybersecurity'; ExampleId = '9ad0f9b6-8ca4-4839-b1c8-061bad20e8da' }
    )
}

function Resolve-VendorAppCategory {
    param(
        [string]$DisplayName,
        [string]$AppId,
        [string]$ObjectId,
        $Catalog
    )

    $name = [string]$DisplayName
    $fromName = $null
    if ($name -match '(?i)phish\s*fence|\binky\b') {
        $fromName = 'Inky'
    }
    elseif ($name -match '(?i)u-?secure') {
        $fromName = 'Usecure'
    }
    elseif ($name -match '(?i)\bskout\b' -or ($name -match '(?i)barracuda' -and $name -match '(?i)cybersecurity')) {
        $fromName = 'Barracuda'
    }

    if ($fromName) { return $fromName }

    $candidates = @($AppId, $ObjectId) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($item in @($Catalog)) {
        foreach ($candidate in $candidates) {
            if ([string]$item.ExampleId -eq [string]$candidate) {
                return [string]$item.Vendor
            }
        }
    }

    return $null
}

function Add-VendorAppMenuNumbers {
    param($Apps)

    $n = 0
    foreach ($app in @($Apps)) {
        if ($null -eq $app) { continue }
        if ($app.Found) {
            $n++
            $app | Add-Member -NotePropertyName Number -NotePropertyValue $n -Force
        }
        else {
            $app | Add-Member -NotePropertyName Number -NotePropertyValue $null -Force
        }
    }
    return @($Apps)
}

function ConvertFrom-VendorAppSelection {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$InputText,

        [AllowEmptyCollection()]
        [object[]]$NumberedApps = @()
    )

    $text = if ($null -eq $InputText) { '' } else { $InputText.Trim() }
    if ([string]::IsNullOrWhiteSpace($text)) {
        return [pscustomobject]@{ Action = 'Invalid'; AppIds = @(); Message = 'Enter a selection.' }
    }
    if ($text -match '^(?i)q(uit)?$') {
        return [pscustomobject]@{ Action = 'Quit'; AppIds = @(); Message = '' }
    }

    $numbered = @($NumberedApps | Where-Object { $null -ne $_ -and $null -ne $_.Number })
    $byNumber = @{}
    foreach ($app in $numbered) {
        $byNumber[[string][int]$app.Number] = $app
    }

    if ($text -match '^(?i)all$') {
        if ($byNumber.Count -eq 0) {
            return [pscustomobject]@{ Action = 'Invalid'; AppIds = @(); Message = 'Nothing is in this tenant.' }
        }
        return [pscustomobject]@{ Action = 'Select'; AppIds = @($numbered | ForEach-Object { [string]$_.AppId }); Message = '' }
    }

    $vendorMap = @{
        'inky'      = 'Inky'
        'usecure'   = 'Usecure'
        'u-secure'  = 'Usecure'
        'barracuda' = 'Barracuda'
        'skout'     = 'Barracuda'
    }
    $key = $text.ToLowerInvariant()
    if ($vendorMap.ContainsKey($key)) {
        $vendor = $vendorMap[$key]
        $hits = @($numbered | Where-Object { $_.Vendor -eq $vendor })
        if ($hits.Count -eq 0) {
            return [pscustomobject]@{ Action = 'Invalid'; AppIds = @(); Message = "No $vendor apps are in this tenant." }
        }
        return [pscustomobject]@{ Action = 'Select'; AppIds = @($hits | ForEach-Object { [string]$_.AppId }); Message = '' }
    }

    $tokens = @($text -split '[,\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($token in $tokens) {
        $range = [regex]::Match($token, '^(\d+)-(\d+)$')
        if ($range.Success) {
            $start = [int]$range.Groups[1].Value
            $end = [int]$range.Groups[2].Value
            if ($end -lt $start) {
                return [pscustomobject]@{ Action = 'Invalid'; AppIds = @(); Message = "Range $token is backwards." }
            }
            for ($n = $start; $n -le $end; $n++) {
                $keyN = [string]$n
                if (-not $byNumber.ContainsKey($keyN)) {
                    return [pscustomobject]@{ Action = 'Invalid'; AppIds = @(); Message = "Number $n is not in the list." }
                }
                [void]$ids.Add([string]$byNumber[$keyN].AppId)
            }
            continue
        }

        if ($token -match '^\d+$') {
            if (-not $byNumber.ContainsKey([string][int]$token)) {
                return [pscustomobject]@{ Action = 'Invalid'; AppIds = @(); Message = "Number $token is not in the list." }
            }
            [void]$ids.Add([string]$byNumber[[string][int]$token].AppId)
            continue
        }

        return [pscustomobject]@{
            Action  = 'Invalid'
            AppIds  = @()
            Message = "Could not read '$token'. Use numbers (1,3 or 1-3), a vendor name, all, or q."
        }
    }

    $unique = @($ids | Select-Object -Unique)
    return [pscustomobject]@{ Action = 'Select'; AppIds = $unique; Message = '' }
}

function Complete-VendorAppRemoval {
    param([Parameter(Mandatory)][int]$Code)
    $global:LASTEXITCODE = $Code
    # $script: is the launcher's scope when this file is invoked as a script block.
    if ($Exit -and -not $NoExit) { exit $Code }
    break VendorAppRun
}

function Test-VendorAppModule {
    $missing = @()
    foreach ($name in @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Applications')) {
        if (-not (Get-Module -ListAvailable -Name $name)) { $missing += $name }
    }
    if ($missing.Count -gt 0) {
        throw @"
Missing required module(s): $($missing -join ', ').
Install hint:
Install-Module Microsoft.Graph -Scope CurrentUser
"@
    }
}

function Connect-VendorAppGraph {
    param([string]$TenantId)

    $scopes = @('Application.ReadWrite.All', 'Directory.Read.All')
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    $need = -not $ctx
    if ($ctx) {
        $have = @($ctx.Scopes)
        foreach ($scope in $scopes) {
            if ($have -notcontains $scope) { $need = $true; break }
        }
        if ($TenantId -and [string]$ctx.TenantId -ne $TenantId) { $need = $true }
    }
    if ($need) {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        Import-Module Microsoft.Graph.Applications -ErrorAction Stop
        $connect = @{ Scopes = $scopes; NoWelcome = $true; ErrorAction = 'Stop' }
        if ($TenantId) { $connect.TenantId = $TenantId }
        Connect-MgGraph @connect | Out-Null
    }
    return (Get-MgContext)
}

function Get-VendorAppTenant {
    $ctx = Get-MgContext
    $name = [string]$ctx.TenantId
    $id = [string]$ctx.TenantId
    $dirModule = Get-Module -ListAvailable -Name 'Microsoft.Graph.Identity.DirectoryManagement' | Select-Object -First 1
    if ($dirModule) {
        try {
            Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop
            $org = Get-MgOrganization -ErrorAction Stop | Select-Object -First 1
            if ($org -and $org.DisplayName) { $name = [string]$org.DisplayName }
            if ($org -and $org.Id) { $id = [string]$org.Id }
        }
        catch {
            Write-Warning "Could not read the organization name: $($_.Exception.Message)"
        }
    }
    [pscustomobject]@{
        DisplayName = $name
        TenantId    = $id
        Account     = [string]$ctx.Account
    }
}

function Get-VendorObjectProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Get-ServicePrincipalByExampleId {
    param([string]$Id)
    $hits = New-Object System.Collections.Generic.List[object]
    try {
        $byObject = Get-MgServicePrincipal -ServicePrincipalId $Id -ErrorAction Stop
        if ($byObject) { [void]$hits.Add($byObject) }
    }
    catch { }
    try {
        $byApp = @(Get-MgServicePrincipal -Filter "appId eq '$Id'" -ErrorAction Stop)
        foreach ($sp in $byApp) {
            if ($sp) { [void]$hits.Add($sp) }
        }
    }
    catch { }
    return $hits.ToArray()
}

function Find-ServicePrincipalsByDisplayName {
    param([string]$Term)
    $props = 'Id,AppId,DisplayName,AccountEnabled,CreatedDateTime,ServicePrincipalType,AppOwnerOrganizationId,AppDisplayName'
    try {
        $spCount = 0
        $search = '"displayName:{0}"' -f $Term
        return @(Get-MgServicePrincipal -Search $search -ConsistencyLevel eventual -CountVariable spCount -All -Property $props -ErrorAction Stop)
    }
    catch {
        Write-Warning "Display name search for '$Term' failed ($($_.Exception.Message)). Trying startswith."
    }

    $rows = New-Object System.Collections.Generic.List[object]
    $prefixes = @($Term, (Get-Culture).TextInfo.ToTitleCase($Term.ToLowerInvariant()), $Term.ToUpperInvariant())
    foreach ($prefix in @($prefixes | Select-Object -Unique)) {
        if ($prefix -match '\s') { continue }
        try {
            $batch = @(Get-MgServicePrincipal -Filter "startswith(displayName,'$prefix')" -All -Property $props -ErrorAction Stop)
            foreach ($sp in $batch) { if ($sp) { [void]$rows.Add($sp) } }
        }
        catch {
            Write-Warning "startswith '$prefix' failed: $($_.Exception.Message)"
        }
    }
    return $rows.ToArray()
}

function Get-DiscoveredVendorApps {
    param($Catalog)

    $byObjectId = @{}
    $terms = @('inky', 'usecure', 'skout', 'barracuda', 'phish')
    foreach ($term in $terms) {
        Write-Host "Searching enterprise apps for '$term'..."
        foreach ($sp in @(Find-ServicePrincipalsByDisplayName -Term $term)) {
            $objectId = [string](Get-VendorObjectProperty $sp 'Id')
            if ($objectId) { $byObjectId[$objectId] = $sp }
        }
    }
    foreach ($item in @($Catalog)) {
        foreach ($sp in @(Get-ServicePrincipalByExampleId -Id $item.ExampleId)) {
            $objectId = [string](Get-VendorObjectProperty $sp 'Id')
            if ($objectId) { $byObjectId[$objectId] = $sp }
        }
    }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($key in @($byObjectId.Keys)) {
        $sp = $byObjectId[$key]
        $displayName = [string](Get-VendorObjectProperty $sp 'DisplayName')
        $appId = [string](Get-VendorObjectProperty $sp 'AppId')
        $objectId = [string](Get-VendorObjectProperty $sp 'Id')
        $vendor = Resolve-VendorAppCategory -DisplayName $displayName -AppId $appId -ObjectId $objectId -Catalog $Catalog
        if (-not $vendor) { continue }
        $label = @($Catalog | Where-Object { $_.Vendor -eq $vendor } | Select-Object -First 1).VendorLabel
        $enabled = Get-VendorObjectProperty $sp 'AccountEnabled'
        [void]$rows.Add([pscustomobject]@{
                Vendor           = $vendor
                VendorLabel      = $label
                Name             = $displayName
                AppId            = $appId
                ObjectId         = $objectId
                Found            = $true
                AccountEnabled   = [bool]$enabled
                Created          = Get-VendorObjectProperty $sp 'CreatedDateTime'
                ServicePrincipal = $sp
            })
    }

    $order = @{ Inky = 0; Usecure = 1; Barracuda = 2 }
    return @($rows.ToArray() | Sort-Object {
            $rank = 9
            if ($order.ContainsKey([string]$_.Vendor)) { $rank = [int]$order[[string]$_.Vendor] }
            '{0:D2}|{1}' -f $rank, [string]$_.Name
        })
}

function Show-VendorAppMenu {
    param(
        $Apps,
        [switch]$ListOnly
    )
    $labels = @{ Inky = 'INKY'; Usecure = 'usecure'; Barracuda = 'Barracuda (Skout)' }
    foreach ($vendor in @('Inky', 'Usecure', 'Barracuda')) {
        $group = @($Apps | Where-Object { $_.Vendor -eq $vendor })
        if ($group.Count -eq 0) { continue }
        Write-Host ''
        Write-Host $labels[$vendor]
        foreach ($app in $group) {
            $state = if ($app.AccountEnabled) { 'enabled' } else { 'disabled' }
            Write-Host ("  [{0}] {1}" -f $app.Number, $app.Name)
            Write-Host ("      appId {0}  objectId {1}  {2}" -f $app.AppId, $app.ObjectId, $state)
        }
    }
    if ($ListOnly) { return }
    Write-Host ''
    Write-Host 'Select: numbers (1,3 or 1-3), a vendor (inky, usecure, barracuda), all, or q to quit'
}

function ConvertTo-VendorSpRecord {
    param($Sp)
    [pscustomobject]@{
        Id                     = [string](Get-VendorObjectProperty $Sp 'Id')
        AppId                  = [string](Get-VendorObjectProperty $Sp 'AppId')
        DisplayName            = [string](Get-VendorObjectProperty $Sp 'DisplayName')
        AppDisplayName         = [string](Get-VendorObjectProperty $Sp 'AppDisplayName')
        AccountEnabled         = [bool](Get-VendorObjectProperty $Sp 'AccountEnabled')
        AppOwnerOrganizationId = [string](Get-VendorObjectProperty $Sp 'AppOwnerOrganizationId')
        ServicePrincipalType   = [string](Get-VendorObjectProperty $Sp 'ServicePrincipalType')
        CreatedDateTime        = [string](Get-VendorObjectProperty $Sp 'CreatedDateTime')
    }
}

function ConvertTo-VendorAssignmentRecord {
    param($Item)
    [pscustomobject]@{
        Id                   = [string](Get-VendorObjectProperty $Item 'Id')
        PrincipalId          = [string](Get-VendorObjectProperty $Item 'PrincipalId')
        PrincipalDisplayName = [string](Get-VendorObjectProperty $Item 'PrincipalDisplayName')
        PrincipalType        = [string](Get-VendorObjectProperty $Item 'PrincipalType')
        AppRoleId            = [string](Get-VendorObjectProperty $Item 'AppRoleId')
        ResourceId           = [string](Get-VendorObjectProperty $Item 'ResourceId')
        ResourceDisplayName  = [string](Get-VendorObjectProperty $Item 'ResourceDisplayName')
    }
}

function ConvertTo-VendorGrantRecord {
    param($Item)
    [pscustomobject]@{
        Id          = [string](Get-VendorObjectProperty $Item 'Id')
        ClientId    = [string](Get-VendorObjectProperty $Item 'ClientId')
        ConsentType = [string](Get-VendorObjectProperty $Item 'ConsentType')
        PrincipalId = [string](Get-VendorObjectProperty $Item 'PrincipalId')
        ResourceId  = [string](Get-VendorObjectProperty $Item 'ResourceId')
        Scope       = [string](Get-VendorObjectProperty $Item 'Scope')
    }
}

function Get-SafeTenantFolderName {
    param([string]$Name)
    $safe = ($Name -replace '[^\w\-]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) { return 'tenant' }
    return $safe
}

# Dot-sourcing loads the functions for tests and does not sign in.
if ($MyInvocation.InvocationName -eq '.') { return }

Set-StrictMode -Version Latest
:VendorAppRun foreach ($_vendorAppOnce in 1) {
Test-VendorAppModule
$catalog = @(Get-VendorEnterpriseAppCatalog)
$ctx = Connect-VendorAppGraph -TenantId $TenantId
$tenant = Get-VendorAppTenant

Write-Host ''
Write-Host "Tenant: $($tenant.DisplayName) ($($tenant.TenantId))"
Write-Host "Signed in: $($tenant.Account)"
Write-Host 'Matching INKY, usecure, and Skout by name. App ids differ per tenant.'
Write-Host ''

$discovered = @(Add-VendorAppMenuNumbers -Apps @(Get-DiscoveredVendorApps -Catalog $catalog))
if ($discovered.Count -eq 0) {
    Write-Host "No INKY, usecure, or Skout enterprise apps were found in $($tenant.DisplayName)."
    Complete-VendorAppRemoval -Code 0
}

if ($CheckOnly) {
    Show-VendorAppMenu -Apps $discovered -ListOnly
    Write-Host ''
    Write-Host 'List only. Run again with -Delete to pick apps and remove them.'
    Complete-VendorAppRemoval -Code 0
}

$preselected = ($All -or $Vendor -or $AppId)
if (-not $preselected -and -not [Environment]::UserInteractive) {
    throw 'Pass -Vendor, -AppId, or -All when there is no console.'
}

$selectedKeys = @()
if ($preselected) {
    $pool = @($discovered)
    if ($Vendor) {
        $pool = @($pool | Where-Object { $Vendor -contains $_.Vendor })
    }
    if ($AppId) {
        $wanted = @($AppId | ForEach-Object { $_.ToLowerInvariant() })
        $known = @()
        foreach ($app in $discovered) {
            $known += $app.AppId.ToLowerInvariant()
            $known += $app.ObjectId.ToLowerInvariant()
        }
        foreach ($id in $wanted) {
            if ($known -notcontains $id) {
                Write-Warning "$id was not found in this tenant."
            }
        }
        $pool = @($pool | Where-Object {
                $wanted -contains $_.AppId.ToLowerInvariant() -or $wanted -contains $_.ObjectId.ToLowerInvariant()
            })
    }
    $selectedKeys = @($pool | ForEach-Object { $_.AppId })
}
else {
    while ($true) {
        Show-VendorAppMenu -Apps $discovered
        $raw = Read-Host 'Select'
        $parsed = ConvertFrom-VendorAppSelection -InputText $raw -NumberedApps $discovered
        if ($parsed.Action -eq 'Quit') {
            Write-Host 'Cancelled.'
            Complete-VendorAppRemoval -Code 0
        }
        if ($parsed.Action -eq 'Invalid') {
            Write-Host $parsed.Message
            continue
        }
        $selectedKeys = @($parsed.AppIds)
        break
    }
}

$selected = @($discovered | Where-Object { $selectedKeys -contains $_.AppId })
if ($selected.Count -eq 0) {
    Write-Host 'Nothing selected.'
    Complete-VendorAppRemoval -Code 0
}

Write-Host ''
Write-Host 'Selected:'
foreach ($app in $selected) {
    Write-Host ("  {0}  [{1}]  {2}" -f $app.VendorLabel, $app.Name, $app.AppId)
    Write-Host ("    objectId {0}" -f $app.ObjectId)
}

if (-not $WhatIfPreference -and -not $Force) {
    $typed = Read-Host "Type DELETE to remove $($selected.Count) app(s) from $($tenant.DisplayName)"
    if ($typed -ne 'DELETE') {
        Write-Host 'Cancelled.'
        Complete-VendorAppRemoval -Code 0
    }
}

if (-not $OutputPath) {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = Join-Path $docs (Join-Path 'EntraVendorAppRemoval' (Join-Path (Get-SafeTenantFolderName $tenant.DisplayName) $stamp))
}
$null = New-Item -ItemType Directory -Path $OutputPath -Force
Write-Host "Backup folder: $OutputPath"

foreach ($app in $selected) {
    $assignedTo = @()
    $assignments = @()
    $grants = @()
    try {
        $assignedTo = @(Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $app.ObjectId -All -ErrorAction Stop)
    }
    catch { Write-Warning "Could not read assignments to $($app.Name): $($_.Exception.Message)" }
    try {
        $assignments = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $app.ObjectId -All -ErrorAction Stop)
    }
    catch { Write-Warning "Could not read app role assignments for $($app.Name): $($_.Exception.Message)" }
    try {
        $grants = @(Get-MgOauth2PermissionGrant -Filter "clientId eq '$($app.ObjectId)'" -All -ErrorAction Stop)
    }
    catch { Write-Warning "Could not read delegated grants for $($app.Name): $($_.Exception.Message)" }

    $payload = [pscustomobject]@{
        ExportedAt            = (Get-Date).ToString('o')
        TenantId              = $tenant.TenantId
        TenantName            = $tenant.DisplayName
        Vendor                = $app.Vendor
        ServicePrincipal      = (ConvertTo-VendorSpRecord $app.ServicePrincipal)
        AppRoleAssignedTo     = @($assignedTo | ForEach-Object { ConvertTo-VendorAssignmentRecord $_ })
        AppRoleAssignments    = @($assignments | ForEach-Object { ConvertTo-VendorAssignmentRecord $_ })
        Oauth2PermissionGrants = @($grants | ForEach-Object { ConvertTo-VendorGrantRecord $_ })
    }
    $path = Join-Path $OutputPath ("{0}.json" -f $app.AppId)
    $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8
}

foreach ($app in $selected) {
    $path = Join-Path $OutputPath ("{0}.json" -f $app.AppId)
    if (-not (Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -le 0) {
        throw "Backup verification failed: $path. Nothing was deleted."
    }
}
Write-Host 'Backup verified on disk.'

$results = New-Object System.Collections.Generic.List[object]
foreach ($app in $selected) {
    if ($WhatIfPreference -or -not $PSCmdlet.ShouldProcess("$($app.Name) [$($app.AppId)]", 'Remove service principal')) {
        [void]$results.Add([pscustomobject]@{
                Vendor = $app.Vendor; Name = $app.Name; AppId = $app.AppId; ObjectId = $app.ObjectId
                Result = 'WhatIf'; Detail = 'Not deleted'
            })
        continue
    }

    try {
        Remove-MgServicePrincipal -ServicePrincipalId $app.ObjectId -ErrorAction Stop
        $still = @(Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" -ErrorAction SilentlyContinue)
        if ($still.Count -gt 0) {
            [void]$results.Add([pscustomobject]@{
                    Vendor = $app.Vendor; Name = $app.Name; AppId = $app.AppId; ObjectId = $app.ObjectId
                    Result = 'Failed'; Detail = 'Service principal still present after delete'
                })
        }
        else {
            [void]$results.Add([pscustomobject]@{
                    Vendor = $app.Vendor; Name = $app.Name; AppId = $app.AppId; ObjectId = $app.ObjectId
                    Result = 'Deleted'; Detail = ''
                })
        }
    }
    catch {
        [void]$results.Add([pscustomobject]@{
                Vendor = $app.Vendor; Name = $app.Name; AppId = $app.AppId; ObjectId = $app.ObjectId
                Result = 'Failed'; Detail = $_.Exception.Message
            })
    }
}

$csvPath = Join-Path $OutputPath 'results.csv'
$results | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8
Write-Host ''
$results | Format-Table Vendor, Name, AppId, Result, Detail -AutoSize | Out-Host
Write-Host "Results: $csvPath"

$deleted = @($results | Where-Object { $_.Result -eq 'Deleted' })
if ($deleted.Count -gt 0) {
    Write-Host ''
    Write-Host 'Deleted enterprise apps stay under Entra > Enterprise applications > Deleted applications for 30 days.'
    Write-Host 'Restore one with: Restore-MgDirectoryDeletedItem -DirectoryObjectId <objectId>'
    Write-Host 'Restoring brings the app back. Consents are not restored. The JSON backup lists them.'
    foreach ($row in $deleted) {
        Write-Host ("  {0}  {1}" -f $row.Name, $row.ObjectId)
    }
}

$failed = @($results | Where-Object { $_.Result -eq 'Failed' })
if ($failed.Count -gt 0) { Complete-VendorAppRemoval -Code 2 }
Complete-VendorAppRemoval -Code 0
}
