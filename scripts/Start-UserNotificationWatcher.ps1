[CmdletBinding()]
param([Parameter(Mandatory)][string]$ConfigPath)
Import-Module "$PSScriptRoot\..\src\Notifications\New-UserNotification.psm1" -Force
$Config = Get-Content (Resolve-Path $ConfigPath) -Raw | ConvertFrom-Json -AsHashtable
Write-Host "Starting watcher. Interval: $($Config.Monitoring.PollIntervalSeconds)s" -ForegroundColor Cyan
while ($true) {
    try { Invoke-UserNotificationCycle -ConfigPath (Resolve-Path $ConfigPath) }
    catch { Write-Warning $_.Exception.Message }
    Start-Sleep -Seconds $Config.Monitoring.PollIntervalSeconds
}
