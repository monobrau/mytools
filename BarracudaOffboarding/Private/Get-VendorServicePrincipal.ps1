$script:HighRiskPermissions = @(
    'User.EnableDisableAccount.All'
    'User.ReadWrite.All'
    'Directory.ReadWrite.All'
    'Application.ReadWrite.All'
    'Mail.ReadWrite'
    'Exchange.ManageAsApp'
    'RoleManagement.ReadWrite.Directory'
)

function Resolve-AppRolePermissionName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ResourceId,

        [Parameter(Mandatory)]
        [string] $AppRoleId,

        [hashtable] $ResourceCache
    )

    if (-not $ResourceCache.ContainsKey($ResourceId)) {
        $resource = Get-MgServicePrincipal -ServicePrincipalId $ResourceId -Property Id, AppRoles, DisplayName -ErrorAction SilentlyContinue
        $ResourceCache[$ResourceId] = $resource
    }

    $resource = $ResourceCache[$ResourceId]
    if (-not $resource) {
        return $AppRoleId
    }

    $role = @($resource.AppRoles) | Where-Object { $_.Id -eq $AppRoleId } | Select-Object -First 1
    if ($role -and $role.Value) {
        return [string]$role.Value
    }

    return $AppRoleId
}

function Get-ServicePrincipalSignInActivity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $AppId
    )

    try {
        $filter = "appId eq '$AppId' and signInEventTypes/any(t: t eq 'servicePrincipal')"
        $uri = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=$([uri]::EscapeDataString($filter))&`$top=25"
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        $values = @($response.value)
        if ($values.Count -eq 0) {
            return @{ LastSignIn = $null; RecentSignIns = @() }
        }

        $parsed = foreach ($entry in $values) {
            $created = $null
            if ($entry.createdDateTime) {
                $created = [datetime]::Parse([string]$entry.createdDateTime).ToUniversalTime()
            }
            [pscustomobject]@{
                CreatedDateTime = $created
                IPAddress       = $entry.ipAddress
                Location        = $entry.location
                Status          = $entry.status
            }
        }

        $last = ($parsed | Where-Object { $_.CreatedDateTime } | Sort-Object CreatedDateTime -Descending | Select-Object -First 1)
        return @{
            LastSignIn    = if ($last) { $last.CreatedDateTime } else { $null }
            RecentSignIns = @($parsed)
        }
    }
    catch {
        Write-Warning "Unable to query service principal sign-ins for appId $AppId : $($_.Exception.Message)"
        return @{ LastSignIn = $null; RecentSignIns = @(); QueryError = $_.Exception.Message }
    }
}

function Get-VendorServicePrincipal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $VendorPatterns,

        [string[]] $KnownGoodServicePrincipals = @(),

        [int] $DormancyDays = 30
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    $resourceCache = @{}
    $matchedSps = [System.Collections.Generic.List[object]]::new()

    $sps = Get-MgServicePrincipal -All -Property Id, AppId, DisplayName, AccountEnabled, AppOwnerOrganizationId, ServicePrincipalType -ErrorAction Stop

    foreach ($sp in $sps) {
        if (-not (Test-VendorPatternMatch -Text $sp.DisplayName -Patterns $VendorPatterns)) {
            continue
        }

        $isKnownGood = $KnownGoodServicePrincipals -contains $sp.AppId -or $KnownGoodServicePrincipals -contains $sp.Id

        $assignments = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All -ErrorAction SilentlyContinue)
        $permissionNames = foreach ($assignment in $assignments) {
            Resolve-AppRolePermissionName -ResourceId $assignment.ResourceId -AppRoleId $assignment.AppRoleId -ResourceCache $resourceCache
        }
        $permissionNames = @($permissionNames | Select-Object -Unique)

        $grants = @(Get-MgOauth2PermissionGrant -Filter "clientId eq '$($sp.Id)'" -All -ErrorAction SilentlyContinue)
        $memberOf = @(Get-MgServicePrincipalMemberOf -ServicePrincipalId $sp.Id -All -ErrorAction SilentlyContinue)
        $directoryRoles = @(
            $memberOf | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.directoryRole' } |
                ForEach-Object { $_.AdditionalProperties.displayName }
        )

        $signInInfo = Get-ServicePrincipalSignInActivity -AppId $sp.AppId
        $lastActivity = $signInInfo.LastSignIn

        $hasHighRisk = $false
        foreach ($perm in $permissionNames) {
            if ($script:HighRiskPermissions -contains $perm -or $perm -like 'Policy.ReadWrite.*') {
                $hasHighRisk = $true
                break
            }
        }

        $severityFinding = $null
        $orgId = (Get-MgContext).TenantId
        if ($sp.AppOwnerOrganizationId -and $orgId -and ($sp.AppOwnerOrganizationId -eq $orgId)) {
            try {
                $app = Get-MgApplication -Filter "appId eq '$($sp.AppId)'" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($app) {
                    $appFull = Get-MgApplication -ApplicationId $app.Id -Property Id, DisplayName, PasswordCredentials, KeyCredentials -ErrorAction SilentlyContinue
                    if ($appFull) {
                        $pwdSummaries = @(
                            @($appFull.PasswordCredentials) | ForEach-Object {
                                [pscustomobject]@{
                                    DisplayName   = $_.DisplayName
                                    KeyId         = $_.KeyId
                                    StartDateTime = $_.StartDateTime
                                    EndDateTime   = $_.EndDateTime
                                    # Never include SecretText / secret values
                                }
                            }
                        )
                        $keySummaries = @(
                            @($appFull.KeyCredentials) | ForEach-Object {
                                [pscustomobject]@{
                                    DisplayName   = $_.DisplayName
                                    KeyId         = $_.KeyId
                                    Type          = $_.Type
                                    Usage         = $_.Usage
                                    StartDateTime = $_.StartDateTime
                                    EndDateTime   = $_.EndDateTime
                                }
                            }
                        )
                        $credentialFinding = New-Finding -Module 'AppRegistration' -Severity 'Medium' -ObjectType 'Application' `
                            -Name $appFull.DisplayName -Identifier $appFull.Id `
                            -Detail ("Tenant-owned app registration has {0} password credential(s) and {1} key credential(s). Credentials are reported only; Remediate does not delete them." -f $pwdSummaries.Count, $keySummaries.Count) `
                            -Evidence @{
                                AppId               = $sp.AppId
                                PasswordCredentialCount = $pwdSummaries.Count
                                KeyCredentialCount      = $keySummaries.Count
                                PasswordCredentials     = $pwdSummaries
                                KeyCredentials          = $keySummaries
                            } `
                            -Recommended 'Review' -AutoSafe:$false
                    }
                }
            }
            catch {
                Write-Warning "Unable to inspect app registration for $($sp.DisplayName): $($_.Exception.Message)"
            }
        }

        $detailParts = [System.Collections.Generic.List[string]]::new()
        [void]$detailParts.Add("Service principal matches vendor pattern. AccountEnabled=$($sp.AccountEnabled); Type=$($sp.ServicePrincipalType).")
        if ($permissionNames.Count -gt 0) {
            [void]$detailParts.Add("App roles: $($permissionNames -join ', ').")
        }
        if ($grants.Count -gt 0) {
            [void]$detailParts.Add("OAuth2 grants: $($grants.Count).")
        }
        if ($directoryRoles.Count -gt 0) {
            [void]$detailParts.Add("Directory roles: $($directoryRoles -join ', ').")
        }
        if ($lastActivity) {
            $ageDays = ([datetime]::UtcNow - $lastActivity).TotalDays
            if ($ageDays -le $DormancyDays) {
                [void]$detailParts.Add("WARNING: Signed in within the last $DormancyDays days (last activity $($lastActivity.ToString('u')) UTC). Vendor platform may still be polling; open a vendor-side offboarding ticket before/alongside revocation.")
            }
            else {
                [void]$detailParts.Add("Last sign-in: $($lastActivity.ToString('u')) UTC ($([int]$ageDays) days ago).")
            }
        }
        else {
            [void]$detailParts.Add('No service-principal sign-in events returned (dormancy is not assumed).')
        }

        $severity = if ($isKnownGood) {
            'Info'
        }
        elseif ($hasHighRisk) {
            'High'
        }
        elseif ($sp.AccountEnabled) {
            'High'
        }
        else {
            'Medium'
        }

        $recommended = if ($isKnownGood) {
            'None'
        }
        elseif ($hasHighRisk -or $sp.AccountEnabled) {
            'Revoke'
        }
        else {
            'Review'
        }

        $detail = if ($isKnownGood) {
            "Suppressed by knownGoodServicePrincipals. $($detailParts -join ' ')"
        }
        else {
            $detailParts -join ' '
        }

        $finding = New-Finding -Module 'ServicePrincipal' -Severity $severity -ObjectType 'ServicePrincipal' `
            -Name $sp.DisplayName -Identifier $sp.Id -Detail $detail `
            -Evidence @{
                AppId                   = $sp.AppId
                AccountEnabled          = $sp.AccountEnabled
                AppOwnerOrganizationId  = $sp.AppOwnerOrganizationId
                ServicePrincipalType    = $sp.ServicePrincipalType
                AppRolePermissions      = $permissionNames
                AppRoleAssignmentCount  = $assignments.Count
                Oauth2GrantCount        = $grants.Count
                Oauth2Scopes            = @($grants | ForEach-Object { $_.Scope })
                DirectoryRoles          = $directoryRoles
                RecentSignInCount       = @($signInInfo.RecentSignIns).Count
                KnownGood               = $isKnownGood
            } `
            -LastActivity $lastActivity -Recommended $recommended -AutoSafe:(-not $isKnownGood -and $recommended -eq 'Revoke')

        [void]$findings.Add($finding)
        [void]$matchedSps.Add($sp)

        if ($credentialFinding) {
            [void]$findings.Add($credentialFinding)
        }
    }

    # Conditional Access references to matched SPs
    if ($matchedSps.Count -gt 0) {
        $caFindings = Get-VendorConditionalAccessFinding -MatchedServicePrincipals $matchedSps
        foreach ($f in $caFindings) {
            [void]$findings.Add($f)
        }
    }

    return @($findings)
}

