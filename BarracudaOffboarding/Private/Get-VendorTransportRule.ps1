function Get-VendorTransportRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $VendorPatterns,

        [string[]] $KnownGoodTransportRules = @(),

        [switch] $IncludeUsecure
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    $rules = @(Get-TransportRule -ErrorAction Stop)

    $patterns = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $VendorPatterns) { [void]$patterns.Add($p) }
    if ($IncludeUsecure) {
        if (-not ($patterns -contains 'usecure')) {
            [void]$patterns.Add('usecure')
        }
    }
    $patternArray = @($patterns.ToArray())

    foreach ($rule in $rules) {
        $nameMatch = Test-VendorPatternMatch -Text $rule.Name -Patterns $patternArray
        $commentMatch = Test-VendorPatternMatch -Text ([string]$rule.Comments) -Patterns $patternArray

        $setScl = $null
        if ($null -ne $rule.SetSCL) {
            $setScl = [int]$rule.SetSCL
        }
        $senderIpRanges = @($rule.SenderIpRanges)
        $sclBypassOnIp = ($null -ne $setScl -and $setScl -eq -1 -and $senderIpRanges.Count -gt 0)

        if (-not ($nameMatch -or $commentMatch -or $sclBypassOnIp)) {
            continue
        }

        $isUsecureOnly = $false
        if ($IncludeUsecure -and -not $sclBypassOnIp) {
            $vendorHit = (Test-VendorPatternMatch -Text $rule.Name -Patterns $VendorPatterns) -or (
                Test-VendorPatternMatch -Text ([string]$rule.Comments) -Patterns $VendorPatterns
            )
            $usecureHit = (Test-VendorPatternMatch -Text $rule.Name -Patterns @('usecure')) -or (
                Test-VendorPatternMatch -Text ([string]$rule.Comments) -Patterns @('usecure')
            )
            if ($usecureHit -and -not $vendorHit) {
                $isUsecureOnly = $true
            }
        }

        $isKnownGood = $KnownGoodTransportRules -contains $rule.Name

        $detailParts = [System.Collections.Generic.List[string]]::new()
        if ($nameMatch) { [void]$detailParts.Add('Rule name matches vendor pattern.') }
        if ($commentMatch) { [void]$detailParts.Add('Rule comments match vendor pattern.') }
        if ($sclBypassOnIp) {
            [void]$detailParts.Add('Rule sets SCL to -1 conditioned on SenderIpRanges. This is a live spoofing gap if those ranges belong to a decommissioned gateway.')
        }
        if ($isUsecureOnly) {
            [void]$detailParts.Add('Matched as uSecure (phish simulation). Contracts are often separate from the security stack; Review only.')
        }
        [void]$detailParts.Add("State=$($rule.State).")

        $severity = if ($isKnownGood) {
            'Info'
        }
        elseif ($sclBypassOnIp) {
            'High'
        }
        elseif ($isUsecureOnly) {
            'Medium'
        }
        else {
            'High'
        }

        $recommended = if ($isKnownGood -or $isUsecureOnly) {
            'Review'
        }
        elseif ($nameMatch -or $commentMatch -or $sclBypassOnIp) {
            'Disable'
        }
        else {
            'Review'
        }

        if ($isKnownGood) {
            $recommended = 'None'
        }

        $detail = if ($isKnownGood) {
            "Suppressed by knownGoodTransportRules. $($detailParts -join ' ')"
        }
        else {
            $detailParts -join ' '
        }

        # AutoSafe only for clear vendor-named rules (not SCL-only or uSecure-only)
        $autoSafe = (-not $isKnownGood -and -not $isUsecureOnly -and ($nameMatch -or $commentMatch) -and $recommended -eq 'Disable')

        [void]$findings.Add((
            New-Finding -Module 'TransportRule' -Severity $severity -ObjectType 'TransportRule' `
                -Name $rule.Name -Identifier $rule.Name -Detail $detail `
                -Evidence @{
                    State           = [string]$rule.State
                    Priority        = $rule.Priority
                    Comments        = [string]$rule.Comments
                    SetSCL          = $setScl
                    SenderIpRanges  = $senderIpRanges
                    NameMatch       = $nameMatch
                    CommentMatch    = $commentMatch
                    SclBypassOnIp   = $sclBypassOnIp
                    UsecureOnly     = $isUsecureOnly
                    KnownGood       = $isKnownGood
                } `
                -Recommended $recommended -AutoSafe:$autoSafe
        ))
    }

    return @($findings)
}
