function Test-UserEligibleForWelcome {
    param($User, [hashtable]$Config)

    if (-not $Config.SendEmployeeEmails) {
        return @{ Eligible=$false; Reason='Employee emails disabled.' }
    }
    if ($Config.Onboarding.SkipHybridSyncedUsers -and $User.IsHybridSynced) {
        return @{ Eligible=$false; Reason='Hybrid-synced user.' }
    }
    if ($Config.Onboarding.AllowedUserTypes -and $User.UserType) {
        if ($User.UserType -notin $Config.Onboarding.AllowedUserTypes) {
            return @{ Eligible=$false; Reason="UserType '$($User.UserType)' not allowed." }
        }
    }

    if ($User.PersonalEmail) {
        return @{ Eligible=$true; Recipient=$User.PersonalEmail; Channel='PersonalEmail' }
    }
    if (-not $User.Mail) {
        return @{ Eligible=$false; Reason='No mailbox yet.'; Deferrable=$true }
    }
    return @{ Eligible=$true; Recipient=$User.Mail; Channel='WorkMailbox' }
}

function Expand-WelcomeTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][hashtable]$Values
    )

    $rendered = $Template
    foreach ($k in $Values.Keys) {
        $v = $Values[$k]
        if ($null -eq $v) { $v = '' }
        $rendered = $rendered.Replace($k, "$v")
    }

    # Remove table rows where the value cell is empty. Anchored so it only matches
    # a single row: <tr> <td>label</td> <td>value</td> </tr>
    # No nested tags in the label cell, no [^<] in the value cell.
    $rowPattern = '(?is)<tr>\s*<td[^>]*>[^<]+</td>\s*<td[^>]*>\s*</td>\s*</tr>'
    $rendered = [regex]::Replace($rendered, $rowPattern, '')

    # Also strip rows where the value is still an unexpanded {{placeholder}}
    $placeholderPattern = '(?is)<tr>\s*<td[^>]*>[^<]+</td>\s*<td[^>]*>\s*\{\{[^}]+\}\}\s*</td>\s*</tr>'
    $rendered = [regex]::Replace($rendered, $placeholderPattern, '')

    return $rendered
}

function Build-AccessPassBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$UserPrincipalName,
        [Parameter(Mandatory)][string]$AccessPass,
        [Parameter(Mandatory)][datetime]$ExpiresAt,
        [Parameter(Mandatory)][string]$LoginUrl
    )

    $expiresLocal = $ExpiresAt.ToLocalTime().ToString('yyyy-MM-dd HH:mm')
    $safeUpn = Escape-HtmlText $UserPrincipalName
    $safePass = Escape-HtmlText $AccessPass
    $safeUrl = Escape-HtmlText $LoginUrl
    return @"
<div style="margin-top:24px;padding:16px;border:1px solid #d0d7de;border-left:4px solid #0a3d62;background:#f6f8fa">
  <h3 style="color:#0a3d62;margin-top:0">Your sign-in details</h3>
  <table cellpadding="6" cellspacing="0" style="border-collapse:collapse">
    <tr><td><b>Login URL</b></td><td><a href="$safeUrl">$safeUrl</a></td></tr>
    <tr><td><b>Username</b></td><td>$safeUpn</td></tr>
    <tr><td><b>Temporary access pass</b></td><td><code style="background:#fff;padding:3px 8px;border:1px solid #ccc;border-radius:3px;font-size:15px">$safePass</code></td></tr>
    <tr><td><b>Valid until</b></td><td>$expiresLocal (local time)</td></tr>
  </table>
  <p style="color:#a00"><b>This pass expires after 24 hours and can be used only once.</b></p>
  <p>After signing in, register multi-factor authentication and set your permanent password.</p>
</div>
"@
}

