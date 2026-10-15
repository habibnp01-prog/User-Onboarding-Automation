<#
.SYNOPSIS
    WinForms wizard for onboarding a new Microsoft 365 user.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigPath
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

function ConvertTo-ConfigHashtable {
    param($o)
    if ($o -is [System.Collections.IEnumerable] -and $o -isnot [string]) {
        @($o | ForEach-Object { ConvertTo-ConfigHashtable $_ })
    } elseif ($o -is [psobject] -and $o.PSObject.Properties.Count -gt 0 -and
              $o -isnot [string] -and $o -isnot [int] -and $o -isnot [long] -and
              $o -isnot [double] -and $o -isnot [bool] -and $o -isnot [datetime]) {
        $h = @{}
        $o.PSObject.Properties | ForEach-Object { $h[$_.Name] = ConvertTo-ConfigHashtable $_.Value }
        $h
    } else { $o }
}

function Measure-PasswordStrength {
    [CmdletBinding()]
    param([string]$Password)
    $result = [ordered]@{
        Length = if ($Password) { $Password.Length } else { 0 }
        HasLower = $false; HasUpper = $false; HasDigit = $false; HasSymbol = $false
        ClassesCount = 0; Label = 'Empty'; Color = 'Red'
        MeetsEntraBase = $false; MeetsWizardMin = $false
    }
    if (-not $Password) { return [pscustomobject]$result }
    $result.HasLower  = [bool]($Password -cmatch '[a-z]')
    $result.HasUpper  = [bool]($Password -cmatch '[A-Z]')
    $result.HasDigit  = [bool]($Password -match '[0-9]')
    $result.HasSymbol = [bool]($Password -match '[^A-Za-z0-9]')
    $classes = 0
    foreach ($f in @($result.HasLower,$result.HasUpper,$result.HasDigit,$result.HasSymbol)) { if ($f) { $classes++ } }
    $result.ClassesCount = $classes
    $result.MeetsWizardMin = ($Password.Length -ge 12)
    $result.MeetsEntraBase = ($Password.Length -ge 8 -and $classes -ge 3)
    if ($Password.Length -lt 8)                            { $result.Label='Too short'; $result.Color='Red' }
    elseif (-not $result.MeetsEntraBase)                   { $result.Label='Weak (fails Entra policy)'; $result.Color='Red' }
    elseif ($Password.Length -lt 12)                       { $result.Label='Acceptable (Entra OK, wizard wants 12+)'; $result.Color='Orange' }
    elseif ($classes -ge 4 -and $Password.Length -ge 14)   { $result.Label='Strong'; $result.Color='Green' }
    elseif ($classes -ge 3 -and $Password.Length -ge 12)   { $result.Label='Good'; $result.Color='Green' }
    else                                                    { $result.Label='Weak'; $result.Color='Orange' }
    return [pscustomobject]$result
}

$repoConfig   = ConvertTo-ConfigHashtable (Get-Content $ConfigPath -Raw | ConvertFrom-Json)
$userSettings = Read-UserSettings
$config       = Merge-Configs -RepoConfig $repoConfig -UserSettings $userSettings

