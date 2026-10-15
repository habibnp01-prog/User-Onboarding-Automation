function ConvertFrom-JsonToHashtable {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Json)

    $obj = $Json | ConvertFrom-Json

    function ConvertTo-Hashtable {
        param($InputObject)
        if ($null -eq $InputObject) { return $null }
        if ($InputObject -is [System.Collections.IEnumerable] -and
            $InputObject -isnot [string]) {
            $list = @()
            foreach ($item in $InputObject) {
                $list += ,(ConvertTo-Hashtable -InputObject $item)
            }
            return ,$list
        }
        if ($InputObject -is [psobject] -and $InputObject.PSObject.Properties.Count -gt 0 -and
            $InputObject -isnot [string] -and
            $InputObject -isnot [int] -and $InputObject -isnot [long] -and
            $InputObject -isnot [double] -and $InputObject -isnot [bool] -and
            $InputObject -isnot [datetime]) {
            $ht = @{}
            foreach ($p in $InputObject.PSObject.Properties) {
                $ht[$p.Name] = ConvertTo-Hashtable -InputObject $p.Value
            }
            return $ht
        }
        return $InputObject
    }

    return ConvertTo-Hashtable -InputObject $obj
}