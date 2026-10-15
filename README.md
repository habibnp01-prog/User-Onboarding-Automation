# User-Onboarding-Automation

Automated Microsoft 365 user creation alerts and welcome notifications.

## Flow

1. New user created in Entra ID / M365.
2. IT admins get a notification email.
3. New employee gets a welcome email (no passwords by email).
4. Every event and delivery status is written to an audit log.
5. Failures alert the administrator.

## Quick start

    Copy-Item .\src\Config\config.sample.json .\src\Config\config.json
    .\scripts\Invoke-UserNotificationOnce.ps1 -ConfigPath .\src\Config\config.json
    .\scripts\Start-UserNotificationWatcher.ps1 -ConfigPath .\src\Config\config.json

See docs\DEPLOYMENT.md for production options.

See docs\TROUBLESHOOTING.md for subject-line, duplicate-UPN, and TAP accessDenied fixes.
Cycle uses watermark+overlap (default 5m), single-instance mutex, retention prune, and returns processed/adminOK/welcomeOK/deferred/failed/pruned summary.

