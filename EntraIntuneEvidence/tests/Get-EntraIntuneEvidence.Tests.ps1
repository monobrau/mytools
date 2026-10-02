#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'Entra Intune evidence classification' {
    BeforeAll {
        $tool = Join-Path (Split-Path -Parent $PSScriptRoot) 'Get-EntraIntuneEvidence.ps1'
        . $tool
    }

    Context 'Get-EntraServiceAccountReasons' {
        It 'matches an svc account by name' {
            $reasons = Get-EntraServiceAccountReasons -DisplayName 'SQL' -UserPrincipalName 'svc-sql@contoso.example' -MailNickname 'svc-sql'
            @($reasons) | Should -Contain 'Name'
        }

        It 'does not treat a person named Samantha as a service account' {
            $reasons = Get-EntraServiceAccountReasons -DisplayName 'Samantha Lee' -UserPrincipalName 'samantha@contoso.example' -MailNickname 'samantha'
            @($reasons).Count | Should -Be 0
        }

        It 'matches sa- names and a service OU' {
            $reasons = Get-EntraServiceAccountReasons -DisplayName 'Backup' -UserPrincipalName 'sa-backup@contoso.example' -OnPremisesDistinguishedName 'CN=Backup,OU=Service Accounts,DC=contoso,DC=example'
            @($reasons) | Should -Contain 'Name'
            @($reasons) | Should -Contain 'OnPremisesOu'
        }

        It 'matches a title that says service account' {
            $reasons = Get-EntraServiceAccountReasons -DisplayName 'Nightly' -JobTitle 'Service account'
            @($reasons) | Should -Contain 'TitleOrDepartment'
        }

        It 'applies an extra pattern' {
            $reasons = Get-EntraServiceAccountReasons -DisplayName 'Nightly' -UserPrincipalName 'nightly@contoso.example' -ExtraPattern 'nightly'
            @($reasons) | Should -Contain 'ExtraPattern'
        }

        It 'keeps a one-word device or app name for review' {
            @(Get-EntraServiceAccountReasons -DisplayName 'scan' -UserPrincipalName 'scan@contoso.example') | Should -Contain 'NeedsReview'
            @(Get-EntraServiceAccountReasons -DisplayName 'Copier' -UserPrincipalName 'copier@contoso.example') | Should -Contain 'NeedsReview'
            @(Get-EntraServiceAccountReasons -DisplayName 'ErpApp' -UserPrincipalName 'erpapp@contoso.example') | Should -Contain 'NeedsReview'
        }

        It 'excludes admin, break-glass, and test accounts' {
            @(Get-EntraServiceAccountReasons -DisplayName 'Administrator' -UserPrincipalName 'administrator@contoso.example').Count | Should -Be 0
            @(Get-EntraServiceAccountReasons -DisplayName 'Break Glass' -UserPrincipalName 'breakglass@contoso.example').Count | Should -Be 0
            @(Get-EntraServiceAccountReasons -DisplayName 'SharePoint Test' -UserPrincipalName 'sharepointtest@contoso.example').Count | Should -Be 0
        }

        It 'excludes a person whose display name has a spaced hyphen' {
            $reasons = Get-EntraServiceAccountReasons -DisplayName 'Jane - Doe' -UserPrincipalName 'jane.doe@contoso.example'
            @($reasons).Count | Should -Be 0
        }

        It 'excludes an obvious person even when the sign-in looks like a service account' {
            $reasons = Get-EntraServiceAccountReasons -DisplayName 'Jane Doe' -UserPrincipalName 'svc-jane@contoso.example'
            @($reasons).Count | Should -Be 0
        }
    }

    Context 'Get-BitLockerDeployedVerdict' {
        It 'marks an encrypted Windows workstation as deployed' {
            Get-BitLockerDeployedVerdict -DeviceType 'windowsRT' -EncryptionState 'encrypted' -AdvancedBitLockerStates 'success' |
                Should -Be 'Yes'
        }

        It 'marks an unprotected OS volume as not deployed' {
            Get-BitLockerDeployedVerdict -DeviceType 'desktop' -EncryptionState 'encrypted' -AdvancedBitLockerStates 'osVolumeUnprotected' |
                Should -Be 'No'
        }

        It 'treats numeric flag 2 as an unprotected OS volume' {
            Get-BitLockerDeployedVerdict -DeviceType 'windowsRT' -EncryptionState 'encrypted' -AdvancedBitLockerStates 2 |
                Should -Be 'No'
        }

        It 'marks a non-Windows device as not applicable' {
            Get-BitLockerDeployedVerdict -DeviceType 'iPad' -EncryptionState 'encrypted' -AdvancedBitLockerStates 'success' |
                Should -Be 'NotApplicable'
        }

        It 'marks a Windows device that is not encrypted as not deployed' {
            Get-BitLockerDeployedVerdict -DeviceType 'windowsRT' -EncryptionState 'notEncrypted' -AdvancedBitLockerStates '' |
                Should -Be 'No'
        }
    }
}