$welcomeTemplatePath = ''
if ($config.WelcomeTemplatePath) {
    $candidate = $config.WelcomeTemplatePath
    if (-not [System.IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path (Split-Path $ConfigPath -Parent) ('..\' + $candidate)
    }
    $resolved = Resolve-Path $candidate -ErrorAction SilentlyContinue
    if ($resolved) { $welcomeTemplatePath = $resolved.Path }
}

$domainObjects = try {
    @(Get-MgDomain | Where-Object { $_.IsVerified -and $_.SupportedServices -contains 'Email' } |
        Select-Object Id, IsDefault, IsInitial)
} catch { @() }
if (-not $domainObjects -or $domainObjects.Count -eq 0) {
    $domainObjects = @([pscustomobject]@{ Id='contoso.com'; IsDefault=$true; IsInitial=$true })
}
$domainObjects = $domainObjects | Sort-Object `
    @{Expression={ if ($_.IsDefault) { 0 } elseif ($_.Id -like '*.onmicrosoft.com') { 2 } else { 1 } }}, Id

$licenses  = try { @(Get-LicenseInventory -IncludeFriendlyNames -ExcludeTrials) } catch { @() }
$allGroups = try { @(Get-GroupInventory -ExcludeOnPremSynced) } catch { @() }
$usageLocations = @('NP','US','GB','IN','AU','CA','DE','FR','JP','SG','AE','NL','SE','CH','IT','ES','BR','MX','ZA')

$form = New-Object System.Windows.Forms.Form
$form.Text = 'New User Onboarding - Microsoft 365'
$form.Size = New-Object System.Drawing.Size -ArgumentList 780, 720
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point -ArgumentList 15, 15
$tabs.Size = New-Object System.Drawing.Size -ArgumentList 740, 600
$form.Controls.Add($tabs)

function New-Label {
    param($Parent, [string]$Text, [int]$Top, [int]$Left = 15, [int]$Width = 160)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.Location = New-Object System.Drawing.Point -ArgumentList $Left, $Top
    $lbl.Size = New-Object System.Drawing.Size -ArgumentList $Width, 22
    $Parent.Controls.Add($lbl)
    return $lbl
}
function New-Text {
    param($Parent, [int]$Left, [int]$Top, [int]$Width, [string]$Text = '')
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point -ArgumentList $Left, $Top
    $tb.Size = New-Object System.Drawing.Size -ArgumentList $Width, 22
    $tb.Text = $Text
    $Parent.Controls.Add($tb)
    return $tb
}

# ---------------- Account tab ----------------
$tabAccount = New-Object System.Windows.Forms.TabPage
$tabAccount.Text = 'Account'
$tabAccount.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 15
$tabs.TabPages.Add($tabAccount)

$y = 20
New-Label $tabAccount 'Display name *' $y | Out-Null
$txtDisplayName = New-Text $tabAccount 185 $y 500 ''
$y += 35
New-Label $tabAccount 'First name' $y | Out-Null
$txtGivenName = New-Text $tabAccount 185 $y 220 ''
$y += 35
New-Label $tabAccount 'Last name' $y | Out-Null
$txtSurname = New-Text $tabAccount 185 $y 220 ''
$y += 35
New-Label $tabAccount 'UPN local part *' $y | Out-Null
$txtUpnPrefix = New-Text $tabAccount 185 $y 220 ''
$lblAt = New-Object System.Windows.Forms.Label
$lblAt.Text = '@'
$lblAt.Location = New-Object System.Drawing.Point -ArgumentList 415, $y
$lblAt.Size = New-Object System.Drawing.Size -ArgumentList 20, 22
$tabAccount.Controls.Add($lblAt)
$cmbDomain = New-Object System.Windows.Forms.ComboBox
$cmbDomain.Location = New-Object System.Drawing.Point -ArgumentList 440, $y
$cmbDomain.Size = New-Object System.Drawing.Size -ArgumentList 245, 22
$cmbDomain.DropDownStyle = 'DropDownList'
foreach ($d in $domainObjects) {
    $label = $d.Id
    if ($d.IsDefault) { $label += '   (default)' }
    elseif ($d.Id -like '*.onmicrosoft.com') { $label += '   (tenant root)' }
    [void]$cmbDomain.Items.Add($label)
}
$defaultIdx = 0
for ($i = 0; $i -lt $domainObjects.Count; $i++) { if ($domainObjects[$i].IsDefault) { $defaultIdx = $i; break } }
if ($cmbDomain.Items.Count -gt 0) { $cmbDomain.SelectedIndex = $defaultIdx }
$tabAccount.Controls.Add($cmbDomain)
$y += 35
New-Label $tabAccount 'Mail nickname *' $y | Out-Null
$txtMailNickname = New-Text $tabAccount 185 $y 220 ''
$y += 35

New-Label $tabAccount 'Password *' $y | Out-Null
$txtPassword = New-Text $tabAccount 185 $y 320 (New-RandomPassword)
$txtPassword.UseSystemPasswordChar = $true
$chkShowPwd = New-Object System.Windows.Forms.CheckBox
$chkShowPwd.Text = 'Show'
$chkShowPwd.Location = New-Object System.Drawing.Point -ArgumentList 515, $y
$chkShowPwd.Size = New-Object System.Drawing.Size -ArgumentList 60, 24
$chkShowPwd.Add_CheckedChanged({ $txtPassword.UseSystemPasswordChar = -not $chkShowPwd.Checked })
$tabAccount.Controls.Add($chkShowPwd)
$btnRegenPwd = New-Object System.Windows.Forms.Button
$btnRegenPwd.Text = 'Regenerate'
$btnRegenPwd.Location = New-Object System.Drawing.Point -ArgumentList 575, $y
$btnRegenPwd.Size = New-Object System.Drawing.Size -ArgumentList 90, 24
$btnRegenPwd.Add_Click({ $txtPassword.Text = New-RandomPassword; $txtPassword.UseSystemPasswordChar = -not $chkShowPwd.Checked })
$tabAccount.Controls.Add($btnRegenPwd)
$y += 30

$lblStrength = New-Object System.Windows.Forms.Label
$lblStrength.Location = New-Object System.Drawing.Point -ArgumentList 185, $y
$lblStrength.Size = New-Object System.Drawing.Size -ArgumentList 500, 20
$tabAccount.Controls.Add($lblStrength)
$y += 25

function Update-StrengthLabel {
    $s = Measure-PasswordStrength -Password $txtPassword.Text
    $color = switch ($s.Color) {
        'Green'  { [System.Drawing.Color]::ForestGreen }
        'Orange' { [System.Drawing.Color]::DarkOrange }
        'Red'    { [System.Drawing.Color]::Firebrick }
        default  { [System.Drawing.Color]::Gray }
    }
    $lblStrength.ForeColor = $color
    $lblStrength.Text = "Strength: $($s.Label)   (length=$($s.Length), classes=$($s.ClassesCount)/4)"
}
$txtPassword.Add_TextChanged({ Update-StrengthLabel })
Update-StrengthLabel

$chkForceChange = New-Object System.Windows.Forms.CheckBox
$chkForceChange.Text = 'Require password change at first sign-in'
$chkForceChange.Location = New-Object System.Drawing.Point -ArgumentList 185, $y
$chkForceChange.Size = New-Object System.Drawing.Size -ArgumentList 500, 22
$chkForceChange.Checked = $true
$tabAccount.Controls.Add($chkForceChange)

$txtGivenName.Add_TextChanged({
    $g = $txtGivenName.Text.Trim(); $s = $txtSurname.Text.Trim()
    $c = ($g + ' ' + $s).Trim()
    if ($c) { $txtDisplayName.Text = $c }
    if ($g -and $s) { $txtMailNickname.Text = ($g.ToLower() + '.' + $s.ToLower()) }
})
$txtSurname.Add_TextChanged({
    $g = $txtGivenName.Text.Trim(); $s = $txtSurname.Text.Trim()
    $c = ($g + ' ' + $s).Trim()
    if ($c) { $txtDisplayName.Text = $c }
    if ($g -and $s) { $txtMailNickname.Text = ($g.ToLower() + '.' + $s.ToLower()) }
})
$txtUpnPrefix.Add_TextChanged({
    if (-not $txtMailNickname.Text -and $txtUpnPrefix.Text) { $txtMailNickname.Text = $txtUpnPrefix.Text }
})

# ---------------- Profile tab ----------------
$tabProfile = New-Object System.Windows.Forms.TabPage
$tabProfile.Text = 'Profile'
$tabProfile.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 15
$tabs.TabPages.Add($tabProfile)

$y = 20
New-Label $tabProfile 'Job title' $y | Out-Null
$txtJobTitle = New-Text $tabProfile 185 $y 500 ''
$y += 35
New-Label $tabProfile 'Department' $y | Out-Null
$txtDepartment = New-Text $tabProfile 185 $y 500 ''
$y += 35
New-Label $tabProfile 'Phone' $y | Out-Null
$txtPhone = New-Text $tabProfile 185 $y 220 ''
$y += 35
New-Label $tabProfile 'Office location' $y | Out-Null
$txtOffice = New-Text $tabProfile 185 $y 220 ''
$y += 35
New-Label $tabProfile 'Employee ID' $y | Out-Null
$txtEmployeeId = New-Text $tabProfile 185 $y 220 ''
$y += 35
New-Label $tabProfile 'Usage location *' $y | Out-Null
$cmbUsage = New-Object System.Windows.Forms.ComboBox
$cmbUsage.Location = New-Object System.Drawing.Point -ArgumentList 185, $y
$cmbUsage.Size = New-Object System.Drawing.Size -ArgumentList 120, 22
$cmbUsage.DropDownStyle = 'DropDownList'
$usageLocations | ForEach-Object { [void]$cmbUsage.Items.Add($_) }
$cmbUsage.SelectedItem = 'NP'
$tabProfile.Controls.Add($cmbUsage)
$y += 35
New-Label $tabProfile 'Manager UPN' $y | Out-Null
$txtManager = New-Text $tabProfile 185 $y 500 ''
$y += 40
New-Label $tabProfile 'Personal email' $y | Out-Null
$txtPersonalEmail = New-Text $tabProfile 185 $y 300 ''
$lblPersonalHint = New-Object System.Windows.Forms.Label
$lblPersonalHint.Text = '(used for welcome email + password reset)'
$lblPersonalHint.Location = New-Object System.Drawing.Point -ArgumentList 495, $y
$lblPersonalHint.Size = New-Object System.Drawing.Size -ArgumentList 280, 22
$lblPersonalHint.ForeColor = [System.Drawing.Color]::Gray
$tabProfile.Controls.Add($lblPersonalHint)
$y += 40

New-Label $tabProfile 'Credentials recipient' $y | Out-Null
$txtCredentialsRecipient = New-Text $tabProfile 185 $y 300 ''
$lblCredHint = New-Object System.Windows.Forms.Label
$lblCredHint.Text = '(where to send username + pass/TAP separately)'
$lblCredHint.Location = New-Object System.Drawing.Point -ArgumentList 495, $y
$lblCredHint.Size = New-Object System.Drawing.Size -ArgumentList 280, 22
$lblCredHint.ForeColor = [System.Drawing.Color]::Gray
$tabProfile.Controls.Add($lblCredHint)

# ---------------- License tab ----------------
$tabLicense = New-Object System.Windows.Forms.TabPage
$tabLicense.Text = 'License'
$tabLicense.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 15
$tabs.TabPages.Add($tabLicense)

$y = 20
New-Label $tabLicense 'Assign license(s)' $y 15 200 | Out-Null
$y += 25
$chkLicenseList = New-Object System.Windows.Forms.CheckedListBox
$chkLicenseList.Location = New-Object System.Drawing.Point -ArgumentList 15, $y
$chkLicenseList.Size = New-Object System.Drawing.Size -ArgumentList 690, 420
$chkLicenseList.CheckOnClick = $true
$tabLicense.Controls.Add($chkLicenseList)
foreach ($l in $licenses) {
    $label = "$($l.DisplayName)  -  $($l.Available) available"
    [void]$chkLicenseList.Items.Add($label, $false)
}

# ---------------- Groups tab ----------------
$tabGroups = New-Object System.Windows.Forms.TabPage
$tabGroups.Text = 'Groups'
$tabGroups.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 15
$tabs.TabPages.Add($tabGroups)

$y = 20
New-Label $tabGroups 'Filter type' $y | Out-Null
$cmbGroupType = New-Object System.Windows.Forms.ComboBox
$cmbGroupType.Location = New-Object System.Drawing.Point -ArgumentList 185, $y
$cmbGroupType.Size = New-Object System.Drawing.Size -ArgumentList 140, 22
$cmbGroupType.DropDownStyle = 'DropDownList'
@('All','Security','M365','Distribution') | ForEach-Object { [void]$cmbGroupType.Items.Add($_) }
$cmbGroupType.SelectedIndex = 0
$tabGroups.Controls.Add($cmbGroupType)
$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Text = 'Search'
$lblSearch.Location = New-Object System.Drawing.Point -ArgumentList 340, $y
$lblSearch.Size = New-Object System.Drawing.Size -ArgumentList 50, 22
$tabGroups.Controls.Add($lblSearch)
$txtGroupSearch = New-Object System.Windows.Forms.TextBox
$txtGroupSearch.Location = New-Object System.Drawing.Point -ArgumentList 395, $y
$txtGroupSearch.Size = New-Object System.Drawing.Size -ArgumentList 310, 22
$tabGroups.Controls.Add($txtGroupSearch)
$y += 35
$chkGroupList = New-Object System.Windows.Forms.CheckedListBox
$chkGroupList.Location = New-Object System.Drawing.Point -ArgumentList 15, $y
$chkGroupList.Size = New-Object System.Drawing.Size -ArgumentList 690, 460
$chkGroupList.CheckOnClick = $true
$tabGroups.Controls.Add($chkGroupList)

$script:groupListCurrent = @()
function Refresh-GroupList {
    $chkGroupList.Items.Clear()
    $type = $cmbGroupType.SelectedItem
    $search = $txtGroupSearch.Text
    $list = $allGroups
    if ($type -and $type -ne 'All') { $list = $list | Where-Object { $_.Type -eq $type } }
    if ($search) { $list = $list | Where-Object { $_.DisplayName -like "*$search*" } }
    $script:groupListCurrent = @($list)
    foreach ($g in $script:groupListCurrent) {
        $display = $g.DisplayName
        if ($g.IsDynamic) { $display += '  (dynamic - cannot add manually)' }
        [void]$chkGroupList.Items.Add($display, $false)
    }
}
$cmbGroupType.Add_SelectedIndexChanged({ Refresh-GroupList })
$txtGroupSearch.Add_TextChanged({ Refresh-GroupList })
Refresh-GroupList

# ---------------- Welcome Message tab ----------------
$tabWelcome = New-Object System.Windows.Forms.TabPage
$tabWelcome.Text = 'Welcome Message'
$tabWelcome.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 15
$tabs.TabPages.Add($tabWelcome)

$y = 15
$lblWelcomeHelp = New-Object System.Windows.Forms.Label
$lblWelcomeHelp.Text = 'Edit the shared welcome template. Changes save back to templates\welcome-email.html.'
$lblWelcomeHelp.Location = New-Object System.Drawing.Point -ArgumentList 15, $y
$lblWelcomeHelp.Size = New-Object System.Drawing.Size -ArgumentList 700, 20
$lblWelcomeHelp.ForeColor = [System.Drawing.Color]::DimGray
$tabWelcome.Controls.Add($lblWelcomeHelp)
$y += 25

$lblPlaceholders = New-Object System.Windows.Forms.Label
$lblPlaceholders.Text = 'Placeholders: {{DisplayName}} {{UPN}} {{Mail}} {{Department}} {{JobTitle}} {{Phone}} {{Office}} {{EmployeeId}} {{Manager}} {{Org}} {{Support}} {{LoginUrl}}'
$lblPlaceholders.Location = New-Object System.Drawing.Point -ArgumentList 15, $y
$lblPlaceholders.Size = New-Object System.Drawing.Size -ArgumentList 700, 20
$lblPlaceholders.ForeColor = [System.Drawing.Color]::DimGray
$tabWelcome.Controls.Add($lblPlaceholders)
$y += 25

$txtWelcomeTemplate = New-Object System.Windows.Forms.TextBox
$txtWelcomeTemplate.Location = New-Object System.Drawing.Point -ArgumentList 15, $y
$txtWelcomeTemplate.Size = New-Object System.Drawing.Size -ArgumentList 700, 400
$txtWelcomeTemplate.Multiline = $true
$txtWelcomeTemplate.ScrollBars = 'Both'
$txtWelcomeTemplate.Font = New-Object System.Drawing.Font -ArgumentList 'Consolas', 9
$txtWelcomeTemplate.WordWrap = $false
$tabWelcome.Controls.Add($txtWelcomeTemplate)
if ($welcomeTemplatePath -and (Test-Path $welcomeTemplatePath)) {
    $txtWelcomeTemplate.Text = Get-Content $welcomeTemplatePath -Raw
}
$y += 410

$lblDeliveryHeader = New-Object System.Windows.Forms.Label
$lblDeliveryHeader.Text = 'Credential delivery:'
$lblDeliveryHeader.Location = New-Object System.Drawing.Point -ArgumentList 15, $y
$lblDeliveryHeader.Size = New-Object System.Drawing.Size -ArgumentList 120, 22
$tabWelcome.Controls.Add($lblDeliveryHeader)
$y += 25

$rdoWelcomeOnly = New-Object System.Windows.Forms.RadioButton
$rdoWelcomeOnly.Text = 'Welcome email only - admin delivers credentials separately'
$rdoWelcomeOnly.Location = New-Object System.Drawing.Point -ArgumentList 15, $y
$rdoWelcomeOnly.Size = New-Object System.Drawing.Size -ArgumentList 690, 22
$rdoWelcomeOnly.Checked = $false
$tabWelcome.Controls.Add($rdoWelcomeOnly)
$y += 25

$rdoWelcomeIncludes = New-Object System.Windows.Forms.RadioButton
$rdoWelcomeIncludes.Text = 'Welcome email includes credentials (single email)'
$rdoWelcomeIncludes.Location = New-Object System.Drawing.Point -ArgumentList 15, $y
$rdoWelcomeIncludes.Size = New-Object System.Drawing.Size -ArgumentList 690, 22
$tabWelcome.Controls.Add($rdoWelcomeIncludes)
$y += 25

$rdoSeparate = New-Object System.Windows.Forms.RadioButton
$rdoSeparate.Text = 'Welcome email + separate credentials email (recommended)'
$rdoSeparate.Location = New-Object System.Drawing.Point -ArgumentList 15, $y
$rdoSeparate.Size = New-Object System.Drawing.Size -ArgumentList 690, 22
$rdoSeparate.Checked = $true
$tabWelcome.Controls.Add($rdoSeparate)
$y += 30

$chkUseTap = New-Object System.Windows.Forms.CheckBox
$chkUseTap.Text = 'Use Temporary Access Pass (24h, one-time) instead of password'
$chkUseTap.Location = New-Object System.Drawing.Point -ArgumentList 15, $y
$chkUseTap.Size = New-Object System.Drawing.Size -ArgumentList 690, 22
$chkUseTap.Checked = $true
$tabWelcome.Controls.Add($chkUseTap)
$y += 30

$btnSaveTemplate = New-Object System.Windows.Forms.Button
$btnSaveTemplate.Text = 'Save Template'
$btnSaveTemplate.Location = New-Object System.Drawing.Point -ArgumentList 15, $y
$btnSaveTemplate.Size = New-Object System.Drawing.Size -ArgumentList 120, 28
$tabWelcome.Controls.Add($btnSaveTemplate)

$lblSaveStatus = New-Object System.Windows.Forms.Label
$lblSaveStatus.Location = New-Object System.Drawing.Point -ArgumentList 145, ($y + 4)
$lblSaveStatus.Size = New-Object System.Drawing.Size -ArgumentList 570, 22
$lblSaveStatus.ForeColor = [System.Drawing.Color]::ForestGreen
$tabWelcome.Controls.Add($lblSaveStatus)

$btnSaveTemplate.Add_Click({
    if (-not $welcomeTemplatePath) {
        $lblSaveStatus.ForeColor = [System.Drawing.Color]::Firebrick
        $lblSaveStatus.Text = 'Template path not resolved.'
        return
    }
    try {
        Set-Content -Path $welcomeTemplatePath -Value $txtWelcomeTemplate.Text -Encoding UTF8
        $lblSaveStatus.ForeColor = [System.Drawing.Color]::ForestGreen
        $lblSaveStatus.Text = "Saved at $(Get-Date -Format HH:mm:ss)."
    } catch {
        $lblSaveStatus.ForeColor = [System.Drawing.Color]::Firebrick
        $lblSaveStatus.Text = "Save failed: $($_.Exception.Message)"
    }
})

# ---------------- Review tab ----------------
$tabReview = New-Object System.Windows.Forms.TabPage
$tabReview.Text = 'Review'
$tabReview.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 15
$tabs.TabPages.Add($tabReview)

$txtReview = New-Object System.Windows.Forms.TextBox
$txtReview.Location = New-Object System.Drawing.Point -ArgumentList 15, 20
$txtReview.Size = New-Object System.Drawing.Size -ArgumentList 690, 500
$txtReview.Multiline = $true
$txtReview.ReadOnly = $true
$txtReview.ScrollBars = 'Vertical'
$txtReview.Font = New-Object System.Drawing.Font -ArgumentList 'Consolas', 10
$tabReview.Controls.Add($txtReview)

# ---------------- Nav buttons ----------------
$btnBack = New-Object System.Windows.Forms.Button
$btnBack.Text = '< Back'
$btnBack.Location = New-Object System.Drawing.Point -ArgumentList 320, 630
$btnBack.Size = New-Object System.Drawing.Size -ArgumentList 100, 30
$form.Controls.Add($btnBack)

$btnNext = New-Object System.Windows.Forms.Button
$btnNext.Text = 'Next >'
$btnNext.Location = New-Object System.Drawing.Point -ArgumentList 430, 630
$btnNext.Size = New-Object System.Drawing.Size -ArgumentList 100, 30
$form.Controls.Add($btnNext)

$btnNone = New-Object System.Windows.Forms.Button
$btnNone.Text = 'None / Skip'
$btnNone.Location = New-Object System.Drawing.Point -ArgumentList 540, 630
$btnNone.Size = New-Object System.Drawing.Size -ArgumentList 100, 30
$btnNone.Visible = $false
$form.Controls.Add($btnNone)

$btnCreate = New-Object System.Windows.Forms.Button
$btnCreate.Text = 'Create User'
$btnCreate.Location = New-Object System.Drawing.Point -ArgumentList 540, 630
$btnCreate.Size = New-Object System.Drawing.Size -ArgumentList 100, 30
$btnCreate.Visible = $false
$form.Controls.Add($btnCreate)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = 'Cancel'
$btnCancel.Location = New-Object System.Drawing.Point -ArgumentList 650, 630
$btnCancel.Size = New-Object System.Drawing.Size -ArgumentList 80, 30
$form.Controls.Add($btnCancel)

function Get-SelectedDomain {
    if (-not $cmbDomain.SelectedItem) { return '' }
    return ($cmbDomain.SelectedItem -split '   ')[0]
}

function Show-Tab {
    param([int]$Index)
    $tabs.SelectedIndex = $Index
    $btnBack.Enabled   = ($Index -gt 0)
    $btnNext.Visible   = ($Index -lt 5)
    $btnNone.Visible   = ($Index -eq 2 -or $Index -eq 3)
    $btnCreate.Visible = ($Index -eq 5)
    if ($Index -eq 5) { Update-Review }
}

function Validate-AccountTab {
    if ([string]::IsNullOrWhiteSpace($txtDisplayName.Text)) {
        [System.Windows.Forms.MessageBox]::Show('Display name is required.', 'Validation') | Out-Null
        return $false
    }
    if ([string]::IsNullOrWhiteSpace($txtUpnPrefix.Text)) {
        [System.Windows.Forms.MessageBox]::Show('UPN local part is required.', 'Validation') | Out-Null
        return $false
    }
    if ($txtUpnPrefix.Text -match '[^a-zA-Z0-9._-]') {
        [System.Windows.Forms.MessageBox]::Show('UPN local part may only contain letters, digits, dots, underscores, and hyphens.', 'Validation') | Out-Null
        return $false
    }
    $strength = Measure-PasswordStrength -Password $txtPassword.Text
    if (-not $strength.MeetsWizardMin) {
        [System.Windows.Forms.MessageBox]::Show("Password must be at least 12 characters. Current: $($strength.Length) chars, strength: $($strength.Label)", 'Validation') | Out-Null
        return $false
    }
    if ($txtPersonalEmail.Text -and $txtPersonalEmail.Text -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        [System.Windows.Forms.MessageBox]::Show('Personal email must be a valid email address.', 'Validation') | Out-Null
        return $false
    }
    if ($txtCredentialsRecipient.Text -and $txtCredentialsRecipient.Text -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        [System.Windows.Forms.MessageBox]::Show('Credentials recipient must be a valid email address.', 'Validation') | Out-Null
        return $false
    }
    if ($rdoSeparate.Checked -and -not $txtCredentialsRecipient.Text -and -not $txtPersonalEmail.Text) {
        [System.Windows.Forms.MessageBox]::Show('Separate credentials email is selected but no recipient is set. Fill Personal Email or Credentials recipient.', 'Validation') | Out-Null
        return $false
    }
    return $true
}

function Update-Review {
    $upn = "$($txtUpnPrefix.Text)@$(Get-SelectedDomain)"
    $strength = Measure-PasswordStrength -Password $txtPassword.Text
    $chosenLicenses = @()
    foreach ($idx in $chkLicenseList.CheckedIndices) {
        if ($idx -lt $licenses.Count) { $chosenLicenses += $licenses[$idx].DisplayName }
    }
    if ($chosenLicenses.Count -eq 0) { $chosenLicenses = @('(no license)') }
    $checkedGroups = @()
    foreach ($idx in $chkGroupList.CheckedIndices) {
        if ($idx -lt $script:groupListCurrent.Count) {
            $checkedGroups += $script:groupListCurrent[$idx].DisplayName
        }
    }
    if ($checkedGroups.Count -eq 0) { $checkedGroups = @('(no groups)') }

    # Delivery plan
    $welcomeTo = if ($txtPersonalEmail.Text) { "$($txtPersonalEmail.Text) (personal)" }
                 elseif ($upn) { "$upn (work mailbox when ready)" }
                 else { '(unset)' }
    $credTo = if ($rdoWelcomeOnly.Checked) { '(not sent - admin delivers manually)' }
              elseif ($rdoWelcomeIncludes.Checked) { "Same as welcome: $welcomeTo" }
              elseif ($txtCredentialsRecipient.Text) { "$($txtCredentialsRecipient.Text) (separate email)" }
              elseif ($txtPersonalEmail.Text) { "$($txtPersonalEmail.Text) (separate email)" }
              else { '(unset)' }
    $credMethod = if ($chkUseTap.Checked) { 'Temporary Access Pass (24h, one-time)' } else { 'Password' }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('=== Account ===')
    [void]$sb.AppendLine("Display name    : $($txtDisplayName.Text)")
    if ($txtGivenName.Text) { [void]$sb.AppendLine("First name      : $($txtGivenName.Text)") }
    if ($txtSurname.Text)   { [void]$sb.AppendLine("Last name       : $($txtSurname.Text)") }
    [void]$sb.AppendLine("UPN             : $upn")
    [void]$sb.AppendLine("Mail nickname   : $($txtMailNickname.Text)")
    [void]$sb.AppendLine("Password        : $($strength.Label) (length=$($strength.Length), classes=$($strength.ClassesCount)/4)")
    [void]$sb.AppendLine("Force change    : $($chkForceChange.Checked)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('=== Profile ===')
    if ($txtJobTitle.Text)     { [void]$sb.AppendLine("Job title       : $($txtJobTitle.Text)") }
    if ($txtDepartment.Text)   { [void]$sb.AppendLine("Department      : $($txtDepartment.Text)") }
    if ($txtPhone.Text)        { [void]$sb.AppendLine("Phone           : $($txtPhone.Text)") }
    if ($txtOffice.Text)       { [void]$sb.AppendLine("Office          : $($txtOffice.Text)") }
    if ($txtEmployeeId.Text)   { [void]$sb.AppendLine("Employee ID     : $($txtEmployeeId.Text)") }
    if ($txtPersonalEmail.Text){ [void]$sb.AppendLine("Personal email  : $($txtPersonalEmail.Text)") }
    [void]$sb.AppendLine("Usage location  : $($cmbUsage.SelectedItem)")
    if ($txtManager.Text)      { [void]$sb.AppendLine("Manager UPN     : $($txtManager.Text)") }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('=== Delivery ===')
    [void]$sb.AppendLine("Welcome email to   : $welcomeTo")
    [void]$sb.AppendLine("Credentials email  : $credTo")
    [void]$sb.AppendLine("Credential method  : $credMethod")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('=== Licenses ===')
    foreach ($lic in $chosenLicenses) { [void]$sb.AppendLine("  - $lic") }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('=== Groups ===')
    foreach ($g in $checkedGroups) { [void]$sb.AppendLine("  - $g") }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Click "Create User" to provision the account.')
    $txtReview.Text = $sb.ToString()
}

$btnBack.Add_Click({ if ($tabs.SelectedIndex -gt 0) { Show-Tab ($tabs.SelectedIndex - 1) } })
$btnNext.Add_Click({
    $current = $tabs.SelectedIndex
    if ($current -eq 0 -and -not (Validate-AccountTab)) { return }
    if ($current -lt 5) { Show-Tab ($current + 1) }
})
$btnNone.Add_Click({
    $current = $tabs.SelectedIndex
    if ($current -eq 2) {
        for ($i = 0; $i -lt $chkLicenseList.Items.Count; $i++) { $chkLicenseList.SetItemChecked($i, $false) }
    }
    if ($current -eq 3) {
        for ($i = 0; $i -lt $chkGroupList.Items.Count; $i++) { $chkGroupList.SetItemChecked($i, $false) }
    }
    Show-Tab ($current + 1)
})
$btnCancel.Add_Click({ $form.Close() })

$btnCreate.Add_Click({
    if (-not (Validate-AccountTab)) { Show-Tab 0; return }

    $upn      = "$($txtUpnPrefix.Text)@$(Get-SelectedDomain)"
    $nickname = if ($txtMailNickname.Text) { $txtMailNickname.Text } else { $txtUpnPrefix.Text }

    $skuIds = @()
    foreach ($idx in $chkLicenseList.CheckedIndices) {
        if ($idx -lt $licenses.Count) { $skuIds += $licenses[$idx].SkuId }
    }
    $groupIds = @()
    foreach ($idx in $chkGroupList.CheckedIndices) {
        if ($idx -lt $script:groupListCurrent.Count) {
            $groupIds += $script:groupListCurrent[$idx].Id
        }
    }

    # Decide credentials recipient
    $credRecipient = ''
    $sendCredEmail = $false
    if ($rdoSeparate.Checked) {
        $sendCredEmail = $true
        if ($txtCredentialsRecipient.Text) { $credRecipient = $txtCredentialsRecipient.Text.Trim() }
        elseif ($txtPersonalEmail.Text)    { $credRecipient = $txtPersonalEmail.Text.Trim() }
    }

    $params = @{
        DisplayName       = $txtDisplayName.Text.Trim()
        UserPrincipalName = $upn
        MailNickname      = $nickname
        Password          = $txtPassword.Text
        UsageLocation     = $cmbUsage.SelectedItem
        Config            = $config
    }
    if ($txtGivenName.Text)             { $params.GivenName      = $txtGivenName.Text.Trim() }
    if ($txtSurname.Text)               { $params.Surname        = $txtSurname.Text.Trim() }
    if ($txtJobTitle.Text)              { $params.JobTitle       = $txtJobTitle.Text.Trim() }
    if ($txtDepartment.Text)            { $params.Department     = $txtDepartment.Text.Trim() }
    if ($txtPhone.Text)                 { $params.Phone          = $txtPhone.Text.Trim() }
    if ($txtOffice.Text)                { $params.OfficeLocation = $txtOffice.Text.Trim() }
    if ($txtEmployeeId.Text)            { $params.EmployeeId     = $txtEmployeeId.Text.Trim() }
    if ($txtPersonalEmail.Text)         { $params.PersonalEmail  = $txtPersonalEmail.Text.Trim() }
    if ($credRecipient)                 { $params.CredentialsRecipient = $credRecipient }
    if ($chkUseTap.Checked)             { $params.UseTemporaryAccessPass = $true }
    if ($sendCredEmail)                 { $params.SendCredentialsEmail = $true }
    if ($rdoWelcomeIncludes.Checked)    { $params.IncludePasswordInWelcome = $true }
    if ($chkForceChange.Checked)        { $params.ForceChangePasswordNextSignIn = $true }
    if ($skuIds.Count -gt 0)            { $params.LicenseSkuIds   = $skuIds }
    if ($txtManager.Text)               { $params.ManagerUpn      = $txtManager.Text.Trim() }
    if ($groupIds.Count -gt 0)          { $params.GroupIds        = $groupIds }

    $btnCreate.Enabled = $false
    $btnCreate.Text = 'Creating...'
    $form.Refresh()

    try {
        $result = New-OnboardedUser @params

        $welcomeTarget = if ($txtPersonalEmail.Text) { "$($txtPersonalEmail.Text) (personal)" } else { "$upn (work mailbox)" }
        $credLine = if ($sendCredEmail) { "Credentials     : $credRecipient" } else { 'Credentials     : (not emailed)' }

        $msg = @"
User created successfully.

UPN              : $($result.UserPrincipalName)
Display name     : $($result.DisplayName)
Licenses assigned: $($result.LicenseSkuIds.Count)
Groups assigned  : $($result.GroupsAssigned.Count)
Groups failed    : $($result.GroupsFailed.Count)
Manager set      : $($result.ManagerSet)
Welcome goes to  : $welcomeTarget
$credLine

Temporary password (shown once):

    $($txtPassword.Text)

"@
        if ($result.TemporaryAccessPass) {
            $msg += "`nTemporary access pass:`n`n    $($result.TemporaryAccessPass)`n`nExpires: $($result.TapExpiresAt)`n"
        }
        if ($result.Errors.Count -gt 0) {
            $msg += "`nWarnings:`n"
            $result.Errors | ForEach-Object { $msg += " - $_`n" }
        }

        [System.Windows.Forms.MessageBox]::Show($msg, 'User Created', 'OK', 'Information') | Out-Null

        $sendNow = [System.Windows.Forms.MessageBox]::Show(
            "Send the welcome email now?",
            'Send Welcome Now', 'YesNo', 'Question'
        )
        if ($sendNow -eq 'Yes') {
            $eventId = "manual-welcome-$($result.UserId)-$((Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'))"
            try {
                $u = Get-NewUserFromGraph -Filter (New-GraphFilterById -Id $result.UserId) | Select-Object -First 1
                if ($u) {
                    $userEvent = [pscustomobject]@{
                        EventId                     = $eventId
                        UserId                      = $u.Id
                        DisplayName                 = $u.DisplayName
                        UserPrincipalName           = $u.UserPrincipalName
                        Mail                        = $u.Mail
                        Department                  = $u.Department
                        JobTitle                    = $u.JobTitle
                        Phone                       = $u.MobilePhone
                        Office                      = $u.OfficeLocation
                        EmployeeId                  = $u.EmployeeId
                        Manager                     = $txtManager.Text
                        PersonalEmail               = $txtPersonalEmail.Text
                        TemporaryAccessPass         = $result.TemporaryAccessPass
                        TemporaryAccessPassExpiresAt = $result.TapExpiresAt
                        CreatedDateTime             = $u.CreatedDateTime
                        UserType                    = if ($u.UserType) { $u.UserType } else { 'Member' }
                        IsHybridSynced              = $false
                        Source                      = 'ManualSendNow'
                    }
                    $wc = @{}
                    foreach ($k in $config.Keys) { $wc[$k] = $config[$k] }
                    $wc['IncludePasswordInWelcome']   = $rdoWelcomeIncludes.IsChecked
                    $wc['IncludeAccessPassInWelcome'] = ($rdoWelcomeIncludes.IsChecked -and $chkUseTap.Checked)
                    $wc['TemporaryPassword']          = $txtPassword.Text
                    $welcomeResult = Send-WelcomeEmail -User $userEvent -Config $wc -EventId $eventId
                    Write-AuditLog -EventId $eventId -UserPrincipalName $u.UserPrincipalName `
                        -Stage 'WelcomeSent' -Status $welcomeResult.Status -Detail $welcomeResult.Detail -LogPath $config.Audit.LogPath
                }
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Welcome send failed: $($_.Exception.Message)", 'Error', 'OK', 'Error') | Out-Null
            }
        }

        $form.Close()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Creation failed:`n`n$($_.Exception.Message)", 'Error', 'OK', 'Error') | Out-Null
        $btnCreate.Enabled = $true
        $btnCreate.Text = 'Create User'
    }
})

Show-Tab 0
[void]$form.ShowDialog()