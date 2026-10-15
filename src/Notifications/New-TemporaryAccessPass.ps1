function New-TemporaryAccessPass {
    <#
    .SYNOPSIS
        Creates a Temporary Access Pass (TAP) for a Microsoft Entra ID user.
    .DESCRIPTION
        TAPs are time-limited passcodes used in place of a password during first-time
        sign-in. The user signs in with the TAP, registers MFA, and sets a permanent
        password. The pass becomes invalid after first successful sign-in (if
        IsUsableOnce is set) or when it expires.

        Requires Entra ID P1/P2 license on the target user. Requires the
        UserAuthenticationMethod.ReadWrite.All Graph scope for the app.

        The valid lifetime range is determined by the tenant's Temporary Access Pass
        authentication method policy. Common ranges are 60-480 minutes (8 hours).
        Check with a Global Admin if you get a badRequest error about lifetime.
    .PARAMETER UserId
        UPN or object ID of the target user.
    .PARAMETER LifetimeMinutes
        Minutes the pass remains valid. Default: 480 (8 hours).
        Must be within the tenant's TAP policy maximum.
    .PARAMETER IsUsableOnce
        If set, the pass becomes invalid after first successful sign-in. Default: true.
    .PARAMETER StartDateTime
        Optional start time (UTC). Default: now.
    .OUTPUTS
        PSCustomObject with TemporaryAccessPass, ExpiresAt, LifetimeMinutes, IsUsableOnce.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$UserId,
        [int]$LifetimeMinutes = 480,
        [bool]$IsUsableOnce = $true,
        [datetime]$StartDateTime
    )

    if ($LifetimeMinutes -lt 10 -or $LifetimeMinutes -gt 43200) {
        throw "LifetimeMinutes must be between 10 and 43200 (30 days). Got: $LifetimeMinutes"
    }

    $body = @{
        lifetimeInMinutes = $LifetimeMinutes
        isUsableOnce      = $IsUsableOnce
    }
    if ($StartDateTime) {
        $body.startDateTime = $StartDateTime.ToUniversalTime().ToString('o')
    }

    try {
        $tap = New-MgUserAuthenticationTemporaryAccessPassMethod `
            -UserId $UserId `
            -BodyParameter $body `
            -ErrorAction Stop
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match 'Invalid LifetimeInMinutes|valid range') {
            $range = ''
            if ($msg -match 'between\s+(\d+)\s+and\s+(\d+)') {
                $range = " Your tenant's TAP policy allows $($matches[1]) to $($matches[2]) minutes."
            }
            throw "TAP creation failed - the requested lifetime of $LifetimeMinutes minutes is outside the tenant's allowed range.$range Adjust TemporaryAccessPass.LifetimeMinutes in config.json to fit within the policy. Original error: $msg"
        }
        if ($msg -match 'Authentication method policy|policy does not allow') {
            throw "TAP creation failed - the tenant's Temporary Access Pass authentication method policy may be disabled. Ask a Global Admin to check Entra - Protection - Authentication methods - Temporary Access Pass. Original error: $msg"
        }
        if ($msg -match 'license|Premium|P1|P2') {
            throw "TAP creation failed - the target user likely needs an Entra ID P1 or P2 license. Original error: $msg"
        }
        throw "TAP creation failed: $msg"
    }

    if (-not $tap -or -not $tap.TemporaryAccessPass) {
        throw 'TAP creation returned no passcode. Check the tenant TAP policy.'
    }

    $expires = if ($tap.PSObject.Properties['TemporaryAccessPassExpiresAt'] -and $tap.TemporaryAccessPassExpiresAt) {
        $tap.TemporaryAccessPassExpiresAt
    } else {
        (Get-Date).ToUniversalTime().AddMinutes($LifetimeMinutes)
    }

    return [pscustomobject]@{
        TemporaryAccessPass = $tap.TemporaryAccessPass
        ExpiresAt           = $expires
        LifetimeMinutes     = $LifetimeMinutes
        IsUsableOnce        = $IsUsableOnce
        MethodId            = $tap.Id
    }
}