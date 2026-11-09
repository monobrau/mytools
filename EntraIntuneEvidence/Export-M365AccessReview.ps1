#Requires -Version 5.1
<#
.SYNOPSIS
    M365 user list for an access review, as a formatted workbook.

.DESCRIPTION
    Writes one row per user, sorted by last name then first name. The workbook
    always contains the user facts. Summary counts and suggestions are written
    only with -IncludeSummary.

    MFA enforced is true when per-user MFA is enabled or enforced, Security
    Defaults is on, or an enabled Conditional Access policy requiring MFA
    includes the user. Report-only policies do not count. Policies that do
    not target all cloud apps are marked as partial.

.PARAMETER OutputFolder
    Folder for the workbook. Default is OneDrive\EntraIntuneEvidence\<tenant>\<timestamp>.

.PARAMETER IncludeSummary
    Add Summary and Suggestions sheets. The user facts are written either way.

.PARAMETER SkipExchange
    Do not connect to Exchange Online. Mailbox type and last activity stay blank
    unless a Graph mailbox probe succeeds.

.PARAMETER Exit
    Exit the process when the export finishes. The launcher sends this for Commands.

.PARAMETER NoExit
    Keep the window open.
#>
[CmdletBinding()]
param(
    [string]$TenantId,
    [string]$OutputFolder,
    [switch]$IncludeSummary,
    [switch]$SkipExchange,
    [switch]$Exit,
    [switch]$NoExit
)

$ErrorActionPreference = 'Stop'

