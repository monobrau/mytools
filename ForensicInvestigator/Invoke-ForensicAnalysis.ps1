<#
.SYNOPSIS
    Forensic system analysis tool using Sysinternals utilities with VirusTotal integration.

.DESCRIPTION
    Downloads and runs Sysinternals tools to perform comprehensive system analysis
    (autoruns, services, network, processes) with optional VirusTotal hash checking.
    Also collects Harkins-style host artifacts and event logs, inventories every
    user Downloads/Desktop (with Zone.Identifier), copies PowerShell history,
    Amcache/SYSTEM hives, Chrome/Edge History DBs, local admins, RMM inventory,
    and Defender detections, then writes a hashed collection manifest.

.PARAMETER OutputPath
    Directory where reports will be saved. Defaults to .\ForensicReports

.PARAMETER VirusTotalApiKey
    VirusTotal API key for hash lookups. If not provided, VT scanning will be skipped.

.PARAMETER EnableVirusTotal
    Switch to enable VirusTotal scanning (requires API key)

.PARAMETER ToolsPath
    Directory where Sysinternals tools will be downloaded. Defaults to .\SysinternalsTools

.PARAMETER CleanupTools
    Switch to delete Sysinternals tools folder after analysis completes

.PARAMETER ExportXLSX
    Switch to export to Excel format (XLSX) instead of CSV. Requires Microsoft Excel to be installed.
    By default, exports to CSV format which works in all environments including ScreenConnect.

.PARAMETER CombinedWorkbook
    Switch to export to a single Excel workbook with all worksheets (slower but consolidated).
    Only applies when -ExportXLSX is used. By default, exports to separate Excel files for faster performance.

.PARAMETER SkipEventLogs
    Skip wevtutil EVTX export (Harkins-style Security/PowerShell/RDP/Sysmon set).

.PARAMETER SkipDownloads
    Skip the all-user Downloads/Desktop inventory.

.PARAMETER SkipHostArtifacts
    Skip prefetch, scheduled tasks, users, software, DNS, and ARP collection.

.EXAMPLE
    .\Invoke-ForensicAnalysis.ps1 -EnableVirusTotal -VirusTotalApiKey "your-api-key"

.EXAMPLE
    .\Invoke-ForensicAnalysis.ps1 -OutputPath "C:\Reports"

.EXAMPLE
    .\Invoke-ForensicAnalysis.ps1 -CleanupTools

.EXAMPLE
    .\Invoke-ForensicAnalysis.ps1 -ExportXLSX

.EXAMPLE
    .\Invoke-ForensicAnalysis.ps1 -ExportXLSX -CombinedWorkbook
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\ForensicReports",

    [Parameter(Mandatory=$false)]
    [string]$VirusTotalApiKey = "",

    [Parameter(Mandatory=$false)]
    [switch]$EnableVirusTotal,

    [Parameter(Mandatory=$false)]
    [string]$ToolsPath = ".\SysinternalsTools",

    [Parameter(Mandatory=$false)]
    [switch]$CleanupTools,

    [Parameter(Mandatory=$false)]
    [switch]$ExportXLSX,

    [Parameter(Mandatory=$false)]
    [switch]$CombinedWorkbook,

    [Parameter(Mandatory=$false)]
    [switch]$SkipEventLogs,

    [Parameter(Mandatory=$false)]
    [switch]$SkipDownloads,

    [Parameter(Mandatory=$false)]
    [switch]$SkipHostArtifacts
)

#Requires -RunAsAdministrator

# TLS 1.2 as numeric 3072 — [Net.SecurityProtocolType]::Tls12 is $null on PS 2.0
# and SecurityProtocolManager is not a real type.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072 } catch { }

# Script version - for verification
$script:Version = "3.1.0"
$script:AdditionalCsvPaths = New-Object 'System.Collections.Generic.List[string]'
$script:EventLogFolder = $null
$script:ArtifactRoot = $null
$script:ZipPath = $null
$script:CollectionStartUtc = $null
$script:RmmNamePattern = 'screenconnect|connectwise|huntress|sentinelone|anydesk|ultraviewer|teamviewer|splashtop|logmein|atera|ninjarmm|connectsecure|cybercns|ltsvc|automate|meshagent|rustdesk|remotepc|bomgar|beyondtrust'
$script:DownloadHashExtensions = @(
    '.exe', '.dll', '.msi', '.scr', '.com', '.sys', '.cpl', '.ocx',
    '.ps1', '.vbs', '.vbe', '.js', '.jse', '.wsf', '.wsh', '.bat', '.cmd', '.hta', '.lnk'
)

# Global configuration
$script:VTApiKey = $VirusTotalApiKey
$script:VTEnabled = $EnableVirusTotal -and ![string]::IsNullOrWhiteSpace($VirusTotalApiKey)
$script:VTCache = @{}
$script:VTRateLimit = 4  # Free API: 4 requests per minute
$script:VTRequestCount = 0
$script:VTLastRequestTime = Get-Date

# Color coding thresholds
$script:ColorScheme = @{
    HighRisk = @{
        Color = 'Red'
        Criteria = 'No signature OR VT detections >= 5'
    }
    MediumRisk = @{
        Color = 'Yellow'
        Criteria = 'Unknown publisher OR VT detections 1-4'
    }
    LowRisk = @{
        Color = 'Green'
        Criteria = 'Verified signature AND VT detections = 0'
    }
}

# Required Sysinternals tools
$script:RequiredTools = @{
    'autorunsc.exe' = 'https://live.sysinternals.com/autorunsc.exe'
    'autorunsc64.exe' = 'https://live.sysinternals.com/autorunsc64.exe'
    'PsService.exe' = 'https://live.sysinternals.com/PsService.exe'
    'PsService64.exe' = 'https://live.sysinternals.com/PsService64.exe'
    'tcpview.exe' = 'https://live.sysinternals.com/Tcpview.exe'
    'tcpvcon.exe' = 'https://live.sysinternals.com/tcpvcon.exe'
    'sigcheck.exe' = 'https://live.sysinternals.com/sigcheck.exe'
    'sigcheck64.exe' = 'https://live.sysinternals.com/sigcheck64.exe'
    'handle.exe' = 'https://live.sysinternals.com/handle.exe'
    'handle64.exe' = 'https://live.sysinternals.com/handle64.exe'
    'listdlls.exe' = 'https://live.sysinternals.com/Listdlls.exe'
    'listdlls64.exe' = 'https://live.sysinternals.com/Listdlls64.exe'
    'psinfo.exe' = 'https://live.sysinternals.com/psinfo.exe'
    'psinfo64.exe' = 'https://live.sysinternals.com/psinfo64.exe'
}

function Write-ColoredMessage {
    param(
        [string]$Message,
        [string]$Color = 'White'
    )
    Write-Host $Message -ForegroundColor $Color
}

function Initialize-Environment {
    Write-ColoredMessage "`n=== Forensic Investigation Tool ===" -Color Cyan
    Write-ColoredMessage "Version: $script:Version" -Color Gray
    Write-ColoredMessage "Initializing environment...`n" -Color Cyan

    # Create directories
    if (!(Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        Write-ColoredMessage "[+] Created output directory: $OutputPath" -Color Green
    }

    if (!(Test-Path $ToolsPath)) {
        New-Item -ItemType Directory -Path $ToolsPath -Force | Out-Null
        Write-ColoredMessage "[+] Created tools directory: $ToolsPath" -Color Green
    }

    # Check if running as admin
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (!$isAdmin) {
        Write-ColoredMessage "[!] Warning: Not running as Administrator. Some tools may not work properly." -Color Yellow
    }

    # Check VT status
    if ($script:VTEnabled) {
        Write-ColoredMessage "[+] VirusTotal scanning: ENABLED" -Color Green
    } else {
        Write-ColoredMessage "[-] VirusTotal scanning: DISABLED" -Color Yellow
    }

    Write-Host ""
}

function Get-SysinternalsTools {
    Write-ColoredMessage "`n=== Downloading Sysinternals Tools ===" -Color Cyan

    $arch = if ([Environment]::Is64BitOperatingSystem) { "64" } else { "" }
    $toolsToDownload = @()

    # Select architecture-appropriate tools
    foreach ($tool in $script:RequiredTools.Keys) {
        if ($arch -eq "64" -and $tool -like "*64.exe") {
            $toolsToDownload += $tool
        } elseif ($arch -eq "" -and $tool -notlike "*64.exe") {
            $toolsToDownload += $tool
        }
    }

    $downloadCount = 0
    foreach ($tool in $toolsToDownload) {
        $toolPath = Join-Path $ToolsPath $tool
        $url = $script:RequiredTools[$tool]

        if (!(Test-Path $toolPath)) {
            try {
                Write-Host "[*] Downloading $tool..." -NoNewline
                $response = Invoke-WebRequest -Uri $url -OutFile $toolPath -UseBasicParsing -ErrorAction Stop
                
                # Verify we got a valid file (not HTML from web filter)
                if (Test-Path $toolPath) {
                    $fileSize = (Get-Item $toolPath).Length
                    if ($fileSize -lt 1000) {
                        # Suspiciously small - might be HTML error page
                        $content = Get-Content $toolPath -Raw -ErrorAction SilentlyContinue
                        if ($content -match '<html|<HTML|<!DOCTYPE|web filter') {
                            Remove-Item $toolPath -Force -ErrorAction SilentlyContinue
                            throw "Web filter blocking download - received HTML instead of tool"
                        }
                    }
                }
                
                Write-ColoredMessage " OK" -Color Green
                $downloadCount++
            } catch {
                Write-ColoredMessage " FAILED" -Color Red
                if ($_.Exception.Message -match 'web filter|HTML|blocked') {
                    Write-ColoredMessage "    ERROR: Web filter is blocking Sysinternals download" -Color Red
                    Write-ColoredMessage "    URL: $url" -Color Yellow
                    Write-ColoredMessage "    SOLUTION: Download manually from https://live.sysinternals.com/" -Color Yellow
                    Write-ColoredMessage "    Or use VPN/proxy to bypass web filter" -Color Yellow
                } else {
                    Write-ColoredMessage "    Error: $($_.Exception.Message)" -Color Red
                    Write-ColoredMessage "    URL: $url" -Color Yellow
                }
            }
        } else {
            Write-ColoredMessage "[*] $tool already exists, skipping" -Color Gray
        }
    }

    Write-ColoredMessage "`n[+] Downloaded $downloadCount new tools" -Color Green
}

function Get-VirusTotalReport {
    param(
        [string]$Hash
    )

    if (!$script:VTEnabled -or [string]::IsNullOrWhiteSpace($Hash)) {
        return $null
    }

    # Check cache first
    if ($script:VTCache.ContainsKey($Hash)) {
        return $script:VTCache[$Hash]
    }

    # Rate limiting
    $timeSinceLastRequest = (Get-Date) - $script:VTLastRequestTime
    if ($script:VTRequestCount -ge $script:VTRateLimit -and $timeSinceLastRequest.TotalSeconds -lt 60) {
        $sleepTime = 60 - $timeSinceLastRequest.TotalSeconds + 1
        Write-Host "[*] Rate limit reached, waiting $([math]::Round($sleepTime)) seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds $sleepTime
        $script:VTRequestCount = 0
    }

    try {
        $headers = @{
            'x-apikey' = $script:VTApiKey
        }

        $url = "https://www.virustotal.com/api/v3/files/$Hash"
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop

        $script:VTRequestCount++
        $script:VTLastRequestTime = Get-Date

        $result = @{
            Malicious = $response.data.attributes.last_analysis_stats.malicious
            Suspicious = $response.data.attributes.last_analysis_stats.suspicious
            Undetected = $response.data.attributes.last_analysis_stats.undetected
            Harmless = $response.data.attributes.last_analysis_stats.harmless
            LastAnalysis = $response.data.attributes.last_analysis_date
        }

        $script:VTCache[$Hash] = $result
        return $result

    } catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            # File not found in VT database
            $result = @{
                Malicious = 0
                Suspicious = 0
                Undetected = 0
                Harmless = 0
                LastAnalysis = "Not found"
            }
            $script:VTCache[$Hash] = $result
            return $result
        }
        Write-Host "[!] VT API Error for hash $Hash : $_" -ForegroundColor Red
        return $null
    }
}

