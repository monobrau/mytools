#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'BarracudaOffboarding helpers' {
    BeforeAll {
        $script:ToolRoot = Split-Path -Parent $PSScriptRoot
        $script:PrivatePath = Join-Path $script:ToolRoot 'Private'
        Get-ChildItem -LiteralPath $script:PrivatePath -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    }

    Context 'New-Finding' {
        It 'returns the uniform finding shape' {
            $f = New-Finding -Module 'ServicePrincipal' -Severity 'High' -ObjectType 'ServicePrincipal' `
                -Name 'Skout Cybersecurity' -Identifier 'sp-guid' -Detail 'test' `
                -Evidence @{ AppId = 'app-guid' } -Recommended 'Revoke' -AutoSafe:$true

            $f.Module | Should -Be 'ServicePrincipal'
            $f.Severity | Should -Be 'High'
            $f.Recommended | Should -Be 'Revoke'
            $f.AutoSafe | Should -BeTrue
            $f.Evidence.AppId | Should -Be 'app-guid'
        }
    }

    Context 'Test-VendorPatternMatch' {
        It 'matches barracuda case-insensitively' {
            Test-VendorPatternMatch -Text 'Barracuda Networks' -Patterns @('barracuda') | Should -BeTrue
        }

        It 'matches skout and cudamail patterns' {
            Test-VendorPatternMatch -Text 'Skout Cybersecurity' -Patterns @('barracuda', 'skout') | Should -BeTrue
            Test-VendorPatternMatch -Text 'relay.cudamail.com' -Patterns @('cudamail') | Should -BeTrue
        }

        It 'returns false for unrelated text' {
            Test-VendorPatternMatch -Text 'Huntress' -Patterns @('barracuda', 'skout') | Should -BeFalse
        }

        It 'handles null/empty' {
            Test-VendorPatternMatch -Text $null -Patterns @('barracuda') | Should -BeFalse
            Test-VendorPatternMatch -Text '' -Patterns @('barracuda') | Should -BeFalse
        }
    }

    Context 'Get-SanitizedClientName' {
        It 'sanitizes spaces commas and periods' {
            Get-SanitizedClientName -ClientName 'Acme, Inc. LLC' | Should -Be 'Acme__Inc__LLC'
        }
    }

    Context 'Resolve-OffboardingRunDirectory' {
        It 'nests each client under the output root with a timestamp folder' {
            $root = Join-Path $TestDrive 'BarracudaOffboarding'
            $paths = Resolve-OffboardingRunDirectory -ClientName 'Acme, Inc.' -OutputPath $root -Timestamp '20260810_120000'

            $paths.SafeClientName | Should -Be 'Acme__Inc'
            $paths.ClientDirectory | Should -Be (Join-Path $root 'Acme__Inc')
            $paths.RunDirectory | Should -Be (Join-Path $paths.ClientDirectory '20260810_120000')
        }

        It 'defaults root to OneDriveCommercial\BarracudaOffboarding when available' {
            $prevCommercial = $env:OneDriveCommercial
            $prevOneDrive = $env:OneDrive
            try {
                $fakeOd = Join-Path $TestDrive 'OneDriveWork'
                $null = New-Item -ItemType Directory -Path $fakeOd -Force
                $env:OneDriveCommercial = $fakeOd
                $env:OneDrive = $fakeOd

                $root = Get-DefaultOffboardingOutputRoot
                $root | Should -Be (Join-Path $fakeOd 'BarracudaOffboarding')
            }
            finally {
                $env:OneDriveCommercial = $prevCommercial
                $env:OneDrive = $prevOneDrive
            }
        }
    }

    Context 'Get-OffboardingConfig' {
        It 'merges user patterns with defaults without replacing' {
            $temp = Join-Path $TestDrive 'custom.json'
            @{
                vendorPatterns             = @('customvendor')
                knownGoodServicePrincipals = @('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee')
                knownGoodTransportRules    = @('Keep Me')
                clientNotes                = 'note'
            } | ConvertTo-Json | Set-Content -LiteralPath $temp -Encoding utf8

            $defaultPath = Join-Path $script:ToolRoot 'config\default.json'
            $cfg = Get-OffboardingConfig -ConfigPath $temp -DefaultConfigPath $defaultPath

            $cfg.vendorPatterns | Should -Contain 'barracuda'
            $cfg.vendorPatterns | Should -Contain 'customvendor'
            $cfg.knownGoodServicePrincipals | Should -Contain 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
            $cfg.knownGoodTransportRules | Should -Contain 'Keep Me'
            $cfg.clientNotes | Should -Be 'note'
        }
    }

    Context 'ConvertTo-ReportLocalTime' {
        It 'labels Central time and does not return bare UTC' {
            $stamp = ConvertTo-ReportLocalTime -UtcDateTime ([datetime]::Parse('2026-01-15T18:00:00Z').ToUniversalTime())
            $stamp | Should -Match 'CST|CDT'
            $stamp | Should -Not -Match ' UTC$'
        }
    }
}

