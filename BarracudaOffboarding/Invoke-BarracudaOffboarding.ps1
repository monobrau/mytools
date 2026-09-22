#Requires -Version 7.4
<#
.SYNOPSIS
    Discover and remediate residual Barracuda tenancy in Microsoft 365 after XDR/EGD/ESG/Essentials offboarding.

.DESCRIPTION
    Discovery-driven. Defaults to read-only Discover mode. Remediation requires -Mode Remediate,
    SupportsShouldProcess / -WhatIf, and per-item confirmation unless -Force.

    Detection uses pattern matches on discovered tenant objects. Vendor IP ranges, app IDs, and
    smart-host FQDNs are never hardcoded; extend patterns via config/default.json or -ConfigPath.

.NOTES
    Requires: Microsoft.Graph (v2.x), ExchangeOnlineManagement (v3.x)
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string] $ClientName,

    [ValidateSet('Discover', 'Remediate')]
    [string] $Mode = 'Discover',

    [ValidateSet('Graph', 'Exchange', 'All')]
    [string[]] $Scope = @('All'),

    # Default: work OneDrive\BarracudaOffboarding\<Client>\<timestamp>
    # Override with -OutputPath to change the root (client subfolder is still created).
    [string] $OutputPath,

    [string] $ConfigPath,

    [int] $DormancyDays = 30,

    [switch] $IncludeUsecure,

    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

Get-ChildItem -LiteralPath (Join-Path $scriptRoot 'Private') -Filter '*.ps1' | ForEach-Object {
    . $_.FullName
}

function Test-RequiredModule {
    param([string[]] $Names)
    $missing = @()
    foreach ($name in $Names) {
        if (-not (Get-Module -ListAvailable -Name $name)) {
            $missing += $name
        }
    }
    if ($missing.Count -gt 0) {
        $hints = foreach ($m in $missing) {
            "Install-Module $m -Scope CurrentUser"
        }
        throw @"
Missing required module(s): $($missing -join ', ').
Install hint(s):
$($hints -join [Environment]::NewLine)
"@
    }
}

function Connect-OffboardingGraph {
    param(
        [ValidateSet('Discover', 'Remediate')]
        [string] $Mode
    )

    $readScopes = @(
        'Application.Read.All'
        'Directory.Read.All'
        'AuditLog.Read.All'
        'Policy.Read.All'
    )
    $writeScopes = @(
        'AppRoleAssignment.ReadWrite.All'
        'DelegatedPermissionGrant.ReadWrite.All'
    )

    $scopes = if ($Mode -eq 'Remediate') {
        $readScopes + $writeScopes
    }
    else {
        $readScopes
    }

    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    $have = @($ctx.Scopes)
    $needConnect = -not $ctx
    if ($ctx) {
        foreach ($s in $scopes) {
            if ($have -notcontains $s) { $needConnect = $true; break }
        }
    }

    if ($needConnect) {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        Import-Module Microsoft.Graph.Applications -ErrorAction Stop
        Import-Module Microsoft.Graph.Identity.SignIns -ErrorAction Stop
        Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop | Out-Null
    }

    return (Get-MgContext)
}

function Test-ScopeSelected {
    param(
        [string[]] $Selected,
        [string] $Name
    )
    return ($Selected -contains 'All' -or $Selected -contains $Name)
}

function Confirm-OffboardingAction {
    param(
        [string] $Target,
        [string] $Action,
        [switch] $Force
    )

    # -Force skips confirmation prompts but still honors -WhatIf (no mutation).
    if ($Force) {
        if ($WhatIfPreference) {
            Write-Host "WhatIf: would perform '$Action' on target '$Target'"
            return $false
        }
        return $true
    }

    return $PSCmdlet.ShouldProcess($Target, $Action)
}

# --- Preflight modules ---
$needGraph = Test-ScopeSelected -Selected $Scope -Name 'Graph'
$needExchange = Test-ScopeSelected -Selected $Scope -Name 'Exchange'
$moduleNames = @()
if ($needGraph) { $moduleNames += 'Microsoft.Graph' }
if ($needExchange) { $moduleNames += 'ExchangeOnlineManagement' }
Test-RequiredModule -Names $moduleNames

