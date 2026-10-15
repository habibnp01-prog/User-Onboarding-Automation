function Escape-HtmlText {
    [CmdletBinding()]
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode("$Value")
}

function Escape-ODataStringLiteral {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Value)
    return ($Value -replace "'", "''")
}

function New-GraphFilterById {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    return "id eq '$(Escape-ODataStringLiteral -Value $Id)'"
}

function New-GraphFilterByUPN {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$UserPrincipalName)
    return "userPrincipalName eq '$(Escape-ODataStringLiteral -Value $UserPrincipalName)'"
}

function Get-NewUserFromGraph {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Filter)
    Get-MgUser -Filter $Filter -All `
        -Property Id,DisplayName,UserPrincipalName,Mail,Department,JobTitle,CreatedDateTime,UserType,OnPremisesSyncEnabled
}

function Send-MgMail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$UserId,
        [Parameter(Mandatory)][hashtable]$BodyParameter
    )
    Send-MgUserMail -UserId $UserId -BodyParameter $BodyParameter
}
