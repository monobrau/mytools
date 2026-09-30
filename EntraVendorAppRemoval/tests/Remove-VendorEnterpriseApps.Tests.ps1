#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'Vendor enterprise app selection' {
    BeforeAll {
        $tool = Join-Path (Split-Path -Parent $PSScriptRoot) 'Remove-VendorEnterpriseApps.ps1'
        . $tool
        $script:Catalog = @(Get-VendorEnterpriseAppCatalog)
        $script:Menu = @(
            [pscustomobject]@{ Number = 1; Vendor = 'Inky'; AppId = 'app-inky-1'; Name = 'INKY one' }
            [pscustomobject]@{ Number = 2; Vendor = 'Inky'; AppId = 'app-inky-2'; Name = 'INKY two' }
            [pscustomobject]@{ Number = 3; Vendor = 'Usecure'; AppId = 'app-usecure'; Name = 'usecure' }
            [pscustomobject]@{ Number = 4; Vendor = 'Barracuda'; AppId = 'app-skout'; Name = 'Skout' }
        )
    }

    Context 'Catalog' {
        It 'lists eight example apps with unique ids' {
            $script:Catalog.Count | Should -Be 8
            @($script:Catalog.ExampleId | Select-Object -Unique).Count | Should -Be 8
        }
    }

    Context 'Resolve-VendorAppCategory' {
        It 'classifies a renamed-id INKY app by name' {
            Resolve-VendorAppCategory -DisplayName 'INKY Phish Fence - Installation' -AppId '11111111-1111-1111-1111-111111111111' -Catalog $script:Catalog |
                Should -Be 'Inky'
        }

        It 'classifies Phish Fence without the word Inky' {
            Resolve-VendorAppCategory -DisplayName 'Phish Fence Remediation' -AppId '22222222-2222-2222-2222-222222222222' -Catalog $script:Catalog |
                Should -Be 'Inky'
        }

        It 'classifies usecure by name when the id is different' {
            Resolve-VendorAppCategory -DisplayName 'usecure - Message Injection' -AppId '33333333-3333-3333-3333-333333333333' -Catalog $script:Catalog |
                Should -Be 'Usecure'
        }

        It 'classifies Skout by name when the id is different' {
            Resolve-VendorAppCategory -DisplayName 'Skout Cybersecurity' -AppId '44444444-4444-4444-4444-444444444444' -Catalog $script:Catalog |
                Should -Be 'Barracuda'
        }

        It 'classifies Barracuda Cybersecurity by name' {
            Resolve-VendorAppCategory -DisplayName 'Barracuda Cybersecurity' -AppId '55555555-5555-5555-5555-555555555555' -Catalog $script:Catalog |
                Should -Be 'Barracuda'
        }

        It 'does not treat other Barracuda products as Skout' {
            Resolve-VendorAppCategory -DisplayName 'Barracuda Email Gateway Defense' -AppId '66666666-6666-6666-6666-666666666666' -Catalog $script:Catalog |
                Should -BeNullOrEmpty
        }

        It 'uses an example id when the display name was renamed' {
            Resolve-VendorAppCategory -DisplayName 'Legacy portal SSO' -AppId '35343bd4-37f5-410b-bb69-fd23e9da03a6' -Catalog $script:Catalog |
                Should -Be 'Inky'
        }

        It 'matches an example id against the object id' {
            Resolve-VendorAppCategory -DisplayName 'Renamed' -ObjectId '9ad0f9b6-8ca4-4839-b1c8-061bad20e8da' -Catalog $script:Catalog |
                Should -Be 'Barracuda'
        }

        It 'ignores unrelated apps' {
            Resolve-VendorAppCategory -DisplayName 'Contoso HR' -AppId '77777777-7777-7777-7777-777777777777' -Catalog $script:Catalog |
                Should -BeNullOrEmpty
        }
    }

    Context 'ConvertFrom-VendorAppSelection' {
        It 'selects comma-separated numbers' {
            $r = ConvertFrom-VendorAppSelection -InputText '1,3' -NumberedApps $script:Menu
            $r.Action | Should -Be 'Select'
            $r.AppIds | Should -Be @('app-inky-1', 'app-usecure')
        }

        It 'selects a number range' {
            $r = ConvertFrom-VendorAppSelection -InputText '1-3' -NumberedApps $script:Menu
            $r.AppIds | Should -Be @('app-inky-1', 'app-inky-2', 'app-usecure')
        }

        It 'selects a vendor by name' {
            $r = ConvertFrom-VendorAppSelection -InputText 'inky' -NumberedApps $script:Menu
            $r.AppIds | Should -Be @('app-inky-1', 'app-inky-2')
        }

        It 'treats skout and barracuda as the same vendor' {
            $r = ConvertFrom-VendorAppSelection -InputText 'skout' -NumberedApps $script:Menu
            $r.AppIds | Should -Be @('app-skout')
            (ConvertFrom-VendorAppSelection -InputText 'barracuda' -NumberedApps $script:Menu).AppIds |
                Should -Be @('app-skout')
        }

        It 'selects every numbered app for all' {
            $r = ConvertFrom-VendorAppSelection -InputText 'all' -NumberedApps $script:Menu
            $r.AppIds.Count | Should -Be 4
        }

        It 'rejects a number that is not listed' {
            $r = ConvertFrom-VendorAppSelection -InputText '9' -NumberedApps $script:Menu
            $r.Action | Should -Be 'Invalid'
        }

        It 'quits on q' {
            (ConvertFrom-VendorAppSelection -InputText 'q' -NumberedApps $script:Menu).Action | Should -Be 'Quit'
        }

        It 'rejects blank input' {
            $r = ConvertFrom-VendorAppSelection -InputText '' -NumberedApps $script:Menu
            $r.Action | Should -Be 'Invalid'
        }
    }
}
