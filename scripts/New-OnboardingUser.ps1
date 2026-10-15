[CmdletBinding()]
param(
    [string]$ConfigPath
)

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path $scriptRoot -Parent

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $projectRoot 'src\Config\config.json'
}
if (-not (Test-Path $ConfigPath)) { throw "Config not found: $ConfigPath" }

# Import module
Import-Module (Join-Path $projectRoot 'src\Notifications\New-UserNotification.psd1') -Force

# Connect if not already connected
$ctx = Get-MgContext -ErrorAction SilentlyContinue
if (-not $ctx) {
    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $scopes = if ($cfg.Scopes) { $cfg.Scopes } else {
        @('User.Read.All','User.ReadWrite.All','Mail.Send','AuditLog.Read.All','Directory.Read.All',
          'Organization.Read.All','Group.Read.All','Group.ReadWrite.All','LicenseAssignment.ReadWrite.All','Domain.Read.All')
    }
    $clientId = if ($cfg.ClientId) { $cfg.ClientId } else { '14d82eec-204b-4c2f-b7e8-296a70dab67e' }
    Write-Host 'Signing in to Microsoft Graph...' -ForegroundColor Cyan
    Connect-MgGraph -ClientId $clientId -Scopes $scopes -NoWelcome
}

# Launch wizard
& (Join-Path $projectRoot 'src\GUI\Show-OnboardingWizard.ps1') -ConfigPath $ConfigPath