function Get-FileHashQuick {
    param([string]$FilePath)

    if (!(Test-Path $FilePath)) {
        return $null
    }

    try {
        $hash = Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction Stop
        return $hash.Hash
    } catch {
        return $null
    }
}

function Get-RiskLevel {
    param(
        [string]$Signature,
        [object]$VTReport
    )

    $riskLevel = "Unknown"
    $riskScore = 0

    # Check signature
    if ([string]::IsNullOrWhiteSpace($Signature) -or $Signature -eq "(Not verified)" -or $Signature -eq "n/a") {
        $riskScore += 10
    } elseif ($Signature -like "*Unknown*" -or $Signature -like "*Cannot*") {
        $riskScore += 5
    }

    # Check VT report
    if ($VTReport) {
        $malicious = [int]$VTReport.Malicious
        $suspicious = [int]$VTReport.Suspicious

        if ($malicious -ge 5) {
            $riskScore += 20
        } elseif ($malicious -ge 1) {
            $riskScore += 10
        }

        if ($suspicious -ge 3) {
            $riskScore += 5
        }
    }

    # Determine risk level
    if ($riskScore -ge 15) {
        return "High"
    } elseif ($riskScore -ge 5) {
        return "Medium"
    } else {
        return "Low"
    }
}

function Get-AutorunEntries {
    Write-ColoredMessage "`n=== Analyzing Autorun Entries ===" -Color Cyan

    $arch = if ([Environment]::Is64BitOperatingSystem) { "autorunsc64.exe" } else { "autorunsc.exe" }
    $autorunsc = Join-Path $ToolsPath $arch

    if (!(Test-Path $autorunsc)) {
        Write-ColoredMessage "[!] Autorunsc not found!" -Color Red
        return @()
    }

    Write-Host "[*] Running Autorunsc with real-time monitoring..."
    Write-Host "[*] Monitoring CPU usage every 5 seconds (Ctrl+C to cancel)..." -ForegroundColor Yellow

    try {
        # Accept EULA automatically with -accepteula
        # Removed -h (hash calculated later) and -v (signature verification - slow/network dependent)

        # Create temp file for autorunsc output (handles UTF-16 encoding properly)
        $tempCsvPath = Join-Path $env:TEMP "autorunsc_output_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

        # Use cmd.exe with native redirection to preserve autorunsc's UTF-16 output
        # This avoids PowerShell's encoding conversion issues
        $cmdLine = "cmd.exe /c `"`"$autorunsc`" -accepteula -a * -c -s > `"$tempCsvPath`"`""

        # Start the process in background
        $startTime = Get-Date
        $processInfo = Start-Process -FilePath "cmd.exe" `
            -ArgumentList "/c `"`"$autorunsc`" -accepteula -a * -c -s > `"$tempCsvPath`"`"" `
            -NoNewWindow `
            -PassThru

        Write-Host "[*] Autorunsc process started (PID: $($processInfo.Id))" -ForegroundColor Green

        # Monitor the process
        $lastCpu = 0

        while (!$processInfo.HasExited) {
            Start-Sleep -Seconds 5

            try {
                # Find autorunsc process (child of cmd.exe)
                $proc = Get-Process -Name "autorunsc*" -ErrorAction SilentlyContinue
                if ($proc) {
                    $runtime = (Get-Date) - $startTime
                    $cpuTime = [math]::Round($proc.CPU, 2)
                    $cpuDelta = $cpuTime - $lastCpu
                    $memoryMB = [math]::Round($proc.WS / 1MB, 2)

                    # Determine status based on CPU delta
                    $status = if ($cpuDelta -gt 0.1) { "WORKING" } else { "IDLE?" }
                    $color = if ($cpuDelta -gt 0.1) { "Green" } else { "Yellow" }

                    Write-Host "`r[$(Get-Date -Format 'HH:mm:ss')] Runtime: $([math]::Round($runtime.TotalMinutes,1))min | CPU: ${cpuTime}s (+${cpuDelta}s) | Memory: ${memoryMB}MB | Status: $status" -ForegroundColor $color -NoNewline

                    $lastCpu = $cpuTime
                }
            } catch {
                # Process may have just exited
            }
        }

        Write-Host "" # New line after monitoring

        # Wait for process to complete
        $processInfo.WaitForExit()

        $totalTime = (Get-Date) - $startTime
        Write-ColoredMessage "[+] Autorunsc completed in $([math]::Round($totalTime.TotalMinutes,1)) minutes (Exit code: $($processInfo.ExitCode))" -Color Green

        $entries = @()

        # Read the CSV file with proper encoding
        if (!(Test-Path $tempCsvPath)) {
            Write-ColoredMessage "[!] Autorunsc output file not found: $tempCsvPath" -Color Red
            return @()
        }

        # Read as UTF-16 LE (which is what autorunsc outputs with -c flag)
        $lines = Get-Content -Path $tempCsvPath -Encoding Unicode | Where-Object { ![string]::IsNullOrWhiteSpace($_) }

        if ($lines.Count -lt 2) {
            Write-ColoredMessage "[!] No output from Autorunsc (only $($lines.Count) lines)" -Color Yellow
            Remove-Item $tempCsvPath -Force -ErrorAction SilentlyContinue
            return @()
        }

        # Parse CSV output
        try {
            $csv = $lines | ConvertFrom-Csv
        } catch {
            Write-ColoredMessage "[!] Failed to parse CSV: $_" -Color Red
            return @()
        }

        $totalEntries = $csv.Count
        $currentEntry = 0

        # Helper function to safely get property value
        function Get-CsvProperty {
            param($obj, [string[]]$names)
            foreach ($name in $names) {
                $prop = $obj.PSObject.Properties[$name]
                if ($prop) {
                    return $prop.Value
                }
            }
            return $null
        }

        foreach ($entry in $csv) {
            $currentEntry++
            Write-Progress -Activity "Analyzing Autorun Entries" -Status "Processing $currentEntry of $totalEntries" -PercentComplete (($currentEntry / $totalEntries) * 100)

            # Try different possible column names (autorunsc format varies)
            $imagePath = Get-CsvProperty $entry @('Image Path', 'ImagePath', 'Path')
            $entryLocation = Get-CsvProperty $entry @('Entry Location', 'EntryLocation', 'Location')
            $entryName = Get-CsvProperty $entry @('Entry', 'Name', 'Item')
            $description = Get-CsvProperty $entry @('Description', 'Desc')
            $enabled = Get-CsvProperty $entry @('Enabled')
            $category = Get-CsvProperty $entry @('Category')
            $profile = Get-CsvProperty $entry @('Profile')

            # Try Signer first (most common), then Company, then Publisher
            $signer = Get-CsvProperty $entry @('Signer', 'Publisher')
            $company = Get-CsvProperty $entry @('Company', 'Manufacturer')
            # Use Signer if available, otherwise Company
            $publisher = if (![string]::IsNullOrWhiteSpace($signer)) { $signer } else { $company }

            $version = Get-CsvProperty $entry @('Version')
            $launchString = Get-CsvProperty $entry @('Launch String', 'LaunchString', 'Command')
            $timestamp = Get-CsvProperty $entry @('Time', 'Timestamp')

            $hash = $null
            $vtReport = $null

            # Get file hash if path exists
            if (![string]::IsNullOrWhiteSpace($imagePath) -and (Test-Path $imagePath -ErrorAction SilentlyContinue)) {
                $hash = Get-FileHashQuick -FilePath $imagePath

                if ($hash -and $script:VTEnabled) {
                    $vtReport = Get-VirusTotalReport -Hash $hash
                }
            }

            # Determine signature/publisher for risk assessment
            $signature = if (![string]::IsNullOrWhiteSpace($publisher)) { $publisher } else { "(Not verified)" }
            $riskLevel = Get-RiskLevel -Signature $signature -VTReport $vtReport

            # Safely format VT detections (handle potential non-integer values)
            $vtDetections = "N/A"
            if ($vtReport) {
                try {
                    $mal = [int]$vtReport.Malicious
                    $sus = [int]$vtReport.Suspicious
                    $undet = [int]$vtReport.Undetected
                    $harm = [int]$vtReport.Harmless
                    $total = $mal + $sus + $undet + $harm
                    $vtDetections = "$mal/$total"
                } catch {
                    $vtDetections = "Error"
                }
            }

            $entries += [PSCustomObject]@{
                Type = "Autorun"
                Timestamp = if ($timestamp) { $timestamp.ToString() } else { "" }
                Category = if ($category) { $category.ToString() } else { "" }
                Profile = if ($profile) { $profile.ToString() } else { "" }
                Enabled = if ($enabled) { $enabled.ToString() } else { "" }
                EntryLocation = if ($entryLocation) { $entryLocation.ToString() } else { "" }
                Entry = if ($entryName) { $entryName.ToString() } else { "" }
                Description = if ($description) { $description.ToString() } else { "" }
                Signer = if ($signer) { $signer.ToString() } else { "" }
                Company = if ($company) { $company.ToString() } else { "" }
                ImagePath = if ($imagePath) { $imagePath.ToString() } else { "" }
                Version = if ($version) { $version.ToString() } else { "" }
                LaunchString = if ($launchString) { $launchString.ToString() } else { "" }
                SHA256 = if ($hash) { $hash } else { "" }
                VT_Malicious = if ($vtReport) { [string]$vtReport.Malicious } else { "N/A" }
                VT_Suspicious = if ($vtReport) { [string]$vtReport.Suspicious } else { "N/A" }
                VT_Detections = $vtDetections
                RiskLevel = $riskLevel
            }
        }

        Write-Progress -Activity "Analyzing Autorun Entries" -Completed
        Write-ColoredMessage "[+] Found $($entries.Count) autorun entries" -Color Green

        # Clean up temp file
        if (Test-Path $tempCsvPath) {
            Remove-Item $tempCsvPath -Force -ErrorAction SilentlyContinue
        }

        return $entries

    } catch {
        Write-ColoredMessage "[!] Error running Autorunsc: $_" -Color Red
        # Clean up temp file on error
        if (Test-Path variable:tempCsvPath) {
            Remove-Item $tempCsvPath -Force -ErrorAction SilentlyContinue
        }
        return @()
    }
}