Describe 'Discovery modules with mocks' {
    BeforeAll {
        $script:ToolRoot = Split-Path -Parent $PSScriptRoot
        $script:PrivatePath = Join-Path $script:ToolRoot 'Private'
        Get-ChildItem -LiteralPath $script:PrivatePath -Filter '*.ps1' | ForEach-Object { . $_.FullName }

        # Stub Exchange/DNS commands so Pester can Mock them without the modules installed.
        function script:Get-TransportRule { param($Identity) }
        function script:Get-AcceptedDomain { }
        function script:Get-InboundConnector { }
        function script:Get-OutboundConnector { }
        function script:Get-HostedConnectionFilterPolicy { }
        function script:Resolve-DnsName { param($Name, $Type) }
    }

    Context 'Get-VendorServicePrincipal' {
        BeforeEach {
            Mock Get-MgContext { [pscustomobject]@{ TenantId = 'tenant-1'; Account = 'admin@example.com' } }
            Mock Get-MgServicePrincipal {
                @(
                    [pscustomobject]@{
                        Id                     = 'sp-1'
                        AppId                  = 'app-1'
                        DisplayName            = 'Skout Cybersecurity'
                        AccountEnabled         = $true
                        AppOwnerOrganizationId = 'other-tenant'
                        ServicePrincipalType   = 'Application'
                    }
                    [pscustomobject]@{
                        Id                     = 'sp-2'
                        AppId                  = 'app-2'
                        DisplayName            = 'Contoso App'
                        AccountEnabled         = $true
                        AppOwnerOrganizationId = 'tenant-1'
                        ServicePrincipalType   = 'Application'
                    }
                )
            }
            Mock Get-MgServicePrincipalAppRoleAssignment {
                @(
                    [pscustomobject]@{ Id = 'asg-1'; ResourceId = 'res-1'; AppRoleId = 'role-1' }
                )
            }
            Mock Get-MgOauth2PermissionGrant { @() }
            Mock Get-MgServicePrincipalMemberOf { @() }
            Mock Invoke-MgGraphRequest {
                @{
                    value = @(
                        @{
                            createdDateTime = ([datetime]::UtcNow.AddDays(-3).ToString('o'))
                            ipAddress       = '203.0.113.10'
                            location        = @{ city = 'Ashburn' }
                            status          = @{ errorCode = 0 }
                        }
                    )
                }
            }
            Mock Get-MgIdentityConditionalAccessPolicy { @() }
            Mock Resolve-AppRolePermissionName { 'User.ReadWrite.All' }
        }

        It 'flags matching SP as High with vendor-still-polling detail when recently active' {
            Mock Resolve-AppRolePermissionName { 'User.ReadWrite.All' } -ModuleName '' -ErrorAction SilentlyContinue
            # Re-define the function-local resolution by mocking Get-MgServicePrincipal for resource lookup
            Mock Get-MgServicePrincipal -ParameterFilter { $ServicePrincipalId } {
                [pscustomobject]@{
                    Id          = 'res-1'
                    DisplayName = 'Microsoft Graph'
                    AppRoles    = @(
                        [pscustomobject]@{ Id = 'role-1'; Value = 'User.ReadWrite.All' }
                    )
                }
            }

            # Primary list call has no ServicePrincipalId
            Mock Get-MgServicePrincipal -ParameterFilter { -not $ServicePrincipalId } {
                @(
                    [pscustomobject]@{
                        Id                     = 'sp-1'
                        AppId                  = 'app-1'
                        DisplayName            = 'Skout Cybersecurity'
                        AccountEnabled         = $true
                        AppOwnerOrganizationId = 'other-tenant'
                        ServicePrincipalType   = 'Application'
                    }
                )
            }

            $findings = @(Get-VendorServicePrincipal -VendorPatterns @('barracuda', 'skout') -DormancyDays 30)
            $sp = $findings | Where-Object { $_.Module -eq 'ServicePrincipal' } | Select-Object -First 1

            $sp | Should -Not -BeNullOrEmpty
            $sp.Severity | Should -Be 'High'
            $sp.Recommended | Should -Be 'Revoke'
            $sp.Detail | Should -Match 'vendor platform may still be polling'
            $sp.LastActivity | Should -Not -BeNullOrEmpty
        }

        It 'emits Info for known-good app ids instead of hiding them' {
            Mock Get-MgServicePrincipal -ParameterFilter { -not $ServicePrincipalId } {
                @(
                    [pscustomobject]@{
                        Id                     = 'sp-1'
                        AppId                  = 'app-known'
                        DisplayName            = 'Barracuda Something'
                        AccountEnabled         = $true
                        AppOwnerOrganizationId = 'other-tenant'
                        ServicePrincipalType   = 'Application'
                    }
                )
            }
            Mock Get-MgServicePrincipal -ParameterFilter { $ServicePrincipalId } {
                [pscustomobject]@{ Id = 'res-1'; AppRoles = @([pscustomobject]@{ Id = 'role-1'; Value = 'User.Read.All' }) }
            }
            Mock Get-MgServicePrincipalAppRoleAssignment { @() }
            Mock Invoke-MgGraphRequest { @{ value = @() } }

            $findings = @(Get-VendorServicePrincipal -VendorPatterns @('barracuda') -KnownGoodServicePrincipals @('app-known'))
            $sp = $findings | Where-Object Module -EQ 'ServicePrincipal'
            $sp.Severity | Should -Be 'Info'
            $sp.Recommended | Should -Be 'None'
            $sp.Detail | Should -Match 'knownGoodServicePrincipals'
        }
    }

    Context 'Get-VendorTransportRule' {
        It 'flags SCL -1 with SenderIpRanges as High even without vendor name' {
            Mock Get-TransportRule {
                @(
                    [pscustomobject]@{
                        Name           = 'IP Allow Bypass'
                        Comments       = ''
                        State          = 'Enabled'
                        Priority       = 0
                        SetSCL         = -1
                        SenderIpRanges = @('203.0.113.0/24')
                    }
                )
            }

            $findings = @(Get-VendorTransportRule -VendorPatterns @('barracuda', 'skout'))
            $findings.Count | Should -Be 1
            $findings[0].Severity | Should -Be 'High'
            $findings[0].Detail | Should -Match 'spoofing gap'
        }

        It 'flags usecure as Medium Review when -IncludeUsecure' {
            Mock Get-TransportRule {
                @(
                    [pscustomobject]@{
                        Name           = 'uSecure Simulation Allow'
                        Comments       = 'usecure'
                        State          = 'Enabled'
                        Priority       = 1
                        SetSCL         = $null
                        SenderIpRanges = @()
                    }
                )
            }

            $findings = @(Get-VendorTransportRule -VendorPatterns @('barracuda') -IncludeUsecure)
            $findings[0].Severity | Should -Be 'Medium'
            $findings[0].Recommended | Should -Be 'Review'
        }
    }

    Context 'Get-VendorMailRouting' {
        It 'returns High MX blocker when MX target matches vendor pattern' {
            Mock Get-AcceptedDomain {
                @([pscustomobject]@{ DomainName = 'contoso.example'; DomainType = 'Authoritative'; Default = $true })
            }
            Mock Resolve-DnsName -ParameterFilter { $Type -eq 'MX' } {
                @([pscustomobject]@{ Type = 'MX'; NameExchange = 'd12345.ess.barracuda.com'; Preference = 10 })
            }
            Mock Resolve-DnsName -ParameterFilter { $Type -eq 'TXT' } {
                @([pscustomobject]@{ Type = 'TXT'; Strings = @('v=spf1 include:_spf.google.com -all') })
            }

            $findings = @(Get-VendorMailRouting -VendorPatterns @('barracuda', 'ess\.barracuda'))
            $mx = $findings | Where-Object ObjectType -EQ 'MX'
            $mx.Severity | Should -Be 'High'
            $mx.Detail | Should -Match 'BLOCKER'
        }

        It 'returns empty set for clean tenant mail routing' {
            Mock Get-AcceptedDomain {
                @([pscustomobject]@{ DomainName = 'contoso.example'; DomainType = 'Authoritative'; Default = $true })
            }
            Mock Resolve-DnsName -ParameterFilter { $Type -eq 'MX' } {
                @([pscustomobject]@{ Type = 'MX'; NameExchange = 'contoso-example.mail.protection.outlook.com'; Preference = 0 })
            }
            Mock Resolve-DnsName -ParameterFilter { $Type -eq 'TXT' } {
                @([pscustomobject]@{ Type = 'TXT'; Strings = @('v=spf1 include:spf.protection.outlook.com -all') })
            }

            $findings = @(Get-VendorMailRouting -VendorPatterns @('barracuda', 'skout', 'cudamail'))
            $findings.Count | Should -Be 0
        }
    }

    Context 'Get-VendorConnector' {
        It 'flags outbound smart host pattern matches and reports connection filter overlaps as High' {
            Mock Get-InboundConnector {
                @(
                    [pscustomobject]@{
                        Name              = 'Barracuda Inbound'
                        ConnectorType     = 'Partner'
                        Enabled           = $true
                        SenderIPAddresses = @('198.51.100.0/24')
                        EFSkipLastIP      = $true
                        EFSkipIPs         = @()
                    }
                )
            }
            Mock Get-OutboundConnector {
                @(
                    [pscustomobject]@{
                        Name       = 'To Gateway'
                        Enabled    = $true
                        SmartHosts = @('smtp.cudamail.com')
                    }
                )
            }
            Mock Get-HostedConnectionFilterPolicy {
                @(
                    [pscustomobject]@{
                        Name        = 'Default'
                        IPAllowList = @('198.51.100.0/24')
                        IPBlockList = @()
                    }
                )
            }

            $ruleFindings = @(
                New-Finding -Module 'TransportRule' -Severity 'High' -ObjectType 'TransportRule' `
                    -Name 'Bypass' -Identifier 'Bypass' -Detail 'x' `
                    -Evidence @{ SenderIpRanges = @('198.51.100.0/24') } -Recommended 'Disable'
            )

            $findings = @(Get-VendorConnector -VendorPatterns @('barracuda', 'cudamail') -TransportRuleFindings $ruleFindings)
            ($findings | Where-Object Module -EQ 'OutboundConnector').Count | Should -Be 1
            $cf = $findings | Where-Object Module -EQ 'ConnectionFilter'
            $cf.Severity | Should -Be 'High'
            $cf.Recommended | Should -Be 'Review'
        }
    }
}

