# Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| No events detected | Lookback too short | Increase LookbackMinutes |
| Duplicate emails | Audit log not shared | Use single sink (Blob/Log Analytics) |
| Welcome skipped | Mailbox not provisioned | Increase MailboxWaitSeconds |
| 403 on Send-MgUserMail | Missing Mail.Send | Grant + consent |
| Hybrid user duplicated | SkipHybridSyncedUsers false | Set true |
| Throttling | Graph limits | Increase Retry.MaxAttempts |


## Recent fixes
- Subject System.Collections.Hashtable: fixed, message.subject must be string, not @{content=}. Verify with Select-String subject = .
- Request_BadRequest duplicate UPN: UPN exists active or soft-deleted. Check Get-MgUser + Get-MgDirectoryDeletedItemAsUser.
- TAP accessDenied: enable TAP policy + assign admin role, then Disconnect-MgGraph.
- Stale token after role grant: Disconnect-MgGraph before next wizard run.

