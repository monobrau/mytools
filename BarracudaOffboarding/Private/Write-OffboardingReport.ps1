function Write-OffboardingReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Findings,

        [Parameter(Mandatory)]
        [string] $ClientName,

        [Parameter(Mandatory)]
        [ValidateSet('Discover', 'Remediate')]
        [string] $Mode,

        [Parameter(Mandatory)]
        [string] $OutputDirectory,

        [string] $Operator = '',

        [string] $ClientNotes = '',

        [int] $DormancyDays = 30
    )

    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    $generated = ConvertTo-ReportLocalTime -UtcDateTime ([datetime]::UtcNow)

    $severityOrder = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
    $sorted = @($Findings | Sort-Object @{ Expression = { $severityOrder[$_.Severity] } }, Module, Name)

    $blockers = @(
        $sorted | Where-Object {
            $_.Module -eq 'MailRouting' -and $_.Severity -eq 'High' -and $_.ObjectType -in @('MX', 'SPF')
        }
    )

    $summary = $sorted | Group-Object Severity | ForEach-Object {
        [pscustomobject]@{ Severity = $_.Name; Count = $_.Count }
    }

    $followUps = [System.Collections.Generic.List[string]]::new()
    $activeSps = @(
        $sorted | Where-Object {
            $_.Module -eq 'ServicePrincipal' -and $_.LastActivity -and (
                ([datetime]::UtcNow - [datetime]$_.LastActivity).TotalDays -le $DormancyDays
            )
        }
    )
    if ($activeSps.Count -gt 0) {
        [void]$followUps.Add("Vendor-side offboarding ticket required: $($activeSps.Count) service principal(s) showed activity inside $DormancyDays days.")
    }
    [void]$followUps.Add('After soak period, manually Remove-MgServicePrincipal for revoked principals if still present. This tool never deletes SPs.')
    $reviewItems = @($sorted | Where-Object { $_.Recommended -eq 'Review' -and $_.Severity -ne 'Info' })
    if ($reviewItems.Count -gt 0) {
        [void]$followUps.Add("$($reviewItems.Count) finding(s) recommended for human Review (connectors, CA, connection filter, SPF, etc.).")
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# Barracuda Offboarding Report: $ClientName")
    [void]$sb.AppendLine("Generated: $generated")
    [void]$sb.AppendLine("Mode: $Mode")
    [void]$sb.AppendLine("Operator: $(if ($Operator) { $Operator } else { '(unknown)' })")
    if ($ClientNotes) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("Client notes: $ClientNotes")
    }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Blockers')
    if ($blockers.Count -eq 0) {
        [void]$sb.AppendLine('None')
    }
    else {
        foreach ($b in $blockers) {
            [void]$sb.AppendLine("- **$($b.ObjectType)** $($b.Name): $($b.Detail)")
        }
    }

    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Summary')
    [void]$sb.AppendLine('| Severity | Count |')
    [void]$sb.AppendLine('| --- | ---: |')
    foreach ($row in @($summary | Sort-Object @{ Expression = { $severityOrder[$_.Severity] } })) {
        [void]$sb.AppendLine("| $($row.Severity) | $($row.Count) |")
    }
    if ($summary.Count -eq 0) {
        [void]$sb.AppendLine('| (none) | 0 |')
    }

    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Findings')
    if ($sorted.Count -eq 0) {
        [void]$sb.AppendLine('No Barracuda / vendor residue candidates discovered.')
    }
    else {
        foreach ($sevName in @('High', 'Medium', 'Low', 'Info')) {
            $group = @($sorted | Where-Object { $_.Severity -eq $sevName })
            if ($group.Count -eq 0) { continue }
            [void]$sb.AppendLine()
            [void]$sb.AppendLine("### Severity: $sevName")
            foreach ($f in $group) {
                $last = if ($f.LastActivity) { ConvertTo-ReportLocalTime -UtcDateTime ([datetime]$f.LastActivity) } else { 'n/a' }
                [void]$sb.AppendLine()
                [void]$sb.AppendLine("#### $($f.Name)")
                [void]$sb.AppendLine("- Type: $($f.ObjectType) | Module: $($f.Module)")
                [void]$sb.AppendLine("- Identifier: $($f.Identifier)")
                [void]$sb.AppendLine("- Last activity: $last")
                [void]$sb.AppendLine("- Detail: $($f.Detail)")
                if ($f.Module -eq 'ServicePrincipal' -and $f.Evidence.AppRolePermissions) {
                    $perms = @($f.Evidence.AppRolePermissions) -join ', '
                    if ($perms) {
                        [void]$sb.AppendLine("- Permissions held: $perms")
                    }
                }
                [void]$sb.AppendLine("- Recommended action: $($f.Recommended)")
                [void]$sb.AppendLine('- Evidence:')
                [void]$sb.AppendLine('```json')
                [void]$sb.AppendLine(($f.Evidence | ConvertTo-Json -Depth 8))
                [void]$sb.AppendLine('```')
            }
        }
    }

    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Manual follow-ups')
    foreach ($item in $followUps) {
        [void]$sb.AppendLine("- $item")
    }

    $mdPath = Join-Path $OutputDirectory 'findings.md'
    $jsonPath = Join-Path $OutputDirectory 'findings.json'
    $sb.ToString() | Set-Content -LiteralPath $mdPath -Encoding utf8
    # -InputObject keeps empty arrays as [] instead of emitting nothing
    ConvertTo-Json -InputObject @($sorted) -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding utf8

    return [pscustomobject]@{
        MarkdownPath = $mdPath
        JsonPath     = $jsonPath
        Blockers     = $blockers
    }
}
