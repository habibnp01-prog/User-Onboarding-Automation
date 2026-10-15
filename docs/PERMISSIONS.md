# Required Microsoft Graph permissions

Application permissions (admin consent required):

| Permission | Purpose |
|---|---|
| User.Read.All | Read user details, detect new users |
| Mail.Send | Send admin + welcome emails |
| AuditLog.Read.All | Read Entra audit logs (event detection) |
| Directory.Read.All | Read directory and license information |
| UserAuthenticationMethod.Read.All | Verify MFA registration state (optional) |

Managed identity: enable system-assigned identity on the host, then grant the same app roles.


## TAP
- Graph: UserAuthenticationMethod.ReadWrite.All
- Entra role: Authentication Administrator (non-admin targets) or Privileged Authentication Administrator (admin targets)
- Policy: Authentication methods > Temporary Access Pass = Enabled. After role grant: Disconnect-MgGraph + reconnect.