function Get-ServiceEntries {
    Write-ColoredMessage "`n=== Analyzing Services ===" -Color Cyan

    Write-Host "[*] Enumerating services..."

    try {
        $services = Get-WmiObject -Class Win32_Service | Where-Object { $_.PathName }
        $entries = @()

        $totalServices = $services.Count
        $currentService = 0

        foreach ($service in $services) {
            $currentService++
            Write-Progress -Activity "Analyzing Services" -Status "Processing $currentService of $totalServices" -PercentComplete (($currentService / $totalServices) * 100)

            # Extract executable path from PathName (may include arguments)
            $pathName = $service.PathName
            $exePath = $pathName

            # Handle quoted paths
            if ($pathName -match '^"([^"]+)"') {
                $exePath = $matches[1]
            } elseif ($pathName -match '^([^\s]+\.exe)') {
                $exePath = $matches[1]
            }

            $hash = $null
            $vtReport = $null
            $signature = "Unknown"

            if (Test-Path $exePath -ErrorAction SilentlyContinue) {
                $hash = Get-FileHashQuick -FilePath $exePath

                if ($hash -and $script:VTEnabled) {
                    $vtReport = Get-VirusTotalReport -Hash $hash
                }

                # Get signature info
                try {
                    $sig = Get-AuthenticodeSignature -FilePath $exePath -ErrorAction SilentlyContinue
                    if ($sig -and $sig.SignerCertificate) {
                        $signature = $sig.SignerCertificate.Subject
                    }
                } catch {
                    $signature = "(Not verified)"
                }
            }

            $riskLevel = Get-RiskLevel -Signature $signature -VTReport $vtReport

            # Safely format VT detections
            $vtDetections = "N/A"
            if ($vtReport) {
                try {
                    $mal = [int]$vtReport.Malicious
                    $sus = [int]$vtReport.Suspicious
                    $undet = [int]$vtReport.Undetected
                    $harm = [int]$vtReport.Harmless
                    $total = $mal + $sus + $undet + $harm
                    $vtDetections = "$mal/$total"
                } catch {
                    $vtDetections = "Error"
                }
            }

            $entries += [PSCustomObject]@{
                Type = "Service"
                ServiceName = $service.Name
                DisplayName = $service.DisplayName
                State = $service.State
                StartMode = $service.StartMode
                PathName = $pathName
                ExecutablePath = $exePath
                Publisher = $signature
                SHA256 = $hash
                VT_Malicious = if ($vtReport) { [string]$vtReport.Malicious } else { "N/A" }
                VT_Suspicious = if ($vtReport) { [string]$vtReport.Suspicious } else { "N/A" }
                VT_Detections = $vtDetections
                RiskLevel = $riskLevel
            }
        }

        Write-Progress -Activity "Analyzing Services" -Completed
        Write-ColoredMessage "[+] Found $($entries.Count) services" -Color Green
        return $entries

    } catch {
        Write-ColoredMessage "[!] Error enumerating services: $_" -Color Red
        return @()
    }
}

function Get-NetworkConnections {
    Write-ColoredMessage "`n=== Analyzing Network Connections ===" -Color Cyan

    Write-Host "[*] Gathering network connections..."

    try {
        $connections = Get-NetTCPConnection -State Listen,Established -ErrorAction Stop
        $entries = @()

        $totalConns = $connections.Count
        $currentConn = 0

        foreach ($conn in $connections) {
            $currentConn++
            Write-Progress -Activity "Analyzing Network Connections" -Status "Processing $currentConn of $totalConns" -PercentComplete (($currentConn / $totalConns) * 100)

            $process = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
            $exePath = $null
            $hash = $null
            $vtReport = $null
            $signature = "Unknown"

            if ($process) {
                try {
                    $exePath = $process.Path
                    if ($exePath -and (Test-Path $exePath)) {
                        $hash = Get-FileHashQuick -FilePath $exePath

                        if ($hash -and $script:VTEnabled) {
                            $vtReport = Get-VirusTotalReport -Hash $hash
                        }

                        $sig = Get-AuthenticodeSignature -FilePath $exePath -ErrorAction SilentlyContinue
                        if ($sig -and $sig.SignerCertificate) {
                            $signature = $sig.SignerCertificate.Subject
                        }
                    }
                } catch {
                    # Process may have exited
                }
            }

            $riskLevel = Get-RiskLevel -Signature $signature -VTReport $vtReport

            # Safely format VT detections
            $vtDetections = "N/A"
            if ($vtReport) {
                try {
                    $mal = [int]$vtReport.Malicious
                    $sus = [int]$vtReport.Suspicious
                    $undet = [int]$vtReport.Undetected
                    $harm = [int]$vtReport.Harmless
                    $total = $mal + $sus + $undet + $harm
                    $vtDetections = "$mal/$total"
                } catch {
                    $vtDetections = "Error"
                }
            }

            $entries += [PSCustomObject]@{
                Type = "Network"
                Protocol = "TCP"
                LocalAddress = $conn.LocalAddress
                LocalPort = $conn.LocalPort
                RemoteAddress = $conn.RemoteAddress
                RemotePort = $conn.RemotePort
                State = $conn.State
                ProcessId = $conn.OwningProcess
                ProcessName = if ($process) { $process.ProcessName } else { "Unknown" }
                ExecutablePath = $exePath
                Publisher = $signature
                SHA256 = $hash
                VT_Malicious = if ($vtReport) { [string]$vtReport.Malicious } else { "N/A" }
                VT_Suspicious = if ($vtReport) { [string]$vtReport.Suspicious } else { "N/A" }
                VT_Detections = $vtDetections
                RiskLevel = $riskLevel
            }
        }

        Write-Progress -Activity "Analyzing Network Connections" -Completed
        Write-ColoredMessage "[+] Found $($entries.Count) network connections" -Color Green
        return $entries

    } catch {
        Write-ColoredMessage "[!] Error gathering network connections: $_" -Color Red
        return @()
    }
}

function Get-RunningProcesses {
    Write-ColoredMessage "`n=== Analyzing Running Processes ===" -Color Cyan

    Write-Host "[*] Enumerating processes..."

    try {
        $processes = Get-Process | Where-Object { $_.Path }
        $entries = @()

        $totalProcs = $processes.Count
        $currentProc = 0

        foreach ($process in $processes) {
            $currentProc++
            Write-Progress -Activity "Analyzing Processes" -Status "Processing $currentProc of $totalProcs" -PercentComplete (($currentProc / $totalProcs) * 100)

            $exePath = $process.Path
            $hash = $null
            $vtReport = $null
            $signature = "Unknown"

            if ($exePath -and (Test-Path $exePath)) {
                $hash = Get-FileHashQuick -FilePath $exePath

                if ($hash -and $script:VTEnabled) {
                    $vtReport = Get-VirusTotalReport -Hash $hash
                }

                try {
                    $sig = Get-AuthenticodeSignature -FilePath $exePath -ErrorAction SilentlyContinue
                    if ($sig -and $sig.SignerCertificate) {
                        $signature = $sig.SignerCertificate.Subject
                    }
                } catch {
                    $signature = "(Not verified)"
                }
            }

            $riskLevel = Get-RiskLevel -Signature $signature -VTReport $vtReport

            # Safely format VT detections
            $vtDetections = "N/A"
            if ($vtReport) {
                try {
                    $mal = [int]$vtReport.Malicious
                    $sus = [int]$vtReport.Suspicious
                    $undet = [int]$vtReport.Undetected
                    $harm = [int]$vtReport.Harmless
                    $total = $mal + $sus + $undet + $harm
                    $vtDetections = "$mal/$total"
                } catch {
                    $vtDetections = "Error"
                }
            }

            $entries += [PSCustomObject]@{
                Type = "Process"
                ProcessName = $process.ProcessName
                ProcessId = $process.Id
                ExecutablePath = $exePath
                Company = $process.Company
                Description = $process.Description
                Publisher = $signature
                SHA256 = $hash
                VT_Malicious = if ($vtReport) { [string]$vtReport.Malicious } else { "N/A" }
                VT_Suspicious = if ($vtReport) { [string]$vtReport.Suspicious } else { "N/A" }
                VT_Detections = $vtDetections
                RiskLevel = $riskLevel
            }
        }

        Write-Progress -Activity "Analyzing Processes" -Completed
        Write-ColoredMessage "[+] Found $($entries.Count) running processes" -Color Green
        return $entries

    } catch {
        Write-ColoredMessage "[!] Error enumerating processes: $_" -Color Red
        return @()
    }
}

