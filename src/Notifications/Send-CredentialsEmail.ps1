function Build-CredentialsBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$User,
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$LoginUrl
    )

    $credLabel = if ($Config.IncludeAccessPassInWelcome -and $User.TemporaryAccessPass) {
        'Temporary access pass'
    } else {
        'Temporary password'
    }
    $credValue = if ($Config.IncludeAccessPassInWelcome -and $User.TemporaryAccessPass) {
        $User.TemporaryAccessPass
    } else {
        $Config.TemporaryPassword
    }

    $expiresRow = ''
    if ($Config.IncludeAccessPassInWelcome -and $User.TemporaryAccessPassExpiresAt) {
        $when = ([datetime]$User.TemporaryAccessPassExpiresAt).ToLocalTime().ToString('yyyy-MM-dd HH:mm')
        $expiresRow = "<tr><td style=`"padding:6px`"><b>Valid until</b></td><td style=`"padding:6px`">$when (local time)</td></tr>"
    }

    $raw = Get-Content $Config.WelcomeTemplatePath -Raw -ErrorAction SilentlyContinue
    # We use a dedicated template if configured, else fall back to the welcome template's wrappers
    $credTemplatePath = if ($Config.CredentialsTemplatePath) { $Config.CredentialsTemplatePath } else { '' }
    $template = ''
    if ($credTemplatePath -and (Test-Path $credTemplatePath)) {
        $template = Get-Content $credTemplatePath -Raw
    }
    if (-not $template) {
        $template = @"
<!DOCTYPE html>
<html><body style="font-family:Segoe UI,Arial,sans-serif;color:#222;font-size:14px;line-height:1.5">
  <div style="padding:12px;border:1px solid #d0d7de;border-left:4px solid #c00;background:#fff8f8;margin-bottom:16px">
    <b style="color:#a00">This email contains sign-in credentials.</b>
    Never forward it. IT support will never ask you for your password or access pass.
  </div>

  <h2 style="color:#0a3d62">Your Microsoft 365 sign-in details</h2>
  <p>Hi {{DisplayName}}, your Microsoft 365 account is ready. Use the details below to sign in for the first time.</p>

  <table cellpadding="6" cellspacing="0" style="border-collapse:collapse">
    <tr><td style="padding:6px"><b>Login URL</b></td><td style="padding:6px"><a href="{{LoginUrl}}">{{LoginUrl}}</a></td></tr>
    <tr><td style="padding:6px"><b>Username</b></td><td style="padding:6px">{{UPN}}</td></tr>
    <tr><td style="padding:6px"><b>{{CredLabel}}</b></td><td style="padding:6px"><code style="background:#f0f0f0;padding:3px 8px;border:1px solid #ccc;border-radius:3px;font-size:15px">{{CredValue}}</code></td></tr>
    {{ExpiresRow}}
  </table>

  <p>On first sign-in you will be asked to register multi-factor authentication and set your permanent password.</p>
  <p>If you did not expect this email, contact IT support at <a href="mailto:{{Support}}">{{Support}}</a>.</p>

  <p style="color:#666;font-size:12px">Sent automatically by {{Org}} IT automation.</p>
</body></html>
"@
    }

    $values = @{
        '{{DisplayName}}' = if ($User.DisplayName) { Escape-HtmlText "$($User.DisplayName)" } else { '' }
        '{{UPN}}'         = if ($User.UserPrincipalName) { Escape-HtmlText "$($User.UserPrincipalName)" } else { '' }
        '{{LoginUrl}}'    = Escape-HtmlText $LoginUrl
        '{{CredLabel}}'   = Escape-HtmlText $credLabel
        '{{CredValue}}'   = Escape-HtmlText $credValue
        '{{ExpiresRow}}'  = $expiresRow
        '{{Support}}'     = if ($Config.ITSupportEmail) { Escape-HtmlText "$($Config.ITSupportEmail)" } else { '' }
        '{{Org}}'         = if ($Config.OrganizationName) { Escape-HtmlText "$($Config.OrganizationName)" } else { '' }
    }

    $body = $template
    foreach ($k in $values.Keys) {
        $v = $values[$k]
        if ($null -eq $v) { $v = '' }
        $body = $body.Replace($k, "$v")
    }
    return $body
}

function Send-CredentialsEmail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$User,
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$EventId,
        [Parameter(Mandatory)][string]$Recipient
    )

    if ($Config.DryRun) {
        return [pscustomobject]@{
            Status    = 'DryRun'
            Detail    = "Would send credentials to $Recipient."
            Recipient = $Recipient
        }
    }

    if (-not $Config.FromMailbox) {
        return [pscustomobject]@{ Status = 'Failed'; Detail = 'No FromMailbox configured.'; Recipient = $Recipient }
    }

    # Require either a TAP or a password
    $hasTap = $Config.IncludeAccessPassInWelcome -and $User.TemporaryAccessPass
    $hasPassword = $Config.TemporaryPassword
    if (-not $hasTap -and -not $hasPassword) {
        return [pscustomobject]@{ Status = 'Failed'; Detail = 'No credentials available (no TAP, no password).'; Recipient = $Recipient }
    }

    $loginUrl = if ($Config.LoginUrl) { $Config.LoginUrl } else { 'https://outlook.office.com' }
    $subjectTemplate = if ($Config.CredentialSubjectTemplate) { $Config.CredentialSubjectTemplate } else { 'Your Microsoft 365 sign-in details - {DisplayName}' }
    $subject = $subjectTemplate.Replace('{DisplayName}', "$($User.DisplayName)").Replace('{UPN}', "$($User.UserPrincipalName)")

    $body = Build-CredentialsBody -User $User -Config $Config -LoginUrl $loginUrl

    Invoke-WithRetry -MaxAttempts $Config.Retry.MaxAttempts `
        -InitialDelaySeconds $Config.Retry.InitialDelaySeconds `
        -MaxDelaySeconds $Config.Retry.MaxDelaySeconds `
        -Action {
            Send-MgMail -UserId $Config.FromMailbox -BodyParameter @{
                message = @{
                    subject = $subject
                    body         = @{ contentType='HTML'; content=$body }
                    toRecipients = @(@{ emailAddress = @{ address = $Recipient } })
                }
                saveToSentItems = $false
            }
        }

    return [pscustomobject]@{
        Status    = 'OK'
        Detail    = "Sent credentials to $Recipient."
        Recipient = $Recipient
    }
}
