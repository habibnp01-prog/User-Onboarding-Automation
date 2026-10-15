function Get-LicenseInventory {
    [CmdletBinding()]
    param(
        [switch]$IncludeFriendlyNames,
        [switch]$ExcludeTrials
    )

    # Friendly-name mapping for common SKUs
    $friendly = @{
        'ENTERPRISEPACK'              = 'Microsoft 365 E3'
        'ENTERPRISEPREMIUM'           = 'Microsoft 365 E5'
        'SPE_E3'                      = 'Microsoft 365 E3 (no Teams)'
        'SPE_E5'                      = 'Microsoft 365 E5 (no Teams)'
        'EMS'                         = 'Enterprise Mobility + Security E3'
        'EMSPREMIUM'                  = 'Enterprise Mobility + Security E5'
        'AAD_PREMIUM'                 = 'Entra ID P1'
        'AAD_PREMIUM_P2'              = 'Entra ID P2'
        'EXCHANGESTANDARD'            = 'Exchange Online (Plan 1)'
        'EXCHANGEENTERPRISE'          = 'Exchange Online (Plan 2)'
        'O365_BUSINESS_ESSENTIALS'    = 'Microsoft 365 Business Basic'
        'O365_BUSINESS_PREMIUM'       = 'Microsoft 365 Business Standard'
        'SMB_BUSINESS_PREMIUM'        = 'Microsoft 365 Business Premium'
        'POWER_BI_PRO'                = 'Power BI Pro'
        'FLOW_FREE'                   = 'Power Automate Free'
        'POWERAPPS_VIRAL'             = 'Power Apps per user'
        'TEAMS_EXPLORATORY'           = 'Microsoft Teams Exploratory'
        'PROJECTPROFESSIONAL'         = 'Project Plan 3'
        'VISIOCLIENT'                 = 'Visio Plan 2'
        'DEVELOPERPACK_E5'            = 'Microsoft 365 Developer E5'
        'Microsoft_Intune_Plan_2'     = 'Intune Plan 2'
        'Microsoft_Intune_Suite'      = 'Intune Suite'
        'Remote_Help_AddOn'           = 'Remote Help Add-On'
    }

    $skus = Get-MgSubscribedSku

    $result = foreach ($sku in $skus) {
        $enabled   = 0
        $suspended = 0
        $warning   = 0
        if ($sku.PrepaidUnits) {
            $enabled   = [int]$sku.PrepaidUnits.Enabled
            $suspended = [int]$sku.PrepaidUnits.Suspended
            $warning   = [int]$sku.PrepaidUnits.Warning
        }
        $consumed  = [int]$sku.ConsumedUnits
        $available = $enabled - $consumed

        $name = $sku.SkuPartNumber
        if ($IncludeFriendlyNames -and $friendly.ContainsKey($sku.SkuPartNumber)) {
            $name = "$($friendly[$sku.SkuPartNumber]) ($($sku.SkuPartNumber))"
        }

        [pscustomobject]@{
            SkuId          = $sku.SkuId
            SkuPartNumber  = $sku.SkuPartNumber
            DisplayName    = $name
            Enabled        = $enabled
            Consumed       = $consumed
            Available      = $available
            Suspended      = $suspended
            Warning        = $warning
            ServicePlans   = $sku.ServicePlans
            AppliesTo      = $sku.AppliesTo
        }
    }

    # Filter out trial / zero-seat / non-user-facing SKUs
    if ($ExcludeTrials) {
        $result = $result | Where-Object {
            $_.Available -gt 0 -and
            $_.SkuPartNumber -notmatch 'TRIAL|_vTrial|Free|TVM_|Remote_Help_AddOn|Power_Virtual'
        }
    }

    # Sort by available descending, then by name
    $result | Sort-Object -Property @{Expression='Available';Descending=$true}, DisplayName
}