function Write-ReportCsv {
    param(
        [AllowNull()][object]$Data,
        [string]$Name,
        [string]$Timestamp
    )

    $rows = @($Data)
    if ($rows.Count -eq 0) {
        Write-ColoredMessage "[*] $Name : no rows" -Color Gray
        return $null
    }

    $path = Join-Path $OutputPath ("{0}_{1}_{2}.csv" -f $env:COMPUTERNAME, $Name, $Timestamp)
    $rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
    Write-ColoredMessage "[+] $Name CSV saved: $path ($($rows.Count) rows)" -Color Green
    [void]$script:AdditionalCsvPaths.Add($path)
    return $path
}

function Get-UserProfileRoots {
    $usersRoot = Join-Path $env:SystemDrive 'Users'
    $excluded = @('All Users', 'Default', 'Default User', 'DefaultAppPool')
    if (-not (Test-Path -LiteralPath $usersRoot)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin $excluded -and $_.Name -notlike 'Default*' }
    )
}

function Get-UserDownloadScanRoots {
    $roots = New-Object System.Collections.Generic.List[object]
    foreach ($profile in (Get-UserProfileRoots)) {
        foreach ($pair in @(
                @{ Location = 'Downloads'; Sub = 'Downloads' },
                @{ Location = 'Desktop'; Sub = 'Desktop' }
            )) {
            $path = Join-Path $profile.FullName $pair.Sub
            if (Test-Path -LiteralPath $path) {
                [void]$roots.Add([pscustomobject]@{
                        User     = $profile.Name
                        Location = $pair.Location
                        Path     = $path
                    })
            }
        }
    }

    $publicRoot = Join-Path $env:SystemDrive 'Users\Public'
    foreach ($pair in @(
            @{ Location = 'Downloads'; Sub = 'Downloads' },
            @{ Location = 'Desktop'; Sub = 'Desktop' }
        )) {
        $path = Join-Path $publicRoot $pair.Sub
        if (Test-Path -LiteralPath $path) {
            [void]$roots.Add([pscustomobject]@{
                    User     = 'Public'
                    Location = $pair.Location
                    Path     = $path
                })
        }
    }

    return @($roots)
}

function Get-ZoneIdentifierInfo {
    param([string]$Path)

    $info = [pscustomobject]@{ ZoneId = $null; ReferrerUrl = $null; HostUrl = $null }
    try {
        $lines = Get-Content -LiteralPath $Path -Stream Zone.Identifier -ErrorAction Stop
        foreach ($line in @($lines)) {
            if ($line -match '^ZoneId=(.+)$') { $info.ZoneId = $Matches[1].Trim() }
            elseif ($line -match '^ReferrerUrl=(.+)$') { $info.ReferrerUrl = $Matches[1].Trim() }
            elseif ($line -match '^HostUrl=(.+)$') { $info.HostUrl = $Matches[1].Trim() }
        }
    }
    catch {
    }

    return $info
}

function Copy-LockedFile {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        return $false
    }

    $destDir = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    try {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
        return $true
    }
    catch {
        $in = $null
        $out = $null
        try {
            $in = [System.IO.File]::Open($Source, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $out = [System.IO.File]::Create($Destination)
            $in.CopyTo($out)
            return $true
        }
        catch {
            Write-ColoredMessage ("[!] Copy failed: {0} ({1})" -f $Source, $_.Exception.Message) -Color Yellow
            return $false
        }
        finally {
            if ($out) { $out.Dispose() }
            if ($in) { $in.Dispose() }
        }
    }
}

function Get-UserDownloadEntries {
    Write-ColoredMessage "`n=== Scanning all user Downloads and Desktop folders ===" -Color Cyan

    $roots = @(Get-UserDownloadScanRoots)
    if ($roots.Count -eq 0) {
        Write-ColoredMessage "[!] No user Downloads/Desktop folders found" -Color Yellow
        return @()
    }

    Write-Host ("[*] Scan roots: {0}" -f (($roots | ForEach-Object { '{0}\{1}' -f $_.User, $_.Location }) -join '; '))

    $entries = New-Object System.Collections.Generic.List[object]
    $scanned = 0
    foreach ($root in $roots) {
        Write-Host ("[*] {0} ({1})" -f $root.Path, $root.User)
        $files = @(Get-ChildItem -LiteralPath $root.Path -File -Force -Recurse -ErrorAction SilentlyContinue)
        foreach ($file in $files) {
            $scanned++
            if ($scanned % 500 -eq 0) {
                Write-Host ("[*] ... {0} files enumerated" -f $scanned)
            }

            $ext = $file.Extension.ToLowerInvariant()
            $hash = $null
            $signature = 'n/a'
            if ($script:DownloadHashExtensions -contains $ext) {
                $hash = Get-FileHashQuick -FilePath $file.FullName
                if ($ext -in @('.exe', '.dll', '.msi', '.scr', '.com', '.sys', '.cpl', '.ocx')) {
                    try {
                        $sig = Get-AuthenticodeSignature -LiteralPath $file.FullName -ErrorAction Stop
                        $signature = if ($sig.SignerCertificate) {
                            '{0} ({1})' -f $sig.Status, $sig.SignerCertificate.Subject
                        } else {
                            [string]$sig.Status
                        }
                    }
                    catch {
                        $signature = 'Unknown'
                    }
                }
            }

            $vtReport = $null
            if ($script:VTEnabled -and $hash) {
                $vtReport = Get-VirusTotalReport -Hash $hash
            }

            $risk = Get-RiskLevel -Signature $signature -VTReport $vtReport
            if ($ext -in @('.exe', '.dll', '.msi', '.scr', '.ps1', '.vbs', '.js', '.bat', '.cmd', '.hta') -and $risk -eq 'Low' -and ($signature -eq 'n/a' -or $signature -eq 'NotSigned' -or $signature -like 'NotSigned*')) {
                $risk = 'Medium'
            }

            $zone = $null
            if ($hash) {
                $zone = Get-ZoneIdentifierInfo -Path $file.FullName
            }

            [void]$entries.Add([pscustomobject]@{
                    Type           = 'UserDownload'
                    User           = $root.User
                    Location       = $root.Location
                    Name           = $file.Name
                    Extension      = $ext
                    Path           = $file.FullName
                    Length         = $file.Length
                    CreationTime   = $file.CreationTime
                    LastWriteTime  = $file.LastWriteTime
                    SHA256         = $hash
                    Signature      = $signature
                    ZoneId         = if ($zone) { $zone.ZoneId } else { $null }
                    ReferrerUrl    = if ($zone) { $zone.ReferrerUrl } else { $null }
                    HostUrl        = if ($zone) { $zone.HostUrl } else { $null }
                    VT_Detections  = if ($vtReport) { $vtReport.Malicious } else { 'N/A' }
                    RiskLevel      = $risk
                })
        }
    }

    Write-ColoredMessage "[+] User Downloads/Desktop files: $($entries.Count) (enumerated $scanned)" -Color Green
    return @($entries)
}

function Get-PrefetchEntries {
    $prefetch = Join-Path $env:WINDIR 'Prefetch'
    if (-not (Test-Path -LiteralPath $prefetch)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $prefetch -File -Force -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 500 |
            ForEach-Object {
                [pscustomobject]@{
                    Name          = $_.Name
                    LastWriteTime = $_.LastWriteTime
                    Length        = $_.Length
                    Path          = $_.FullName
                }
            }
    )
}

function Get-ScheduledTaskEntries {
    try {
        return @(
            Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
                $info = $_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
                $actions = @(
                    foreach ($action in @($_.Actions)) {
                        ('{0} {1}' -f $action.Execute, $action.Arguments).Trim()
                    }
                ) -join '; '

                [pscustomobject]@{
                    TaskName        = $_.TaskName
                    TaskPath        = $_.TaskPath
                    State           = [string]$_.State
                    Principal       = $_.Principal.UserId
                    LastRunTime     = if ($info) { $info.LastRunTime } else { $null }
                    NextRunTime     = if ($info) { $info.NextRunTime } else { $null }
                    LastTaskResult  = if ($info) { $info.LastTaskResult } else { $null }
                    Actions         = $actions
                }
            }
        )
    }
    catch {
        Write-ColoredMessage "[!] Scheduled tasks: $_" -Color Yellow
        return @()
    }
}

function Get-InstalledSoftwareEntries {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
            $name = $_.PSObject.Properties['DisplayName']
            if ($null -eq $name -or [string]::IsNullOrWhiteSpace([string]$name.Value)) {
                return
            }

            $ver = $_.PSObject.Properties['DisplayVersion']
            $pub = $_.PSObject.Properties['Publisher']
            $date = $_.PSObject.Properties['InstallDate']
            [void]$rows.Add([pscustomobject]@{
                    DisplayName    = [string]$name.Value
                    DisplayVersion = if ($ver) { [string]$ver.Value } else { '' }
                    Publisher      = if ($pub) { [string]$pub.Value } else { '' }
                    InstallDate    = if ($date) { [string]$date.Value } else { '' }
                    Hive           = $path
                })
        }
    }

    return @($rows | Sort-Object DisplayName)
}

function Get-LocalAccountEntries {
    $rows = New-Object System.Collections.Generic.List[object]
    try {
        Get-LocalUser -ErrorAction Stop | ForEach-Object {
            [void]$rows.Add([pscustomobject]@{
                    Name        = $_.Name
                    Enabled     = $_.Enabled
                    LastLogon   = $_.LastLogon
                    PasswordRequired = $_.PasswordRequired
                    SID         = $_.SID.Value
                    Description = $_.Description
                })
        }
    }
    catch {
        Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True" -ErrorAction SilentlyContinue | ForEach-Object {
            [void]$rows.Add([pscustomobject]@{
                    Name        = $_.Name
                    Enabled     = -not $_.Disabled
                    LastLogon   = $null
                    PasswordRequired = $null
                    SID         = $_.SID
                    Description = $_.Description
                })
        }
    }

    return @($rows)
}

function Get-LoggedOnUserEntries {
    $rows = New-Object System.Collections.Generic.List[object]
    try {
        $q = query user 2>$null
        if ($q) {
            [void]$rows.Add([pscustomobject]@{ Source = 'quser'; Text = [string]$q })
        }
    }
    catch {
    }

    Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue | ForEach-Object {
        [void]$rows.Add([pscustomobject]@{
                Source = 'Win32_ComputerSystem'
                Text   = $_.UserName
            })
    }

    return @($rows)
}

