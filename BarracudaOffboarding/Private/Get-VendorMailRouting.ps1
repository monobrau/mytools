function Get-VendorMailRouting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $VendorPatterns
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    $domains = @(Get-AcceptedDomain -ErrorAction Stop)

    foreach ($domain in $domains) {
        $domainName = [string]$domain.DomainName

        # MX
        try {
            $mxRecords = @(Resolve-DnsName -Name $domainName -Type MX -ErrorAction Stop | Where-Object { $_.Type -eq 'MX' })
        }
        catch {
            Write-Warning "MX lookup failed for $domainName : $($_.Exception.Message)"
            $mxRecords = @()
        }

        foreach ($mx in $mxRecords) {
            $target = [string]$mx.NameExchange
            if (Test-VendorPatternMatch -Text $target -Patterns $VendorPatterns) {
                [void]$findings.Add((
                    New-Finding -Module 'MailRouting' -Severity 'High' -ObjectType 'MX' `
                        -Name $domainName -Identifier "$domainName MX -> $target" `
                        -Detail "BLOCKER: MX for accepted domain '$domainName' still points at vendor target '$target' (preference $($mx.Preference)). Mail is still routing through the old gateway. Do not proceed with remediation until MX is cut over." `
                        -Evidence @{
                            DomainName  = $domainName
                            DomainType  = [string]$domain.DomainType
                            Default     = [bool]$domain.Default
                            NameExchange = $target
                            Preference  = $mx.Preference
                        } `
                        -Recommended 'Review' -AutoSafe:$false
                ))
            }
        }

        # SPF (TXT at apex)
        try {
            $txtRecords = @(Resolve-DnsName -Name $domainName -Type TXT -ErrorAction Stop | Where-Object { $_.Type -eq 'TXT' })
        }
        catch {
            Write-Warning "TXT lookup failed for $domainName : $($_.Exception.Message)"
            $txtRecords = @()
        }

        foreach ($txt in $txtRecords) {
            $strings = @($txt.Strings) -join ''
            if ($strings -notmatch '(?i)v=spf1') {
                continue
            }

            if (Test-VendorPatternMatch -Text $strings -Patterns $VendorPatterns) {
                [void]$findings.Add((
                    New-Finding -Module 'MailRouting' -Severity 'High' -ObjectType 'SPF' `
                        -Name $domainName -Identifier "$domainName SPF" `
                        -Detail "SPF TXT for '$domainName' includes a vendor pattern match. Removing an SPF include is mail-flow-affecting and belongs in its own change window. Recommendation: Review." `
                        -Evidence @{
                            DomainName = $domainName
                            SpfRecord  = $strings
                        } `
                        -Recommended 'Review' -AutoSafe:$false
                ))
            }
        }
    }

    return @($findings)
}
