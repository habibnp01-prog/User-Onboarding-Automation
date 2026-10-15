function Get-CycleWatermark {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [int]$LookbackMinutes = 15,
        [int]$OverlapMinutes = 5
    )
    $now = (Get-Date).ToUniversalTime()
    $defaultSince = $now.AddMinutes(-$LookbackMinutes).ToLocalTime()
    $wmPath = "$LogPath.watermark.txt"
    if (-not (Test-Path $wmPath)) { return $defaultSince }
    try {
        $raw = (Get-Content $wmPath -Raw).Trim()
        $wm = [datetime]$raw
        $wmSince = $wm.ToUniversalTime().AddMinutes(-$OverlapMinutes).ToLocalTime()
        if ($wmSince -lt $defaultSince) { return $wmSince }
        return $defaultSince
    } catch { return $defaultSince }
}

function Set-CycleWatermark {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LogPath)
    $wmPath = "$LogPath.watermark.txt"
    $dir = Split-Path $wmPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    (Get-Date).ToUniversalTime().ToString('o') | Set-Content -Path $wmPath -Encoding UTF8
}

function Get-NewUserEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][datetime]$Since
    )
    if ($Config.Monitoring.Mode -eq 'Polling') {
        return Get-NewUserEventsByPolling -Config $Config -Since $Since
    }
    return Get-NewUserEventsByChangeNotification -Config $Config -Since $Since
}

function Get-NewUserEventsByPolling {
    param([hashtable]$Config, [datetime]$Since)

    $filter = "createdDateTime ge $($Since.ToUniversalTime().ToString('o'))"
    $users  = Get-NewUserFromGraph -Filter $filter

    foreach ($u in $users) {
        [pscustomobject]@{
            EventId           = "poll-$($u.Id)-$($u.CreatedDateTime.ToString('yyyyMMddHHmmss'))"
            UserId            = $u.Id
            DisplayName       = $u.DisplayName
            UserPrincipalName = $u.UserPrincipalName
            Mail              = $u.Mail
            Department        = $u.Department
            JobTitle          = $u.JobTitle
            CreatedDateTime   = $u.CreatedDateTime
            UserType          = $u.UserType
            IsHybridSynced    = [bool]$u.OnPremisesSyncEnabled
            Source            = 'Polling'
        }
    }
}

function Get-NewUserEventsByChangeNotification {
    param([hashtable]$Config, [datetime]$Since)
    throw 'Graph change notifications not yet wired. Use Monitoring.Mode = Polling.'
}
