function Test-EventProcessed {
    [CmdletBinding()]
    param(
        [string]$EventId,
        [string]$LogPath,
        [string]$UserPrincipalName
    )
    if (-not $LogPath -or -not (Test-Path $LogPath)) { return $false }
    if (-not $EventId -and -not $UserPrincipalName) { return $false }

    # Single streaming pass: avoids loading the file twice (was O(2N) per event).
    $eventNeedle = if ($EventId) { '"EventId":"' + $EventId + '"' } else { $null }
    $upnNeedle = if ($UserPrincipalName) { '"UserPrincipalName":"' + $UserPrincipalName + '"' } else { $null }

    foreach ($line in [System.IO.File]::ReadLines($LogPath)) {
        if ($eventNeedle -and $line.Contains($eventNeedle)) { return $true }
        if ($upnNeedle -and $line.Contains($upnNeedle) -and $line.Contains('"Stage":"AdminSent"')) { return $true }
    }

    return $false
}

function Protect-AuditDetail {
    [CmdletBinding()]
    param([string]$Detail)
    if (-not $Detail) { return $Detail }
    $redacted = $Detail `
        -replace '(?i)(temporary\s*(access\s*)?pass(word)?|secret|tap|cred(ential)?s?)\s*[:=]\s*\S+', '$1=[REDACTED]' `
        -replace '(?i)\b[A-Za-z0-9-_]{32,}\b', '[REDACTED-TOKEN]'
    return $redacted
}

function Write-AuditLog {
    param(
        [string]$EventId,
        [string]$UserPrincipalName,
        [string]$Stage,
        [string]$Status,
        [string]$Detail,
        [string]$LogPath
    )
    $entry = [ordered]@{
        Timestamp         = (Get-Date).ToUniversalTime().ToString('o')
        EventId           = $EventId
        UserPrincipalName = $UserPrincipalName
        Stage             = $Stage
        Status            = $Status
        Detail            = (Protect-AuditDetail -Detail $Detail)
    } | ConvertTo-Json -Compress

    $dir = Split-Path $LogPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -Path $LogPath -Value $entry
}

function Get-DeferredWelcomeEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath
    )
    if (-not (Test-Path $LogPath)) { return @() }

    $lines = Get-Content $LogPath

    # Group everything by UPN so we can reason per-user
    $byUpn = @{}
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $obj = $line | ConvertFrom-Json } catch { continue }
        if (-not $obj.UserPrincipalName) { continue }
        if (-not $byUpn.ContainsKey($obj.UserPrincipalName)) { $byUpn[$obj.UserPrincipalName] = @() }
        $byUpn[$obj.UserPrincipalName] += $obj
    }

    $deferred = @()
    foreach ($upn in $byUpn.Keys) {
        $entries = $byUpn[$upn]

        # Find the last WelcomeSent entry for this UPN
        $lastWelcome = $null
        foreach ($e in $entries) {
            if ($e.Stage -eq 'WelcomeSent') { $lastWelcome = $e }
        }
        if (-not $lastWelcome) { continue }
        if ($lastWelcome.Status -ne 'Deferred') { continue }

        # If the admin was notified, use the admin's EventId for the retry
        # (otherwise fall back to the deferred line's own EventId)
        $adminEntry = $null
        foreach ($e in $entries) {
            if ($e.Stage -eq 'AdminSent') { $adminEntry = $e; break }
        }
        $eventIdToUse = if ($adminEntry -and $adminEntry.EventId) { $adminEntry.EventId } else { $lastWelcome.EventId }

        $deferred += [pscustomobject]@{
            EventId           = $eventIdToUse
            UserPrincipalName = $upn
        }
    }
    return $deferred
}

function Invoke-AuditRetention {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [int]$RetentionDays = 90
    )
    if ($RetentionDays -le 0 -or -not (Test-Path $LogPath)) { return 0 }
    $cutoff = (Get-Date).ToUniversalTime().AddDays(-$RetentionDays)
    $kept = @()
    $removed = 0
    foreach ($line in [System.IO.File]::ReadLines($LogPath)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $obj = $line | ConvertFrom-Json } catch { $kept += $line; continue }
        try { $ts = [datetime]$obj.Timestamp } catch { $kept += $line; continue }
        if ($ts.ToUniversalTime() -lt $cutoff) { $removed++ } else { $kept += $line }
    }
    if ($removed -gt 0) {
        $tmp = "$LogPath.tmp"
        $kept | Set-Content -Path $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $LogPath -Force
    }
    return $removed
}