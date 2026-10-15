<#
.SYNOPSIS
    Single entry point for the User Onboarding Toolkit.
.PARAMETER Mode
    Gui (default) | Cycle | Watch
.PARAMETER Reconfigure
    Force re-prompt for environment fields (AdminRecipients, etc.)
.PARAMETER ForceLogin
    Ignore cached Graph token, sign in fresh.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [ValidateSet('Gui','Cycle','Watch')]
    [string]$Mode = 'Gui',
    [switch]$Reconfigure,
    [switch]$ForceLogin
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path $scriptRoot -Parent

if (-not $ConfigPath) { $ConfigPath = Join-Path $projectRoot 'src\Config\config.json' }
if (-not (Test-Path $ConfigPath)) { throw "Config not found: $ConfigPath" }
$ConfigPath = (Resolve-Path $ConfigPath).Path
Write-Host "Config: $ConfigPath" -ForegroundColor DarkGray

# Import module
$modulePath = Join-Path $projectRoot 'src\Notifications\New-UserNotification.psd1'
Remove-Module New-UserNotification -ErrorAction SilentlyContinue
Import-Module $modulePath -Force
Write-Host 'Module loaded: New-UserNotification' -ForegroundColor Green

# Load repo config
$repoConfig = ConvertFrom-JsonToHashtable -Json (Get-Content $ConfigPath -Raw)

# Optional: force logout
if ($ForceLogin) {
    Write-Host 'Forcing fresh login...' -ForegroundColor Yellow
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
}

# Connect (this also merges user settings and prompts as needed)
Connect-NotificationGraph -Config $repoConfig -ConfigPath $ConfigPath -Reconfigure:$Reconfigure

# Merge repo + user settings into final config for the dispatch
$userSettings = Read-UserSettings
$finalConfig = Merge-Configs -RepoConfig $repoConfig -UserSettings $userSettings

switch ($Mode) {
    'Cycle' {
        Write-Host ''
        Write-Host 'Running one notification cycle...' -ForegroundColor Cyan
        Invoke-UserNotificationCycle -ConfigPath $ConfigPath
        Write-Host 'Cycle complete.' -ForegroundColor Green
    }
    'Watch' {
        $interval = if ($finalConfig.Monitoring -and $finalConfig.Monitoring.PollIntervalSeconds) {
            [int]$finalConfig.Monitoring.PollIntervalSeconds
        } else { 300 }
        Write-Host ''
        Write-Host "Watching. Polling every $interval seconds. Ctrl+C to stop." -ForegroundColor Cyan
        while ($true) {
            try { Invoke-UserNotificationCycle -ConfigPath $ConfigPath }
            catch { Write-Warning "Cycle error: $($_.Exception.Message)" }
            Start-Sleep -Seconds $interval
        }
    }
    'Gui' {
        $guiPath = Join-Path $projectRoot 'src\GUI\Show-OnboardingWizard.ps1'
        if (Test-Path $guiPath) {
            Write-Host ''
            Write-Host 'Launching onboarding wizard...' -ForegroundColor Cyan
            & $guiPath -ConfigPath $ConfigPath
        } else {
            Write-Host 'GUI not installed. Falling back to one cycle.' -ForegroundColor Yellow
            Invoke-UserNotificationCycle -ConfigPath $ConfigPath
        }
    }
}