function Get-DnsCacheEntries {
    try {
        return @(
            Get-DnsClientCache -ErrorAction Stop |
                Select-Object -First 2000 |
                ForEach-Object {
                    [pscustomobject]@{
                        Entry  = $_.Entry
                        Data   = $_.Data
                        Type   = [string]$_.Type
                        Status = [string]$_.Status
                    }
                }
        )
    }
    catch {
        return @()
    }
}

function Get-ArpEntries {
    $rows = New-Object System.Collections.Generic.List[object]
    try {
        Get-NetNeighbor -ErrorAction Stop | ForEach-Object {
            [void]$rows.Add([pscustomobject]@{
                    IPAddress        = $_.IPAddress
                    LinkLayerAddress = $_.LinkLayerAddress
                    State            = [string]$_.State
                    InterfaceAlias   = $_.InterfaceAlias
                })
        }
    }
    catch {
    }

    return @($rows)
}

function Get-LocalAdminEntries {
    $rows = New-Object System.Collections.Generic.List[object]
    try {
        Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | ForEach-Object {
            [void]$rows.Add([pscustomobject]@{
                    Name            = $_.Name
                    SID             = $_.SID.Value
                    ObjectClass     = [string]$_.ObjectClass
                    PrincipalSource = [string]$_.PrincipalSource
                })
        }
    }
    catch {
        try {
            $net = net localgroup administrators 2>$null
            [void]$rows.Add([pscustomobject]@{
                    Name            = 'net localgroup'
                    SID             = ''
                    ObjectClass     = 'raw'
                    PrincipalSource = [string]$net
                })
        }
        catch {
        }
    }

    return @($rows)
}

function Get-RmmInventoryEntries {
    $rows = New-Object System.Collections.Generic.List[object]
    $rx = $script:RmmNamePattern

    Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match $rx -or $_.DisplayName -match $rx -or $_.PathName -match $rx
    } | ForEach-Object {
        [void]$rows.Add([pscustomobject]@{
                Kind        = 'Service'
                Name        = $_.Name
                DisplayName = $_.DisplayName
                State       = $_.State
                StartMode   = $_.StartMode
                Path        = $_.PathName
            })
    }

    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -match $rx -or ($_.Path -and $_.Path -match $rx)
    } | ForEach-Object {
        [void]$rows.Add([pscustomobject]@{
                Kind        = 'Process'
                Name        = $_.ProcessName
                DisplayName = $_.Id
                State       = 'Running'
                StartMode   = ''
                Path        = $_.Path
            })
    }

    foreach ($path in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
            $dn = $_.PSObject.Properties['DisplayName']
            if ($null -eq $dn -or [string]$dn.Value -notmatch $rx) {
                return
            }

            $loc = $_.PSObject.Properties['InstallLocation']
            [void]$rows.Add([pscustomobject]@{
                    Kind        = 'Uninstall'
                    Name        = [string]$dn.Value
                    DisplayName = [string]$dn.Value
                    State       = 'Installed'
                    StartMode   = ''
                    Path        = if ($loc) { [string]$loc.Value } else { '' }
                })
        }
    }

    return @($rows)
}

function Get-DefenderDetectionEntries {
    $rows = New-Object System.Collections.Generic.List[object]
    try {
        Get-MpThreatDetection -ErrorAction Stop | ForEach-Object {
            $resources = @($_.Resources) -join '; '
            [void]$rows.Add([pscustomobject]@{
                    InitialDetectionTime       = $_.InitialDetectionTime
                    LastThreatStatusChangeTime = $_.LastThreatStatusChangeTime
                    ThreatID                   = $_.ThreatID
                    ActionSuccess              = $_.ActionSuccess
                    DomainUser                 = $_.DomainUser
                    ProcessName                = $_.ProcessName
                    Resources                  = $resources
                    CleaningActionID           = $_.CleaningActionID
                })
        }
    }
    catch {
        Write-ColoredMessage "[!] Get-MpThreatDetection unavailable" -Color Yellow
    }

    return @($rows)
}

function Copy-PowerShellHistory {
    param([string]$Timestamp)

    Write-ColoredMessage "`n=== Copying PowerShell history and transcripts ===" -Color Cyan
    $destRoot = Join-Path $script:ArtifactRoot 'PowerShell'
    $index = New-Object System.Collections.Generic.List[object]

    foreach ($profile in (Get-UserProfileRoots)) {
        $userDest = Join-Path $destRoot $profile.Name
        $candidates = New-Object System.Collections.Generic.List[System.IO.FileInfo]

        $psrl = Join-Path $profile.FullName 'AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine'
        if (Test-Path -LiteralPath $psrl) {
            foreach ($f in @(Get-ChildItem -LiteralPath $psrl -File -Filter '*_history.txt' -Force -ErrorAction SilentlyContinue)) {
                [void]$candidates.Add($f)
            }
        }

        foreach ($rel in @('Documents\PowerShell', 'Documents\WindowsPowerShell')) {
            $t = Join-Path $profile.FullName $rel
            if (Test-Path -LiteralPath $t) {
                foreach ($f in @(Get-ChildItem -LiteralPath $t -File -Force -Recurse -Filter '*transcript*' -ErrorAction SilentlyContinue)) {
                    [void]$candidates.Add($f)
                }
            }
        }

        $temp = Join-Path $profile.FullName 'AppData\Local\Temp'
        if (Test-Path -LiteralPath $temp) {
            foreach ($f in @(Get-ChildItem -LiteralPath $temp -File -Force -Filter '*PowerShell_transcript*' -ErrorAction SilentlyContinue)) {
                [void]$candidates.Add($f)
            }
        }

        foreach ($file in $candidates) {
            $copied = Join-Path $userDest $file.Name
            $ok = Copy-LockedFile -Source $file.FullName -Destination $copied
            [void]$index.Add([pscustomobject]@{
                    User         = $profile.Name
                    Kind         = $(if ($file.Name -like '*transcript*') { 'Transcript' } else { 'History' })
                    SourcePath   = $file.FullName
                    CopiedPath   = $(if ($ok) { $copied } else { '' })
                    Length       = $file.Length
                    LastWriteTime = $file.LastWriteTime
                    Copied       = $ok
                })
        }
    }

    Write-ReportCsv -Data $index -Name 'PowerShellHistory' -Timestamp $Timestamp | Out-Null
    Write-ColoredMessage ("[+] PowerShell history/transcript sources: {0}" -f $index.Count) -Color Green
}

function Copy-ExecutionHives {
    param([string]$Timestamp)

    Write-ColoredMessage "`n=== Copying Amcache and SYSTEM hives (offline parse) ===" -Color Cyan
    $dest = Join-Path $script:ArtifactRoot 'Hives'
    $index = New-Object System.Collections.Generic.List[object]
    $sources = @(
        (Join-Path $env:WINDIR 'AppCompat\Programs\Amcache.hve'),
        (Join-Path $env:WINDIR 'AppCompat\Programs\Amcache.hve.LOG1'),
        (Join-Path $env:WINDIR 'AppCompat\Programs\Amcache.hve.LOG2'),
        (Join-Path $env:WINDIR 'System32\config\SYSTEM'),
        (Join-Path $env:WINDIR 'System32\config\SYSTEM.LOG1'),
        (Join-Path $env:WINDIR 'System32\config\SYSTEM.LOG2')
    )

    foreach ($source in $sources) {
        if (-not (Test-Path -LiteralPath $source)) {
            continue
        }

        $copied = Join-Path $dest (Split-Path -Leaf $source)
        $ok = Copy-LockedFile -Source $source -Destination $copied
        $hash = $null
        if ($ok) {
            $hash = Get-FileHashQuick -FilePath $copied
        }

        [void]$index.Add([pscustomobject]@{
                Source   = $source
                Copied   = $ok
                Dest     = $(if ($ok) { $copied } else { '' })
                SHA256   = $hash
                Length   = (Get-Item -LiteralPath $source -Force -ErrorAction SilentlyContinue).Length
            })
    }

    Write-ReportCsv -Data $index -Name 'HiveCopies' -Timestamp $Timestamp | Out-Null
}

function Copy-BrowserHistoryDatabases {
    param([string]$Timestamp)

    Write-ColoredMessage "`n=== Copying Chrome/Edge History databases (no live query) ===" -Color Cyan
    $destRoot = Join-Path $script:ArtifactRoot 'BrowserHistory'
    $index = New-Object System.Collections.Generic.List[object]

    foreach ($profile in (Get-UserProfileRoots)) {
        $pairs = @(
            @{ Browser = 'Chrome'; Root = (Join-Path $profile.FullName 'AppData\Local\Google\Chrome\User Data') },
            @{ Browser = 'Edge'; Root = (Join-Path $profile.FullName 'AppData\Local\Microsoft\Edge\User Data') },
            @{ Browser = 'Brave'; Root = (Join-Path $profile.FullName 'AppData\Local\BraveSoftware\Brave-Browser\User Data') }
        )

        foreach ($pair in $pairs) {
            if (-not (Test-Path -LiteralPath $pair.Root)) {
                continue
            }

            Get-ChildItem -LiteralPath $pair.Root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $history = Join-Path $_.FullName 'History'
                if (-not (Test-Path -LiteralPath $history)) {
                    return
                }

                $leaf = '{0}_{1}_{2}_History' -f $profile.Name, $pair.Browser, $_.Name
                $copied = Join-Path $destRoot $leaf
                $ok = Copy-LockedFile -Source $history -Destination $copied
                $journal = $history + '-journal'
                if (Test-Path -LiteralPath $journal) {
                    Copy-LockedFile -Source $journal -Destination ($copied + '-journal') | Out-Null
                }

                [void]$index.Add([pscustomobject]@{
                        User     = $profile.Name
                        Browser  = $pair.Browser
                        Profile  = $_.Name
                        Source   = $history
                        Copied   = $ok
                        Dest     = $(if ($ok) { $copied } else { '' })
                        SHA256   = $(if ($ok) { Get-FileHashQuick -FilePath $copied } else { $null })
                    })
            }
        }
    }

    Write-ReportCsv -Data $index -Name 'BrowserHistoryCopies' -Timestamp $Timestamp | Out-Null
    Write-ColoredMessage ("[+] Browser History DBs copied: {0}" -f @($index | Where-Object Copied).Count) -Color Green
}

