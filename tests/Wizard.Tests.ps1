#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\src\Notifications\New-UserNotification.psd1" -Force
}

Describe 'Wizard support functions' {

    InModuleScope New-UserNotification {
        It 'Get-LicenseInventory returns SKUs with available seats' {
            Mock Get-MgSubscribedSku {
                Write-Output -NoEnumerate ([pscustomobject]@{
                    SkuId='sku-1'; SkuPartNumber='ENTERPRISEPACK'; ConsumedUnits=10
                    PrepaidUnits=[pscustomobject]@{ Enabled=25; Suspended=0; Warning=0 }
                    ServicePlans=@(); AppliesTo='User'
                })
            }
            $result = @(Get-LicenseInventory -ExcludeTrials)
            $result.Count | Should -Be 1
            $result[0].Available | Should -Be 15
        }

        It 'Get-LicenseInventory excludes trial SKUs when asked' {
            Mock Get-MgSubscribedSku {
                Write-Output -NoEnumerate ([pscustomobject]@{
                    SkuId='sku-t'; SkuPartNumber='FLOW_FREE'; ConsumedUnits=0
                    PrepaidUnits=[pscustomobject]@{ Enabled=10000; Suspended=0; Warning=0 }
                    ServicePlans=@(); AppliesTo='User'
                })
                Write-Output -NoEnumerate ([pscustomobject]@{
                    SkuId='sku-1'; SkuPartNumber='DEVELOPERPACK_E5'; ConsumedUnits=10
                    PrepaidUnits=[pscustomobject]@{ Enabled=25; Suspended=0; Warning=0 }
                    ServicePlans=@(); AppliesTo='User'
                })
            }
            $result = @(Get-LicenseInventory -ExcludeTrials)
            $result.Count | Should -Be 1
            $result[0].SkuPartNumber | Should -Be 'DEVELOPERPACK_E5'
        }

        It 'Get-LicenseInventory excludes zero-availability SKUs' {
            Mock Get-MgSubscribedSku {
                Write-Output -NoEnumerate ([pscustomobject]@{
                    SkuId='sku-full'; SkuPartNumber='ENTERPRISEPACK'; ConsumedUnits=25
                    PrepaidUnits=[pscustomobject]@{ Enabled=25; Suspended=0; Warning=0 }
                    ServicePlans=@(); AppliesTo='User'
                })
            }
            $result = @(Get-LicenseInventory -ExcludeTrials)
            $result.Count | Should -Be 0
        }

        It 'Get-GroupInventory classifies M365 vs Security' {
            Mock Get-MgGroup {
                Write-Output -NoEnumerate ([pscustomobject]@{
                    Id='g1'; DisplayName='Team Group'; GroupTypes=@('Unified')
                    SecurityEnabled=$false; MailEnabled=$true; OnPremisesSyncEnabled=$null
                    Description=$null; MembershipRule=$null
                })
                Write-Output -NoEnumerate ([pscustomobject]@{
                    Id='g2'; DisplayName='Security Group'; GroupTypes=@()
                    SecurityEnabled=$true; MailEnabled=$false; OnPremisesSyncEnabled=$null
                    Description=$null; MembershipRule=$null
                })
            }
            $result = @(Get-GroupInventory)
            ($result | Where-Object DisplayName -eq 'Team Group').Type     | Should -Be 'M365'
            ($result | Where-Object DisplayName -eq 'Security Group').Type | Should -Be 'Security'
        }

        It 'Get-GroupInventory excludes on-prem-synced groups when asked' {
            Mock Get-MgGroup {
                Write-Output -NoEnumerate ([pscustomobject]@{
                    Id='g1'; DisplayName='Cloud Group'; GroupTypes=@()
                    SecurityEnabled=$true; MailEnabled=$false; OnPremisesSyncEnabled=$null
                    Description=$null; MembershipRule=$null
                })
                Write-Output -NoEnumerate ([pscustomobject]@{
                    Id='g2'; DisplayName='Synced Group'; GroupTypes=@()
                    SecurityEnabled=$true; MailEnabled=$false; OnPremisesSyncEnabled=$true
                    Description=$null; MembershipRule=$null
                })
            }
            $result = @(Get-GroupInventory -ExcludeOnPremSynced)
            $result.Count | Should -Be 1
            $result[0].DisplayName | Should -Be 'Cloud Group'
        }

        It 'New-RandomPassword meets default Entra policy' {
            $pw = New-RandomPassword
            $pw.Length | Should -BeGreaterOrEqual 12
            $pw | Should -Match '[a-z]'
            $pw | Should -Match '[A-Z]'
            $pw | Should -Match '[0-9]'
        }

        It 'New-RandomPassword rejects length below 12' {
            { New-RandomPassword -Length 8 } | Should -Throw '*at least 12*'
        }

        It 'New-OnboardedUser rejects invalid UPN' {
            Mock New-MgUser { }
            {
                New-OnboardedUser -DisplayName 'X' -UserPrincipalName 'not-an-email' `
                    -MailNickname 'x' -Password 'A1b2C3d4E5f6G7' `
                    -UsageLocation 'NP' -Config @{}
            } | Should -Throw '*Invalid UserPrincipalName*'
        }

        It 'New-OnboardedUser rejects short password' {
            Mock New-MgUser { }
            {
                New-OnboardedUser -DisplayName 'X' -UserPrincipalName 'x@contoso.com' `
                    -MailNickname 'x' -Password 'short' `
                    -UsageLocation 'NP' -Config @{}
            } | Should -Throw '*at least 8 characters*'
        }

        It 'New-OnboardedUser creates a user and returns a summary' {
            Mock New-MgUser {
                [pscustomobject]@{
                    Id='u-new'; DisplayName='Jane Doe'
                    UserPrincipalName='jane@contoso.com'; Mail='jane@contoso.com'
                    Department='IT'; JobTitle='Engineer'
                    CreatedDateTime=(Get-Date); UserType='Member'
                }
            }
            Mock Send-MgMail { }
            Mock Write-AuditLog { }

            $cfg = @{ Audit = @{ LogPath = "$TestDrive/audit.jsonl" }; DryRun = $true }

            $result = New-OnboardedUser `
                -DisplayName 'Jane Doe' `
                -UserPrincipalName 'jane@contoso.com' `
                -MailNickname 'jane' `
                -Password 'A1b2C3d4E5f6G7' `
                -UsageLocation 'NP' `
                -Config $cfg

            $result.Created | Should -BeTrue
            $result.UserPrincipalName | Should -Be 'jane@contoso.com'
            $result.LicenseAssigned | Should -BeFalse
            $result.GroupsAssigned.Count | Should -Be 0
        }

        It 'New-OnboardedUser accepts Phone / OfficeLocation / EmployeeId' {
            Mock New-MgUser {
                [pscustomobject]@{
                    Id='u-poe'; DisplayName='Jane'
                    UserPrincipalName='jane@contoso.com'; Mail='jane@contoso.com'
                    Department=$null; JobTitle=$null
                    MobilePhone='+977-9800000000'
                    OfficeLocation='Kathmandu HQ'
                    EmployeeId='EMP-0001'
                    CreatedDateTime=(Get-Date); UserType='Member'
                }
            }
            Mock Send-MgMail { }
            Mock Write-AuditLog { }

            $cfg = @{ Audit = @{ LogPath = "$TestDrive/audit2.jsonl" }; DryRun = $true }

            {
                New-OnboardedUser `
                    -DisplayName 'Jane' `
                    -UserPrincipalName 'jane@contoso.com' `
                    -MailNickname 'jane' `
                    -Password 'A1b2C3d4E5f6G7' `
                    -Phone '+977-9800000000' `
                    -OfficeLocation 'Kathmandu HQ' `
                    -EmployeeId 'EMP-0001' `
                    -UsageLocation 'NP' `
                    -Config $cfg
            } | Should -Not -Throw

            Should -Invoke New-MgUser -Times 1 -Exactly -ParameterFilter {
                $MobilePhone    -eq '+977-9800000000' -and
                $OfficeLocation -eq 'Kathmandu HQ'      -and
                $EmployeeId     -eq 'EMP-0001'
            }
        }

        It 'New-OnboardedUser assigns multiple licenses in one call' {
            Mock New-MgUser {
                [pscustomobject]@{
                    Id='u-multi'; DisplayName='Multi'
                    UserPrincipalName='multi@contoso.com'; Mail='multi@contoso.com'
                    Department=$null; JobTitle=$null
                    CreatedDateTime=(Get-Date); UserType='Member'
                }
            }
            Mock Set-MgUserLicense { }
            Mock Send-MgMail { }
            Mock Write-AuditLog { }

            $cfg = @{ Audit = @{ LogPath = "$TestDrive/audit3.jsonl" }; DryRun = $true }

            $result = New-OnboardedUser `
                -DisplayName 'Multi' `
                -UserPrincipalName 'multi@contoso.com' `
                -MailNickname 'multi' `
                -Password 'A1b2C3d4E5f6G7' `
                -LicenseSkuIds @('sku-a','sku-b','sku-c') `
                -UsageLocation 'NP' `
                -Config $cfg

            $result.LicenseAssigned | Should -BeTrue
            $result.LicenseSkuIds.Count | Should -Be 3

            Should -Invoke Set-MgUserLicense -Times 1 -Exactly -ParameterFilter {
                ($BodyParameter.AddLicenses | Measure-Object).Count -eq 3
            }
        }
    }
}