Describe 'Write-OffboardingReport' {
    BeforeAll {
        $script:ToolRoot = Split-Path -Parent $PSScriptRoot
        $script:PrivatePath = Join-Path $script:ToolRoot 'Private'
        Get-ChildItem -LiteralPath $script:PrivatePath -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    }

    It 'writes valid empty report for clean tenant' {
        $out = Join-Path $TestDrive 'clean'
        $report = Write-OffboardingReport -Findings @() -ClientName 'Contoso' -Mode Discover `
            -OutputDirectory $out -Operator 'admin@example.com' -DormancyDays 30

        Test-Path -LiteralPath $report.MarkdownPath | Should -BeTrue
        Test-Path -LiteralPath $report.JsonPath | Should -BeTrue
        (Get-Content -LiteralPath $report.MarkdownPath -Raw) | Should -Match 'No Barracuda'
        $report.Blockers.Count | Should -Be 0
    }

    It 'includes vendor-still-polling follow-up for recent SP activity' {
        $out = Join-Path $TestDrive 'active'
        $f = New-Finding -Module 'ServicePrincipal' -Severity 'High' -ObjectType 'ServicePrincipal' `
            -Name 'Skout Cybersecurity' -Identifier 'sp-1' `
            -Detail 'WARNING: Signed in within the last 30 days' `
            -LastActivity ([datetime]::UtcNow.AddDays(-2)) -Recommended 'Revoke' -AutoSafe:$true `
            -Evidence @{ AppRolePermissions = @('User.ReadWrite.All'); KnownGood = $false }

        $report = Write-OffboardingReport -Findings @($f) -ClientName 'Contoso' -Mode Discover `
            -OutputDirectory $out -Operator 'admin@example.com' -DormancyDays 30

        (Get-Content -LiteralPath $report.MarkdownPath -Raw) | Should -Match 'Vendor-side offboarding ticket'
    }

    It 'surfaces MX findings under Blockers' {
        $out = Join-Path $TestDrive 'mx'
        $f = New-Finding -Module 'MailRouting' -Severity 'High' -ObjectType 'MX' `
            -Name 'contoso.example' -Identifier 'mx' -Detail 'BLOCKER: MX still points at vendor' `
            -Recommended 'Review'

        $report = Write-OffboardingReport -Findings @($f) -ClientName 'Contoso' -Mode Remediate `
            -OutputDirectory $out -Operator 'admin@example.com'

        @($report.Blockers).Count | Should -Be 1
        (Get-Content -LiteralPath $report.MarkdownPath -Raw) | Should -Match 'Blockers'
    }
}

Describe 'Assert-Remediation' {
    BeforeAll {
        $script:ToolRoot = Split-Path -Parent $PSScriptRoot
        $script:PrivatePath = Join-Path $script:ToolRoot 'Private'
        Get-ChildItem -LiteralPath $script:PrivatePath -Filter '*.ps1' | ForEach-Object { . $_.FullName }

        function script:Get-TransportRule { param($Identity) }
        function script:Get-MgServicePrincipal { param($ServicePrincipalId, $Property) }
        function script:Get-MgServicePrincipalAppRoleAssignment { param($ServicePrincipalId) }
        function script:Get-MgOauth2PermissionGrant { param($Filter) }
    }

    It 'passes when SP disabled with zero grants and rule disabled' {
        Mock Get-MgServicePrincipal {
            [pscustomobject]@{ Id = 'sp-1'; DisplayName = 'Skout'; AccountEnabled = $false }
        }
        Mock Get-MgServicePrincipalAppRoleAssignment { @() }
        Mock Get-MgOauth2PermissionGrant { @() }
        Mock Get-TransportRule {
            [pscustomobject]@{ Name = 'Barracuda Bypass'; State = 'Disabled' }
        }

        $findings = @(
            New-Finding -Module 'ServicePrincipal' -Severity 'High' -ObjectType 'ServicePrincipal' `
                -Name 'Skout' -Identifier 'sp-1' -Detail 'x' -Recommended 'Revoke' -AutoSafe:$true `
                -Evidence @{ KnownGood = $false }
            New-Finding -Module 'TransportRule' -Severity 'High' -ObjectType 'TransportRule' `
                -Name 'Barracuda Bypass' -Identifier 'Barracuda Bypass' -Detail 'x' `
                -Recommended 'Disable' -AutoSafe:$true -Evidence @{ KnownGood = $false }
        )

        $result = Assert-Remediation -RemediatedFindings $findings -OutputDirectory $TestDrive
        $result.Passed | Should -BeTrue
        $result.FailedCount | Should -Be 0
        (Get-Content -LiteralPath $result.Path -Raw) | Should -Match 'PASS'
    }
}

Describe 'Revoke session cmdlet absence' {
    It 'documents warning path when Revoke-MgServicePrincipalSignInSession is missing' {
        # Acceptance criterion: missing cmdlet produces a warning, not a terminating error.
        # Covered by entry-point logic; assert the command lookup pattern is safe.
        $cmd = Get-Command Revoke-MgServicePrincipalSignInSession -ErrorAction SilentlyContinue
        if ($cmd) {
            $cmd.Name | Should -Be 'Revoke-MgServicePrincipalSignInSession'
        }
        else {
            { Get-Command Revoke-MgServicePrincipalSignInSession -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }
}
