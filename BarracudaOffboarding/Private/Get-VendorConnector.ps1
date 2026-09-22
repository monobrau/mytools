function Get-VendorConnector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $VendorPatterns,

        [object[]] $TransportRuleFindings = @()
    )

    $findings = [System.Collections.Generic.List[object]]::new()

    # Collect IP ranges from flagged transport rules for connection-filter overlap checks
    $ruleIpRanges = [System.Collections.Generic.List[string]]::new()
    foreach ($tf in $TransportRuleFindings) {
        foreach ($ip in @($tf.Evidence.SenderIpRanges)) {
            if ($ip) { [void]$ruleIpRanges.Add([string]$ip) }
        }
    }

    $inbound = @(Get-InboundConnector -ErrorAction Stop)
    $outbound = @(Get-OutboundConnector -ErrorAction Stop)
    $connectorIpRanges = [System.Collections.Generic.List[string]]::new()

    foreach ($connector in $inbound) {
        $senderIps = @($connector.SenderIPAddresses)
        $nameMatch = Test-VendorPatternMatch -Text $connector.Name -Patterns $VendorPatterns
        $partnerWithIps = ($connector.ConnectorType -eq 'Partner' -and $senderIps.Count -gt 0)

        if (-not ($nameMatch -or $partnerWithIps)) {
            continue
        }

        foreach ($ip in $senderIps) {
            if ($ip) { [void]$connectorIpRanges.Add([string]$ip) }
        }

        $severity = if ($nameMatch) { 'High' } else { 'Medium' }
        $detail = if ($nameMatch) {
            "Inbound connector name matches vendor pattern. ConnectorType=$($connector.ConnectorType); Enabled=$($connector.Enabled)."
        }
        else {
            "Partner inbound connector with populated SenderIPAddresses (candidate for review). Enabled=$($connector.Enabled)."
        }
        $detail += " EFSkipLastIP=$($connector.EFSkipLastIP); EFSkipIPs=$($connector.EFSkipIPs -join ', ')."

        [void]$findings.Add((
            New-Finding -Module 'InboundConnector' -Severity $severity -ObjectType 'InboundConnector' `
                -Name $connector.Name -Identifier $connector.Name -Detail $detail `
                -Evidence @{
                    ConnectorType      = [string]$connector.ConnectorType
                    Enabled            = [bool]$connector.Enabled
                    SenderIPAddresses  = $senderIps
                    EFSkipLastIP       = $connector.EFSkipLastIP
                    EFSkipIPs          = @($connector.EFSkipIPs)
                    NameMatch          = $nameMatch
                } `
                -Recommended 'Review' -AutoSafe:$false
        ))
    }

    foreach ($connector in $outbound) {
        $smartHosts = @($connector.SmartHosts)
        $matchedHosts = @(
            $smartHosts | Where-Object { Test-VendorPatternMatch -Text ([string]$_) -Patterns $VendorPatterns }
        )
        $nameMatch = Test-VendorPatternMatch -Text $connector.Name -Patterns $VendorPatterns

        if ($matchedHosts.Count -eq 0 -and -not $nameMatch) {
            continue
        }

        $detail = "Outbound connector candidate. Enabled=$($connector.Enabled)."
        if ($matchedHosts.Count -gt 0) {
            $detail += " SmartHosts matching vendor pattern: $($matchedHosts -join ', ')."
        }
        if ($nameMatch) {
            $detail += ' Name matches vendor pattern.'
        }

        [void]$findings.Add((
            New-Finding -Module 'OutboundConnector' -Severity 'High' -ObjectType 'OutboundConnector' `
                -Name $connector.Name -Identifier $connector.Name -Detail $detail `
                -Evidence @{
                    Enabled     = [bool]$connector.Enabled
                    SmartHosts  = $smartHosts
                    MatchedHosts = $matchedHosts
                    NameMatch   = $nameMatch
                } `
                -Recommended 'Review' -AutoSafe:$false
        ))
    }

    # Connection filter policy — report only, never automate IPAllowList changes
    $cfFindings = Get-VendorConnectionFilterFinding -VendorPatterns $VendorPatterns `
        -RelatedIpRanges (@($ruleIpRanges + $connectorIpRanges) | Select-Object -Unique)
    foreach ($f in $cfFindings) {
        [void]$findings.Add($f)
    }

    return @($findings)
}

function Get-VendorConnectionFilterFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $VendorPatterns,

        [string[]] $RelatedIpRanges = @()
    )

    $findings = [System.Collections.Generic.List[object]]::new()

    try {
        $policies = @(Get-HostedConnectionFilterPolicy -ErrorAction Stop)
    }
    catch {
        Write-Warning "Unable to read hosted connection filter policy: $($_.Exception.Message)"
        return @()
    }

    foreach ($policy in $policies) {
        $allowList = @($policy.IPAllowList)
        if ($allowList.Count -eq 0) {
            continue
        }

        $overlaps = @(
            $allowList | Where-Object {
                $entry = [string]$_
                foreach ($related in $RelatedIpRanges) {
                    if ($entry -eq $related -or $entry -like "$related*" -or $related -like "$entry*") {
                        return $true
                    }
                }
                return $false
            }
        )

        $severity = if ($overlaps.Count -gt 0) { 'High' } else { 'Medium' }
        $detail = "Hosted connection filter IPAllowList has $($allowList.Count) entr(y/ies). Recommendation is Review; IPAllowList is never modified automatically."
        if ($overlaps.Count -gt 0) {
            $detail += " Overlap with flagged transport-rule or inbound-connector ranges: $($overlaps -join ', '). An allow-listed range for a decommissioned gateway bypasses filtering."
        }

        [void]$findings.Add((
            New-Finding -Module 'ConnectionFilter' -Severity $severity -ObjectType 'HostedConnectionFilterPolicy' `
                -Name $policy.Name -Identifier $policy.Name -Detail $detail `
                -Evidence @{
                    IPAllowList = $allowList
                    Overlaps    = $overlaps
                    IPBlockList = @($policy.IPBlockList)
                } `
                -Recommended 'Review' -AutoSafe:$false
        ))
    }

    return @($findings)
}
