# Deployment

Pick one host:

- Azure Function (PowerShell, timer trigger) - recommended
- Azure Automation runbook
- Container App / ACI with scheduled task
- GitHub Actions scheduled workflow (small tenants)

## Steps

1. Register app in Entra, upload certificate, grant app roles, admin-consent.
2. Deploy code + config.json (secrets via Key Vault references).
3. Start with DryRun=true, SendEmployeeEmails=false.
4. Verify audit log entries for a test user.
5. Flip DryRun=false; leave SendEmployeeEmails=false until template is approved.
6. Enable SendEmployeeEmails=true.


## Promotion
DryRun=true verify audit log, then DryRun=false. Ensure OverlapMinutes=5, RetentionDays=90, single watcher only (mutex skips parallel runs).

