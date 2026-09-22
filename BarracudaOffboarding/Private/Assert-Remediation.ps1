function Assert-Remediation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $RemediatedFindings,

        [Parameter(Mandatory)]
        [string] $OutputDirectory
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add('# Remediation Verification')
    [void]$lines.Add("Generated: $(ConvertTo-ReportLocalTime -UtcDateTime ([datetime]::UtcNow))")
    [void]$lines.Add('')

    $failed = 0

    $spFindings = @($RemediatedFindings | Where-Object { $_.Module -eq 'ServicePrincipal' -and $_.Recommended -eq 'Revoke' -and -not $_.Evidence.KnownGood })
    foreach ($f in $spFindings) {
        $spId = $f.Identifier
        $sp = Get-MgServicePrincipal -ServicePrincipalId $spId -Property Id, DisplayName, AccountEnabled -ErrorAction SilentlyContinue
        $assignments = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $spId -All -ErrorAction SilentlyContinue)
        $grants = @(Get-MgOauth2PermissionGrant -Filter "clientId eq '$spId'" -All -ErrorAction SilentlyContinue)

        $enabledOk = $sp -and ($sp.AccountEnabled -eq $false)
        $rolesOk = $assignments.Count -eq 0
        $grantsOk = $grants.Count -eq 0
        $pass = $enabledOk -and $rolesOk -and $grantsOk

        if (-not $pass) { $failed++ }
        $status = if ($pass) { 'PASS' } else { 'FAIL' }
        [void]$lines.Add("- [$status] ServicePrincipal $($f.Name) ($spId): AccountEnabled=$($sp.AccountEnabled); AppRoleAssignments=$($assignments.Count); Oauth2Grants=$($grants.Count)")
    }

    $ruleFindings = @($RemediatedFindings | Where-Object { $_.Module -eq 'TransportRule' -and $_.Recommended -eq 'Disable' -and $_.AutoSafe })
    foreach ($f in $ruleFindings) {
        $rule = Get-TransportRule -Identity $f.Identifier -ErrorAction SilentlyContinue
        $pass = $rule -and ([string]$rule.State -eq 'Disabled')
        if (-not $pass) { $failed++ }
        $status = if ($pass) { 'PASS' } else { 'FAIL' }
        $state = if ($rule) { $rule.State } else { 'Missing' }
        [void]$lines.Add("- [$status] TransportRule $($f.Name): State=$state")
    }

    if ($spFindings.Count -eq 0 -and $ruleFindings.Count -eq 0) {
        [void]$lines.Add('No remediated objects to verify.')
    }

    [void]$lines.Add('')
    if ($failed -eq 0) {
        [void]$lines.Add('Overall: PASS')
    }
    else {
        [void]$lines.Add("Overall: FAIL ($failed assertion(s) failed)")
    }

    $path = Join-Path $OutputDirectory 'verification.md'
    $lines -join [Environment]::NewLine | Set-Content -LiteralPath $path -Encoding utf8

    return [pscustomobject]@{
        Path       = $path
        FailedCount = $failed
        Passed     = ($failed -eq 0)
    }
}
