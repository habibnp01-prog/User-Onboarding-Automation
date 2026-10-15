[CmdletBinding()]
param([Parameter(Mandatory)][string]$ConfigPath)
Import-Module "$PSScriptRoot\..\src\Notifications\New-UserNotification.psm1" -Force
Invoke-UserNotificationCycle -ConfigPath (Resolve-Path $ConfigPath)