$paths = Resolve-OffboardingRunDirectory -ClientName $ClientName -OutputPath $OutputPath
$safeClient = $paths.SafeClientName
$runDirectory = $paths.RunDirectory
$null = New-Item -ItemType Directory -Path $paths.ClientDirectory -Force
$null = New-Item -ItemType Directory -Path $runDirectory -Force
Write-Host "Client folder: $($paths.ClientDirectory)"

$transcriptStarted = $false
$previousConfirmPreference = $null
Start-Transcript -LiteralPath (Join-Path $runDirectory 'transcript.log') -ErrorAction Stop | Out-Null
$transcriptStarted = $true

try {
    $defaultConfigPath = Join-Path $scriptRoot 'config\default.json'
    $config = Get-OffboardingConfig -ConfigPath $ConfigPath -DefaultConfigPath $defaultConfigPath
    $patterns = @($config.vendorPatterns)

    Write-Host "Barracuda Offboarding | Client=$ClientName | Mode=$Mode | Scope=$($Scope -join ',') | Output=$runDirectory"

    $mgContext = $null
    if ($needGraph) {
        $mgContext = Connect-OffboardingGraph -Mode $Mode
    }
    if ($needExchange) {
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
        $exo = Get-ConnectionInformation -ErrorAction SilentlyContinue
        if (-not $exo) {
            Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
        }
    }

    $operator = if ($mgContext -and $mgContext.Account) { [string]$mgContext.Account } else { $env:USERNAME }
    $allFindings = [System.Collections.Generic.List[object]]::new()

    # --- Discovery ---
    if ($needGraph) {
        Write-Host 'Discovering service principals / CA / app registrations...'
        $spFindings = @(Get-VendorServicePrincipal -VendorPatterns $patterns `
                -KnownGoodServicePrincipals @($config.knownGoodServicePrincipals) `
                -DormancyDays $DormancyDays)
        foreach ($f in $spFindings) { [void]$allFindings.Add($f) }
    }

    $transportFindings = @()
    if ($needExchange) {
        Write-Host 'Discovering transport rules...'
        $transportFindings = @(Get-VendorTransportRule -VendorPatterns $patterns `
                -KnownGoodTransportRules @($config.knownGoodTransportRules) `
                -IncludeUsecure:$IncludeUsecure)
        foreach ($f in $transportFindings) { [void]$allFindings.Add($f) }

        Write-Host 'Discovering connectors and connection filter...'
        $connectorFindings = @(Get-VendorConnector -VendorPatterns $patterns -TransportRuleFindings $transportFindings)
        foreach ($f in $connectorFindings) { [void]$allFindings.Add($f) }

        Write-Host 'Discovering mail routing (MX / SPF)...'
        $mailFindings = @(Get-VendorMailRouting -VendorPatterns $patterns)
        foreach ($f in $mailFindings) { [void]$allFindings.Add($f) }
    }

    $report = Write-OffboardingReport -Findings @($allFindings) -ClientName $ClientName -Mode $Mode `
        -OutputDirectory $runDirectory -Operator $operator -ClientNotes ([string]$config.clientNotes) `
        -DormancyDays $DormancyDays

    Write-Host "Report written: $($report.MarkdownPath)"

    if ($Mode -eq 'Discover') {
        Write-Host 'Discover mode complete. No mutating calls were made.'
        return [pscustomobject]@{
            Mode          = $Mode
            OutputDirectory = $runDirectory
            FindingCount  = $allFindings.Count
            BlockerCount  = @($report.Blockers).Count
            ReportPath    = $report.MarkdownPath
        }
    }

    # --- Remediate ---
    # Phase 0: Preflight blockers
    $blockers = @($report.Blockers)
    if ($blockers.Count -gt 0 -and -not $Force) {
        throw "Aborting Remediate: $($blockers.Count) High severity MX/SPF blocker(s) present. Cut over mail routing or re-run with -Force."
    }
    if ($blockers.Count -gt 0 -and $Force) {
        Write-Warning "Proceeding despite $($blockers.Count) MX/SPF blocker(s) because -Force was specified."
    }

    # -Force skips ShouldProcess confirmation prompts; -WhatIf still prevents mutation.
    $previousConfirmPreference = $ConfirmPreference
    if ($Force) {
        $ConfirmPreference = 'None'
    }

    # Phase 1: Backup (must exist and be non-zero before mutation)
    Write-Host 'Writing pre-change backup...'
    if ($needGraph) {
        $spBackup = [System.Collections.Generic.List[object]]::new()
        $spTargets = @($allFindings | Where-Object { $_.Module -eq 'ServicePrincipal' -and -not $_.Evidence.KnownGood })
        foreach ($f in $spTargets) {
            $sp = Get-MgServicePrincipal -ServicePrincipalId $f.Identifier -Property Id, AppId, DisplayName, AccountEnabled, AppOwnerOrganizationId, ServicePrincipalType
            $assignments = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $f.Identifier -All -ErrorAction SilentlyContinue)
            $grants = @(Get-MgOauth2PermissionGrant -Filter "clientId eq '$($f.Identifier)'" -All -ErrorAction SilentlyContinue)
            [void]$spBackup.Add([pscustomobject]@{
                    ServicePrincipal = $sp
                    AppRoleAssignments = $assignments
                    Oauth2PermissionGrants = $grants
                })
        }
        $spBackupPath = Join-Path $runDirectory 'servicePrincipals.json'
        $spBackup | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $spBackupPath -Encoding utf8
    }

    if ($needExchange) {
        $rules = @(Get-TransportRule -ErrorAction Stop)
        $rules | Export-Clixml -LiteralPath (Join-Path $runDirectory 'transportRules.xml')
        $connectors = [pscustomobject]@{
            Inbound  = @(Get-InboundConnector)
            Outbound = @(Get-OutboundConnector)
        }
        $connectors | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $runDirectory 'connectors.json') -Encoding utf8
        $cf = @(Get-HostedConnectionFilterPolicy)
        $cf | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $runDirectory 'connectionFilter.json') -Encoding utf8
    }

    $requiredBackup = @(
        (Join-Path $runDirectory 'findings.json')
        (Join-Path $runDirectory 'findings.md')
        (Join-Path $runDirectory 'transcript.log')
    )
    if ($needGraph) { $requiredBackup += (Join-Path $runDirectory 'servicePrincipals.json') }
    if ($needExchange) {
        $requiredBackup += (Join-Path $runDirectory 'transportRules.xml')
        $requiredBackup += (Join-Path $runDirectory 'connectors.json')
        $requiredBackup += (Join-Path $runDirectory 'connectionFilter.json')
    }

    foreach ($path in $requiredBackup) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Backup verification failed: missing $path. Aborting before mutation."
        }
        if ((Get-Item -LiteralPath $path).Length -le 0) {
            throw "Backup verification failed: zero-length $path. Aborting before mutation."
        }
    }
    Write-Host 'Backup verified on disk.'

    $remediated = [System.Collections.Generic.List[object]]::new()

    # Phase 2: Graph revocation
    if ($needGraph) {
        Write-Host 'Phase 2: Graph revocation...'
        $toRevoke = @(
            $allFindings | Where-Object {
                $_.Module -eq 'ServicePrincipal' -and $_.Recommended -eq 'Revoke' -and -not $_.Evidence.KnownGood
            }
        )

        foreach ($f in $toRevoke) {
            $spId = $f.Identifier
            $target = "$($f.Name) [$spId]"

            if (-not (Confirm-OffboardingAction -Target $target -Action 'Revoke app roles, oauth grants, and disable service principal' -Force:$Force)) {
                Write-Host "Skipped SP: $target"
                continue
            }

            $assignments = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $spId -All -ErrorAction SilentlyContinue)
            foreach ($a in $assignments) {
                if ($PSCmdlet.ShouldProcess("$($a.Id) on $target", 'Remove-MgServicePrincipalAppRoleAssignment')) {
                    Remove-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $spId -AppRoleAssignmentId $a.Id -ErrorAction Stop
                }
            }

            $grants = @(Get-MgOauth2PermissionGrant -Filter "clientId eq '$spId'" -All -ErrorAction SilentlyContinue)
            foreach ($g in $grants) {
                if ($PSCmdlet.ShouldProcess("$($g.Id) on $target", 'Remove-MgOauth2PermissionGrant')) {
                    Remove-MgOauth2PermissionGrant -OAuth2PermissionGrantId $g.Id -ErrorAction Stop
                }
            }

            if ($PSCmdlet.ShouldProcess($target, 'Update-MgServicePrincipal AccountEnabled=false')) {
                Update-MgServicePrincipal -ServicePrincipalId $spId -AccountEnabled:$false -ErrorAction Stop
            }

            $revokeCmd = Get-Command Revoke-MgServicePrincipalSignInSession -ErrorAction SilentlyContinue
            if ($revokeCmd) {
                if ($PSCmdlet.ShouldProcess($target, 'Revoke-MgServicePrincipalSignInSession')) {
                    try {
                        Revoke-MgServicePrincipalSignInSession -ServicePrincipalId $spId -ErrorAction Stop
                    }
                    catch {
                        Write-Warning "Revoke-MgServicePrincipalSignInSession failed for $target : $($_.Exception.Message). Disabling blocks new token issuance; existing tokens typically expire within about an hour."
                    }
                }
            }
            else {
                Write-Warning "Revoke-MgServicePrincipalSignInSession is not available on this Microsoft.Graph SDK version. Disabling alone blocks new token issuance; existing tokens typically expire within about an hour."
            }

            [void]$remediated.Add($f)
        }
    }

    # Phase 3: Exchange
    if ($needExchange) {
        Write-Host 'Phase 3: Exchange remediation...'
        $rulesToDisable = @(
            $allFindings | Where-Object {
                $_.Module -eq 'TransportRule' -and $_.Recommended -eq 'Disable' -and -not $_.Evidence.KnownGood
            }
        )

        foreach ($f in $rulesToDisable) {
            $target = "TransportRule $($f.Name)"
            $action = 'Disable-TransportRule'
            if (-not $f.AutoSafe -and -not $Force) {
                # SCL-only / ambiguous: require confirmation (ShouldProcess already ConfirmImpact High)
            }
            if (-not (Confirm-OffboardingAction -Target $target -Action $action -Force:$Force)) {
                Write-Host "Skipped rule: $target"
                continue
            }
            if ($PSCmdlet.ShouldProcess($target, $action)) {
                Disable-TransportRule -Identity $f.Identifier -Confirm:$false -ErrorAction Stop
                [void]$remediated.Add($f)
            }
        }

        $connectorFindings = @(
            $allFindings | Where-Object { $_.Module -in @('InboundConnector', 'OutboundConnector') }
        )
        foreach ($f in $connectorFindings) {
            $target = "$($f.ObjectType) $($f.Name)"
            if ($Force) {
                Write-Warning "Connector remediation is Review-only by default. -Force does not auto-disable connectors. Skipping $target."
                continue
            }
            if ($PSCmdlet.ShouldProcess($target, 'Disable connector (operator-confirmed)')) {
                if ($f.ObjectType -eq 'InboundConnector') {
                    Set-InboundConnector -Identity $f.Identifier -Enabled $false -Confirm:$false -ErrorAction Stop
                }
                else {
                    Set-OutboundConnector -Identity $f.Identifier -Enabled $false -Confirm:$false -ErrorAction Stop
                }
                [void]$remediated.Add($f)
            }
            else {
                Write-Host "Connector left for Review: $target"
            }
        }

        Write-Host 'Connection filter IPAllowList is report-only; no automatic changes.'
    }

    # Phase 4: Verification
    Write-Host 'Phase 4: Verification...'
    $verification = Assert-Remediation -RemediatedFindings @($remediated) -OutputDirectory $runDirectory
    Write-Host "Verification report: $($verification.Path)"

    if (-not $verification.Passed) {
        Write-Error "Verification failed with $($verification.FailedCount) assertion(s). See $($verification.Path)"
        exit 1
    }

    return [pscustomobject]@{
        Mode            = $Mode
        OutputDirectory = $runDirectory
        FindingCount    = $allFindings.Count
        RemediatedCount = $remediated.Count
        ReportPath      = $report.MarkdownPath
        VerificationPath = $verification.Path
        Passed          = $true
    }
}
catch {
    Write-Error $_
    exit 1
}
finally {
    if ($null -ne $previousConfirmPreference) {
        $ConfirmPreference = $previousConfirmPreference
    }
    if ($transcriptStarted) {
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    }
}