function Copy-DefenderDetectionHistory {
    param([string]$Timestamp)

    $src = Join-Path $env:ProgramData 'Microsoft\Windows Defender\Scans\History\Service\DetectionHistory'
    if (-not (Test-Path -LiteralPath $src)) {
        return
    }

    $dest = Join-Path $script:ArtifactRoot 'Defender\DetectionHistory'
    Write-ColoredMessage "`n=== Copying Defender DetectionHistory ===" -Color Cyan
    try {
        Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force -ErrorAction Stop
        Write-ColoredMessage "[+] Defender DetectionHistory copied" -Color Green
    }
    catch {
        Write-ColoredMessage "[!] Defender DetectionHistory copy failed: $_" -Color Yellow
    }
}

function Write-CollectionManifest {
    param([string]$Timestamp)

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $admin = ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    $fileRows = New-Object System.Collections.Generic.List[object]
    $scanRoots = New-Object System.Collections.Generic.List[string]
    if ($script:EventLogFolder) { [void]$scanRoots.Add($script:EventLogFolder) }
    if ($script:ArtifactRoot) { [void]$scanRoots.Add($script:ArtifactRoot) }
    foreach ($csv in @($script:AdditionalCsvPaths)) {
        if ($csv -and (Test-Path -LiteralPath $csv)) {
            [void]$scanRoots.Add($csv)
        }
    }

    foreach ($root in $scanRoots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) {
            continue
        }

        if ((Get-Item -LiteralPath $root).PSIsContainer) {
            Get-ChildItem -LiteralPath $root -File -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -like '*.zip' -or $_.Name -like '*.sha256' -or $_.FullName -match '\\DetectionHistory\\') {
                    return
                }

                [void]$fileRows.Add([pscustomobject]@{
                        Path   = $_.FullName
                        Length = $_.Length
                        SHA256 = (Get-FileHashQuick -FilePath $_.FullName)
                    })
            }
        }
        else {
            [void]$fileRows.Add([pscustomobject]@{
                    Path   = $root
                    Length = (Get-Item -LiteralPath $root).Length
                    SHA256 = (Get-FileHashQuick -FilePath $root)
                })
        }
    }

    $manifest = [ordered]@{
        ScriptVersion = $script:Version
        ComputerName  = $env:COMPUTERNAME
        StartUtc      = if ($script:CollectionStartUtc) { $script:CollectionStartUtc.ToString('o') } else { $null }
        EndUtc        = [datetime]::UtcNow.ToString('o')
        Collector     = $identity.Name
        IsAdmin       = $admin
        OSCaption     = if ($os) { $os.Caption } else { '' }
        OSVersion     = if ($os) { $os.Version } else { [Environment]::OSVersion.Version.ToString() }
        OutputPath    = $OutputPath
        ArtifactRoot  = $script:ArtifactRoot
        EventLogFolder = $script:EventLogFolder
        VirusTotal    = [bool]$script:VTEnabled
        FileCount     = $fileRows.Count
        Files         = @($fileRows)
    }

    $jsonPath = Join-Path $OutputPath ("{0}_CollectionSummary_{1}.json" -f $env:COMPUTERNAME, $Timestamp)
    ($manifest | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    Write-ColoredMessage "[+] Collection manifest: $jsonPath" -Color Green
    [void]$script:AdditionalCsvPaths.Add($jsonPath)
    return $jsonPath
}

function Write-ZipHashFile {
    param([string]$ZipPath)

    if (-not $ZipPath -or -not (Test-Path -LiteralPath $ZipPath)) {
        return
    }

    $hash = Get-FileHashQuick -FilePath $ZipPath
    $hashPath = $ZipPath + '.sha256'
    $line = '{0}  {1}' -f $hash, (Split-Path -Leaf $ZipPath)
    Set-Content -LiteralPath $hashPath -Value $line -Encoding ASCII
    Write-ColoredMessage "[+] Zip hash: $hashPath" -Color Green
}

function Export-PriorityEvidence {
    param([string]$Timestamp)

    Write-ColoredMessage "`n=== Priority evidence (Zone.ID / PS history / hives / browser / admins / RMM / Defender) ===" -Color Cyan
    Write-ReportCsv -Data (Get-LocalAdminEntries) -Name 'LocalAdministrators' -Timestamp $Timestamp | Out-Null
    Write-ReportCsv -Data (Get-RmmInventoryEntries) -Name 'RmmInventory' -Timestamp $Timestamp | Out-Null
    Write-ReportCsv -Data (Get-DefenderDetectionEntries) -Name 'DefenderDetections' -Timestamp $Timestamp | Out-Null
    Copy-PowerShellHistory -Timestamp $Timestamp
    Copy-ExecutionHives -Timestamp $Timestamp
    Copy-BrowserHistoryDatabases -Timestamp $Timestamp
    Copy-DefenderDetectionHistory -Timestamp $Timestamp
}

function Export-HostArtifactReports {
    param([string]$Timestamp)

    Write-ColoredMessage "`n=== Collecting host artifacts (Harkins-style) ===" -Color Cyan
    Write-ReportCsv -Data (Get-PrefetchEntries) -Name 'Prefetch' -Timestamp $Timestamp | Out-Null
    Write-ReportCsv -Data (Get-ScheduledTaskEntries) -Name 'ScheduledTasks' -Timestamp $Timestamp | Out-Null
    Write-ReportCsv -Data (Get-InstalledSoftwareEntries) -Name 'InstalledSoftware' -Timestamp $Timestamp | Out-Null
    Write-ReportCsv -Data (Get-LocalAccountEntries) -Name 'LocalUsers' -Timestamp $Timestamp | Out-Null
    Write-ReportCsv -Data (Get-LoggedOnUserEntries) -Name 'LoggedOnUsers' -Timestamp $Timestamp | Out-Null
    Write-ReportCsv -Data (Get-DnsCacheEntries) -Name 'DnsCache' -Timestamp $Timestamp | Out-Null
    Write-ReportCsv -Data (Get-ArpEntries) -Name 'Arp' -Timestamp $Timestamp | Out-Null

    $sysInfoPath = Join-Path $OutputPath ("{0}_SystemInfo_{1}.txt" -f $env:COMPUTERNAME, $Timestamp)
    try {
        systeminfo | Out-File -FilePath $sysInfoPath -Encoding UTF8
        Write-ColoredMessage "[+] SystemInfo saved: $sysInfoPath" -Color Green
    }
    catch {
        Write-ColoredMessage "[!] systeminfo failed: $_" -Color Yellow
    }
}

function Export-EventLogs {
    param([string]$Timestamp)

    Write-ColoredMessage "`n=== Exporting event logs (Harkins set) ===" -Color Cyan
    $logFolder = Join-Path $OutputPath ("EventLogs_{0}" -f $Timestamp)
    New-Item -ItemType Directory -Path $logFolder -Force | Out-Null

    $logs = @(
        'Security', 'System', 'Application',
        'Microsoft-Windows-PowerShell/Operational', 'Windows PowerShell',
        'Microsoft-Windows-Sysmon/Operational',
        'Microsoft-Windows-TaskScheduler/Operational',
        'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational',
        'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational',
        'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational',
        'Microsoft-Windows-WinRM/Operational',
        'Microsoft-Windows-WMI-Activity/Operational',
        'Microsoft-Windows-SMBClient/Security',
        'Microsoft-Windows-SMBServer/Security',
        'Microsoft-Windows-Windows Defender/Operational',
        'Microsoft-Windows-CodeIntegrity/Operational',
        'Microsoft-Windows-Bits-Client/Operational',
        'Microsoft-Windows-Windows Firewall With Advanced Security/Firewall',
        'Microsoft-Windows-DNS-Client/Operational'
    )

    $exported = 0
    foreach ($log in $logs) {
        $safe = ($log -replace '[\\/]', '-')
        $outFile = Join-Path $logFolder ($safe + '.evtx')
        try {
            wevtutil epl $log $outFile 2>$null
            if (Test-Path -LiteralPath $outFile) {
                $exported++
                Write-Host (" [+] {0}" -f $log)
            }
            else {
                Write-Host (" [-] {0} (missing or empty)" -f $log)
            }
        }
        catch {
            Write-Host (" [-] {0} ({1})" -f $log, $_.Exception.Message)
        }
    }

    Write-ColoredMessage "[+] Event logs exported: $exported / $($logs.Count) -> $logFolder" -Color Green
    $script:EventLogFolder = $logFolder
    return $logFolder
}

