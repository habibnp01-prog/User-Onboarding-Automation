#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\src\Notifications\New-UserNotification.psd1" -Force
}

Describe 'User creation detection' {
    InModuleScope New-UserNotification {
        BeforeAll {
            $script:Config = @{
                Audit = @{ LogPath = "$TestDrive/audit.jsonl"; RetentionDays = 90 }
                Retry = @{ MaxAttempts = 3; InitialDelaySeconds = 0; MaxDelaySeconds = 0 }
                Onboarding = @{
                    RequireLicense        = $false
                    RequireMailbox        = $false
                    MailboxWaitSeconds    = 0
                    AllowedUserTypes      = @('Member')
                    DepartmentAllowList   = @()
                    SkipHybridSyncedUsers = $true
                }
                Monitoring = @{ Mode = 'Polling'; PollIntervalSeconds = 300; LookbackMinutes = 15 }
            }
        }

        It 'returns new users from Graph' {
            Mock Get-NewUserFromGraph {
                [pscustomobject]@{
                    Id                    = 'u1'
                    DisplayName           = 'Jane Doe'
                    UserPrincipalName     = 'jane@contoso.com'
                    Mail                  = 'jane@contoso.com'
                    Department            = 'IT'
                    JobTitle              = 'Engineer'
                    CreatedDateTime       = (Get-Date)
                    UserType              = 'Member'
                    OnPremisesSyncEnabled = $false
                }
            }

            $events = Get-NewUserEvents -Config $script:Config -Since (Get-Date).AddMinutes(-15)
            @($events).Count | Should -Be 1
            @($events)[0].UserPrincipalName | Should -Be 'jane@contoso.com'
        }
    }
}

