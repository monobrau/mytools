function New-Finding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Module,

        [Parameter(Mandatory)]
        [ValidateSet('High', 'Medium', 'Low', 'Info')]
        [string] $Severity,

        [Parameter(Mandatory)]
        [string] $ObjectType,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Identifier,

        [Parameter(Mandatory)]
        [string] $Detail,

        [hashtable] $Evidence = @{},

        # object (not [datetime]) so $null is a valid "no activity" value
        [object] $LastActivity = $null,

        [ValidateSet('Revoke', 'Disable', 'Review', 'None')]
        [string] $Recommended = 'Review',

        [bool] $AutoSafe = $false
    )

    if ($null -ne $LastActivity -and $LastActivity -isnot [datetime]) {
        throw "LastActivity must be DateTime or `$null. Got: $($LastActivity.GetType().FullName)"
    }

    [pscustomobject]@{
        Module       = $Module
        Severity     = $Severity
        ObjectType   = $ObjectType
        Name         = $Name
        Identifier   = $Identifier
        Detail       = $Detail
        Evidence     = $Evidence
        LastActivity = $LastActivity
        Recommended  = $Recommended
        AutoSafe     = $AutoSafe
    }
}

function Test-VendorPatternMatch {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [string[]] $Patterns
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    foreach ($pattern in $Patterns) {
        if ($Text -match "(?i)$pattern") {
            return $true
        }
    }

    return $false
}

function Get-OffboardingConfig {
    [CmdletBinding()]
    param(
        [string] $ConfigPath,
        [string] $DefaultConfigPath
    )

    $defaults = @{
        vendorPatterns             = @(
            'barracuda'
            'skout'
            'cudamail'
            'cudasvc'
            'ess\.barracuda'
            'barracudanetworks'
        )
        knownGoodServicePrincipals = @()
        knownGoodTransportRules    = @()
        clientNotes                = ''
    }

    $config = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $defaults.Keys) {
        $config[$key] = $defaults[$key]
    }

    $paths = @()
    if ($DefaultConfigPath -and (Test-Path -LiteralPath $DefaultConfigPath)) {
        $paths += $DefaultConfigPath
    }
    if ($ConfigPath) {
        if (-not (Test-Path -LiteralPath $ConfigPath)) {
            throw "Config file not found: $ConfigPath"
        }
        $paths += $ConfigPath
    }

    foreach ($path in $paths) {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($raw.vendorPatterns) {
            $merged = [System.Collections.Generic.List[string]]::new()
            foreach ($p in $config.vendorPatterns) { [void]$merged.Add([string]$p) }
            foreach ($p in @($raw.vendorPatterns)) {
                if ($p -and -not ($merged -contains [string]$p)) {
                    [void]$merged.Add([string]$p)
                }
            }
            $config.vendorPatterns = @($merged.ToArray())
        }
        if ($null -ne $raw.knownGoodServicePrincipals) {
            $kg = [System.Collections.Generic.List[string]]::new()
            foreach ($p in @($config.knownGoodServicePrincipals)) { if ($p) { [void]$kg.Add([string]$p) } }
            foreach ($p in @($raw.knownGoodServicePrincipals)) {
                if ($p -and -not ($kg -contains [string]$p)) { [void]$kg.Add([string]$p) }
            }
            $config.knownGoodServicePrincipals = @($kg.ToArray())
        }
        if ($null -ne $raw.knownGoodTransportRules) {
            $kg = [System.Collections.Generic.List[string]]::new()
            foreach ($p in @($config.knownGoodTransportRules)) { if ($p) { [void]$kg.Add([string]$p) } }
            foreach ($p in @($raw.knownGoodTransportRules)) {
                if ($p -and -not ($kg -contains [string]$p)) { [void]$kg.Add([string]$p) }
            }
            $config.knownGoodTransportRules = @($kg.ToArray())
        }
        if ($null -ne $raw.clientNotes -and [string]$raw.clientNotes -ne '') {
            $config.clientNotes = [string]$raw.clientNotes
        }
    }

    return $config
}

function ConvertTo-ReportLocalTime {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [datetime] $UtcDateTime
    )

    if ($null -eq $UtcDateTime) {
        return $null
    }

    $utc = [datetime]::SpecifyKind($UtcDateTime.ToUniversalTime(), [System.DateTimeKind]::Utc)
    $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('Central Standard Time')
    $local = [System.TimeZoneInfo]::ConvertTimeFromUtc($utc, $tz)
    $isDst = $tz.IsDaylightSavingTime($local)
    $label = if ($isDst) { 'CDT' } else { 'CST' }
    return '{0:yyyy-MM-dd HH:mm:ss} {1}' -f $local, $label
}

function Get-SanitizedClientName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ClientName
    )

    ($ClientName -replace '[^\w\-]', '_').Trim('_')
}

function Get-DefaultOffboardingOutputRoot {
    <#
    .SYNOPSIS
        Work OneDrive\BarracudaOffboarding, with Desktop fallback if OneDrive is unavailable.
    #>
    [CmdletBinding()]
    param()

    $oneDrive = $null
    if (-not [string]::IsNullOrWhiteSpace($env:OneDriveCommercial) -and (Test-Path -LiteralPath $env:OneDriveCommercial)) {
        $oneDrive = $env:OneDriveCommercial
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:OneDrive) -and (Test-Path -LiteralPath $env:OneDrive)) {
        $oneDrive = $env:OneDrive
    }

    if ($oneDrive) {
        return (Join-Path $oneDrive 'BarracudaOffboarding')
    }

    Write-Warning 'Work OneDrive not found (OneDriveCommercial/OneDrive). Falling back to Desktop\BarracudaOffboarding.'
    return (Join-Path $env:USERPROFILE 'Desktop\BarracudaOffboarding')
}

function Resolve-OffboardingRunDirectory {
    <#
    .SYNOPSIS
        Build per-client run folder: <OutputRoot>\<Client>\<yyyyMMdd_HHmmss>
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ClientName,

        [string] $OutputPath,

        [string] $Timestamp
    )

    $root = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        Get-DefaultOffboardingOutputRoot
    }
    else {
        $OutputPath
    }

    $safeClient = Get-SanitizedClientName -ClientName $ClientName
    if (-not $Timestamp) {
        $Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    }

    $clientDirectory = Join-Path $root $safeClient
    $runDirectory = Join-Path $clientDirectory $Timestamp
    return [pscustomobject]@{
        OutputRoot      = $root
        ClientDirectory = $clientDirectory
        RunDirectory    = $runDirectory
        SafeClientName  = $safeClient
    }
}
