function Invoke-UserNotificationCycle {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigPath)

    if (-not (Test-Path $ConfigPath)) { throw "Config file not found: $ConfigPath" }

    $Config = ConvertFrom-JsonToHashtable -Json (Get-Content $ConfigPath -Raw)

    $userSettings = Read-UserSettings
    foreach ($k in $userSettings.Keys) {
        if ($k -eq 'LastUpdated') { continue }
        $Config[$k] = $userSettings[$k]
    }

    Test-NotificationConfig -Config $Config

    # Single-instance guard: prevent parallel watchers double-sending.
    $mutex = New-Object System.Threading.Mutex($false, 'Global\UserOnboardingAutomationCycle')
    if (-not $mutex.WaitOne(0)) {
        throw 'Another notification cycle is already running. Skipping this run.'
    }

    $stats = @{ Processed = 0; AdminOK = 0; WelcomeOK = 0; WelcomeDeferred = 0; Failed = 0 }
    try {
        Connect-NotificationGraph -Config $Config -ConfigPath $ConfigPath

        $overlap = if ($Config.Monitoring.OverlapMinutes -ne $null) { [int]$Config.Monitoring.OverlapMinutes } else { 5 }
        $since = Get-CycleWatermark -LogPath $Config.Audit.LogPath `
            -LookbackMinutes $Config.Monitoring.LookbackMinutes -OverlapMinutes $overlap
        $events = Get-NewUserEvents -Config $Config -Since $since
        Set-CycleWatermark -LogPath $Config.Audit.LogPath

        # ------------------------------------------------------------------
        # Main pass: detect new users, admin-notify, first-attempt welcome
        # ------------------------------------------------------------------
        foreach ($u in @($events)) {
            # Skip if same EventId OR same UPN already received AdminSent
            if (Test-EventProcessed -EventId $u.EventId -LogPath $Config.Audit.LogPath `
                    -UserPrincipalName $u.UserPrincipalName) {
                continue
            }
            $stats.Processed++

            Write-AuditLog -EventId $u.EventId -UserPrincipalName $u.UserPrincipalName `
                -Stage 'Detected' -Status 'OK' -Detail $u.Source -LogPath $Config.Audit.LogPath

            # Non-blocking mailbox handling: no Start-Sleep. Admin notifies immediately;
            # welcome is deferred to the retry pass if the mailbox is still missing.
            if ($Config.Onboarding.RequireMailbox -and -not $u.Mail) {
                try {
                    $refetched = Get-NewUserFromGraph -Filter (New-GraphFilterById -Id $u.UserId) |
                        Select-Object -First 1
                    if ($refetched -and $refetched.Mail) { $u.Mail = $refetched.Mail }
                } catch {
                    Write-Verbose "Mailbox refetch failed for $($u.UserPrincipalName): $($_.Exception.Message)"
                }
                if (-not $u.Mail) {
                    try {
                        $adminResult = Send-AdminNotification -User $u -Config $Config -EventId $u.EventId
                        Write-AuditLog -EventId $u.EventId -UserPrincipalName $u.UserPrincipalName `
                            -Stage 'AdminSent' -Status $adminResult.Status -Detail $adminResult.Detail `
                            -LogPath $Config.Audit.LogPath
                        if ($adminResult.Status -eq 'OK') { $stats.AdminOK++ } else { $stats.Failed++ }
                    } catch {
                        Write-AuditLog -EventId $u.EventId -UserPrincipalName $u.UserPrincipalName `
                            -Stage 'AdminSent' -Status 'Failed' -Detail $_.Exception.Message `
                            -LogPath $Config.Audit.LogPath
                        $stats.Failed++
                    }
                    Write-AuditLog -EventId $u.EventId -UserPrincipalName $u.UserPrincipalName `
                        -Stage 'WelcomeSent' -Status 'Deferred' -Detail 'No mailbox yet; will retry.' `
                        -LogPath $Config.Audit.LogPath
                    $stats.WelcomeDeferred++
                    continue
                }
            }

            try {
                $adminResult = Send-AdminNotification -User $u -Config $Config -EventId $u.EventId
                Write-AuditLog -EventId $u.EventId -UserPrincipalName $u.UserPrincipalName `
                    -Stage 'AdminSent' -Status $adminResult.Status -Detail $adminResult.Detail `
                    -LogPath $Config.Audit.LogPath
                if ($adminResult.Status -eq 'OK') { $stats.AdminOK++ }
                elseif ($adminResult.Status -eq 'Failed') { $stats.Failed++ }
            } catch {
                Write-AuditLog -EventId $u.EventId -UserPrincipalName $u.UserPrincipalName `
                    -Stage 'AdminSent' -Status 'Failed' -Detail $_.Exception.Message `
                    -LogPath $Config.Audit.LogPath
                $stats.Failed++
            }

            try {
                $welcomeResult = Send-WelcomeEmail -User $u -Config $Config -EventId $u.EventId
                Write-AuditLog -EventId $u.EventId -UserPrincipalName $u.UserPrincipalName `
                    -Stage 'WelcomeSent' -Status $welcomeResult.Status -Detail $welcomeResult.Detail `
                    -LogPath $Config.Audit.LogPath
                if ($welcomeResult.Status -eq 'OK') { $stats.WelcomeOK++ }
                elseif ($welcomeResult.Status -eq 'Deferred') { $stats.WelcomeDeferred++ }
                elseif ($welcomeResult.Status -eq 'Failed') { $stats.Failed++ }
            } catch {
                Write-AuditLog -EventId $u.EventId -UserPrincipalName $u.UserPrincipalName `
                    -Stage 'WelcomeSent' -Status 'Failed' -Detail $_.Exception.Message `
                    -LogPath $Config.Audit.LogPath
                $stats.Failed++
            }
        }

        # ------------------------------------------------------------------
        # Deferred welcome retry pass
        # ------------------------------------------------------------------
        $logPath = $Config.Audit.LogPath
        if (Test-Path $logPath) {
            $deferred = @(Get-DeferredWelcomeEvents -LogPath $logPath)
            foreach ($d in $deferred) {
                try {
                    $u = Get-NewUserFromGraph -Filter (New-GraphFilterByUPN -UserPrincipalName $d.UserPrincipalName) |
                        Select-Object -First 1
                    if (-not $u) {
                        Write-AuditLog -EventId $d.EventId -UserPrincipalName $d.UserPrincipalName `
                            -Stage 'WelcomeSent' -Status 'Failed' `
                            -Detail 'User no longer exists; cannot retry welcome.' -LogPath $logPath
                        $stats.Failed++
                        continue
                    }

                    $userEvent = [pscustomobject]@{
                        EventId           = $d.EventId
                        UserId            = $u.Id
                        DisplayName       = $u.DisplayName
                        UserPrincipalName = $u.UserPrincipalName
                        Mail              = $u.Mail
                        Department        = $u.Department
                        JobTitle          = $u.JobTitle
                        CreatedDateTime   = $u.CreatedDateTime
                        UserType          = if ($u.UserType) { $u.UserType } else { 'Member' }
                        IsHybridSynced    = [bool]$u.OnPremisesSyncEnabled
                        Source            = 'DeferredRetry'
                    }

                    $welcomeResult = Send-WelcomeEmail -User $userEvent -Config $Config -EventId $d.EventId
                    Write-AuditLog -EventId $d.EventId -UserPrincipalName $d.UserPrincipalName `
                        -Stage 'WelcomeSent' -Status $welcomeResult.Status -Detail $welcomeResult.Detail -LogPath $logPath
                    if ($welcomeResult.Status -eq 'OK') { $stats.WelcomeOK++ }
                    elseif ($welcomeResult.Status -eq 'Failed') { $stats.Failed++ }
                } catch {
                    Write-AuditLog -EventId $d.EventId -UserPrincipalName $d.UserPrincipalName `
                        -Stage 'WelcomeSent' -Status 'Failed' -Detail $_.Exception.Message -LogPath $logPath
                    $stats.Failed++
                }
            }
        }

        # Retention: prune audit log per config (default 90d).
        $retDays = if ($Config.Audit.RetentionDays -ne $null) { [int]$Config.Audit.RetentionDays } else { 90 }
        $pruned = Invoke-AuditRetention -LogPath $Config.Audit.LogPath -RetentionDays $retDays

        $summary = [pscustomobject]@{
            Processed       = $stats.Processed
            AdminOK         = $stats.AdminOK
            WelcomeOK       = $stats.WelcomeOK
            WelcomeDeferred = $stats.WelcomeDeferred
            Failed          = $stats.Failed
            Pruned          = $pruned
        }
        Write-Host ("Cycle summary: processed={0} adminOK={1} welcomeOK={2} deferred={3} failed={4} pruned={5}" -f `
            $summary.Processed, $summary.AdminOK, $summary.WelcomeOK, $summary.WelcomeDeferred, $summary.Failed, $summary.Pruned) -ForegroundColor Cyan
        if ($summary.Failed -gt 0) {
            Write-Warning ("{0} failure(s) this cycle. See {1} for details." -f $summary.Failed, $Config.Audit.LogPath)
        }
        return $summary
    }
    finally {
        try { $mutex.ReleaseMutex() } catch { }
        $mutex.Dispose()
    }
}
