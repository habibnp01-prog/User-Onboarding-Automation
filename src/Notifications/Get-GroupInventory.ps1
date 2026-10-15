function Get-GroupInventory {
    [CmdletBinding()]
    param(
        [ValidateSet('All','Security','M365','Distribution','MailEnabled','Assigned')]
        [string]$Type = 'All',

        [string]$Search,

        [switch]$ExcludeOnPremSynced
    )

    $groups = Get-MgGroup -All -Property `
        Id,DisplayName,Description,GroupTypes,SecurityEnabled,MailEnabled,OnPremisesSyncEnabled,MembershipRule

    $result = foreach ($g in $groups) {

        if ($ExcludeOnPremSynced -and $g.OnPremisesSyncEnabled) { continue }

        # Classify
        $kind = 'Unknown'
        if ($g.GroupTypes -contains 'Unified') {
            $kind = 'M365'
        } elseif ($g.GroupTypes -contains 'DynamicMembership') {
            $kind = 'Dynamic'
        } elseif ($g.SecurityEnabled -and -not $g.MailEnabled) {
            $kind = 'Security'
        } elseif ($g.SecurityEnabled -and $g.MailEnabled) {
            $kind = 'MailEnabled'
        } elseif (-not $g.SecurityEnabled -and $g.MailEnabled) {
            $kind = 'Distribution'
        }

        # Apply type filter
        if ($Type -ne 'All') {
            switch ($Type) {
                'Security'     { if ($kind -notin 'Security','MailEnabled') { continue } }
                'M365'         { if ($kind -ne 'M365') { continue } }
                'Distribution' { if ($kind -ne 'Distribution') { continue } }
                'MailEnabled'  { if ($kind -notin 'MailEnabled','Distribution') { continue } }
                'Assigned'     { if ($g.GroupTypes -contains 'DynamicMembership') { continue } }
            }
        }

        # Apply search
        if ($Search) {
            if ($g.DisplayName -notlike "*$Search*") { continue }
        }

        [pscustomobject]@{
            Id             = $g.Id
            DisplayName    = $g.DisplayName
            Type           = $kind
            SecurityEnabled= $g.SecurityEnabled
            MailEnabled    = $g.MailEnabled
            IsOnPremSynced = [bool]$g.OnPremisesSyncEnabled
            IsDynamic      = ($g.GroupTypes -contains 'DynamicMembership')
            Description    = $g.Description
            MembershipRule = $g.MembershipRule
        }
    }

    $result | Sort-Object -Property Type, DisplayName
}