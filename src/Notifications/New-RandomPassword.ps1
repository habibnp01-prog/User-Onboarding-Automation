function New-RandomPassword {
    [CmdletBinding()]
    param(
        [int]$Length = 16,
        [switch]$NoSymbols
    )

    if ($Length -lt 12) {
        throw 'Password length must be at least 12 for Entra ID default policy.'
    }

    # Character pools chosen to satisfy default Entra password policy.
    # Exclude ambiguous chars (0/O, 1/l/I) to reduce transcription errors.
    $lower  = 'abcdefghijkmnpqrstuvwxyz'.ToCharArray()
    $upper  = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()
    $digit  = '23456789'.ToCharArray()
    $symbol = '@#$%^&*!?-_'.ToCharArray()

    $all = @($lower + $upper + $digit)
    if (-not $NoSymbols) { $all += $symbol }

    # Guarantee at least one of each required character class
    $chars = @(
        ($lower | Get-Random)
        ($upper | Get-Random)
        ($digit | Get-Random)
    )
    if (-not $NoSymbols) { $chars += ($symbol | Get-Random) }

    while ($chars.Count -lt $Length) {
        $chars += ($all | Get-Random)
    }

    # Shuffle using Fisher-Yates to preserve randomness after the required-class insertions
    for ($i = $chars.Count - 1; $i -gt 0; $i--) {
        $j = Get-Random -Minimum 0 -Maximum ($i + 1)
        $tmp = $chars[$i]
        $chars[$i] = $chars[$j]
        $chars[$j] = $tmp
    }

    return -join $chars
}