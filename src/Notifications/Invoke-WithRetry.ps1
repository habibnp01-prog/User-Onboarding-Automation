function Invoke-WithRetry {
    param(
        [scriptblock]$Action,
        [int]$MaxAttempts = 5,
        [int]$InitialDelaySeconds = 15,
        [int]$MaxDelaySeconds = 300,
        [switch]$NoJitter
    )
    $nonRetryable = '(?i)\b(400|401|403|404|BadRequest|Unauthorized|Forbidden|NotFound|InvalidRequest|ErrorSendAsDenied|accessDenied)\b'
    $attempt = 0
    while ($true) {
        $attempt++
        try { return & $Action }
        catch {
            $msg = $_.Exception.Message
            if ($attempt -ge $MaxAttempts) { throw }
            if ($msg -match $nonRetryable) { throw }
            $delay = [Math]::Min($InitialDelaySeconds * [Math]::Pow(2, $attempt - 1), $MaxDelaySeconds)
            # Honor Retry-After header when the Graph SDK surfaces it
            $retryAfter = $null
            try {
                $resp = $_.Exception.Response
                if ($resp -and $resp.Headers -and $resp.Headers['Retry-After']) {
                    $retryAfter = [int]$resp.Headers['Retry-After']
                }
            } catch { }
            if ($retryAfter -and $retryAfter -gt 0) {
                $delay = [Math]::Min($retryAfter, $MaxDelaySeconds)
            } elseif (-not $NoJitter -and $delay -gt 0) {
                $jitter = Get-Random -Minimum (-0.2 * $delay) -Maximum (0.2 * $delay)
                $delay = [Math]::Max(0, [int]($delay + $jitter))
            }
            if ($delay -gt 0) { Start-Sleep -Seconds $delay }
        }
    }
}
