@{
    RootModule        = 'New-UserNotification.psm1'
    ModuleVersion     = '0.7.0'
    GUID              = 'a1b2c3d4-e5f6-4789-abcd-ef0123456789'
    Author            = 'IT Automation'
    CompanyName       = 'Contoso'
    Copyright         = '(c) 2026'
    Description       = 'Microsoft 365 user onboarding notification automation.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
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

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}