function Get-VendorConditionalAccessFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]] $MatchedServicePrincipals
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    $spIds = @($MatchedServicePrincipals | ForEach-Object { $_.Id })
    $spMap = @{}
    foreach ($sp in $MatchedServicePrincipals) {
        $spMap[$sp.Id] = $sp.DisplayName
    }

    try {
        $policies = @(Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop)
    }
    catch {
        Write-Warning "Unable to read Conditional Access policies: $($_.Exception.Message)"
        return @()
    }

    foreach ($policy in $policies) {
        $includeApps = @($policy.Conditions.Applications.IncludeApplications)
        $excludeApps = @($policy.Conditions.Applications.ExcludeApplications)
        $includeUsers = @($policy.Conditions.Users.IncludeUsers)
        $excludeUsers = @($policy.Conditions.Users.ExcludeUsers)
        $hits = [System.Collections.Generic.List[string]]::new()

        foreach ($id in $spIds) {
            if ($includeApps -contains $id -or $excludeApps -contains $id -or $includeUsers -contains $id -or $excludeUsers -contains $id) {
                [void]$hits.Add("$($spMap[$id]) ($id)")
            }
        }

        # Named locations: report for human review when policy references any; IP overlap with connectors is checked in connector module when ranges are supplied via Evidence later.
        $includeLocations = @($policy.Conditions.Locations.IncludeLocations)
        $excludeLocations = @($policy.Conditions.Locations.ExcludeLocations)

        if ($hits.Count -eq 0 -and $includeLocations.Count -eq 0 -and $excludeLocations.Count -eq 0) {
            continue
        }

        if ($hits.Count -eq 0) {
            continue
        }

        [void]$findings.Add((
            New-Finding -Module 'ConditionalAccess' -Severity 'Medium' -ObjectType 'ConditionalAccessPolicy' `
                -Name $policy.DisplayName -Identifier $policy.Id `
                -Detail ("Policy references matched service principal(s): {0}. Recommendation is Review only; CA changes are never automated." -f ($hits -join '; ')) `
                -Evidence @{
                    State            = $policy.State
                    MatchedPrincipals = @($hits)
                    IncludeApplications = $includeApps
                    ExcludeApplications = $excludeApps
                    IncludeLocations    = $includeLocations
                    ExcludeLocations    = $excludeLocations
                } `
                -Recommended 'Review' -AutoSafe:$false
        ))
    }

    return @($findings)
}