function Get-AccessReviewFolderName {
    param([string]$Name)
    $safe = ($Name -replace '[^\w\-]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) { return 'tenant' }
    return $safe
}

function Get-AccessReviewOneDriveRoot {
    foreach ($candidate in @($env:OneDriveCommercial, $env:OneDrive)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            return $candidate.TrimEnd('\')
        }
    }
    $regPaths = @(
        'HKCU:\Software\Microsoft\OneDrive\Accounts\Business1'
        'HKCU:\Software\Microsoft\OneDrive\Accounts\Business2'
        'HKCU:\Software\Microsoft\OneDrive\Accounts\Personal'
    )
    foreach ($reg in $regPaths) {
        if (-not (Test-Path -LiteralPath $reg)) { continue }
        $item = Get-ItemProperty -LiteralPath $reg -ErrorAction SilentlyContinue
        $folder = $null
        if ($item -and $item.PSObject.Properties['UserFolder']) { $folder = [string]$item.UserFolder }
        if (-not [string]::IsNullOrWhiteSpace($folder)) { return $folder.TrimEnd('\') }
    }
    return $null
}

function Format-AccessReviewLicense {
    param([string]$Part)
    $known = @{
        SPE_E3 = 'Microsoft 365 E3'
        SPE_E5 = 'Microsoft 365 E5'
        ENTERPRISEPACK = 'Office 365 E3'
        ENTERPRISEPREMIUM = 'Office 365 E5'
        SPB = 'Microsoft 365 Business Premium'
        O365_BUSINESS_PREMIUM = 'Microsoft 365 Business Standard'
        O365_BUSINESS_ESSENTIALS = 'Microsoft 365 Business Basic'
        EXCHANGESTANDARD = 'Exchange Online (Plan 1)'
        EXCHANGEENTERPRISE = 'Exchange Online (Plan 2)'
        ATP_ENTERPRISE = 'Defender for Office 365 Plan 1'
        EMS = 'Enterprise Mobility + Security E3'
        EMSPREMIUM = 'Enterprise Mobility + Security E5'
        FLOW_FREE = 'Power Automate Free'
        POWER_BI_STANDARD = 'Power BI Free'
        TEAMS_EXPLORATORY = 'Microsoft Teams Exploratory'
    }
    if ($known.ContainsKey($Part)) { return ('{0} ({1})' -f $known[$Part], $Part) }
    return $Part
}

function Test-GuestTypeSelected {
    param($Value)
    if ($null -eq $Value) { return $false }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    if ($text -match '^(?i)none|0$') { return $false }
    return $true
}

function Test-CaPolicyAppliesToUser {
    param($Policy, $User)
    $conditions = $Policy.Conditions
    if (-not $conditions -or -not $conditions.Users) { return $false }
    $c = $conditions.Users
    $uid = [string]$User.Id
    $grp = $script:AccessReviewUserGroups[$uid]
    $rol = $script:AccessReviewUserRoles[$uid]
    if (-not $grp) { $grp = New-Object 'System.Collections.Generic.HashSet[string]' }
    if (-not $rol) { $rol = New-Object 'System.Collections.Generic.HashSet[string]' }
    $isGuest = [string]$User.UserType -eq 'Guest'
    $exGuest = Test-GuestTypeSelected $c.ExcludeGuestsOrExternalUsers.GuestOrExternalUserTypes
    $inGuest = Test-GuestTypeSelected $c.IncludeGuestsOrExternalUsers.GuestOrExternalUserTypes

    if ($c.ExcludeUsers -contains $uid) { return $false }
    if ($isGuest -and ($c.ExcludeUsers -contains 'GuestsOrExternalUsers' -or $exGuest)) { return $false }
    foreach ($id in @($c.ExcludeGroups)) { if ($id -and $grp.Contains([string]$id)) { return $false } }
    foreach ($id in @($c.ExcludeRoles)) { if ($id -and $rol.Contains([string]$id)) { return $false } }

    if ($c.IncludeUsers -contains 'All') { return $true }
    if ($c.IncludeUsers -contains $uid) { return $true }
    if ($isGuest -and ($c.IncludeUsers -contains 'GuestsOrExternalUsers' -or $inGuest)) { return $true }
    foreach ($id in @($c.IncludeGroups)) { if ($id -and $grp.Contains([string]$id)) { return $true } }
    foreach ($id in @($c.IncludeRoles)) { if ($id -and $rol.Contains([string]$id)) { return $true } }
    return $false
}

function Get-CaAppScope {
    param($Policy)
    $apps = @($Policy.Conditions.Applications.IncludeApplications)
    $excluded = @($Policy.Conditions.Applications.ExcludeApplications | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($apps -contains 'All' -and $excluded.Count -eq 0) { return 'All cloud apps' }
    return 'Partial'
}

function Sort-AccessReviewRow {
    param($Rows)
    $list = @($Rows | Where-Object { $null -ne $_ })
    $named = @($list | Where-Object { $_.Lastname } | Sort-Object Lastname, Firstname, Username)
    $unnamed = @($list | Where-Object { -not $_.Lastname } | Sort-Object DisplayName, Username)
    return @($named) + @($unnamed)
}

function Get-AccessReviewSuggestion {
    param(
        $Rows,
        [bool]$RegistrationKnown
    )
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($row in @(Sort-AccessReviewRow $Rows)) {
        if (-not $row.AccountEnabled) { continue }
        $parts = New-Object System.Collections.Generic.List[string]
        if (-not $row.MfaEnabled) {
            $parts.Add('MFA is not enforced for this enabled account.')
        }
        if ($RegistrationKnown -and $null -ne $row.MfaRegistered -and -not [bool]$row.MfaRegistered) {
            $parts.Add('No MFA method is registered.')
        }
        if ($parts.Count -eq 0) { continue }
        $items.Add([pscustomobject]@{
            Suggestion = ($parts -join ' ')
            Lastname   = $row.Lastname
            Firstname  = $row.Firstname
            Username   = $row.Username
        })
    }
    return $items.ToArray()
}

function ConvertTo-ExcelColumn {
    param([int]$Number)
    $n = $Number
    $name = ''
    while ($n -gt 0) {
        $n--
        $name = [char](65 + ($n % 26)) + $name
        $n = [math]::Floor($n / 26)
    }
    return $name
}

function ConvertTo-ExcelSerialDate {
    param([datetime]$Value)
    return [int]($Value.Date - [datetime]'1899-12-30').TotalDays
}

function ConvertTo-SpreadsheetText {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Security.SecurityElement]::Escape($Text)
}

function Get-AccessReviewFactColumn {
    return @(
        @{ Key = 'Lastname'; Header = 'Last name'; Width = 20; Type = 'text' }
        @{ Key = 'Firstname'; Header = 'First name'; Width = 16; Type = 'text' }
        @{ Key = 'DisplayName'; Header = 'Display name'; Width = 28; Type = 'text' }
        @{ Key = 'Username'; Header = 'Username'; Width = 36; Type = 'text' }
        @{ Key = 'AccountEnabled'; Header = 'Account enabled'; Width = 18; Type = 'yesno' }
        @{ Key = 'UserType'; Header = 'User type'; Width = 14; Type = 'text' }
        @{ Key = 'HasMailbox'; Header = 'Has mailbox'; Width = 14; Type = 'yesno' }
        @{ Key = 'MailboxType'; Header = 'Mailbox type'; Width = 24; Type = 'text' }
        @{ Key = 'LastSignIn'; Header = 'Last sign-in'; Width = 16; Type = 'signin' }
        @{ Key = 'DaysSinceLastSignIn'; Header = 'Days since last sign-in'; Width = 24; Type = 'int' }
        @{ Key = 'MailboxLastUserAction'; Header = 'Mailbox last activity'; Width = 22; Type = 'date' }
        @{ Key = 'MfaEnabled'; Header = 'MFA enforced'; Width = 16; Type = 'yesno' }
        @{ Key = 'MfaEnforcedBy'; Header = 'Enforced by'; Width = 42; Type = 'text' }
        @{ Key = 'MfaRegistered'; Header = 'MFA registered'; Width = 16; Type = 'yesnoblank' }
        @{ Key = 'MfaMethods'; Header = 'MFA methods'; Width = 36; Type = 'text' }
        @{ Key = 'PerUserMfaState'; Header = 'Per-user MFA'; Width = 16; Type = 'text' }
        @{ Key = 'Licenses'; Header = 'Licenses'; Width = 42; Type = 'text' }
    )
}

function Get-FactCell {
    param($Row, $Column)
    $key = $Column.Key
    switch ($Column.Type) {
        'yesno' {
            $value = 'No'
            if ($Row.$key) { $value = 'Yes' }
            return @{ Style = 0; Type = 'text'; Value = $value }
        }
        'yesnoblank' {
            $raw = $Row.$key
            if ($null -eq $raw -or [string]::IsNullOrWhiteSpace([string]$raw)) { return $null }
            $value = 'No'
            if ([bool]$raw) { $value = 'Yes' }
            return @{ Style = 0; Type = 'text'; Value = $value }
        }
        'signin' {
            if ($Row.LastSignIn) {
                return @{ Style = 5; Type = 'date'; Value = (ConvertTo-ExcelSerialDate ([datetime]$Row.LastSignIn)) }
            }
            if ($Row.NeverSignedIn) { return @{ Style = 0; Type = 'text'; Value = 'Never' } }
            return $null
        }
        'date' {
            if (-not $Row.$key) { return $null }
            return @{ Style = 5; Type = 'date'; Value = (ConvertTo-ExcelSerialDate ([datetime]$Row.$key)) }
        }
        'int' {
            if ($null -eq $Row.$key -or [string]$Row.$key -eq '') { return $null }
            return @{ Style = 6; Type = 'number'; Value = [int]$Row.$key }
        }
        default {
            $text = [string]$Row.$key
            if ([string]::IsNullOrWhiteSpace($text)) { return $null }
            return @{ Style = 0; Type = 'text'; Value = $text }
        }
    }
}

function Get-WorksheetXml {
    param(
        [int[]]$Widths,
        $Rows,
        [string]$TabColor = 'FF1F4E79',
        [string]$FreezeCell = '',
        [string]$TableName = '',
        [string[]]$Merges = @(),
        [string]$Conditional = '',
        [string]$HeaderLeft = '',
        [string]$FooterLeft = ''
    )
    $rowCount = 0
    $colCount = 0
    if ($null -ne $Rows) { $rowCount = $Rows.Count }
    if ($null -ne $Widths) { $colCount = $Widths.Count }
    $lastRow = [Math]::Max(1, $rowCount)
    $lastCol = [Math]::Max(1, $colCount)
    $end = '{0}{1}' -f (ConvertTo-ExcelColumn $lastCol), $lastRow
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    [void]$sb.Append('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')
    [void]$sb.Append('<sheetPr><tabColor rgb="' + $TabColor + '"/><pageSetUpPr fitToPage="1"/></sheetPr>')
    [void]$sb.Append('<dimension ref="A1:' + $end + '"/>')
    [void]$sb.Append('<sheetViews><sheetView workbookViewId="0">')
    if ($FreezeCell) {
        [void]$sb.Append('<pane ySplit="1" topLeftCell="' + $FreezeCell + '" activePane="bottomLeft" state="frozen"/>')
    }
    [void]$sb.Append('</sheetView></sheetViews>')
    [void]$sb.Append('<sheetFormatPr defaultRowHeight="15"/>')
    [void]$sb.Append('<cols>')
    for ($i = 0; $i -lt $Widths.Count; $i++) {
        [void]$sb.Append('<col min="' + ($i + 1) + '" max="' + ($i + 1) + '" width="' + $Widths[$i] + '" customWidth="1"/>')
    }
    [void]$sb.Append('</cols><sheetData>')
    for ($r = 0; $r -lt $rowCount; $r++) {
        $rowNumber = $r + 1
        [void]$sb.Append('<row r="' + $rowNumber + '">')
        $cells = $Rows[$r]
        for ($c = 0; $c -lt $cells.Count; $c++) {
            $cell = $cells[$c]
            if (-not $cell) { continue }
            $ref = '{0}{1}' -f (ConvertTo-ExcelColumn ($c + 1)), $rowNumber
            if ($cell.Type -eq 'text') {
                [void]$sb.Append('<c r="' + $ref + '" t="inlineStr" s="' + $cell.Style + '"><is><t>' + (ConvertTo-SpreadsheetText ([string]$cell.Value)) + '</t></is></c>')
            }
            else {
                [void]$sb.Append('<c r="' + $ref + '" s="' + $cell.Style + '"><v>' + $cell.Value + '</v></c>')
            }
        }
        [void]$sb.Append('</row>')
    }
    [void]$sb.Append('</sheetData>')
    $mergeList = @($Merges | Where-Object { $_ })
    if ($mergeList.Count -gt 0) {
        [void]$sb.Append('<mergeCells count="' + $mergeList.Count + '">')
        foreach ($merge in $mergeList) {
            [void]$sb.Append('<mergeCell ref="' + $merge + '"/>')
        }
        [void]$sb.Append('</mergeCells>')
    }
    if ($Conditional) { [void]$sb.Append($Conditional) }
    [void]$sb.Append('<pageMargins left="0.5" right="0.5" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>')
    [void]$sb.Append('<pageSetup orientation="landscape" fitToWidth="1" fitToHeight="0" paperSize="1"/>')
    $left = (ConvertTo-SpreadsheetText ($HeaderLeft -replace '&', 'and'))
    $foot = (ConvertTo-SpreadsheetText ($FooterLeft -replace '&', 'and'))
    [void]$sb.Append('<headerFooter><oddHeader>&amp;L' + $left + '&amp;RPage &amp;P of &amp;N</oddHeader><oddFooter>&amp;L' + $foot + '</oddFooter></headerFooter>')
    if ($TableName -and $lastRow -ge 2) {
        [void]$sb.Append('<tableParts count="1"><tablePart r:id="rId1"/></tableParts>')
    }
    [void]$sb.Append('</worksheet>')
    return $sb.ToString()
}

function Get-TableXml {
    param([string]$Name, [string[]]$Headers, [int]$LastRow)
    $lastCol = ConvertTo-ExcelColumn $Headers.Count
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    [void]$sb.Append('<table xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" id="1" name="' + $Name + '" displayName="' + $Name + '" ref="A1:' + $lastCol + $LastRow + '" totalsRowCount="0">')
    [void]$sb.Append('<autoFilter ref="A1:' + $lastCol + $LastRow + '"/>')
    [void]$sb.Append('<tableColumns count="' + $Headers.Count + '">')
    for ($i = 0; $i -lt $Headers.Count; $i++) {
        [void]$sb.Append('<tableColumn id="' + ($i + 1) + '" name="' + (ConvertTo-SpreadsheetText $Headers[$i]) + '"/>')
    }
    [void]$sb.Append('</tableColumns>')
    [void]$sb.Append('<tableStyleInfo name="TableStyleMedium2" showFirstColumn="0" showLastColumn="0" showRowStripes="1" showColumnStripes="0"/>')
    [void]$sb.Append('</table>')
    return $sb.ToString()
}

function Get-FactConditionalXml {
    param($Columns, [int]$LastRow)
    if ($LastRow -lt 2) { return '' }
    $enabled = 0
    $mfa = 0
    for ($i = 0; $i -lt $Columns.Count; $i++) {
        if ($Columns[$i].Key -eq 'AccountEnabled') { $enabled = $i + 1 }
        if ($Columns[$i].Key -eq 'MfaEnabled') { $mfa = $i + 1 }
    }
    if (-not $enabled -or -not $mfa) { return '' }
    $enabledLetter = ConvertTo-ExcelColumn $enabled
    $mfaLetter = ConvertTo-ExcelColumn $mfa
    $lastLetter = ConvertTo-ExcelColumn $Columns.Count
    $mfaRef = '{0}2:{0}{1}' -f $mfaLetter, $LastRow
    $rowRef = 'A2:{0}{1}' -f $lastLetter, $LastRow
    return (
        '<conditionalFormatting sqref="' + $mfaRef + '"><cfRule type="expression" dxfId="0" priority="1"><formula>AND($' + $enabledLetter + '2="Yes",$' + $mfaLetter + '2="No")</formula></cfRule></conditionalFormatting>' +
        '<conditionalFormatting sqref="' + $rowRef + '"><cfRule type="expression" dxfId="1" priority="2"><formula>$' + $enabledLetter + '2="No"</formula></cfRule></conditionalFormatting>'
    )
}

function Get-StylesXml {
    @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy-mm-dd"/></numFmts>
  <fonts count="6">
    <font><sz val="11"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
    <font><b/><sz val="18"/><color rgb="FF1F4E79"/><name val="Calibri"/></font>
    <font><b/><sz val="12"/><color rgb="FF1F4E79"/><name val="Calibri"/></font>
    <font><sz val="11"/><color rgb="FF666666"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><color rgb="FF1F4E79"/><name val="Calibri"/></font>
  </fonts>
  <fills count="6">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FF1F4E79"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFF4CCCC"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFFCE4D6"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFE7EEF7"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/><diagonal/></border>
    <border>
      <left style="thin"><color rgb="FFD0D7E2"/></left>
      <right style="thin"><color rgb="FFD0D7E2"/></right>
      <top style="thin"><color rgb="FFD0D7E2"/></top>
      <bottom style="thin"><color rgb="FFD0D7E2"/></bottom>
      <diagonal/>
    </border>
  </borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="9">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
    <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
    <xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>
    <xf numFmtId="0" fontId="5" fillId="0" borderId="0" xfId="0" applyFont="1"/>
    <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
    <xf numFmtId="1" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
    <xf numFmtId="1" fontId="5" fillId="3" borderId="0" xfId="0" applyNumberFormat="1" applyFill="1" applyFont="1"/>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment wrapText="1" vertical="center"/></xf>
  </cellXfs>
  <dxfs count="2">
    <dxf><fill><patternFill patternType="solid"><fgColor rgb="FFF4CCCC"/><bgColor rgb="FFF4CCCC"/></patternFill></fill></dxf>
    <dxf><font><color rgb="FF808080"/></font></dxf>
  </dxfs>
</styleSheet>
'@
}

function Add-WorkbookPart {
    param($Archive, [string]$Name, [string]$Content)
    $entry = $Archive.CreateEntry($Name, [IO.Compression.CompressionLevel]::Optimal)
    $stream = $entry.Open()
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Content)
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally { $stream.Dispose() }
}

function Add-ReviewRow {
    param($List, [object[]]$Cells)
    [void]$List.Add($Cells)
}

function New-HeaderRow {
    param([string[]]$Headers)
    $cells = New-Object System.Collections.Generic.List[object]
    foreach ($header in $Headers) {
        $cells.Add(@{ Style = 1; Type = 'text'; Value = $header })
    }
    return , $cells.ToArray()
}

function Export-AccessReviewWorkbook {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$TenantName,
        [string]$PrimaryDomain,
        [Parameter(Mandatory)][datetime]$Generated,
        $Rows,
        [bool]$IncludeSummary,
        $SecurityDefaults,
        $CaPolicies,
        [bool]$SignInAvailable,
        [bool]$RegistrationKnown
    )
    $facts = @(Get-AccessReviewFactColumn)
    $sorted = @(Sort-AccessReviewRow $Rows)
    $stampText = $Generated.ToString('yyyy-MM-dd HH:mm')
    $headerLeft = 'M365 access review - ' + $TenantName
    $footer = $TenantName
    if ($PrimaryDomain) { $footer = $TenantName + ' (' + $PrimaryDomain + ')' }

    $userRows = New-Object System.Collections.Generic.List[object]
    Add-ReviewRow -List $userRows -Cells (New-HeaderRow ($facts | ForEach-Object { $_.Header }))
    foreach ($row in $sorted) {
        $cells = New-Object System.Collections.Generic.List[object]
        foreach ($column in $facts) {
            $cells.Add((Get-FactCell -Row $row -Column $column))
        }
        Add-ReviewRow -List $userRows -Cells $cells.ToArray()
    }
    $userWidths = @($facts | ForEach-Object { [int]$_.Width })
    $userXml = Get-WorksheetXml -Widths $userWidths -Rows $userRows.ToArray() -FreezeCell 'A2' -TableName 'AccessReviewUsers' -Conditional (Get-FactConditionalXml -Columns $facts -LastRow $userRows.Count) -HeaderLeft $headerLeft -FooterLeft $footer

    $sheetXml = New-Object System.Collections.Generic.List[object]
    $tableXml = $null
    $sheetXml.Add([pscustomobject]@{ Name = 'Users'; Xml = $userXml; Table = ($userRows.Count -ge 2) })
    if ($userRows.Count -ge 2) {
        $tableXml = Get-TableXml -Name 'AccessReviewUsers' -Headers @($facts | ForEach-Object { $_.Header }) -LastRow $userRows.Count
    }
    if ($IncludeSummary) {
        $enabled = @($sorted | Where-Object { $_.AccountEnabled })
        $notEnforced = @($enabled | Where-Object { -not $_.MfaEnabled }).Count
        $summary = New-Object System.Collections.Generic.List[object]
        Add-ReviewRow -List $summary -Cells @(
            @{ Style = 2; Type = 'text'; Value = 'M365 access review' }, $null, $null, $null
        )
        Add-ReviewRow -List $summary -Cells @($null, $null, $null, $null)
        Add-ReviewRow -List $summary -Cells @(
            @{ Style = 4; Type = 'text'; Value = 'Tenant' },
            @{ Style = 0; Type = 'text'; Value = $TenantName }, $null, $null
        )
        Add-ReviewRow -List $summary -Cells @(
            @{ Style = 4; Type = 'text'; Value = 'Primary domain' },
            @{ Style = 0; Type = 'text'; Value = $PrimaryDomain }, $null, $null
        )
        Add-ReviewRow -List $summary -Cells @(
            @{ Style = 4; Type = 'text'; Value = 'Generated' },
            @{ Style = 0; Type = 'text'; Value = $stampText }, $null, $null
        )
        Add-ReviewRow -List $summary -Cells @($null, $null, $null, $null)
        Add-ReviewRow -List $summary -Cells @(@{ Style = 3; Type = 'text'; Value = 'Counts' }, $null, $null, $null)
        Add-ReviewRow -List $summary -Cells @(
            @{ Style = 1; Type = 'text'; Value = 'Metric' },
            @{ Style = 1; Type = 'text'; Value = 'Count' }, $null, $null
        )
        $countRows = @(
            @{ Name = 'Total users'; Value = @($sorted).Count; Gap = $false }
            @{ Name = 'Enabled'; Value = @($enabled).Count; Gap = $false }
            @{ Name = 'Disabled'; Value = @($sorted | Where-Object { -not $_.AccountEnabled }).Count; Gap = $false }
            @{ Name = 'Guests'; Value = @($sorted | Where-Object { $_.UserType -eq 'Guest' }).Count; Gap = $false }
            @{ Name = 'With a mailbox'; Value = @($sorted | Where-Object { $_.HasMailbox }).Count; Gap = $false }
            @{ Name = 'Enabled, MFA not enforced'; Value = $notEnforced; Gap = ($notEnforced -gt 0) }
        )
        if ($RegistrationKnown) {
            $notRegistered = @($enabled | Where-Object { $null -ne $_.MfaRegistered -and -not [bool]$_.MfaRegistered }).Count
            $countRows += @{ Name = 'Enabled, MFA not registered'; Value = $notRegistered; Gap = ($notRegistered -gt 0) }
        }
        foreach ($count in $countRows) {
            $style = 6
            if ($count.Gap) { $style = 7 }
            Add-ReviewRow -List $summary -Cells @(
                @{ Style = 0; Type = 'text'; Value = $count.Name },
                @{ Style = $style; Type = 'number'; Value = $count.Value }, $null, $null
            )
        }
        Add-ReviewRow -List $summary -Cells @($null, $null, $null, $null)
        Add-ReviewRow -List $summary -Cells @(@{ Style = 3; Type = 'text'; Value = 'Tenant MFA enforcement' }, $null, $null, $null)
        $defaults = 'Unknown'
        if ($SecurityDefaults -eq $true) { $defaults = 'Enabled' }
        elseif ($SecurityDefaults -eq $false) { $defaults = 'Disabled' }
        Add-ReviewRow -List $summary -Cells @(
            @{ Style = 4; Type = 'text'; Value = 'Security defaults' },
            @{ Style = 0; Type = 'text'; Value = $defaults }, $null, $null
        )
        Add-ReviewRow -List $summary -Cells @($null, $null, $null, $null)
        Add-ReviewRow -List $summary -Cells @(@{ Style = 3; Type = 'text'; Value = 'Conditional Access policies that require MFA' }, $null, $null, $null)
        Add-ReviewRow -List $summary -Cells @(
            @{ Style = 1; Type = 'text'; Value = 'Policy' },
            @{ Style = 1; Type = 'text'; Value = 'State' },
            @{ Style = 1; Type = 'text'; Value = 'App scope' }, $null
        )
        $policies = @($CaPolicies)
        if ($policies.Count -eq 0) {
            Add-ReviewRow -List $summary -Cells @(
                @{ Style = 0; Type = 'text'; Value = 'None found' }, $null, $null, $null
            )
        }
        else {
            foreach ($policy in $policies) {
                Add-ReviewRow -List $summary -Cells @(
                    @{ Style = 0; Type = 'text'; Value = [string]$policy.DisplayName },
                    @{ Style = 0; Type = 'text'; Value = [string]$policy.State },
                    @{ Style = 0; Type = 'text'; Value = [string]$policy.Scope }, $null
                )
            }
        }
        Add-ReviewRow -List $summary -Cells @($null, $null, $null, $null)
        Add-ReviewRow -List $summary -Cells @(
            @{ Style = 4; Type = 'text'; Value = 'MFA enforced counts per-user MFA, Security Defaults, and enabled Conditional Access policies. Report-only policies are listed and do not count. Partial means the policy does not target every cloud app.' },
            $null, $null, $null
        )
        $summaryXml = Get-WorksheetXml -Widths @(42, 22, 20, 36) -Rows $summary.ToArray() -Merges @('A1:D1') -HeaderLeft $headerLeft -FooterLeft $footer -TabColor 'FF1F4E79'
        $sheetXml.Add([pscustomobject]@{ Name = 'Summary'; Xml = $summaryXml; Table = $false })

        $suggestions = @(Get-AccessReviewSuggestion -Rows $sorted -RegistrationKnown $RegistrationKnown)
        $suggestRows = New-Object System.Collections.Generic.List[object]
        $suggestRows.Add((New-HeaderRow @('Suggestion', 'Last name', 'First name', 'Username')))
        if ($suggestions.Count -eq 0) {
            $none = 'No suggestions. Every enabled account has MFA enforced.'
            if (-not $RegistrationKnown) { $none += ' MFA registration was not available.' }
            Add-ReviewRow -List $suggestRows -Cells @(
                @{ Style = 8; Type = 'text'; Value = $none }, $null, $null, $null
            )
        }
        else {
            foreach ($item in $suggestions) {
                Add-ReviewRow -List $suggestRows -Cells @(
                    @{ Style = 8; Type = 'text'; Value = $item.Suggestion },
                    @{ Style = 0; Type = 'text'; Value = [string]$item.Lastname },
                    @{ Style = 0; Type = 'text'; Value = [string]$item.Firstname },
                    @{ Style = 0; Type = 'text'; Value = [string]$item.Username }
                )
            }
        }
        $suggestXml = Get-WorksheetXml -Widths @(72, 20, 16, 36) -Rows $suggestRows.ToArray() -FreezeCell 'A2' -HeaderLeft $headerLeft -FooterLeft $footer -TabColor 'FFC65911'
        $sheetXml.Add([pscustomobject]@{ Name = 'Suggestions'; Xml = $suggestXml; Table = $false })
    }

    $folder = Split-Path -Parent $Path
    if ($folder -and -not (Test-Path -LiteralPath $folder)) {
        $null = New-Item -ItemType Directory -Path $folder -Force
    }
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $contentTypes = New-Object System.Text.StringBuilder
        [void]$contentTypes.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        [void]$contentTypes.Append('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
        [void]$contentTypes.Append('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
        [void]$contentTypes.Append('<Default Extension="xml" ContentType="application/xml"/>')
        [void]$contentTypes.Append('<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
        [void]$contentTypes.Append('<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>')
        [void]$contentTypes.Append('<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>')
        [void]$contentTypes.Append('<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>')
        for ($i = 0; $i -lt $sheetXml.Count; $i++) {
            [void]$contentTypes.Append('<Override PartName="/xl/worksheets/sheet' + ($i + 1) + '.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>')
        }
        if ($tableXml) {
            [void]$contentTypes.Append('<Override PartName="/xl/tables/table1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.table+xml"/>')
        }
        [void]$contentTypes.Append('</Types>')

        $rootRels = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>
'@
        $wb = New-Object System.Text.StringBuilder
        [void]$wb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        [void]$wb.Append('<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')
        [void]$wb.Append('<workbookViews><workbookView activeTab="0"/></workbookViews><sheets>')
        $wbRels = New-Object System.Text.StringBuilder
        [void]$wbRels.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        [void]$wbRels.Append('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">')
        for ($i = 0; $i -lt $sheetXml.Count; $i++) {
            $safeName = ConvertTo-SpreadsheetText $sheetXml[$i].Name
            [void]$wb.Append('<sheet name="' + $safeName + '" sheetId="' + ($i + 1) + '" r:id="rId' + ($i + 1) + '"/>')
            [void]$wbRels.Append('<Relationship Id="rId' + ($i + 1) + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet' + ($i + 1) + '.xml"/>')
        }
        $styleId = $sheetXml.Count + 1
        [void]$wbRels.Append('<Relationship Id="rId' + $styleId + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>')
        [void]$wb.Append('</sheets></workbook>')
        [void]$wbRels.Append('</Relationships>')

        $created = $Generated.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $core = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>' + (ConvertTo-SpreadsheetText ('M365 access review - ' + $TenantName)) + '</dc:title><dc:creator>mytools</dc:creator><cp:lastModifiedBy>mytools</cp:lastModifiedBy><dcterms:created xsi:type="dcterms:W3CDTF">' + $created + '</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">' + $created + '</dcterms:modified></cp:coreProperties>'
        $app = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>mytools</Application></Properties>'

        Add-WorkbookPart $zip '[Content_Types].xml' $contentTypes.ToString()
        Add-WorkbookPart $zip '_rels/.rels' $rootRels
        Add-WorkbookPart $zip 'docProps/core.xml' $core
        Add-WorkbookPart $zip 'docProps/app.xml' $app
        Add-WorkbookPart $zip 'xl/workbook.xml' $wb.ToString()
        Add-WorkbookPart $zip 'xl/_rels/workbook.xml.rels' $wbRels.ToString()
        Add-WorkbookPart $zip 'xl/styles.xml' (Get-StylesXml)
        for ($i = 0; $i -lt $sheetXml.Count; $i++) {
            Add-WorkbookPart $zip ('xl/worksheets/sheet' + ($i + 1) + '.xml') $sheetXml[$i].Xml
            if ($sheetXml[$i].Table -and $tableXml) {
                $sheetRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/table" Target="../tables/table1.xml"/></Relationships>'
                Add-WorkbookPart $zip ('xl/worksheets/_rels/sheet' + ($i + 1) + '.xml.rels') $sheetRels
            }
        }
        if ($tableXml) { Add-WorkbookPart $zip 'xl/tables/table1.xml' $tableXml }
    }
    finally { $zip.Dispose() }
}

if ($MyInvocation.InvocationName -eq '.') { return }

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    throw 'Microsoft.Graph is not installed. Run: Install-Module Microsoft.Graph -Scope CurrentUser'
}
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module Microsoft.Graph.Users -ErrorAction SilentlyContinue
Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction SilentlyContinue
Import-Module Microsoft.Graph.Identity.SignIns -ErrorAction SilentlyContinue
Import-Module Microsoft.Graph.Reports -ErrorAction SilentlyContinue

$scopes = @(
    'User.Read.All'
    'Directory.Read.All'
    'AuditLog.Read.All'
    'UserAuthenticationMethod.Read.All'
    'Policy.Read.All'
    'MailboxSettings.Read'
)
$script:GraphOpened = $false
$script:ExoOpened = $false
try {
    $context = Get-MgContext
    $signedIn = $false
    if ($context) {
        $have = @($context.Scopes)
        $signedIn = $true
        foreach ($scope in $scopes) {
            $found = $false
            foreach ($existing in $have) {
                if ([string]$existing -match [regex]::Escape($scope)) { $found = $true; break }
            }
            if (-not $found) { $signedIn = $false; break }
        }
    }
    if (-not $signedIn) {
        $connect = @{ Scopes = $scopes; NoWelcome = $true }
        if (-not [string]::IsNullOrWhiteSpace($TenantId)) { $connect['TenantId'] = $TenantId }
        Write-Host 'Connecting to Microsoft Graph...'
        Connect-MgGraph @connect
        $script:GraphOpened = $true
    }

    $org = @(Get-MgOrganization) | Select-Object -First 1
    $tenantName = [string]$org.DisplayName
    if ([string]::IsNullOrWhiteSpace($tenantName)) { $tenantName = 'tenant' }
    $primary = @($org.VerifiedDomains | Where-Object { $_.IsDefault }) | Select-Object -First 1
    $primaryDomain = [string]$primary.Name
    Write-Host ("Connected to: {0} ({1})" -f $tenantName, $primaryDomain)

    $exoConnected = $false
    if (-not $SkipExchange) {
        if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
            Write-Warning 'ExchangeOnlineManagement is not installed. Mailbox type and last activity will be blank unless Graph can see the mailbox.'
        }
        else {
            Import-Module ExchangeOnlineManagement -ErrorAction Stop
            try {
                Write-Host 'Connecting to Exchange Online...'
                try { Connect-ExchangeOnline -ShowBanner:$false -DisableWAM }
                catch {
                    Write-Warning 'Exchange sign-in with -DisableWAM failed. Trying device code.'
                    Connect-ExchangeOnline -ShowBanner:$false -Device
                }
                $exoConnected = $true
                $script:ExoOpened = $true
            }
            catch {
                Write-Warning 'Exchange Online connect failed. Falling back to a Graph mailbox probe.'
            }
        }
    }

    Write-Host 'Pulling users...'
    $userProps = @('Id', 'DisplayName', 'GivenName', 'Surname', 'UserPrincipalName', 'UserType', 'AccountEnabled', 'AssignedLicenses', 'SignInActivity')
    $signInAvailable = $true
    try {
        $users = @(Get-MgUser -All -Property $userProps | Select-Object $userProps)
    }
    catch {
        Write-Warning 'Sign-in activity was not readable. Last sign-in will be blank.'
        $signInAvailable = $false
        $userProps = @($userProps | Where-Object { $_ -ne 'SignInActivity' })
        $users = @(Get-MgUser -All -Property $userProps | Select-Object $userProps)
    }
    Write-Host ("  {0} users" -f $users.Count)

    $skuMap = @{}
    Get-MgSubscribedSku -All | ForEach-Object { $skuMap[$_.SkuId.ToString()] = [string]$_.SkuPartNumber }

    $mailboxMap = @{}
    if ($exoConnected) {
        Write-Host 'Pulling mailboxes...'
        $mailboxes = @(Get-EXOMailbox -ResultSize Unlimited -Properties ExternalDirectoryObjectId, RecipientTypeDetails)
        $mbIndex = 0
        foreach ($mb in $mailboxes) {
            $mbIndex++
            if (($mbIndex % 25) -eq 0) { Write-Host ("  mailbox activity {0} / {1}" -f $mbIndex, $mailboxes.Count) }
            $lastAction = $null
            try {
                $lastAction = (Get-EXOMailboxStatistics -Identity $mb.ExternalDirectoryObjectId -Properties LastUserActionTime).LastUserActionTime
            }
            catch { }
            $mailboxMap[$mb.ExternalDirectoryObjectId.ToString()] = [pscustomobject]@{
                Type       = [string]$mb.RecipientTypeDetails
                LastAction = $lastAction
            }
        }
        Write-Host ("  {0} mailboxes" -f $mailboxes.Count)
    }
    else {
        Write-Host 'Probing mailboxes...'
        $mbIndex = 0
        foreach ($u in $users) {
            $mbIndex++
            if (($mbIndex % 25) -eq 0) { Write-Host ("  mailbox probe {0} / {1}" -f $mbIndex, $users.Count) }
            try {
                Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($u.Id)/mailboxSettings" | Out-Null
                $mailboxMap[$u.Id.ToString()] = [pscustomobject]@{ Type = 'Mailbox (type unknown)'; LastAction = $null }
            }
            catch { }
        }
    }

    Write-Host 'Pulling MFA registration...'
    $mfaMap = @{}
    $registrationKnown = $true
    try {
        Get-MgReportAuthenticationMethodUserRegistrationDetail -All | ForEach-Object { $mfaMap[$_.Id.ToString()] = $_ }
    }
    catch {
        Write-Warning 'MFA registration was not readable. That column will be blank.'
        $registrationKnown = $false
    }

    Write-Host 'Pulling per-user MFA...'
    $perUserMfa = @{}
    $userIndex = 0
    foreach ($u in $users) {
        $userIndex++
        if (($userIndex % 25) -eq 0) { Write-Host ("  per-user MFA {0} / {1}" -f $userIndex, $users.Count) }
        try {
            $req = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/users/$($u.Id)/authentication/requirements"
            $perUserMfa[$u.Id.ToString()] = [string]$req.perUserMfaState
        }
        catch { $perUserMfa[$u.Id.ToString()] = '' }
    }

    $secDefaults = $null
    try {
        $defaultsPolicy = Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy
        if ($null -ne $defaultsPolicy.IsEnabled) { $secDefaults = [bool]$defaultsPolicy.IsEnabled }
    }
    catch { }
    $mfaCaPolicies = @()
    try {
        $mfaCaPolicies = @(Get-MgIdentityConditionalAccessPolicy -All | Where-Object {
            $_.GrantControls.BuiltInControls -contains 'mfa' -or $_.GrantControls.AuthenticationStrength.Id
        })
    }
    catch { Write-Warning 'Conditional Access policies were not readable.' }
    $enforcingCa = @($mfaCaPolicies | Where-Object { $_.State -eq 'enabled' })

    $script:AccessReviewUserGroups = @{}
    $script:AccessReviewUserRoles = @{}
    if ($enforcingCa.Count -gt 0) {
        Write-Host 'Pulling group and role membership...'
        $userIndex = 0
        foreach ($u in $users) {
            $userIndex++
            if (($userIndex % 25) -eq 0) { Write-Host ("  membership {0} / {1}" -f $userIndex, $users.Count) }
            $groups = New-Object 'System.Collections.Generic.HashSet[string]'
            $roles = New-Object 'System.Collections.Generic.HashSet[string]'
            try {
                Get-MgUserTransitiveMemberOf -UserId $u.Id -All | ForEach-Object {
                    $kind = [string]$_.AdditionalProperties.'@odata.type'
                    if ($kind -eq '#microsoft.graph.group') { [void]$groups.Add($_.Id.ToString()) }
                    elseif ($kind -eq '#microsoft.graph.directoryRole') {
                        $template = [string]$_.AdditionalProperties.roleTemplateId
                        if ($template) { [void]$roles.Add($template) }
                    }
                }
            }
            catch { }
            $script:AccessReviewUserGroups[$u.Id.ToString()] = $groups
            $script:AccessReviewUserRoles[$u.Id.ToString()] = $roles
        }
    }

    Write-Host 'Building the workbook...'
    $now = Get-Date
    $built = foreach ($u in $users) {
        $id = $u.Id.ToString()
        $latest = $null
        if ($signInAvailable -and $u.SignInActivity) {
            $latest = @(
                $u.SignInActivity.LastSignInDateTime,
                $u.SignInActivity.LastNonInteractiveSignInDateTime,
                $u.SignInActivity.LastSuccessfulSignInDateTime
            ) | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1
        }
        $mb = $mailboxMap[$id]
        $mfa = $mfaMap[$id]
        $enforcedBy = New-Object System.Collections.Generic.List[string]
        $pu = [string]$perUserMfa[$id]
        if ($pu -match '^(?i)enabled$|^(?i)enforced$') { $enforcedBy.Add("Per-user ($pu)") }
        if ($secDefaults) { $enforcedBy.Add('Security Defaults') }
        foreach ($policy in $enforcingCa) {
            if (Test-CaPolicyAppliesToUser -Policy $policy -User $u) {
                $note = ''
                if ((Get-CaAppScope $policy) -eq 'Partial') { $note = ' (partial app scope)' }
                $enforcedBy.Add(('CA: {0}{1}' -f $policy.DisplayName, $note))
            }
        }
        $registered = $null
        if ($registrationKnown -and $mfa) { $registered = [bool]$mfa.IsMfaRegistered }
        $methods = ''
        if ($registrationKnown -and $mfa) { $methods = @($mfa.MethodsRegistered) -join '; ' }
        $licenses = @($u.AssignedLicenses | ForEach-Object {
            $sku = $_.SkuId.ToString()
            if ($skuMap.ContainsKey($sku)) { Format-AccessReviewLicense $skuMap[$sku] } else { $sku }
        }) -join '; '
        [pscustomobject]@{
            Lastname              = [string]$u.Surname
            Firstname             = [string]$u.GivenName
            DisplayName           = [string]$u.DisplayName
            Username              = [string]$u.UserPrincipalName
            AccountEnabled        = [bool]$u.AccountEnabled
            UserType              = [string]$u.UserType
            HasMailbox            = [bool]$mb
            MailboxType           = $(if ($mb) { [string]$mb.Type } else { '' })
            LastSignIn            = $(if ($latest) { [datetime]$latest } else { $null })
            NeverSignedIn         = [bool]($signInAvailable -and -not $latest)
            DaysSinceLastSignIn   = $(if ($latest) { [int]($now - [datetime]$latest).TotalDays } else { $null })
            MailboxLastUserAction = $(if ($mb -and $mb.LastAction) { [datetime]$mb.LastAction } else { $null })
            MfaEnabled            = [bool]($enforcedBy.Count -gt 0)
            MfaEnforcedBy         = ($enforcedBy -join '; ')
            MfaRegistered         = $registered
            MfaMethods            = $methods
            PerUserMfaState       = $pu
            Licenses              = $licenses
        }
    }

    if (-not $OutputFolder) {
        $root = Get-AccessReviewOneDriveRoot
        if (-not $root) {
            Write-Warning 'No local OneDrive path is set. Saving the workbook under Documents instead.'
            $root = [Environment]::GetFolderPath('MyDocuments')
        }
        $OutputFolder = Join-Path $root (Join-Path 'EntraIntuneEvidence' (Join-Path (Get-AccessReviewFolderName $tenantName) $now.ToString('yyyyMMdd-HHmmss')))
    }
    $null = New-Item -ItemType Directory -Path $OutputFolder -Force
    $xlsxPath = Join-Path $OutputFolder ('{0}_M365-AccessReview_{1}.xlsx' -f (Get-AccessReviewFolderName $tenantName), $now.ToString('yyyy-MM-dd'))
    $policyRows = @($mfaCaPolicies | ForEach-Object {
        [pscustomobject]@{
            DisplayName = [string]$_.DisplayName
            State       = [string]$_.State
            Scope       = (Get-CaAppScope $_)
        }
    })
    Export-AccessReviewWorkbook -Path $xlsxPath -TenantName $tenantName -PrimaryDomain $primaryDomain -Generated $now -Rows $built -IncludeSummary:([bool]$IncludeSummary) -SecurityDefaults $secDefaults -CaPolicies $policyRows -SignInAvailable $signInAvailable -RegistrationKnown $registrationKnown

    Write-Host ("Users: {0}" -f @($built).Count)
    if ($IncludeSummary) {
        $enabledRows = @($built | Where-Object { $_.AccountEnabled })
        Write-Host ("Enabled, MFA not enforced: {0}" -f @($enabledRows | Where-Object { -not $_.MfaEnabled }).Count)
        if ($registrationKnown) {
            Write-Host ("Enabled, MFA not registered: {0}" -f @($enabledRows | Where-Object { $null -ne $_.MfaRegistered -and -not $_.MfaRegistered }).Count)
        }
        $defaultsText = 'Unknown'
        if ($secDefaults -eq $true) { $defaultsText = 'Enabled' }
        elseif ($secDefaults -eq $false) { $defaultsText = 'Disabled' }
        Write-Host ("Security defaults: {0}" -f $defaultsText)
    }
    Write-Host ("Exported: {0}" -f $xlsxPath)
}
finally {
    if ($script:ExoOpened) {
        try { Disconnect-ExchangeOnline -Confirm:$false | Out-Null } catch { }
    }
    if ($script:GraphOpened) {
        try { Disconnect-MgGraph | Out-Null } catch { }
    }
}
if ($Exit -and -not $NoExit) { exit 0 }