function Export-ToExcel {
    param(
        [Parameter(Mandatory=$true)]
        [object[]]$Data,

        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [Parameter(Mandatory=$true)]
        [string]$WorksheetName
    )

    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false

        if (Test-Path $FilePath) {
            $workbook = $excel.Workbooks.Open($FilePath)
        } else {
            $workbook = $excel.Workbooks.Add()
        }

        # Check if worksheet exists
        $worksheet = $workbook.Worksheets | Where-Object { $_.Name -eq $WorksheetName }
        if (!$worksheet) {
            $worksheet = $workbook.Worksheets.Add()
            $worksheet.Name = $WorksheetName
        } else {
            $worksheet.Cells.Clear()
        }

        # Convert data to CSV format first (safer and more reliable)
        $csvData = $Data | ConvertTo-Csv -NoTypeInformation

        # Parse CSV to get clean string data
        $csvLines = $csvData
        $headers = $csvLines[0] -split ',' | ForEach-Object { $_.Trim('"') }

        # Write headers
        for ($col = 0; $col -lt $headers.Count; $col++) {
            $worksheet.Cells.Item(1, $col + 1) = $headers[$col]
        }

        # Format header row
        $headerRow = $worksheet.Rows.Item(1)
        $headerRow.Font.Bold = $true
        $headerRow.Interior.ColorIndex = 15  # Gray

        # Write data rows
        for ($row = 1; $row -lt $csvLines.Count; $row++) {
            $line = $csvLines[$row]
            # Simple CSV parsing - split by comma but respect quotes
            $values = @()
            $currentValue = ""
            $inQuotes = $false

            for ($i = 0; $i -lt $line.Length; $i++) {
                $char = $line[$i]
                if ($char -eq '"') {
                    $inQuotes = -not $inQuotes
                } elseif ($char -eq ',' -and -not $inQuotes) {
                    $values += $currentValue.Trim('"')
                    $currentValue = ""
                } else {
                    $currentValue += $char
                }
            }
            $values += $currentValue.Trim('"')

            # Write row
            for ($col = 0; $col -lt $values.Count; $col++) {
                $worksheet.Cells.Item($row + 1, $col + 1) = $values[$col]
            }

            # Apply color coding based on RiskLevel
            $riskLevel = $Data[$row - 1].RiskLevel
            $excelRow = $row + 1

            switch ($riskLevel) {
                "High" {
                    $rowRange = $worksheet.Rows.Item($excelRow)
                    $rowRange.Interior.Color = 255  # Red
                    $rowRange.Font.Color = 16777215  # White
                }
                "Medium" {
                    $rowRange = $worksheet.Rows.Item($excelRow)
                    $rowRange.Interior.Color = 65535  # Yellow
                    $rowRange.Font.Color = 0  # Black
                }
                "Low" {
                    $rowRange = $worksheet.Rows.Item($excelRow)
                    $rowRange.Interior.Color = 5287936  # Green
                    $rowRange.Font.Color = 16777215  # White
                }
            }
        }

        # Auto-fit columns
        $worksheet.UsedRange.EntireColumn.AutoFit() | Out-Null

        # Save and close
        # Excel file format constant: 51 = xlWorkbookDefault (.xlsx)
        $workbook.SaveAs($FilePath, 51)
        $workbook.Close($false)  # $false = don't save again
        $excel.Quit()

        # Clean up COM objects
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($worksheet) | Out-Null
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($workbook) | Out-Null
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()

        return $true

    } catch {
        Write-ColoredMessage "[!] Excel export error: $_" -Color Red
        if ($workbook) {
            try { $workbook.Close($false) } catch {}
        }
        if ($excel) {
            try { $excel.Quit() } catch {}
        }
        return $false
    }
}

function Export-Results {
    param(
        [object[]]$AutorunEntries,
        [object[]]$ServiceEntries,
        [object[]]$NetworkEntries,
        [object[]]$ProcessEntries
    )

    Write-ColoredMessage "`n=== Exporting Results ===" -Color Cyan

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $hostname = $env:COMPUTERNAME

    # ALWAYS default to CSV export (works in ScreenConnect and all environments)
    # Excel COM is NEVER checked unless -ExportXLSX flag is explicitly provided
    # This prevents Excel registration issues in headless environments
    $excelAvailable = $false
    
    if ($ExportXLSX) {
        # Only check for Excel if user explicitly requested XLSX export
        Write-ColoredMessage "[*] XLSX export requested - checking for Microsoft Excel..." -Color Yellow
        try {
            $testExcel = New-Object -ComObject Excel.Application -ErrorAction Stop
            $testExcel.Quit()
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($testExcel) | Out-Null
            $excelAvailable = $true
            if ($CombinedWorkbook) {
                Write-ColoredMessage "[+] Microsoft Excel detected - will export to single combined XLSX workbook (slower)" -Color Green
            } else {
                Write-ColoredMessage "[+] Microsoft Excel detected - will export to separate XLSX files (faster)" -Color Green
            }
        } catch {
            Write-ColoredMessage "[!] Microsoft Excel not available - falling back to CSV export" -Color Yellow
            $excelAvailable = $false
        }
    } else {
        # Default: CSV export (no Excel COM initialization)
        Write-ColoredMessage "[+] Exporting to CSV format (default - no Excel required)" -Color Green
    }

    if ($excelAvailable -and $CombinedWorkbook) {
        # Export to Excel with color coding - SINGLE WORKBOOK
        # Ensure absolute path for Excel
        $absoluteOutputPath = (Resolve-Path -Path $OutputPath).Path
        $excelPath = Join-Path $absoluteOutputPath "${hostname}_ForensicAnalysis_${timestamp}.xlsx"

        try {
            # Create Excel instance ONCE
            $excel = New-Object -ComObject Excel.Application
            $excel.Visible = $false
            $excel.DisplayAlerts = $false

            # Create workbook ONCE
            $workbook = $excel.Workbooks.Add()

            # Helper function to add worksheet with data - REFACTORED for reliability
            $addWorksheet = {
                param($wb, $data, $sheetName)

                if ($data.Count -eq 0) { return }

                Write-Host "[*] Adding $sheetName worksheet..."

                # Add new worksheet
                $worksheet = $wb.Worksheets.Add()
                $worksheet.Name = $sheetName

                # Convert data to CSV format first (safer than direct Excel manipulation)
                $csvData = $data | ConvertTo-Csv -NoTypeInformation

                # Parse CSV to get clean string data
                $csvLines = $csvData
                $headers = $csvLines[0] -split ',' | ForEach-Object { $_.Trim('"') }

                # Write headers
                for ($col = 0; $col -lt $headers.Count; $col++) {
                    $worksheet.Cells.Item(1, $col + 1) = $headers[$col]
                }

                # Format header row
                $headerRow = $worksheet.Rows.Item(1)
                $headerRow.Font.Bold = $true
                $headerRow.Interior.ColorIndex = 15  # Gray

                # Write data rows
                for ($row = 1; $row -lt $csvLines.Count; $row++) {
                    $line = $csvLines[$row]
                    # Simple CSV parsing - split by comma but respect quotes
                    $values = @()
                    $currentValue = ""
                    $inQuotes = $false

                    for ($i = 0; $i -lt $line.Length; $i++) {
                        $char = $line[$i]
                        if ($char -eq '"') {
                            $inQuotes = -not $inQuotes
                        } elseif ($char -eq ',' -and -not $inQuotes) {
                            $values += $currentValue.Trim('"')
                            $currentValue = ""
                        } else {
                            $currentValue += $char
                        }
                    }
                    $values += $currentValue.Trim('"')

                    # Write row
                    for ($col = 0; $col -lt $values.Count; $col++) {
                        $worksheet.Cells.Item($row + 1, $col + 1) = $values[$col]
                    }

                    # Apply color coding based on RiskLevel (column varies by sheet)
                    $riskLevel = $data[$row - 1].RiskLevel
                    $excelRow = $row + 1

                    switch ($riskLevel) {
                        "High" {
                            $rowRange = $worksheet.Rows.Item($excelRow)
                            $rowRange.Interior.Color = 255  # Red
                            $rowRange.Font.Color = 16777215  # White
                        }
                        "Medium" {
                            $rowRange = $worksheet.Rows.Item($excelRow)
                            $rowRange.Interior.Color = 65535  # Yellow
                            $rowRange.Font.Color = 0  # Black
                        }
                        "Low" {
                            $rowRange = $worksheet.Rows.Item($excelRow)
                            $rowRange.Interior.Color = 5287936  # Green
                            $rowRange.Font.Color = 16777215  # White
                        }
                    }
                }

                # Auto-fit columns
                $worksheet.UsedRange.EntireColumn.AutoFit() | Out-Null
            }

            # Add all worksheets
            if ($AutorunEntries.Count -gt 0) {
                & $addWorksheet $workbook $AutorunEntries "Autoruns"
            }
            if ($ServiceEntries.Count -gt 0) {
                & $addWorksheet $workbook $ServiceEntries "Services"
            }
            if ($NetworkEntries.Count -gt 0) {
                & $addWorksheet $workbook $NetworkEntries "Network"
            }
            if ($ProcessEntries.Count -gt 0) {
                & $addWorksheet $workbook $ProcessEntries "Processes"
            }

            # Delete the default blank worksheets
            $excel.DisplayAlerts = $false
            foreach ($sheet in $workbook.Worksheets) {
                if ($sheet.Name -like "Sheet*" -and $sheet.UsedRange.Cells.Count -eq 1) {
                    try {
                        $sheet.Delete()
                    } catch {
                        # Ignore if we can't delete (might be the last sheet)
                    }
                }
            }

            # Save workbook
            Write-Host "[*] Saving workbook..."
            # Excel file format constant: 51 = xlWorkbookDefault (.xlsx)
            $workbook.SaveAs($excelPath, 51)
            $workbook.Close($false)
            $excel.Quit()

            # Clean up COM objects
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($workbook) | Out-Null
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()

            Write-ColoredMessage "`n[+] Excel report saved: $excelPath" -Color Green
            return $excelPath

        } catch {
            Write-ColoredMessage "[!] Excel export failed: $_" -Color Red
            Write-ColoredMessage "[!] Falling back to CSV export" -Color Yellow

            # Cleanup on error
            if ($workbook) {
                try { $workbook.Close($false) } catch {}
            }
            if ($excel) {
                try { $excel.Quit() } catch {}
            }

            $excelAvailable = $false
        }
    }

    if ($excelAvailable -and !$CombinedWorkbook) {
        # Export to separate Excel files (faster than combined workbook)
        $excelPaths = @()

        # Resolve absolute path once
        $absoluteOutputPath = (Resolve-Path -Path $OutputPath).Path

        try {
            if ($AutorunEntries.Count -gt 0) {
                $excelPath = Join-Path $absoluteOutputPath "${hostname}_Autoruns_${timestamp}.xlsx"
                if (Export-ToExcel -Data $AutorunEntries -FilePath $excelPath -WorksheetName "Autoruns") {
                    Write-ColoredMessage "[+] Autoruns Excel saved: $excelPath" -Color Green
                    $excelPaths += $excelPath
                }
            }

            if ($ServiceEntries.Count -gt 0) {
                $excelPath = Join-Path $absoluteOutputPath "${hostname}_Services_${timestamp}.xlsx"
                if (Export-ToExcel -Data $ServiceEntries -FilePath $excelPath -WorksheetName "Services") {
                    Write-ColoredMessage "[+] Services Excel saved: $excelPath" -Color Green
                    $excelPaths += $excelPath
                }
            }

            if ($NetworkEntries.Count -gt 0) {
                $excelPath = Join-Path $absoluteOutputPath "${hostname}_Network_${timestamp}.xlsx"
                if (Export-ToExcel -Data $NetworkEntries -FilePath $excelPath -WorksheetName "Network") {
                    Write-ColoredMessage "[+] Network Excel saved: $excelPath" -Color Green
                    $excelPaths += $excelPath
                }
            }

            if ($ProcessEntries.Count -gt 0) {
                $excelPath = Join-Path $absoluteOutputPath "${hostname}_Processes_${timestamp}.xlsx"
                if (Export-ToExcel -Data $ProcessEntries -FilePath $excelPath -WorksheetName "Processes") {
                    Write-ColoredMessage "[+] Processes Excel saved: $excelPath" -Color Green
                    $excelPaths += $excelPath
                }
            }

            if ($excelPaths.Count -gt 0) {
                Write-ColoredMessage "`n[+] Exported $($excelPaths.Count) Excel files with color coding" -Color Green
                return $excelPaths -join ", "
            } else {
                # All Excel exports failed silently (COM errors when running as SYSTEM)
                Write-ColoredMessage "[!] All Excel exports failed (likely running as SYSTEM account)" -Color Yellow
                Write-ColoredMessage "[!] Falling back to CSV export" -Color Yellow
                $excelAvailable = $false
            }
        } catch {
            Write-ColoredMessage "[!] Separate Excel export failed: $_" -Color Red
            Write-ColoredMessage "[!] Falling back to CSV export" -Color Yellow
            $excelAvailable = $false
        }
    }

    if (!$excelAvailable) {
        # Export to CSV
        $csvPaths = @()

        if ($AutorunEntries.Count -gt 0) {
            $csvPath = Join-Path $OutputPath "${hostname}_Autoruns_${timestamp}.csv"
            $AutorunEntries | Export-Csv -Path $csvPath -NoTypeInformation
            Write-ColoredMessage "[+] Autoruns CSV saved: $csvPath" -Color Green
            $csvPaths += $csvPath
        }

        if ($ServiceEntries.Count -gt 0) {
            $csvPath = Join-Path $OutputPath "${hostname}_Services_${timestamp}.csv"
            $ServiceEntries | Export-Csv -Path $csvPath -NoTypeInformation
            Write-ColoredMessage "[+] Services CSV saved: $csvPath" -Color Green
            $csvPaths += $csvPath
        }

        if ($NetworkEntries.Count -gt 0) {
            $csvPath = Join-Path $OutputPath "${hostname}_Network_${timestamp}.csv"
            $NetworkEntries | Export-Csv -Path $csvPath -NoTypeInformation
            Write-ColoredMessage "[+] Network CSV saved: $csvPath" -Color Green
            $csvPaths += $csvPath
        }

        if ($ProcessEntries.Count -gt 0) {
            $csvPath = Join-Path $OutputPath "${hostname}_Processes_${timestamp}.csv"
            $ProcessEntries | Export-Csv -Path $csvPath -NoTypeInformation
            Write-ColoredMessage "[+] Processes CSV saved: $csvPath" -Color Green
            $csvPaths += $csvPath
        }

        foreach ($extra in @($script:AdditionalCsvPaths)) {
            if ($extra -and (Test-Path -LiteralPath $extra) -and ($csvPaths -notcontains $extra)) {
                $csvPaths += $extra
            }
        }

        $zipSources = @($csvPaths)
        if ($script:EventLogFolder -and (Test-Path -LiteralPath $script:EventLogFolder)) {
            $zipSources += $script:EventLogFolder
        }

        if ($script:ArtifactRoot -and (Test-Path -LiteralPath $script:ArtifactRoot)) {
            $zipSources += $script:ArtifactRoot
        }

        foreach ($p in $csvPaths) {
            if ($p -and ($script:AdditionalCsvPaths -notcontains $p)) {
                [void]$script:AdditionalCsvPaths.Add($p)
            }
        }

        Write-CollectionManifest -Timestamp $timestamp | Out-Null
        foreach ($extra in @($script:AdditionalCsvPaths)) {
            if ($extra -and (Test-Path -LiteralPath $extra) -and ($zipSources -notcontains $extra)) {
                $zipSources += $extra
            }
        }

        # Create zip archive of CSV files + event logs + artifacts
        if ($zipSources.Count -gt 0) {
            try {
                $zipPath = Join-Path $OutputPath "${hostname}_ForensicAnalysis_${timestamp}.zip"
                Compress-Archive -Path $zipSources -DestinationPath $zipPath -Force -ErrorAction Stop
                $script:ZipPath = $zipPath
                Write-ColoredMessage "[+] Reports archived: $zipPath" -Color Green
                Write-ZipHashFile -ZipPath $zipPath
            } catch {
                Write-ColoredMessage "[!] Warning: Failed to create zip archive: $_" -Color Yellow
            }
        }

        Write-ColoredMessage "`n[!] Note: CSV files do not include color coding. Use Excel for color-coded risk levels." -Color Yellow
        return $csvPaths -join ", "
    }
}

