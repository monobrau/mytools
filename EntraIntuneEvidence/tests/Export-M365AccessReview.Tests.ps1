#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'M365 access review workbook' {
    BeforeAll {
        $tool = Join-Path (Split-Path -Parent $PSScriptRoot) 'Export-M365AccessReview.ps1'
        . $tool
        $script:AccessReviewUserGroups = @{}
        $script:AccessReviewUserRoles = @{}

        function New-ReviewUser {
            param([string]$Id, [string]$Type = 'Member')
            [pscustomobject]@{ Id = $Id; UserType = $Type }
        }

        function New-CaPolicy {
            param(
                [string]$Name = 'Require MFA',
                [string[]]$IncludeUsers = @('All'),
                [string[]]$ExcludeUsers = @(),
                [string[]]$IncludeGroups = @(),
                [string[]]$Apps = @('All'),
                [string[]]$ExcludeApps = @()
            )
            [pscustomobject]@{
                DisplayName = $Name
                State = 'enabled'
                Conditions = [pscustomobject]@{
                    Users = [pscustomobject]@{
                        IncludeUsers = $IncludeUsers
                        ExcludeUsers = $ExcludeUsers
                        IncludeGroups = $IncludeGroups
                        ExcludeGroups = @()
                        IncludeRoles = @()
                        ExcludeRoles = @()
                        ExcludeGuestsOrExternalUsers = [pscustomobject]@{ GuestOrExternalUserTypes = $null }
                        IncludeGuestsOrExternalUsers = [pscustomobject]@{ GuestOrExternalUserTypes = $null }
                    }
                    Applications = [pscustomobject]@{
                        IncludeApplications = $Apps
                        ExcludeApplications = $ExcludeApps
                    }
                }
                GrantControls = [pscustomobject]@{ BuiltInControls = @('mfa') }
            }
        }

        $script:SampleRows = @(
            [pscustomobject]@{
                Lastname = ''
                Firstname = ''
                DisplayName = 'Scanner'
                Username = 'scanner@contoso.example'
                AccountEnabled = $false
                UserType = 'Member'
                HasMailbox = $false
                MailboxType = ''
                LastSignIn = $null
                NeverSignedIn = $true
                DaysSinceLastSignIn = $null
                MailboxLastUserAction = $null
                MfaEnabled = $false
                MfaEnforcedBy = ''
                MfaRegistered = $null
                MfaMethods = ''
                PerUserMfaState = ''
                Licenses = ''
            }
            [pscustomobject]@{
                Lastname = 'Lang'
                Firstname = 'Melissa'
                DisplayName = 'Melissa Lang'
                Username = 'melissa.lang@contoso.example'
                AccountEnabled = $true
                UserType = 'Member'
                HasMailbox = $true
                MailboxType = 'UserMailbox'
                LastSignIn = [datetime]'2026-11-01'
                NeverSignedIn = $false
                DaysSinceLastSignIn = 8
                MailboxLastUserAction = [datetime]'2026-10-30'
                MfaEnabled = $false
                MfaEnforcedBy = ''
                MfaRegistered = $false
                MfaMethods = ''
                PerUserMfaState = 'disabled'
                Licenses = 'Microsoft 365 E3 (SPE_E3)'
            }
        )
    }

    Context 'Conditional Access scope' {
        It 'includes a member of an all-users policy' {
            $policy = New-CaPolicy
            $user = New-ReviewUser -Id 'user-1'
            Test-CaPolicyAppliesToUser -Policy $policy -User $user | Should -BeTrue
        }

        It 'stops at a user exclusion' {
            $policy = New-CaPolicy -ExcludeUsers @('user-1')
            $user = New-ReviewUser -Id 'user-1'
            Test-CaPolicyAppliesToUser -Policy $policy -User $user | Should -BeFalse
        }

        It 'includes a member of a scoped group' {
            $policy = New-CaPolicy -IncludeUsers @() -IncludeGroups @('group-1')
            $groups = New-Object 'System.Collections.Generic.HashSet[string]'
            [void]$groups.Add('group-1')
            $script:AccessReviewUserGroups['user-2'] = $groups
            $user = New-ReviewUser -Id 'user-2'
            Test-CaPolicyAppliesToUser -Policy $policy -User $user | Should -BeTrue
        }

        It 'marks a policy that skips an app as partial' {
            Get-CaAppScope (New-CaPolicy -ExcludeApps @('office')) | Should -Be 'Partial'
            Get-CaAppScope (New-CaPolicy) | Should -Be 'All cloud apps'
        }
    }

    Context 'Sort and suggestions' {
        It 'lists people with a last name before other accounts' {
            $sorted = @(Sort-AccessReviewRow $script:SampleRows)
            $sorted[0].Username | Should -Be 'melissa.lang@contoso.example'
            $sorted[1].Username | Should -Be 'scanner@contoso.example'
        }

        It 'suggests only the enabled account that has no MFA' {
            $suggestions = @(Get-AccessReviewSuggestion -Rows $script:SampleRows -RegistrationKnown $true)
            $suggestions.Count | Should -Be 1
            $suggestions[0].Username | Should -Be 'melissa.lang@contoso.example'
            $suggestions[0].Suggestion | Should -Match 'not enforced'
            $suggestions[0].Suggestion | Should -Match 'No MFA method is registered'
        }
    }

    Context 'Workbook' {
        It 'writes the user facts without summary sheets unless asked' {
            $path = Join-Path $TestDrive 'basic.xlsx'
            Export-AccessReviewWorkbook -Path $path -TenantName 'Contoso' -PrimaryDomain 'contoso.example' -Generated ([datetime]'2026-11-09T10:00:00') -Rows $script:SampleRows -IncludeSummary $false -SecurityDefaults $false -CaPolicies @() -SignInAvailable $true -RegistrationKnown $true
            $zip = [IO.Compression.ZipFile]::OpenRead($path)
            try {
                $names = @($zip.Entries | ForEach-Object { $_.FullName })
                $names | Should -Contain 'xl/worksheets/sheet1.xml'
                $names | Should -Not -Contain 'xl/worksheets/sheet2.xml'
                $sheet = $zip.GetEntry('xl/worksheets/sheet1.xml')
                $reader = New-Object IO.StreamReader($sheet.Open())
                try { $xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
                $book = $zip.GetEntry('xl/workbook.xml')
                $bookReader = New-Object IO.StreamReader($book.Open())
                try { $bookXml = $bookReader.ReadToEnd() } finally { $bookReader.Dispose() }
            }
            finally { $zip.Dispose() }
            $bookXml | Should -Match 'name="Users"'
            $bookXml | Should -Not -Match 'name="Summary"'
            $bookXml | Should -Not -Match 'name="Suggestions"'
            $xml | Should -Match 'Last name'
            $xml | Should -Match 'Licenses'
            $xml | Should -Match 'melissa.lang@contoso.example'
            $xml | Should -Match 'MFA enforced'
        }

        It 'adds summary and suggestion sheets when requested' {
            $path = Join-Path $TestDrive 'full.xlsx'
            Export-AccessReviewWorkbook -Path $path -TenantName 'Contoso' -PrimaryDomain 'contoso.example' -Generated ([datetime]'2026-11-09T10:00:00') -Rows $script:SampleRows -IncludeSummary $true -SecurityDefaults $false -CaPolicies @([pscustomobject]@{ DisplayName = 'Require MFA'; State = 'enabled'; Scope = 'All cloud apps' }) -SignInAvailable $true -RegistrationKnown $true
            $zip = [IO.Compression.ZipFile]::OpenRead($path)
            try {
                $book = $zip.GetEntry('xl/workbook.xml')
                $reader = New-Object IO.StreamReader($book.Open())
                try { $bookXml = $reader.ReadToEnd() } finally { $reader.Dispose() }
                $suggest = $zip.GetEntry('xl/worksheets/sheet3.xml')
                $suggestReader = New-Object IO.StreamReader($suggest.Open())
                try { $suggestXml = $suggestReader.ReadToEnd() } finally { $suggestReader.Dispose() }
            }
            finally { $zip.Dispose() }
            $bookXml | Should -Match 'name="Users"'
            $bookXml | Should -Match 'name="Summary"'
            $bookXml | Should -Match 'name="Suggestions"'
            $suggestXml | Should -Match 'MFA is not enforced'
        }
    }
}