function Send-WelcomeEmail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$User,
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$EventId
    )

    $elig = Test-UserEligibleForWelcome -User $User -Config $Config
    if (-not $elig.Eligible) {
        $status = if ($elig.Deferrable) { 'Deferred' } else { 'Skipped' }
        return [pscustomobject]@{ Status = $status; Detail = $elig.Reason; Recipient = $null }
    }

    if ($Config.DryRun) {
        return [pscustomobject]@{
            Status    = 'DryRun'
            Detail    = "Would send to $($elig.Recipient) ($($elig.Channel))."
            Recipient = $elig.Recipient
        }
    }

    if (-not $Config.FromMailbox) {
        return [pscustomobject]@{ Status = 'Failed'; Detail = 'No FromMailbox configured.'; Recipient = $null }
    }

    $subject = "Welcome to $($Config.OrganizationName) - Your Account Details"
    $rawTemplate = Get-Content $Config.WelcomeTemplatePath -Raw

    # Access pass block (preferred) or password block (fallback)
    $accessBlock = ''
    $loginUrl = if ($Config.LoginUrl) { $Config.LoginUrl } else { 'https://outlook.office.com' }

    if ($Config.IncludeAccessPassInWelcome -and $User.TemporaryAccessPass) {
        $accessBlock = Build-AccessPassBlock -UserPrincipalName $User.UserPrincipalName `
            -AccessPass $User.TemporaryAccessPass `
            -ExpiresAt  $User.TemporaryAccessPassExpiresAt `
            -LoginUrl   $loginUrl
    } elseif ($Config.IncludePasswordInWelcome -and $elig.Channel -eq 'PersonalEmail' -and $Config.TemporaryPassword) {
        $accessBlock = @"
<div style="margin-top:24px;padding:16px;border:1px solid #d0d7de;border-left:4px solid #c00;background:#fff8f8">
  <h3 style="color:#a00;margin-top:0">Your temporary sign-in details</h3>
  <table cellpadding="6" cellspacing="0" style="border-collapse:collapse">
    <tr><td><b>Login URL</b></td><td><a href="$loginUrl">$loginUrl</a></td></tr>
    <tr><td><b>Username</b></td><td>$($User.UserPrincipalName)</td></tr>
    <tr><td><b>Temporary password</b></td><td><code>$($Config.TemporaryPassword)</code></td></tr>
  </table>
  <p style="color:#a00"><b>Change this password immediately after your first sign-in.</b></p>
</div>
"@
    }

    $values = @{
        '{{DisplayName}}'      = if ($User.DisplayName) { Escape-HtmlText "$($User.DisplayName)" } else { '' }
        '{{UPN}}'              = if ($User.UserPrincipalName) { Escape-HtmlText "$($User.UserPrincipalName)" } else { '' }
        '{{Mail}}'             = if ($User.Mail)        { Escape-HtmlText "$($User.Mail)" }        else { '' }
        '{{Department}}'       = if ($User.Department)  { Escape-HtmlText "$($User.Department)" }  else { '' }
        '{{JobTitle}}'         = if ($User.JobTitle)    { Escape-HtmlText "$($User.JobTitle)" }    else { '' }
        '{{Phone}}'            = if ($User.Phone)       { Escape-HtmlText "$($User.Phone)" }       else { '' }
        '{{Office}}'           = if ($User.Office)      { Escape-HtmlText "$($User.Office)" }      else { '' }
        '{{EmployeeId}}'       = if ($User.EmployeeId)  { Escape-HtmlText "$($User.EmployeeId)" }  else { '' }
        '{{Manager}}'          = if ($User.Manager)     { Escape-HtmlText "$($User.Manager)" }     else { '' }
        '{{Org}}'              = Escape-HtmlText "$($Config.OrganizationName)"
        '{{Support}}'          = Escape-HtmlText "$($Config.ITSupportEmail)"
        '{{LoginUrl}}'         = $loginUrl
        '{{PasswordBlock}}'    = $accessBlock
        '{{AccessPassBlock}}'  = $accessBlock
    }

    $body = Expand-WelcomeTemplate -Template $rawTemplate -Values $values

    Invoke-WithRetry -MaxAttempts $Config.Retry.MaxAttempts `
        -InitialDelaySeconds $Config.Retry.InitialDelaySeconds `
        -MaxDelaySeconds $Config.Retry.MaxDelaySeconds `
        -Action {
            Send-MgMail -UserId $Config.FromMailbox -BodyParameter @{
                message = @{
                    subject = $subject
                    body         = @{ contentType='HTML'; content=$body }
                    toRecipients = @(@{ emailAddress = @{ address = $elig.Recipient } })
                }
                saveToSentItems = $false
            }
        }

    return [pscustomobject]@{
        Status    = 'OK'
        Detail    = "Sent to $($elig.Recipient) ($($elig.Channel))."
        Recipient = $elig.Recipient
    }
}
