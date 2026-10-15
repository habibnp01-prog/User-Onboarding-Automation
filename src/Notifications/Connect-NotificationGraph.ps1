function Get-RequiredGraphScopes {
    <#
    .SYNOPSIS
        Canonical list of Graph scopes the toolkit needs. Config may add more,
        but the toolkit always requests at least these so login consent is
        complete on first run and no feature ever fails mid-flow.
    #>
    [CmdletBinding()]
    param()

    return @(
        # ---- Read user / directory data ----
        'User.Read.All',
        'Directory.Read.All',
        'Organization.Read.All',
        'Domain.Read.All',

        # ---- Create / modify users ----
        'User.ReadWrite.All',

        # ---- Send mail (admin notification + welcome + credentials) ----
        'Mail.Send',

        # ---- Audit log reads for event detection ----
        'AuditLog.Read.All',

        # ---- Group management ----
        'Group.Read.All',
        'Group.ReadWrite.All',

        # ---- License assignment ----
        'LicenseAssignment.ReadWrite.All',

        # ---- Temporary Access Pass (TAP) generation ----
        'UserAuthenticationMethod.ReadWrite.All'
    )
}

function Connect-NotificationGraph {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [string]$ConfigPath,
        [switch]$Reconfigure
    )

    $publicClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'

    # ----------------------------------------------------------
    # 0. Build the scope list - union of built-in + config
    # ----------------------------------------------------------
    $requiredScopes = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($s in (Get-RequiredGraphScopes)) { [void]$requiredScopes.Add($s) }
    if ($Config.Scopes) {
        foreach ($s in $Config.Scopes) {
            if ($s) { [void]$requiredScopes.Add($s) }
        }
    }
    $scopes = @($requiredScopes) | Sort-Object

    # Load user settings from the profile location
    $userSettings = Read-UserSettings

    # Overlay user settings onto config so downstream code sees the full picture
    foreach ($k in $userSettings.Keys) {
        if ($k -eq 'LastUpdated') { continue }
        $Config[$k] = $userSettings[$k]
    }

    # ----------------------------------------------------------
    # 1. Determine whether we need to (re)connect
    #    Reconnect if: no session, wrong tenant, or missing scopes
    # ----------------------------------------------------------
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    $needConnect = $true
    $missingScopes = @()
    if (-not $Reconfigure -and $ctx -and $ctx.TenantId) {
        if (-not $Config.TenantId -or $Config.TenantId -eq $ctx.TenantId) {
            $sessionScopes = if ($ctx.Scopes) { @($ctx.Scopes) } else { @() }
            $missingScopes = @($scopes | Where-Object { $_ -notin $sessionScopes })
            if ($missingScopes.Count -eq 0) {
                $needConnect = $false
            } else {
                Write-Host "Session is missing required scopes: $($missingScopes -join ', ')" -ForegroundColor Yellow
                Write-Host "Reconnecting to request them..." -ForegroundColor Yellow
            }
        }
    }

    if ($needConnect) {
        switch ($Config.AuthMode) {
            'Interactive' {
                $clientId = if ($Config.ClientId) { $Config.ClientId } else { $publicClientId }

                Write-Host 'Sign in with your Microsoft 365 admin account...' -ForegroundColor Cyan
                Write-Host "Requesting scopes:" -ForegroundColor DarkGray
                foreach ($s in $scopes) { Write-Host "  - $s" -ForegroundColor DarkGray }

                $connectArgs = @{
                    ClientId  = $clientId
                    Scopes    = $scopes
                    NoWelcome = $true
                }
                if ($Config.TenantId) { $connectArgs.TenantId = $Config.TenantId }

                Connect-MgGraph @connectArgs
            }
            'Certificate' {
                if (-not $Config.TenantId) { throw 'Certificate mode requires TenantId.' }
                if (-not $Config.ClientId) { throw 'Certificate mode requires ClientId.' }
                $cert = Get-Item "Cert:\$($Config.CertificateStore)\My\$($Config.CertificateThumbprint)"
                if (-not $cert) { throw "Certificate not found: $($Config.CertificateThumbprint)." }
                Connect-MgGraph -TenantId $Config.TenantId -ClientId $Config.ClientId -Certificate $cert -NoWelcome
            }
            'ManagedIdentity' {
                Connect-MgGraph -Identity -NoWelcome
            }
            default { throw "Unsupported AuthMode '$($Config.AuthMode)'." }
        }
    }

    $ctx = Get-MgContext
    if (-not $ctx) { throw 'No Microsoft Graph session available.' }

    # ----------------------------------------------------------
    # 2. Auto-pick from context
    # ----------------------------------------------------------
    $Config.TenantId = $ctx.TenantId
    $Config.ClientId = $ctx.ClientId

    # ----------------------------------------------------------
    # 3. Auto-pick OrganizationName via Graph
    # ----------------------------------------------------------
    if (-not $Config.OrganizationName -or $Reconfigure) {
        try {
            $org = Get-MgOrganization -ErrorAction Stop | Select-Object -First 1
            if ($org -and $org.DisplayName) { $Config.OrganizationName = $org.DisplayName.Trim() }
        } catch {
            Write-Verbose "Could not read organization display name: $($_.Exception.Message)"
        }
    }

    # ----------------------------------------------------------
    # 4. Prompt for missing (or reconfigure) environment fields
    # ----------------------------------------------------------
    $needSetup = $Reconfigure
    if (-not $Config.AdminRecipients -or $Config.AdminRecipients.Count -eq 0) { $needSetup = $true }
    if (-not $Config.OrganizationName) { $needSetup = $true }
    if (-not $Config.ITSupportEmail)   { $needSetup = $true }
    if (-not $Config.FromMailbox)      { $needSetup = $true }

    if ($needSetup -and $Config.AuthMode -eq 'Interactive') {
        Write-Host ''
        Write-Host 'Environment setup - press Enter to accept the default shown in brackets.' -ForegroundColor Cyan
        Write-Host ''

        $defaultAdmins = if ($Config.AdminRecipients -and $Config.AdminRecipients.Count -gt 0) {
            ($Config.AdminRecipients -join ',')
        } elseif ($ctx.Account) { $ctx.Account } else { '' }

        do {
            $input1 = Read-Host "Admin recipients (comma-separated) [$defaultAdmins]"
            if ([string]::IsNullOrWhiteSpace($input1)) { $input1 = $defaultAdmins }
            $admins = @($input1 -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
            $badAdmins = @($admins | Where-Object { $_ -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$' })
            if ($badAdmins.Count -gt 0) { Write-Host "  Invalid: $($badAdmins -join ', ')" -ForegroundColor Yellow }
        } while ($admins.Count -eq 0 -or $badAdmins.Count -gt 0)
        $Config.AdminRecipients = $admins

        if (-not $Config.OrganizationName) {
            do {
                $orgInput = Read-Host 'Organization name'
                if ([string]::IsNullOrWhiteSpace($orgInput)) {
                    Write-Host '  Organization name is required.' -ForegroundColor Yellow
                }
            } while ([string]::IsNullOrWhiteSpace($orgInput))
            $Config.OrganizationName = $orgInput.Trim()
        }

        $defaultSupport = if ($Config.ITSupportEmail) { $Config.ITSupportEmail } elseif ($ctx.Account) { $ctx.Account } else { '' }
        do {
            $support = Read-Host "IT support email [$defaultSupport]"
            if ([string]::IsNullOrWhiteSpace($support)) { $support = $defaultSupport }
            $support = $support.Trim()
            if ($support -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { Write-Host '  Invalid email.' -ForegroundColor Yellow }
        } while ($support -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$')
        $Config.ITSupportEmail = $support

        $defaultFrom = if ($Config.FromMailbox) { $Config.FromMailbox } elseif ($ctx.Account) { $ctx.Account } else { '' }
        do {
            $from = Read-Host "Sender mailbox (FromMailbox) [$defaultFrom]"
            if ([string]::IsNullOrWhiteSpace($from)) { $from = $defaultFrom }
            $from = $from.Trim()
            if ($from -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { Write-Host '  Invalid email.' -ForegroundColor Yellow }
        } while ($from -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$')
        $Config.FromMailbox = $from

        Write-Host ''
    }

    # ----------------------------------------------------------
    # 5. Persist environment fields to USER SETTINGS
    # ----------------------------------------------------------
    $toSave = @{
        TenantId         = $Config.TenantId
        ClientId         = $Config.ClientId
        Account          = $ctx.Account
        OrganizationName = $Config.OrganizationName
        AdminRecipients  = $Config.AdminRecipients
        ITSupportEmail   = $Config.ITSupportEmail
        FromMailbox      = $Config.FromMailbox
    }

    $existing = Read-UserSettings
    $changed = $false
    foreach ($k in $toSave.Keys) {
        $oldVal = $existing[$k]
        $newVal = $toSave[$k]
        if ($oldVal -is [array] -or $newVal -is [array]) {
            $oldJoined = @($oldVal) -join '|'
            $newJoined = @($newVal) -join '|'
            if ($oldJoined -ne $newJoined) { $changed = $true; break }
        } elseif ($oldVal -ne $newVal) {
            $changed = $true; break
        }
    }

    if ($changed) {
        Write-UserSettings -Settings $toSave
    } else {
        Write-Verbose 'User settings unchanged; skipping write.'
    }
}