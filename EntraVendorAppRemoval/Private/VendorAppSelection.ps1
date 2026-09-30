# Catalog names and example IDs. The GUID on a vendor enterprise app is different
# in each tenant (per-customer app registration, or a service principal object
# id). Discovery matches the display name. ExampleId is only an extra exact
# match for appId or object id when the name was renamed.

function Get-VendorEnterpriseAppCatalog {
    @(
        [pscustomobject]@{ Vendor = 'Inky'; VendorLabel = 'INKY'; Name = 'INKY Phish Fence - Installation'; ExampleId = '939be9d0-ed9f-48df-8867-f04004e7e460' }
        [pscustomobject]@{ Vendor = 'Inky'; VendorLabel = 'INKY'; Name = 'Inky Dashboard SSO'; ExampleId = '35343bd4-37f5-410b-bb69-fd23e9da03a6' }
        [pscustomobject]@{ Vendor = 'Inky'; VendorLabel = 'INKY'; Name = 'INKY Phish Fence - Directory Synchronization'; ExampleId = 'f02bffa3-76d9-41d3-8452-3d548c1290b7' }
        [pscustomobject]@{ Vendor = 'Inky'; VendorLabel = 'INKY'; Name = 'Inky Phish Fence Remediation'; ExampleId = 'dadbac07-d008-4b2d-b954-732074411c81' }
        [pscustomobject]@{ Vendor = 'Inky'; VendorLabel = 'INKY'; Name = 'INKY - Setup and Maintenance'; ExampleId = '0fdacf15-7cc1-4477-82df-b88e0ce107f3' }
        [pscustomobject]@{ Vendor = 'Usecure'; VendorLabel = 'usecure'; Name = 'usecure'; ExampleId = 'ccfeac09-c6ae-4dd7-b621-2f3c0bcf72d5' }
        [pscustomobject]@{ Vendor = 'Usecure'; VendorLabel = 'usecure'; Name = 'usecure - Message Injection'; ExampleId = '24decd76-8045-478f-b5d5-35b6b254d0d0' }
        [pscustomobject]@{ Vendor = 'Barracuda'; VendorLabel = 'Barracuda (Skout)'; Name = 'Skout Cybersecurity'; ExampleId = '9ad0f9b6-8ca4-4839-b1c8-061bad20e8da' }
    )
}

function Resolve-VendorAppCategory {
    param(
        [string]$DisplayName,
        [string]$AppId,
        [string]$ObjectId,
        $Catalog
    )

    $name = [string]$DisplayName
    $fromName = $null
    if ($name -match '(?i)phish\s*fence|\binky\b') {
        $fromName = 'Inky'
    }
    elseif ($name -match '(?i)u-?secure') {
        $fromName = 'Usecure'
    }
    elseif ($name -match '(?i)\bskout\b' -or ($name -match '(?i)barracuda' -and $name -match '(?i)cybersecurity')) {
        $fromName = 'Barracuda'
    }

    if ($fromName) { return $fromName }

    $candidates = @($AppId, $ObjectId) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($item in @($Catalog)) {
        foreach ($candidate in $candidates) {
            if ([string]$item.ExampleId -eq [string]$candidate) {
                return [string]$item.Vendor
            }
        }
    }

    return $null
}

function Add-VendorAppMenuNumbers {
    param($Apps)

    $n = 0
    foreach ($app in @($Apps)) {
        if ($app.Found) {
            $n++
            $app | Add-Member -NotePropertyName Number -NotePropertyValue $n -Force
        }
        else {
            $app | Add-Member -NotePropertyName Number -NotePropertyValue $null -Force
        }
    }
    return @($Apps)
}

function ConvertFrom-VendorAppSelection {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$InputText,

        [AllowEmptyCollection()]
        [object[]]$NumberedApps = @()
    )

    $text = if ($null -eq $InputText) { '' } else { $InputText.Trim() }
    if ([string]::IsNullOrWhiteSpace($text)) {
        return [pscustomobject]@{ Action = 'Invalid'; AppIds = @(); Message = 'Enter a selection.' }
    }
    if ($text -match '^(?i)q(uit)?$') {
        return [pscustomobject]@{ Action = 'Quit'; AppIds = @(); Message = '' }
    }

    $numbered = @($NumberedApps | Where-Object { $null -ne $_.Number })
    $byNumber = @{}
    foreach ($app in $numbered) {
        $byNumber[[string][int]$app.Number] = $app
    }

    if ($text -match '^(?i)all$') {
        if ($byNumber.Count -eq 0) {
            return [pscustomobject]@{ Action = 'Invalid'; AppIds = @(); Message = 'Nothing is in this tenant.' }
        }
        return [pscustomobject]@{ Action = 'Select'; AppIds = @($numbered | ForEach-Object { [string]$_.AppId }); Message = '' }
    }

    $vendorMap = @{
        'inky'       = 'Inky'
        'usecure'    = 'Usecure'
        'u-secure'   = 'Usecure'
        'barracuda'  = 'Barracuda'
        'skout'      = 'Barracuda'
    }
    $key = $text.ToLowerInvariant()
    if ($vendorMap.ContainsKey($key)) {
        $vendor = $vendorMap[$key]
        $hits = @($numbered | Where-Object { $_.Vendor -eq $vendor })
        if ($hits.Count -eq 0) {
            return [pscustomobject]@{ Action = 'Invalid'; AppIds = @(); Message = "No $vendor apps are in this tenant." }
        }
        return [pscustomobject]@{ Action = 'Select'; AppIds = @($hits | ForEach-Object { [string]$_.AppId }); Message = '' }
    }

    $tokens = @($text -split '[,\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($token in $tokens) {
        $range = [regex]::Match($token, '^(\d+)-(\d+)$')
        if ($range.Success) {
            $start = [int]$range.Groups[1].Value
            $end = [int]$range.Groups[2].Value
            if ($end -lt $start) {
                return [pscustomobject]@{ Action = 'Invalid'; AppIds = @(); Message = "Range $token is backwards." }
            }
            for ($n = $start; $n -le $end; $n++) {
                $keyN = [string]$n
                if (-not $byNumber.ContainsKey($keyN)) {
                    return [pscustomobject]@{ Action = 'Invalid'; AppIds = @(); Message = "Number $n is not in the list." }
                }
                [void]$ids.Add([string]$byNumber[$keyN].AppId)
            }
            continue
        }

        if ($token -match '^\d+$') {
            if (-not $byNumber.ContainsKey([string][int]$token)) {
                return [pscustomobject]@{ Action = 'Invalid'; AppIds = @(); Message = "Number $token is not in the list." }
            }
            [void]$ids.Add([string]$byNumber[[string][int]$token].AppId)
            continue
        }

        return [pscustomobject]@{
            Action  = 'Invalid'
            AppIds  = @()
            Message = "Could not read '$token'. Use numbers (1,3 or 1-3), a vendor name, all, or q."
        }
    }

    $unique = @($ids | Select-Object -Unique)
    return [pscustomobject]@{ Action = 'Select'; AppIds = $unique; Message = '' }
}
