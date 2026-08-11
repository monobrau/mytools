# ScreenConnect — paste ONE complete block (top to bottom). Do not paste line-by-line out of order.
# Downloads Update-HpSupportAssistant.ps1 from GitHub and runs it.

# =============================================================================
# BACKSTAGE PowerShell — CHECK ONLY (keeps console open)
# =============================================================================
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$url = 'https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?' + (Get-Date -Format 'yyyyMMddHHmmss')
$wc = New-Object System.Net.WebClient
$wc.Headers.Add('User-Agent', 'HpSupportAssistantUpdate-bootstrap/1.0.3')
$script = [System.Text.Encoding]::UTF8.GetString($wc.DownloadData($url))
if ($script.Length -gt 0 -and [int][char]$script[0] -eq 0xFEFF) { $script = $script.Substring(1) }
Write-Host ("Downloaded {0} chars from GitHub" -f $script.Length)
& ([scriptblock]::Create($script))

# =============================================================================
# BACKSTAGE PowerShell — SILENT UPDATE (keeps console open)
# =============================================================================
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$url = 'https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?' + (Get-Date -Format 'yyyyMMddHHmmss')
$wc = New-Object System.Net.WebClient
$wc.Headers.Add('User-Agent', 'HpSupportAssistantUpdate-bootstrap/1.0.3')
$script = [System.Text.Encoding]::UTF8.GetString($wc.DownloadData($url))
if ($script.Length -gt 0 -and [int][char]$script[0] -eq 0xFEFF) { $script = $script.Substring(1) }
Write-Host ("Downloaded {0} chars from GitHub" -f $script.Length)
& ([scriptblock]::Create($script)) -Update

# =============================================================================
# COMMANDS tab — CHECK ONLY (#!ps)
# =============================================================================
#!ps
#timeout=300000
#maxlength=100000
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$url = 'https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?' + (Get-Date -Format 'yyyyMMddHHmmss')
$wc = New-Object System.Net.WebClient
$wc.Headers.Add('User-Agent', 'HpSupportAssistantUpdate-bootstrap/1.0.3')
$script = [System.Text.Encoding]::UTF8.GetString($wc.DownloadData($url))
if ($script.Length -gt 0 -and [int][char]$script[0] -eq 0xFEFF) { $script = $script.Substring(1) }
& ([scriptblock]::Create($script)) -Exit

# =============================================================================
# COMMANDS tab — SILENT UPDATE (#!ps)
# =============================================================================
#!ps
#timeout=600000
#maxlength=100000
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$url = 'https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?' + (Get-Date -Format 'yyyyMMddHHmmss')
$wc = New-Object System.Net.WebClient
$wc.Headers.Add('User-Agent', 'HpSupportAssistantUpdate-bootstrap/1.0.3')
$script = [System.Text.Encoding]::UTF8.GetString($wc.DownloadData($url))
if ($script.Length -gt 0 -and [int][char]$script[0] -eq 0xFEFF) { $script = $script.Substring(1) }
& ([scriptblock]::Create($script)) -Update -Exit

# =============================================================================
# COMMANDS tab — CHECK ONLY (#!pwsh)
# =============================================================================
#!pwsh
#timeout=300000
#maxlength=100000
$ProgressPreference = 'SilentlyContinue'
$url = 'https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?' + (Get-Date -Format 'yyyyMMddHHmmss')
$wc = New-Object System.Net.WebClient
$wc.Headers.Add('User-Agent', 'HpSupportAssistantUpdate-bootstrap/1.0.3')
$script = [System.Text.Encoding]::UTF8.GetString($wc.DownloadData($url))
if ($script.Length -gt 0 -and [int][char]$script[0] -eq 0xFEFF) { $script = $script.Substring(1) }
& ([scriptblock]::Create($script)) -Exit

# =============================================================================
# COMMANDS tab — SILENT UPDATE (#!pwsh)
# =============================================================================
#!pwsh
#timeout=600000
#maxlength=100000
$ProgressPreference = 'SilentlyContinue'
$url = 'https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?' + (Get-Date -Format 'yyyyMMddHHmmss')
$wc = New-Object System.Net.WebClient
$wc.Headers.Add('User-Agent', 'HpSupportAssistantUpdate-bootstrap/1.0.3')
$script = [System.Text.Encoding]::UTF8.GetString($wc.DownloadData($url))
if ($script.Length -gt 0 -and [int][char]$script[0] -eq 0xFEFF) { $script = $script.Substring(1) }
& ([scriptblock]::Create($script)) -Update -Exit
