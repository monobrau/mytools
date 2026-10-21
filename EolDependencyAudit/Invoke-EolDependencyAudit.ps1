#Requires -Version 5.1
<#
.SYNOPSIS
    See which processes load out-of-support runtimes, without keeping event text.

.DESCRIPTION
    Measures the Security log, then optionally audits a small set of sentinel
    DLLs (execute/traverse only). Event 4663 is read for process name and
    file name. The script stores hit counts. It does not export event messages.

    Built-in families: VC2005, VC2008, VC2010, VC2012, VC2013, DotNet31,
    DotNet5, DotNet6, DotNet7, DotNet8, Silverlight, Sql2008, Sql2012,
    SqlCompact. DotNet8 is off unless named. Add a family with -CatalogPath
    (see dependencies.example.csv). Private copies outside those folders are
    not seen.

    The approach follows Microsoft's VC++ runtime auditing guidance. This
    script is separate from that sample: it audits sentinel files, caps the
    event read, and refuses to arm auditing when 4663 traffic is already
    above -MaxDailyLogMB per day.

.PARAMETER Action
    Measure  Log size, 4663 pace, installed sentinels, and any hits. No ACL changes.
    Enable   Arm sentinel auditing when the log pace is under the cap.
    Collect  Hit list only. No ACL changes.
    Disable  Remove this script's execute-audit rule from the sentinels.
    Watch    Measure, disarm when over the cap, otherwise arm and collect.

.PARAMETER CheckOnly
    Same as -Action Measure when -Action is omitted.

.PARAMETER Dependency
    Family names to include. Repeat or comma-separate. Omit for every family
    marked EOL. Use All for every built-in family, including DotNet8.

.PARAMETER SampleMinutes
    With Measure, arm auditing, watch the Security log, then remove the rules.
    This is the added-cost check. It is not used by Watch.

.PARAMETER MaxDailyLogMB
    Refuse Enable and Watch when the current 4663 pace is above this many MB/day.
    Default 64. -Force continues anyway.

.PARAMETER SinceHours
    How far back Collect and Measure look for hits. Default 24.

.PARAMETER CatalogPath
    CSV of extra families. A Name that already exists replaces that family.

.PARAMETER Force
    Arm auditing even when the pace is over the cap or the event read hits its cap.

.NOTES
    Exit 0: no selected family was loaded in the window.
    Exit 1: at least one selected family was loaded.
    Exit 2: error.
    Exit 3: auditing was not left armed because the log cap was exceeded.
