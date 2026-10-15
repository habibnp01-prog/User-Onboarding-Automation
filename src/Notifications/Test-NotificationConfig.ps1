function Test-NotificationConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)

    $validAuth = @('Interactive', 'Certificate', 'ManagedIdentity')
    if (-not $Config.AuthMode -or $Config.AuthMode -notin $validAuth) {
        throw "Invalid AuthMode '$($Config.AuthMode)'. Must be one of: $($validAuth -join ', ')."
    }
    if ($Config.AuthMode -eq 'Certificate') {
        if (-not $Config.TenantId) { throw 'Certificate mode requires TenantId.' }
        if (-not $Config.ClientId) { throw 'Certificate mode requires ClientId.' }
        if (-not $Config.CertificateThumbprint) { throw 'Certificate mode requires CertificateThumbprint.' }
    }

    $emailRe = '^[^@\s]+@[^@\s]+\.[^@\s]+$'
    foreach ($a in @($Config.AdminRecipients)) {
        if ($a -and $a -notmatch $emailRe) { throw "Invalid AdminRecipients entry: '$a'." }
    }
    foreach ($f in @('ITSupportEmail', 'FromMailbox')) {
        if ($Config[$f] -and $Config[$f] -notmatch $emailRe) { throw "Invalid ${f}: '$($Config[$f])'." }
    }

    if (-not $Config.Retry) { throw 'Missing Retry section.' }
    if ($Config.Retry.MaxAttempts -lt 1) { throw 'Retry.MaxAttempts must be >= 1.' }
    if ($Config.Retry.InitialDelaySeconds -lt 0) { throw 'Retry.InitialDelaySeconds must be >= 0.' }
    if ($Config.Retry.MaxDelaySeconds -lt 0) { throw 'Retry.MaxDelaySeconds must be >= 0.' }

    if (-not $Config.Monitoring) { throw 'Missing Monitoring section.' }
    if ($Config.Monitoring.LookbackMinutes -le 0) { throw 'Monitoring.LookbackMinutes must be > 0.' }
    if ($Config.Monitoring.PollIntervalSeconds -le 0) { throw 'Monitoring.PollIntervalSeconds must be > 0.' }
    if ($Config.Monitoring.Mode -and $Config.Monitoring.Mode -ne 'Polling') {
        throw "Unsupported Monitoring.Mode '$($Config.Monitoring.Mode)'. Only 'Polling' is wired."
    }

    if (-not $Config.Audit -or -not $Config.Audit.LogPath) { throw 'Missing Audit.LogPath.' }
    if ($Config.Onboarding.MailboxWaitSeconds -ne $null -and $Config.Onboarding.MailboxWaitSeconds -lt 0) {
        throw 'Onboarding.MailboxWaitSeconds must be >= 0.'
    }

    foreach ($t in @('WelcomeTemplatePath', 'AdminTemplatePath')) {
        if ($Config[$t] -and -not (Test-Path $Config[$t])) {
            Write-Warning "$t not found: $($Config[$t])"
        }
    }
}
