$script:ModuleRoot = $PSScriptRoot

$orderedFiles = @(
    'ConvertFrom-JsonToHashtable.ps1',
    'UserSettings.ps1',
    'Test-NotificationConfig.ps1',
    'Connect-NotificationGraph.ps1',
    'Get-NewUserEvents.ps1',
    'Write-AuditLog.ps1',
    'Invoke-WithRetry.ps1',
    'Send-AdminNotification.ps1',
    'Send-WelcomeEmail.ps1',
    'Send-CredentialsEmail.ps1',
    'Get-LicenseInventory.ps1',
    'Get-GroupInventory.ps1',
    'New-RandomPassword.ps1',
    'New-TemporaryAccessPass.ps1',
    'New-UserProvisioning.ps1',
    'Invoke-UserNotificationCycle.ps1'
)

foreach ($f in $orderedFiles) {
    $full = Join-Path $PSScriptRoot $f
    if (Test-Path $full) { . $full }
}

Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1' | ForEach-Object {
    if ($orderedFiles -notcontains $_.Name) { . $_.FullName }
}

Export-ModuleMember -Function @(
    'Connect-NotificationGraph',
    'Get-RequiredGraphScopes',
    'ConvertFrom-JsonToHashtable',
    'Test-NotificationConfig',
    'Escape-ODataStringLiteral',
    'Escape-HtmlText',
    'Protect-AuditDetail',
    'New-GraphFilterById',
    'New-GraphFilterByUPN',
    'Get-CycleWatermark',
    'Set-CycleWatermark',
    'Get-UserSettingsPath',
    'Read-UserSettings',
    'Write-UserSettings',
    'Merge-Configs',
    'Get-NewUserEvents',
    'Get-NewUserFromGraph',
    'Test-EventProcessed',
    'Write-AuditLog',
    'Invoke-AuditRetention',
    'Get-DeferredWelcomeEvents',
    'Invoke-WithRetry',
    'Send-AdminNotification',
    'Send-WelcomeEmail',
    'Send-CredentialsEmail',
    'Send-MgMail',
    'Test-UserEligibleForWelcome',
    'Invoke-UserNotificationCycle',
    'Get-LicenseInventory',
    'Get-GroupInventory',
    'New-RandomPassword',
    'New-OnboardedUser',
    'New-TemporaryAccessPass'
)