function Show-Summary {
    param(
        [object[]]$AutorunEntries,
        [object[]]$ServiceEntries,
        [object[]]$NetworkEntries,
        [object[]]$ProcessEntries,
        [AllowNull()][object]$DownloadEntries = $null
    )

    $allEntries = @()
    $allEntries += $AutorunEntries
    $allEntries += $ServiceEntries
    $allEntries += $NetworkEntries
    $allEntries += $ProcessEntries
    $allEntries += @($DownloadEntries)

    $highRisk = ($allEntries | Where-Object { $_.RiskLevel -eq "High" }).Count
    $mediumRisk = ($allEntries | Where-Object { $_.RiskLevel -eq "Medium" }).Count
    $lowRisk = ($allEntries | Where-Object { $_.RiskLevel -eq "Low" }).Count

    Write-ColoredMessage "`n=== Analysis Summary ===" -Color Cyan
    Write-Host "Total Items Analyzed: $($allEntries.Count)"
    Write-ColoredMessage "  High Risk (Red):    $highRisk" -Color Red
    Write-ColoredMessage "  Medium Risk (Yellow): $mediumRisk" -Color Yellow
    Write-ColoredMessage "  Low Risk (Green):   $lowRisk" -Color Green

    $downloadCount = @($DownloadEntries).Count
    Write-Host "`nBreakdown by Category:"
    Write-Host "  Autoruns:           $($AutorunEntries.Count)"
    Write-Host "  Services:           $($ServiceEntries.Count)"
    Write-Host "  Network:            $($NetworkEntries.Count)"
    Write-Host "  Processes:          $($ProcessEntries.Count)"
    Write-Host "  User Downloads/Desktop: $downloadCount"

    if ($script:VTEnabled) {
        $vtScanned = ($allEntries | Where-Object { $_.VT_Detections -ne "N/A" }).Count
        Write-Host "`nVirusTotal Scans: $vtScanned items"
    }

    if ($highRisk -gt 0) {
        Write-ColoredMessage "`n[!] WARNING: Found $highRisk high-risk items requiring immediate attention!" -Color Red
    }
}

# Main execution
try {
    $ErrorActionPreference = "Stop"

    Initialize-Environment
    Get-SysinternalsTools

    # Prompt for VT API key if enabled but not provided (interactive hosts only)
    if ($EnableVirusTotal -and [string]::IsNullOrWhiteSpace($script:VTApiKey)) {
        if ([Environment]::UserInteractive) {
            $script:VTApiKey = Read-Host "Enter your VirusTotal API key"
            $script:VTEnabled = ![string]::IsNullOrWhiteSpace($script:VTApiKey)
        }
        else {
            Write-ColoredMessage "[!] -EnableVirusTotal set but no key; skipping VT (non-interactive)" -Color Yellow
            $script:VTEnabled = $false
        }
    }

    $runStamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:CollectionStartUtc = [datetime]::UtcNow
    $script:ArtifactRoot = Join-Path $OutputPath ("Artifacts_{0}" -f $runStamp)
    New-Item -ItemType Directory -Path $script:ArtifactRoot -Force | Out-Null

    # Run analyses
    $autorunEntries = Get-AutorunEntries
    $serviceEntries = Get-ServiceEntries
    $networkEntries = Get-NetworkConnections
    $processEntries = Get-RunningProcesses

    $downloadEntries = @()
    if (-not $SkipDownloads) {
        $downloadEntries = @(Get-UserDownloadEntries)
        Write-ReportCsv -Data $downloadEntries -Name 'UserDownloads' -Timestamp $runStamp | Out-Null
    }

    if (-not $SkipHostArtifacts) {
        Export-HostArtifactReports -Timestamp $runStamp
    }

    $savedEapPriority = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        Export-PriorityEvidence -Timestamp $runStamp
    }
    finally {
        $ErrorActionPreference = $savedEapPriority
    }

    if (-not $SkipEventLogs) {
        $savedEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            Export-EventLogs -Timestamp $runStamp | Out-Null
        }
        finally {
            $ErrorActionPreference = $savedEap
        }
    }

    # Export results
    $reportPath = Export-Results -AutorunEntries $autorunEntries -ServiceEntries $serviceEntries -NetworkEntries $networkEntries -ProcessEntries $processEntries

    # Show summary
    Show-Summary -AutorunEntries $autorunEntries -ServiceEntries $serviceEntries -NetworkEntries $networkEntries -ProcessEntries $processEntries -DownloadEntries $downloadEntries

    Write-ColoredMessage "`n=== Forensic Analysis Complete ===" -Color Cyan
    Write-ColoredMessage "Report(s): $reportPath" -Color Green

    # Cleanup Sysinternals tools if requested
    if ($CleanupTools) {
        Write-ColoredMessage "`n[*] Cleaning up Sysinternals tools..." -Color Yellow
        if (Test-Path $ToolsPath) {
            try {
                Remove-Item -Path $ToolsPath -Recurse -Force -ErrorAction Stop
                Write-ColoredMessage "[+] Sysinternals tools deleted successfully" -Color Green
            } catch {
                Write-ColoredMessage "[!] Warning: Failed to delete tools directory: $_" -Color Yellow
            }
        } else {
            Write-ColoredMessage "[*] Tools directory not found, nothing to clean up" -Color Gray
        }
    }

} catch {
    Write-ColoredMessage "`n[!] Fatal Error: $_" -Color Red
    Write-ColoredMessage $_.ScriptStackTrace -Color Red

    # Cleanup tools even on error if requested
    if ($CleanupTools -and (Test-Path $ToolsPath)) {
        Write-ColoredMessage "`n[*] Cleaning up Sysinternals tools (error cleanup)..." -Color Yellow
        try {
            Remove-Item -Path $ToolsPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-ColoredMessage "[+] Sysinternals tools deleted" -Color Green
        } catch {
            # Silent failure on error cleanup
        }
    }

    exit 1
}
