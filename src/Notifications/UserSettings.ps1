function Get-UserSettingsPath {
    [CmdletBinding()]
    param()
    $dir = Join-Path $env:USERPROFILE '.user-onboarding-automation'
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return (Join-Path $dir 'settings.json')
}

function Read-UserSettings {
    [CmdletBinding()]
    param()
    $path = Get-UserSettingsPath
    if (-not (Test-Path $path)) { return @{} }
    try {
        $raw = Get-Content $path -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
        return (ConvertFrom-JsonToHashtable -Json $raw)
    } catch {
        Write-Warning "Could not read user settings from $path : $($_.Exception.Message)"
        return @{}
    }
}

function Write-UserSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Settings)
    $path = Get-UserSettingsPath

    # Merge with existing so partial writes don't clobber other fields
    $existing = Read-UserSettings
    foreach ($k in $Settings.Keys) { $existing[$k] = $Settings[$k] }

    $existing['LastUpdated'] = (Get-Date).ToUniversalTime().ToString('o')
    $existing | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
    Write-Host "User settings saved to $path" -ForegroundColor Cyan
}

function Merge-Configs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$RepoConfig,
        [hashtable]$UserSettings
    )
    if (-not $UserSettings) { $UserSettings = Read-UserSettings }

    $merged = @{}
    # Start with repo config
    foreach ($k in $RepoConfig.Keys) { $merged[$k] = $RepoConfig[$k] }
    # Overlay user settings (these win)
    foreach ($k in $UserSettings.Keys) {
        if ($k -eq 'LastUpdated') { continue }
        $merged[$k] = $UserSettings[$k]
    }
    return $merged
}