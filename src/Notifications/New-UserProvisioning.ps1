function New-OnboardedUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$UserPrincipalName,
        [Parameter(Mandatory)][string]$MailNickname,
        [Parameter(Mandatory)][string]$Password,
        [switch]$ForceChangePasswordNextSignIn,

        [string]$GivenName,
        [string]$Surname,
        [string]$JobTitle,
        [string]$Department,
        [string]$UsageLocation = 'NP',

        [string]$Phone,
        [string]$OfficeLocation,
        [string]$EmployeeId,

        [string]$PersonalEmail,
        [string]$CredentialsRecipient,

        [switch]$IncludePasswordInWelcome,
        [switch]$UseTemporaryAccessPass,
        [switch]$SendCredentialsEmail,

        [string[]]$LicenseSkuIds,
        [string]$LicenseSkuId,

        [string]$ManagerUpn,
        [string[]]$GroupIds,

        [Parameter(Mandatory)][hashtable]$Config,
        [switch]$SkipNotifications
    )

    if (-not $LicenseSkuIds -and $LicenseSkuId) { $LicenseSkuIds = @($LicenseSkuId) }
    if (-not $LicenseSkuIds) { $LicenseSkuIds = @() }

    if ($UserPrincipalName -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        throw "Invalid UserPrincipalName: $UserPrincipalName"
    }
    if ($Password.Length -lt 8) {
        throw 'Password must be at least 8 characters.'
    }
    if ($PersonalEmail -and $PersonalEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        throw "Invalid PersonalEmail: $PersonalEmail"
    }
    if ($CredentialsRecipient -and $CredentialsRecipient -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        throw "Invalid CredentialsRecipient: $CredentialsRecipient"
    }

    # ---- Create user ----
    $passwordProfile = @{
        Password                      = $Password
        ForceChangePasswordNextSignIn = [bool]$ForceChangePasswordNextSignIn
    }
    $newUserParams = @{
        DisplayName       = $DisplayName
        UserPrincipalName = $UserPrincipalName
        MailNickname      = $MailNickname
        AccountEnabled    = $true
        PasswordProfile   = $passwordProfile
        UsageLocation     = $UsageLocation
    }
    if ($GivenName)      { $newUserParams.GivenName      = $GivenName }
    if ($Surname)        { $newUserParams.Surname        = $Surname }
    if ($JobTitle)       { $newUserParams.JobTitle       = $JobTitle }
    if ($Department)     { $newUserParams.Department     = $Department }
    if ($Phone)          { $newUserParams.MobilePhone    = $Phone }
    if ($OfficeLocation) { $newUserParams.OfficeLocation = $OfficeLocation }
    if ($EmployeeId)     { $newUserParams.EmployeeId     = $EmployeeId }
    if ($PersonalEmail)  { $newUserParams.OtherMails     = @($PersonalEmail) }

    $user = New-MgUser @newUserParams
    if (-not $user -or -not $user.Id) { throw 'User creation returned no object.' }
    Write-Host "Created user $($user.UserPrincipalName) (Id: $($user.Id))" -ForegroundColor Green

    $result = [ordered]@{
        UserId              = $user.Id
        UserPrincipalName   = $user.UserPrincipalName
        DisplayName         = $user.DisplayName
        Created             = $true
        LicenseAssigned     = $false
        LicenseSkuIds       = @()
        GroupsAssigned      = @()
        GroupsFailed        = @()
        ManagerSet          = $false
        TemporaryAccessPass = $null
        TapExpiresAt        = $null
        Errors              = @()
    }

    # ---- Manager ----
    if ($ManagerUpn) {
        try {
            $manager = Get-MgUser -UserId $ManagerUpn -ErrorAction Stop
            Set-MgUserManagerByRef -UserId $user.Id -BodyParameter @{
                '@odata.id' = "https://graph.microsoft.com/v1.0/users/$($manager.Id)"
            }
            $result.ManagerSet = $true
            Write-Host "Manager set to $ManagerUpn." -ForegroundColor Green
        } catch {
            $msg = "Manager assignment failed: $($_.Exception.Message)"
            Write-Warning $msg
            $result.Errors += $msg
        }
    }

    # ---- Licenses ----
    if ($LicenseSkuIds.Count -gt 0) {
        try {
            $addLicenses = @()
            foreach ($sku in $LicenseSkuIds) {
                $addLicenses += @{ SkuId = $sku; DisabledPlans = @() }
            }
            Set-MgUserLicense -UserId $user.Id -BodyParameter @{
                AddLicenses    = $addLicenses
                RemoveLicenses = @()
            }
            $result.LicenseAssigned = $true
            $result.LicenseSkuIds   = $LicenseSkuIds
            Write-Host "Assigned $($LicenseSkuIds.Count) license(s)." -ForegroundColor Green
        } catch {
            $msg = "License assignment failed: $($_.Exception.Message)"
            Write-Warning $msg
            $result.Errors += $msg
        }
    }

    # ---- Groups ----
    if ($GroupIds -and $GroupIds.Count -gt 0) {
        foreach ($gid in $GroupIds) {
            try {
                New-MgGroupMember -GroupId $gid -DirectoryObjectId $user.Id
                $result.GroupsAssigned += $gid
                Write-Host "Added to group: $gid" -ForegroundColor Green
            } catch {
                $msg = "Group membership failed for $gid : $($_.Exception.Message)"
                Write-Warning $msg
                $result.GroupsFailed += $gid
                $result.Errors += $msg
            }
        }
    }

    # ---- Temporary Access Pass ----
    if ($UseTemporaryAccessPass) {
        try {
            $tapConfig = $Config.TemporaryAccessPass
            $tapMinutes = 1440
            $tapOnce    = $true
            if ($tapConfig) {
                if ($tapConfig.LifetimeMinutes) { $tapMinutes = [int]$tapConfig.LifetimeMinutes }
                if ($tapConfig.ContainsKey('IsUsableOnce')) { $tapOnce = [bool]$tapConfig.IsUsableOnce }
            }

            $tap = New-TemporaryAccessPass -UserId $user.Id `
                -LifetimeMinutes $tapMinutes `
                -IsUsableOnce $tapOnce
            $result.TemporaryAccessPass = $tap.TemporaryAccessPass
            $result.TapExpiresAt        = $tap.ExpiresAt
            Write-Host "Temporary access pass generated (expires $($tap.ExpiresAt))." -ForegroundColor Green
        } catch {
            $msg = "TAP generation failed: $($_.Exception.Message)"
            Write-Warning $msg
            $result.Errors += $msg
        }
    }

    # ---- Notifications ----
    if (-not $SkipNotifications -and $Config) {
        $eventId = "provision-$($user.Id)-$((Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'))"
        $logPath = $Config.Audit.LogPath

        $userEvent = [pscustomobject]@{
            EventId                     = $eventId
            UserId                      = $user.Id
            DisplayName                 = $user.DisplayName
            UserPrincipalName           = $user.UserPrincipalName
            Mail                        = $user.Mail
            Department                  = if ($Department)     { $Department }     else { $user.Department }
            JobTitle                    = if ($JobTitle)       { $JobTitle }       else { $user.JobTitle }
            Phone                       = if ($Phone)          { $Phone }          else { $user.MobilePhone }
            Office                      = if ($OfficeLocation) { $OfficeLocation } else { $user.OfficeLocation }
            EmployeeId                  = if ($EmployeeId)     { $EmployeeId }     else { $user.EmployeeId }
            Manager                     = $ManagerUpn
            PersonalEmail               = $PersonalEmail
            TemporaryAccessPass         = $result.TemporaryAccessPass
            TemporaryAccessPassExpiresAt = $result.TapExpiresAt
            CreatedDateTime             = $user.CreatedDateTime
            UserType                    = if ($user.UserType) { $user.UserType } else { 'Member' }
            IsHybridSynced              = $false
            Source                      = 'GuiProvisioning'
        }

        Write-AuditLog -EventId $eventId -UserPrincipalName $user.UserPrincipalName `
            -Stage 'Detected' -Status 'OK' -Detail 'GuiProvisioning' -LogPath $logPath

        # Admin notification
        try {
            $adminResult = Send-AdminNotification -User $userEvent -Config $Config -EventId $eventId
            Write-AuditLog -EventId $eventId -UserPrincipalName $user.UserPrincipalName `
                -Stage 'AdminSent' -Status $adminResult.Status -Detail $adminResult.Detail -LogPath $logPath
        } catch {
            Write-AuditLog -EventId $eventId -UserPrincipalName $user.UserPrincipalName `
                -Stage 'AdminSent' -Status 'Failed' -Detail $_.Exception.Message -LogPath $logPath
        }

        # Welcome email (informational only - no secrets unless explicitly enabled)
        try {
            $welcomeConfig = @{}
            foreach ($k in $Config.Keys) { $welcomeConfig[$k] = $Config[$k] }
            $welcomeConfig['IncludePasswordInWelcome']   = [bool]$IncludePasswordInWelcome
            $welcomeConfig['IncludeAccessPassInWelcome'] = $false
            $welcomeConfig['TemporaryPassword']          = $Password

            $welcomeResult = Send-WelcomeEmail -User $userEvent -Config $welcomeConfig -EventId $eventId
            Write-AuditLog -EventId $eventId -UserPrincipalName $user.UserPrincipalName `
                -Stage 'WelcomeSent' -Status $welcomeResult.Status -Detail $welcomeResult.Detail -LogPath $logPath
        } catch {
            Write-AuditLog -EventId $eventId -UserPrincipalName $user.UserPrincipalName `
                -Stage 'WelcomeSent' -Status 'Failed' -Detail $_.Exception.Message -LogPath $logPath
        }

        # Credentials email (separate, contains TAP or password)
        if ($SendCredentialsEmail -and $CredentialsRecipient) {
            try {
                $credConfig = @{}
                foreach ($k in $Config.Keys) { $credConfig[$k] = $Config[$k] }
                $credConfig['IncludeAccessPassInWelcome'] = [bool]($result.TemporaryAccessPass)
                $credConfig['TemporaryPassword']          = $Password

                $credResult = Send-CredentialsEmail -User $userEvent -Config $credConfig `
                    -EventId $eventId -Recipient $CredentialsRecipient
                Write-AuditLog -EventId $eventId -UserPrincipalName $user.UserPrincipalName `
                    -Stage 'CredentialsSent' -Status $credResult.Status -Detail $credResult.Detail -LogPath $logPath
            } catch {
                Write-AuditLog -EventId $eventId -UserPrincipalName $user.UserPrincipalName `
                    -Stage 'CredentialsSent' -Status 'Failed' -Detail $_.Exception.Message -LogPath $logPath
            }
        }
    }

    return [pscustomobject]$result
}