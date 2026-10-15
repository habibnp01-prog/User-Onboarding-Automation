# Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| No events detected | Lookback too short | Increase LookbackMinutes |
| Duplicate emails | Audit log not shared | Use single sink (Blob/Log Analytics) |
| Welcome skipped | Mailbox not provisioned | Increase MailboxWaitSeconds |
| 403 on Send-MgUserMail | Missing Mail.Send | Grant + consent |
| Hybrid user duplicated | SkipHybridSyncedUsers false | Set true |
| Throttling | Graph limits | Increase Retry.MaxAttempts |
