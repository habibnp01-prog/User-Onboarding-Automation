function Send-MgMail {
    param([string]$UserId, [hashtable]$BodyParameter)
    Send-MgUserMail -UserId $UserId -BodyParameter $BodyParameter
}

function Send-AdminNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$User,
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$EventId
    )

    if ($Config.DryRun) {
        return [pscustomobject]@{ Status = 'DryRun'; Detail = 'DryRun enabled.' }
    }

    # Validate recipients BEFORE trying to send
    $recipients = @()
    if ($Config.AdminRecipients) { $recipients = @($Config.AdminRecipients | Where-Object { $_ }) }
    if ($recipients.Count -eq 0) {
        return [pscustomobject]@{
            Status = 'Failed'
            Detail = 'No AdminRecipients configured. Add recipients in user settings or config.'
        }
    }
    if (-not $Config.FromMailbox) {
        return [pscustomobject]@{ Status = 'Failed'; Detail = 'No FromMailbox configured.' }
    }

    $subject = "New Microsoft 365 User Created - $($User.DisplayName)"
    $body = Get-Content $Config.AdminTemplatePath -Raw
    $body = $body.
        Replace('{{DisplayName}}', (Escape-HtmlText "$($User.DisplayName)")).
        Replace('{{UPN}}',         (Escape-HtmlText "$($User.UserPrincipalName)")).
        Replace('{{Mail}}',        (Escape-HtmlText "$($User.Mail)")).
        Replace('{{Department}}',  (Escape-HtmlText "$($User.Department)")).
        Replace('{{JobTitle}}',    (Escape-HtmlText "$($User.JobTitle)")).
        Replace('{{Created}}',     (Escape-HtmlText "$($User.CreatedDateTime)")).
        Replace('{{UserType}}',    (Escape-HtmlText "$($User.UserType)")).
        Replace('{{Source}}',      (Escape-HtmlText "$($User.Source)")).
        Replace('{{EventId}}',     (Escape-HtmlText "$EventId")).
        Replace('{{EntraLink}}',   "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/overview/userId/$($User.UserId)")

    $message = @{
        subject = $subject
        body         = @{ contentType = 'HTML'; content = $body }
        toRecipients = @($recipients | ForEach-Object { @{ emailAddress = @{ address = $_ } } })
    }

    Invoke-WithRetry -MaxAttempts $Config.Retry.MaxAttempts `
        -InitialDelaySeconds $Config.Retry.InitialDelaySeconds `
        -MaxDelaySeconds $Config.Retry.MaxDelaySeconds `
        -Action {
            Send-MgMail -UserId $Config.FromMailbox -BodyParameter @{
                message         = $message
                saveToSentItems = $false
            }
        }

    return [pscustomobject]@{ Status = 'OK'; Detail = "Sent to $($recipients.Count) recipient(s)." }
}