Describe 'Duplicate suppression' {
    InModuleScope New-UserNotification {
        It 'skips an event already in the audit log' {
            $log = "$TestDrive/audit.jsonl"
            Write-AuditLog -EventId 'evt-1' -UserPrincipalName 'jane@contoso.com' `
                -Stage 'Detected' -Status 'OK' -Detail '' -LogPath $log
            Test-EventProcessed -EventId 'evt-1' -LogPath $log | Should -BeTrue
        }

        It 'returns false when the event has never been seen' {
            $log = "$TestDrive/audit-2.jsonl"
            Test-EventProcessed -EventId 'evt-never' -LogPath $log | Should -BeFalse
        }

        It 'returns true when the same UPN already has an AdminSent entry' {
            $log = "$TestDrive/audit-3.jsonl"
            Write-AuditLog -EventId 'evt-first' -UserPrincipalName 'jane@contoso.com' `
                -Stage 'AdminSent' -Status 'OK' -Detail '' -LogPath $log
            Test-EventProcessed -EventId 'evt-second' -LogPath $log `
                -UserPrincipalName 'jane@contoso.com' | Should -BeTrue
        }

        It 'returns false for a different UPN' {
            $log = "$TestDrive/audit-4.jsonl"
            Write-AuditLog -EventId 'evt-first' -UserPrincipalName 'jane@contoso.com' `
                -Stage 'AdminSent' -Status 'OK' -Detail '' -LogPath $log
            Test-EventProcessed -EventId 'evt-second' -LogPath $log `
                -UserPrincipalName 'other@contoso.com' | Should -BeFalse
        }
    }
}

Describe 'Welcome email safety' {
    InModuleScope New-UserNotification {
        BeforeAll {
            $script:Config = @{
                SendEmployeeEmails = $true
                Onboarding = @{
                    SkipHybridSyncedUsers = $true
                    AllowedUserTypes      = @('Member')
                }
                WelcomeTemplatePath = $global:__welcomeTemplatePath
            }
        }

        It 'does not include a password or token' {
            $body = Get-Content $script:Config.WelcomeTemplatePath -Raw
            $body | Should -Not -Match 'password\s*[:=]\s*\S'
            $body | Should -Not -Match 'Bearer\s'
        }

        It 'skips when mailbox is missing' {
            $u = [pscustomobject]@{
                Mail = $null; UserType = 'Member'; IsHybridSynced = $false
                UserPrincipalName = 'x@y'
            }
            (Test-UserEligibleForWelcome -User $u -Config $script:Config).Eligible | Should -BeFalse
        }

        It 'marks missing-mailbox skip as Deferrable' {
            $u = [pscustomobject]@{
                Mail = $null; UserType = 'Member'; IsHybridSynced = $false
                UserPrincipalName = 'x@y'
            }
            (Test-UserEligibleForWelcome -User $u -Config $script:Config).Deferrable | Should -BeTrue
        }

        It 'skips hybrid-synced users when configured' {
            $u = [pscustomobject]@{
                Mail = 'x@y'; UserType = 'Member'; IsHybridSynced = $true
                UserPrincipalName = 'x@y'
            }
            (Test-UserEligibleForWelcome -User $u -Config $script:Config).Eligible | Should -BeFalse
        }

        It 'skips when UserType is not in the allowed list' {
            $u = [pscustomobject]@{
                Mail = 'x@y'; UserType = 'Guest'; IsHybridSynced = $false
                UserPrincipalName = 'x@y'
            }
            (Test-UserEligibleForWelcome -User $u -Config $script:Config).Eligible | Should -BeFalse
        }

        It 'allows a standard member with a mailbox' {
            $u = [pscustomobject]@{
                Mail = 'jane@contoso.com'; UserType = 'Member'; IsHybridSynced = $false
                UserPrincipalName = 'jane@contoso.com'
            }
            (Test-UserEligibleForWelcome -User $u -Config $script:Config).Eligible | Should -BeTrue
        }

        It 'returns Deferred status when Send-WelcomeEmail skips for missing mailbox' {
            $u = [pscustomobject]@{
                Mail = $null; UserType = 'Member'; IsHybridSynced = $false
                UserPrincipalName = 'x@y'
            }
            $r = Send-WelcomeEmail -User $u -Config $script:Config -EventId 'evt-x'
            $r.Status | Should -Be 'Deferred'
        }
    }
}

Describe 'Retry behavior' {
    InModuleScope New-UserNotification {
        It 'retries transient Graph failures then succeeds' {
            $script:calls = 0
            Mock Send-MgMail {
                $script:calls++
                if ($script:calls -lt 3) { throw 'throttled' }
            }
            {
                Invoke-WithRetry -MaxAttempts 3 -InitialDelaySeconds 0 -MaxDelaySeconds 0 -Action {
                    Send-MgMail -UserId 'x' -BodyParameter @{}
                }
            } | Should -Not -Throw
            $script:calls | Should -Be 3
        }

        It 'gives up after MaxAttempts and rethrows' {
            $script:calls2 = 0
            Mock Send-MgMail {
                $script:calls2++
                throw 'permanent failure'
            }
            {
                Invoke-WithRetry -MaxAttempts 3 -InitialDelaySeconds 0 -MaxDelaySeconds 0 -Action {
                    Send-MgMail -UserId 'x' -BodyParameter @{}
                }
            } | Should -Throw
            $script:calls2 | Should -Be 3
        }
    }
}

Describe 'Deferred welcome events' {
    InModuleScope New-UserNotification {
        It 'finds a Deferred welcome with no later resolution' {
            $log = "$TestDrive/audit-deferred.jsonl"
            Write-AuditLog -EventId 'evt-def' -UserPrincipalName 'x@y' `
                -Stage 'WelcomeSent' -Status 'Deferred' -Detail 'No mailbox yet.' -LogPath $log

            $deferred = @(Get-DeferredWelcomeEvents -LogPath $log)
            $deferred.Count | Should -Be 1
            $deferred[0].UserPrincipalName | Should -Be 'x@y'
        }

        It 'ignores Deferred that was later resolved with OK' {
            $log = "$TestDrive/audit-resolved.jsonl"
            Write-AuditLog -EventId 'evt-r' -UserPrincipalName 'x@y' `
                -Stage 'WelcomeSent' -Status 'Deferred' -Detail 'No mailbox yet.' -LogPath $log
            Write-AuditLog -EventId 'evt-r' -UserPrincipalName 'x@y' `
                -Stage 'WelcomeSent' -Status 'OK' -Detail '' -LogPath $log

            $deferred = @(Get-DeferredWelcomeEvents -LogPath $log)
            $deferred.Count | Should -Be 0
        }

        It 'returns nothing when no Deferred entries exist' {
            $log = "$TestDrive/audit-none.jsonl"
            Write-AuditLog -EventId 'evt-o' -UserPrincipalName 'x@y' `
                -Stage 'WelcomeSent' -Status 'OK' -Detail '' -LogPath $log

            $deferred = @(Get-DeferredWelcomeEvents -LogPath $log)
            $deferred.Count | Should -Be 0
        }
    }
}