#>
[CmdletBinding()]
param(
    [string]$Action = '',
    [switch]$CheckOnly,
    [string[]]$Dependency,
    [int]$SinceHours = 24,
    [int]$RateHours = 1,
    [int]$MaxDailyLogMB = 64,
    [int]$SampleMinutes = 0,
    [int]$MaxEvents = 20000,
    [string]$CatalogPath,
    [string]$ReportPath,
    [switch]$Force,
    [switch]$NoExit,
    [switch]$Exit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$script:ExitCode = 0

function Write-Line([string]$Message) {
    Write-Host $Message
    try { [Console]::Out.Flush() } catch { }
}

function Write-Section([string]$Message) {
    Write-Line "=== $Message ==="
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-MB([int64]$Bytes) {
    return ('{0:N1} MB' -f ($Bytes / 1MB))
}

function Get-SafeRoot {
    param([string]$Root)
    if ([string]::IsNullOrWhiteSpace($Root)) { return $null }
    $expanded = [Environment]::ExpandEnvironmentVariables($Root).Trim()
    if (-not (Test-Path -LiteralPath $expanded)) { return $null }
    $full = [IO.Path]::GetFullPath($expanded).TrimEnd('\')
    if ($full -match '^[A-Za-z]:$') { return $null }
    $windows = $env:SystemRoot.TrimEnd('\')
    $blocked = @(
        $windows
        (Join-Path $windows 'WinSxS')
        ([Environment]::GetFolderPath('ProgramFiles'))
        (${env:ProgramFiles(x86)})
    )
    foreach ($block in $blocked) {
        if ($block -and ($full -eq $block.TrimEnd('\'))) { return $null }
    }
    return $full
}

function New-Family {
    param(
        [string]$Name,
        [bool]$Eol,
        [string]$Kind,
        [string[]]$Roots,
        [string]$Names,
        [string]$VersionPrefix,
        [string]$PathMatch
    )
    [pscustomobject]@{
        Name          = $Name
        Eol           = $Eol
        Kind          = $Kind
        Roots         = $Roots
        Names         = $Names
        VersionPrefix = $VersionPrefix
        PathMatch     = $PathMatch
    }
}

function Get-BuiltinCatalog {
    $sys32 = Join-Path $env:SystemRoot 'System32'
    $syswow = Join-Path $env:SystemRoot 'SysWOW64'
    $fusion = Join-Path $env:SystemRoot 'WinSxS\Fusion'
    $dotnet = @(
        (Join-Path $env:ProgramFiles 'dotnet\shared\Microsoft.NETCore.App')
        (Join-Path ${env:ProgramFiles(x86)} 'dotnet\shared\Microsoft.NETCore.App')
    )
    $silver = @(
        (Join-Path $env:ProgramFiles 'Microsoft Silverlight')
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Silverlight')
    )
    $compact = @(
        (Join-Path $env:ProgramFiles 'Microsoft SQL Server Compact Edition\v4.0')
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft SQL Server Compact Edition\v4.0')
    )
    @(
        (New-Family 'VC2005' $true 'Walk' @($fusion) '^(msvcr80|msvcp80)\.dll$' '' 'microsoft\.vc80')
        (New-Family 'VC2008' $true 'Walk' @($fusion) '^(msvcr90|msvcp90)\.dll$' '' 'microsoft\.vc90')
        (New-Family 'VC2010' $true 'File' @($sys32, $syswow) 'msvcr100.dll|msvcp100.dll' '' '')
        (New-Family 'VC2012' $true 'File' @($sys32, $syswow) 'msvcr110.dll|msvcp110.dll' '' '')
        (New-Family 'VC2013' $true 'File' @($sys32, $syswow) 'msvcr120.dll|msvcp120.dll' '' '')
        (New-Family 'DotNet31' $true 'Version' $dotnet 'coreclr.dll' '3.1' '')
        (New-Family 'DotNet5' $true 'Version' $dotnet 'coreclr.dll' '5.' '')
        (New-Family 'DotNet6' $true 'Version' $dotnet 'coreclr.dll' '6.' '')
        (New-Family 'DotNet7' $true 'Version' $dotnet 'coreclr.dll' '7.' '')
        (New-Family 'DotNet8' $false 'Version' $dotnet 'coreclr.dll' '8.' '')
        (New-Family 'Silverlight' $true 'Walk' $silver '^(npctrl|coreclr)\.dll$' '' '')
        (New-Family 'Sql2008' $true 'File' @($sys32, $syswow) 'sqlncli10.dll' '' '')
        (New-Family 'Sql2012' $true 'File' @($sys32, $syswow) 'sqlncli11.dll' '' '')
        (New-Family 'SqlCompact' $true 'File' $compact 'sqlceqp40.dll' '' '')
    )
}

function Import-ExtraCatalog {
    param([string]$Path, [object[]]$Catalog)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Catalog }
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Line "Catalog not found: $Path"
        $script:ExitCode = 2
        return $Catalog
    }
    $rows = @(Import-Csv -LiteralPath $Path)
    $byName = @{}
    foreach ($item in $Catalog) { $byName[$item.Name.ToLowerInvariant()] = $item }
    foreach ($row in $rows) {
        $name = [string]$row.Name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($name -notmatch '^[A-Za-z][A-Za-z0-9]{0,31}$') {
            Write-Line "Catalog name skipped (letters and digits only): $name"
            continue
        }
        $eolText = [string]$row.Eol
        $eol = $eolText -match '^(1|true|yes)$'
        $kind = [string]$row.Kind
        if ($kind -notin @('File', 'Walk', 'Version')) {
            Write-Line "Catalog kind skipped for ${name}: $kind"
            continue
        }
        $roots = @([string]$row.Roots -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $family = New-Family $name $eol $kind $roots ([string]$row.Names) ([string]$row.VersionPrefix) ([string]$row.PathMatch)
        $byName[$name.ToLowerInvariant()] = $family
        Write-Line "Catalog: $name ($kind)"
    }
    return @($byName.Values)
}

function Resolve-SelectedFamilies {
    param([object[]]$Catalog, [string[]]$Names)
    $wanted = @()
    foreach ($name in $Names) {
        foreach ($part in ([string]$name -split '[,\s;]+')) {
            if (-not [string]::IsNullOrWhiteSpace($part)) { $wanted += $part.Trim() }
        }
    }
    if ($wanted.Count -eq 0) {
        return @($Catalog | Where-Object { $_.Eol })
    }
    $allToken = $false
    foreach ($token in $wanted) {
        if ($token -eq '*' -or $token -eq 'All') { $allToken = $true }
    }
    if ($allToken) { return @($Catalog) }
    $selected = @()
    foreach ($token in $wanted) {
        $hit = $Catalog | Where-Object { $_.Name -eq $token }
        if (-not $hit) {
            $known = ($Catalog | ForEach-Object { $_.Name }) -join ', '
            Write-Line "Unknown dependency '$token'. Known: $known"
            $script:ExitCode = 2
            continue
        }
        $selected += $hit
    }
    return $selected
}

function Add-Sentinel {
    param([System.Collections.Generic.List[object]]$List, [string]$Dependency, [string]$FullName)
    if (-not (Test-Path -LiteralPath $FullName -PathType Leaf)) { return }
    $full = [IO.Path]::GetFullPath($FullName)
    foreach ($existing in $List) {
        if ($existing.FullName -eq $full) { return }
    }
    $tail = ''
    if ($full.Length -gt 2) { $tail = $full.Substring(2).ToLowerInvariant() }
    $List.Add([pscustomobject]@{
        Dependency = $Dependency
        FullName   = $full
        Name       = [IO.Path]::GetFileName($full)
        Tail       = $tail
    }) | Out-Null
}

function Find-Sentinels {
    param([object[]]$Families)
    $list = New-Object 'System.Collections.Generic.List[object]'
    foreach ($family in $Families) {
        $roots = @($family.Roots)
        foreach ($root in $roots) {
            $safe = Get-SafeRoot -Root $root
            if (-not $safe) {
                if ($root -and (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables($root)))) {
                    Write-Line "Skip broad path for $($family.Name): $root"
                }
                continue
            }
            if ($family.Kind -eq 'File') {
                foreach ($fileName in ([string]$family.Names -split '\|')) {
                    $fileName = $fileName.Trim()
                    if (-not $fileName) { continue }
                    Add-Sentinel -List $list -Dependency $family.Name -FullName (Join-Path $safe $fileName)
                }
            }
            elseif ($family.Kind -eq 'Version') {
                $prefix = [string]$family.VersionPrefix
                $dirs = @(Get-ChildItem -LiteralPath $safe -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name.StartsWith($prefix) })
                foreach ($dir in $dirs) {
                    foreach ($fileName in ([string]$family.Names -split '\|')) {
                        $fileName = $fileName.Trim()
                        if (-not $fileName) { continue }
                        Add-Sentinel -List $list -Dependency $family.Name -FullName (Join-Path $dir.FullName $fileName)
                    }
                }
            }
            elseif ($family.Kind -eq 'Walk') {
                $regex = [string]$family.Names
                $pathRegex = [string]$family.PathMatch
                $files = @(Get-ChildItem -LiteralPath $safe -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $regex })
                foreach ($file in $files) {
                    if ($pathRegex -and ($file.FullName -notmatch $pathRegex)) { continue }
                    Add-Sentinel -List $list -Dependency $family.Name -FullName $file.FullName
                }
            }
        }
    }
    return @($list.ToArray())
}

function Get-SecurityBudget {
    param([int]$Hours, [int]$Cap)
    $log = Get-WinEvent -ListLog Security -ErrorAction Stop
    $size = [int64]$log.FileSize
    $max = [int64]$log.MaximumSizeInBytes
    $records = [int64]$log.RecordCount
    $bytesEach = [int64]1500
    if ($records -gt 0 -and $size -gt 0) { $bytesEach = [int64]($size / $records) }
    $ms = [int64]$Hours * 3600000
    if ($ms -lt 1) { $ms = 3600000 }
    $xpath = "*[System[(EventID=4663) and TimeCreated[timediff(@SystemTime) <= $ms]]]"
    $count = 0
    $hitCap = $false
    $query = New-Object System.Diagnostics.Eventing.Reader.EventLogQuery('Security', ([System.Diagnostics.Eventing.Reader.PathType]::LogName), $xpath)
    $query.ReverseDirection = $true
    $reader = New-Object System.Diagnostics.Eventing.Reader.EventLogReader $query
    try {
        while ($true) {
            $ev = $reader.ReadEvent()
            if ($null -eq $ev) { break }
            $ev.Dispose()
            $count++
            if ($count -ge $Cap) { $hitCap = $true; break }
        }
    }
    finally { $reader.Dispose() }
    $paceBytes = [int64]0
    if ($Hours -gt 0) { $paceBytes = [int64](($count / $Hours) * 24 * $bytesEach) }
    [pscustomobject]@{
        SizeBytes   = $size
        MaxBytes    = $max
        RecordCount = $records
        BytesEach   = $bytesEach
        Mode        = [string]$log.LogMode
        EventCount  = $count
        HitCap      = $hitCap
        RateHours   = $Hours
        PaceBytes   = $paceBytes
    }
}

function Write-Budget {
    param($Budget, [int]$CapMb, [int]$SentinelCount)
    $pct = 0
    if ($Budget.MaxBytes -gt 0) { $pct = [int](($Budget.SizeBytes * 100) / $Budget.MaxBytes) }
    Write-Section 'Security log'
    Write-Line ("Size: {0} of {1} ({2}%)" -f (Format-MB $Budget.SizeBytes), (Format-MB $Budget.MaxBytes), $pct)
    Write-Line ("Mode: {0}   Records: {1}   About {2} bytes each" -f $Budget.Mode, $Budget.RecordCount, $Budget.BytesEach)
    $paceLabel = Format-MB $Budget.PaceBytes
    if ($Budget.HitCap) { $paceLabel = "at least $paceLabel" }
    Write-Line ("4663 in the last {0}h: {1}   Pace: {2}/day" -f $Budget.RateHours, $Budget.EventCount, $paceLabel)
    $example = [int64](1000 * $Budget.BytesEach)
    Write-Line ("One sentinel load is one 4663. 1000 loads is about {0}, and this script does not keep the message." -f (Format-MB $example))
    Write-Line "Sentinel files selected on this PC: $SentinelCount"
    Write-Line "Cap: $CapMb MB/day of current 4663 traffic."
    $audit = 'unknown'
    try {
        $raw = & auditpol.exe /get /subcategory:'File System' /r 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) {
            $parsed = $raw | ConvertFrom-Csv
            $audit = [string]$parsed.'Inclusion Setting'
            if (-not $audit) { $audit = 'unknown' }
        }
    } catch { }
    Write-Line "File System success auditing: $audit"
    if ($audit -ne 'Success' -and $audit -ne 'Success and Failure') {
        Write-Line 'Hits stay empty until File System success auditing is on. Enable and Watch turn that on locally.'
    }
}

function Test-OverBudget {
    param($Budget, [int]$CapMb)
    if ($Budget.Mode -ne 'Circular') { return $true }
    if ($Budget.HitCap) { return $true }
    $capBytes = [int64]$CapMb * 1MB
    if ($Budget.PaceBytes -gt $capBytes) { return $true }
    return $false
}

function Get-FileSystemAuditRule {
    return New-Object System.Security.AccessControl.FileSystemAuditRule(
        'Everyone',
        [System.Security.AccessControl.FileSystemRights]::ExecuteFile,
        [System.Security.AccessControl.AuditFlags]::Success)
}

function Test-OurAuditRule {
    param($Rule)
    if (-not $Rule) { return $false }
    $who = [string]$Rule.IdentityReference
    if ($who -ne 'Everyone' -and $who -ne 'S-1-1-0') { return $false }
    $success = [System.Security.AccessControl.AuditFlags]::Success
    if (($Rule.AuditFlags -band $success) -ne $success) { return $false }
    $rights = $Rule.FileSystemRights
    $exec = [System.Security.AccessControl.FileSystemRights]::ExecuteFile
    if (($rights -band $exec) -ne $exec) { return $false }
    $broad = [System.Security.AccessControl.FileSystemRights]'ReadData, WriteData, AppendData, Delete'
    if (($rights -band $broad) -ne 0) { return $false }
    return $true
}

function Set-SentinelAudit {
    param([object[]]$Sentinels)
    $rule = Get-FileSystemAuditRule
    $added = 0
    $already = 0
    foreach ($sentinel in $Sentinels) {
        try {
            $acl = Get-Acl -LiteralPath $sentinel.FullName -Audit -ErrorAction Stop
            $present = $false
            foreach ($existing in @($acl.Audit)) {
                if (Test-OurAuditRule $existing) { $present = $true; break }
            }
            if ($present) { $already++; continue }
            $acl.AddAuditRule($rule)
            Set-Acl -LiteralPath $sentinel.FullName -AclObject $acl -ErrorAction Stop
            $added++
        }
        catch {
            Write-Line "Audit rule failed on $($sentinel.FullName): $($_.Exception.Message)"
        }
    }
    Write-Line "Audit rules added: $added   already present: $already"
}

function Remove-SentinelAudit {
    param([object[]]$Sentinels)
    $removed = 0
    foreach ($sentinel in $Sentinels) {
        try {
            $acl = Get-Acl -LiteralPath $sentinel.FullName -Audit -ErrorAction Stop
            $changed = $false
            foreach ($existing in @($acl.Audit)) {
                if (Test-OurAuditRule $existing) {
                    [void]$acl.RemoveAuditRule($existing)
                    $changed = $true
                }
            }
            if ($changed) {
                Set-Acl -LiteralPath $sentinel.FullName -AclObject $acl -ErrorAction Stop
                $removed++
            }
        }
        catch {
            Write-Line "Could not clear $($sentinel.FullName): $($_.Exception.Message)"
        }
    }
    Write-Line "Sentinel files cleared of this execute-audit rule: $removed"
}

function Enable-FileSystemSuccessAudit {
    & auditpol.exe /set /subcategory:'File System' /success:enable | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Line 'auditpol could not enable File System success auditing.'
        return $false
    }
    Write-Line 'File System success auditing is on for this computer.'
    return $true
}

function Test-SentinelObject {
    param([string]$ObjectName, $Sentinel)
    if (-not $ObjectName -or -not $Sentinel.Tail) { return $false }
    $norm = $ObjectName.ToLowerInvariant().Replace('/', '\')
    return $norm.EndsWith($Sentinel.Tail)
}

function Get-DependencyHits {
    param([object[]]$Sentinels, [int]$WindowMinutes, [int]$Cap)
    $result = @{
        Rows   = New-Object System.Collections.Generic.List[object]
        Capped = $false
        Seen   = 0
    }
    if (-not $Sentinels -or $Sentinels.Count -eq 0) { return $result }
    $ms = [int64]$WindowMinutes * 60000
    if ($ms -lt 60000) { $ms = 60000 }
    $xpath = "*[System[(EventID=4663) and TimeCreated[timediff(@SystemTime) <= $ms]]]"
    $query = New-Object System.Diagnostics.Eventing.Reader.EventLogQuery('Security', ([System.Diagnostics.Eventing.Reader.PathType]::LogName), $xpath)
    $query.ReverseDirection = $true
    $reader = New-Object System.Diagnostics.Eventing.Reader.EventLogReader $query
    $agg = @{}
    try {
        while ($true) {
            $ev = $reader.ReadEvent()
            if ($null -eq $ev) { break }
            try {
                $result.Seen++
                if ($result.Seen -gt $Cap) { $result.Capped = $true; break }
                $props = $ev.Properties
                if ($props.Count -lt 7) { continue }
                $objectName = ''
                $process = ''
                if ($props.Count -ge 12) {
                    $objectName = [string]$props[6].Value
                    $process = [string]$props[11].Value
                }
                if ($objectName -notmatch '\\') {
                    $objectName = ''
                    $process = ''
                    for ($pi = 0; $pi -lt $props.Count; $pi++) {
                        $candidate = [string]$props[$pi].Value
                        if ($candidate -notmatch '\\') { continue }
                        if (-not $process -and $candidate -match '\.exe$') { $process = $candidate; continue }
                        if (-not $objectName) { $objectName = $candidate }
                    }
                }
                if ($objectName -notmatch '\\') { continue }
                foreach ($sentinel in $Sentinels) {
                    if (-not (Test-SentinelObject $objectName $sentinel)) { continue }
                    if (-not $process) { $process = '(unknown)' }
                    $key = $sentinel.Dependency + '|' + $process.ToLowerInvariant() + '|' + $sentinel.Name.ToLowerInvariant()
                    if (-not $agg.ContainsKey($key)) {
                        $agg[$key] = [pscustomobject]@{
                            Host       = $env:COMPUTERNAME
                            Dependency = $sentinel.Dependency
                            Process    = $process
                            Sentinel   = $sentinel.Name
                            Hits       = 0
                            FirstSeen  = $ev.TimeCreated
                            LastSeen   = $ev.TimeCreated
                        }
                    }
                    $row = $agg[$key]
                    $row.Hits++
                    if ($ev.TimeCreated -lt $row.FirstSeen) { $row.FirstSeen = $ev.TimeCreated }
                    if ($ev.TimeCreated -gt $row.LastSeen) { $row.LastSeen = $ev.TimeCreated }
                }
            }
            finally { $ev.Dispose() }
        }
    }
    finally { $reader.Dispose() }
    foreach ($row in $agg.Values) { $result.Rows.Add($row) | Out-Null }
    return $result
}

function Write-Usage {
    param([object[]]$Families, [object[]]$Sentinels, $Hits, [int]$WindowMinutes)
    Write-Section "Use in the last $WindowMinutes minutes"
    if ($Hits.Capped) {
        Write-Line "Stopped after $($Hits.Seen) Security 4663 events. Counts are a floor. A family with no hits in that slice is not proof it is unused."
    }
    $anyUsed = $false
    foreach ($family in $Families) {
        $files = @($Sentinels | Where-Object { $_.Dependency -eq $family.Name })
        if ($files.Count -eq 0) {
            Write-Line "$($family.Name)  NOT INSTALLED"
            continue
        }
        $rows = @($Hits.Rows | Where-Object { $_.Dependency -eq $family.Name } | Sort-Object Hits -Descending)
        if ($rows.Count -eq 0) {
            if ($Hits.Capped) { Write-Line "$($family.Name)  INSTALLED  $($files.Count) sentinel file(s)  UNKNOWN (event cap)" }
            else { Write-Line "$($family.Name)  INSTALLED  $($files.Count) sentinel file(s)  NOT USED" }
            continue
        }
        $anyUsed = $true
        $procs = @($rows | Select-Object -ExpandProperty Process -Unique)
        Write-Line "$($family.Name)  INSTALLED  $($files.Count) sentinel file(s)  USED by $($procs.Count) process path(s)"
        $shown = 0
        foreach ($row in $rows) {
            $shown++
            if ($shown -gt 15) { break }
            Write-Line ("  {0}  {1} hits  {2}  {3} -> {4}" -f $row.Process, $row.Hits, $row.Sentinel, $row.FirstSeen, $row.LastSeen)
        }
        if ($rows.Count -gt 15) { Write-Line "  ... $($rows.Count - 15) more process/file rows" }
    }
    return $anyUsed
}

function Write-ReportFiles {
    param($Budget, $Hits, [string]$ActionName)
    $dir = Split-Path -Parent $ReportPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $budgetFile = Join-Path $dir 'budget.txt'
    $lines = @(
        ("Time={0:o}" -f (Get-Date))
        "Action=$ActionName"
        "SizeBytes=$($Budget.SizeBytes)"
        "MaxBytes=$($Budget.MaxBytes)"
        "Mode=$($Budget.Mode)"
        "RecordBytes=$($Budget.BytesEach)"
        "Event4663=$($Budget.EventCount)"
        "EventCap=$($Budget.HitCap)"
        "PaceBytesPerDay=$($Budget.PaceBytes)"
    )
    Set-Content -LiteralPath $budgetFile -Value $lines -Encoding ASCII
    $csvRows = @()
    if ($Hits.Rows -and $Hits.Rows.PSObject.Methods['ToArray']) { $csvRows = @($Hits.Rows.ToArray()) }
    elseif ($Hits.Rows) { $csvRows = @($Hits.Rows) }
    if ($csvRows.Count -eq 0) {
        if (Test-Path -LiteralPath $ReportPath) { Remove-Item -LiteralPath $ReportPath -Force }
    }
    else {
        $csvRows | Export-Csv -LiteralPath $ReportPath -NoTypeInformation -Encoding ASCII
    }
    $runLog = Join-Path $dir 'runs.log'
    $used = @($Hits.Rows | Select-Object -ExpandProperty Dependency -Unique) -join ','
    if (-not $used) { $used = '-' }
    Add-Content -LiteralPath $runLog -Value ("{0:o} {1} pace_bytes_day={2} used={3}" -f (Get-Date), $ActionName, $Budget.PaceBytes, $used) -Encoding ASCII
    if (Test-Path -LiteralPath $runLog) {
        $kept = @(Get-Content -LiteralPath $runLog -Tail 200)
        Set-Content -LiteralPath $runLog -Value $kept -Encoding ASCII
    }
    Write-Line "Report: $ReportPath"
    Write-Line "Budget: $budgetFile"
}

function Invoke-Sample {
    param([object[]]$Sentinels, [int]$Minutes, [int]$CapMb, $BudgetBefore)
    Write-Section "Sample $Minutes minute(s)"
    Write-Line 'Arming sentinel auditing for the sample, then removing it.'
    if (-not (Enable-FileSystemSuccessAudit)) {
        $script:ExitCode = 2
        return @{ Rows = @(); Capped = $false; Seen = 0 }
    }
    Set-SentinelAudit -Sentinels $Sentinels
    $started = Get-Date
    $stopEarly = $false
    $elapsedMin = 0
    for ($minute = 1; $minute -le $Minutes; $minute++) {
        Start-Sleep -Seconds 60
        $elapsedMin = $minute
        try {
            $now = Get-WinEvent -ListLog Security
            $delta = [int64]$now.FileSize - [int64]$BudgetBefore.SizeBytes
            Write-Line ("Sample minute {0}: Security log grew {1}" -f $minute, (Format-MB $delta))
            if ($delta -gt ([int64]$CapMb * 1MB)) {
                Write-Line 'Sample stopped early. Growth during the sample already passed the daily cap.'
                $stopEarly = $true
                break
            }
        }
        catch {
            Write-Line "Sample minute ${minute}: could not read the Security log."
        }
    }
    if ($elapsedMin -lt 1) { $elapsedMin = 1 }
    $after = Get-WinEvent -ListLog Security
    $deltaBytes = [int64]$after.FileSize - [int64]$BudgetBefore.SizeBytes
    if ($deltaBytes -lt 0) { $deltaBytes = 0 }
    $projected = [int64](($deltaBytes / $elapsedMin) * 1440)
    $hits = Get-DependencyHits -Sentinels $Sentinels -WindowMinutes ($elapsedMin + 1) -Cap $MaxEvents
    $hitBytes = [int64]0
    foreach ($row in $hits.Rows) { $hitBytes += ([int64]$row.Hits * [int64]$BudgetBefore.BytesEach) }
    $hitPace = [int64](($hitBytes / $elapsedMin) * 1440)
    Write-Line ("Security log grew {0} in {1} min. Projected {2}/day while this busy." -f (Format-MB $deltaBytes), $elapsedMin, (Format-MB $projected))
    Write-Line ("Sentinel hits account for about {0}/day. Other 4663 traffic is the rest." -f (Format-MB $hitPace))
    Remove-SentinelAudit -Sentinels $Sentinels
    $capBytes = [int64]$CapMb * 1MB
    if ($stopEarly -or $projected -gt $capBytes) {
        Write-Line "Result: sample is over the $CapMb MB/day cap. Auditing was removed."
        $script:ExitCode = 3
    }
    else {
        Write-Line "Result: sample is under the $CapMb MB/day cap. Auditing was removed."
    }
    return $hits
}

$allowed = @('Measure', 'Enable', 'Collect', 'Disable', 'Watch')
if (-not $Action) {
    if ($CheckOnly) { $Action = 'Measure' }
    else { $Action = 'Measure' }
}
if ($allowed -notcontains $Action) {
    Write-Line "Action must be one of: $($allowed -join ', ')"
    $script:ExitCode = 2
}
if ($SampleMinutes -gt 0 -and $Action -ne 'Measure') {
    Write-Line '-SampleMinutes is only used with Measure.'
    $script:ExitCode = 2
}
if ($SinceHours -lt 1) { $SinceHours = 1 }
if ($RateHours -lt 1) { $RateHours = 1 }
if ($MaxDailyLogMB -lt 1) { $MaxDailyLogMB = 1 }
if ($MaxEvents -lt 100) { $MaxEvents = 100 }
if (-not $ReportPath) {
    $ReportPath = Join-Path $env:ProgramData 'EolDependencyAudit\usage.csv'
}

if (-not (Test-IsAdmin)) {
    Write-Line 'Result: Run elevated. The Security log and file audit ACLs require an administrator.'
    $script:ExitCode = 2
}

if ($script:ExitCode -eq 2) {
    if ($Exit) { exit $script:ExitCode }
    return
}

Write-Section 'EOL dependency use'
Write-Line "Action: $Action"
if ($Force) { Write-Line 'Force: log cap will not block auditing.' }

$catalog = Import-ExtraCatalog -Path $CatalogPath -Catalog @(Get-BuiltinCatalog)
if ($script:ExitCode -eq 2) {
    if ($Exit) { exit $script:ExitCode }
    return
}
$families = @(Resolve-SelectedFamilies -Catalog $catalog -Names $Dependency)
if ($script:ExitCode -eq 2 -or $families.Count -eq 0) {
    if ($families.Count -eq 0 -and $script:ExitCode -eq 0) { Write-Line 'No dependencies selected.' }
    if ($script:ExitCode -eq 0) { $script:ExitCode = 2 }
    if ($Exit) { exit $script:ExitCode }
    return
}
Write-Line ("Families: {0}" -f (($families | ForEach-Object { $_.Name }) -join ', '))

Write-Line 'Looking for sentinel files...'
$sentinels = @(Find-Sentinels -Families $families)
Write-Line "Sentinels on disk: $($sentinels.Count)"
$shownFiles = 0
foreach ($sentinel in $sentinels) {
    $shownFiles++
    if ($shownFiles -gt 20) { break }
    Write-Line "  $($sentinel.Dependency)  $($sentinel.FullName)"
}
if ($sentinels.Count -gt 20) { Write-Line "  ... $($sentinels.Count - 20) more" }

$budget = $null
try { $budget = Get-SecurityBudget -Hours $RateHours -Cap $MaxEvents }
catch {
    Write-Line "Could not read the Security log: $($_.Exception.Message)"
    $script:ExitCode = 2
    if ($Exit) { exit $script:ExitCode }
    return
}
Write-Budget -Budget $budget -CapMb $MaxDailyLogMB -SentinelCount $sentinels.Count
$over = Test-OverBudget -Budget $budget -CapMb $MaxDailyLogMB
if ($over) {
    $why = "current 4663 pace is above $MaxDailyLogMB MB/day"
    if ($budget.Mode -ne 'Circular') { $why = "Security log mode is $($budget.Mode), not Circular" }
    elseif ($budget.HitCap) { $why = "4663 count hit the read cap of $MaxEvents, so the pace is only a floor" }
    Write-Line "Log gate: $why."
}
else {
    Write-Line 'Log gate: current 4663 pace is under the cap.'
}

$emptyHits = @{ Rows = @(); Capped = $false; Seen = 0 }
$hits = $emptyHits

if ($Action -eq 'Disable') {
    Write-Section 'Disarm'
    Remove-SentinelAudit -Sentinels $sentinels
    Write-Line 'File System auditing was left as it is. Other files may still need it.'
    Write-Line 'Result: sentinel execute-audit removed.'
}
elseif ($Action -eq 'Measure' -and $SampleMinutes -gt 0) {
    if ($sentinels.Count -eq 0) {
        Write-Line 'Result: nothing to sample. No sentinel files for the selected families.'
    }
    elseif ($over -and -not $Force) {
        Write-Line 'Result: sample refused. The log is already over the cap. Pass -Force to sample anyway.'
        $script:ExitCode = 3
    }
    else {
        $hits = Invoke-Sample -Sentinels $sentinels -Minutes $SampleMinutes -CapMb $MaxDailyLogMB -BudgetBefore $budget
        $used = Write-Usage -Families $families -Sentinels $sentinels -Hits $hits -WindowMinutes ($SampleMinutes + 1)
        if ($script:ExitCode -ne 3 -and $used) { $script:ExitCode = 1 }
    }
}
elseif ($Action -eq 'Enable' -or $Action -eq 'Watch') {
    if ($sentinels.Count -eq 0) {
        Write-Line 'Result: no sentinel files. Auditing was not changed.'
    }
    elseif ($over -and -not $Force) {
        Write-Section 'Disarm'
        Remove-SentinelAudit -Sentinels $sentinels
        Write-Line 'Result: auditing was not left on. Current 4663 pace is over the cap.'
        $script:ExitCode = 3
    }
    else {
        if ($over -and $Force) { Write-Line 'Force: arming even though the log gate failed.' }
        Write-Section 'Arm'
        if (-not (Enable-FileSystemSuccessAudit)) { $script:ExitCode = 2 }
        else { Set-SentinelAudit -Sentinels $sentinels }
    }
}

if ($Action -eq 'Measure' -or $Action -eq 'Collect' -or $Action -eq 'Watch') {
    if ($Action -eq 'Measure' -and $SampleMinutes -gt 0) {
        # Sample already printed use.
    }
    elseif ($sentinels.Count -eq 0) {
        Write-Usage -Families $families -Sentinels $sentinels -Hits $emptyHits -WindowMinutes ($SinceHours * 60) | Out-Null
    }
    else {
        Write-Line "Reading 4663 events for the last $SinceHours hours..."
        $hits = Get-DependencyHits -Sentinels $sentinels -WindowMinutes ($SinceHours * 60) -Cap $MaxEvents
        $used = Write-Usage -Families $families -Sentinels $sentinels -Hits $hits -WindowMinutes ($SinceHours * 60)
        if ($script:ExitCode -eq 0 -and $used) { $script:ExitCode = 1 }
    }
}

if ($budget) {
    try { Write-ReportFiles -Budget $budget -Hits $hits -ActionName $Action }
    catch { Write-Line "Could not write the report: $($_.Exception.Message)" }
}

if ($script:ExitCode -eq 0) { Write-Line 'Result: no selected dependency was loaded in the window.' }
elseif ($script:ExitCode -eq 1) { Write-Line 'Result: at least one selected dependency was loaded.' }

if ($Exit) { exit $script:ExitCode }
