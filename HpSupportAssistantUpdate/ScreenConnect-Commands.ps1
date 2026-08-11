# ScreenConnect paste helpers for HpSupportAssistantUpdate.
#
# BACKSTAGE: use the ONE-LINERS only. Multi-line paste is often applied
# bottom-to-top in Backstage PowerShell and breaks the download.
#
# COMMANDS tab: multi-line #!ps / #!pwsh blocks are fine.

# =============================================================================
# BACKSTAGE — CHECK ONLY (one line — copy this entire line)
# =============================================================================
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u='https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss'); $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.0.3'); $script=[Text.Encoding]::UTF8.GetString($wc.DownloadData($u)); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script))

# =============================================================================
# BACKSTAGE — SILENT UPDATE (one line — copy this entire line)
# =============================================================================
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u='https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss'); $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.0.3'); $script=[Text.Encoding]::UTF8.GetString($wc.DownloadData($u)); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script)) -Update

# =============================================================================
# COMMANDS tab — CHECK ONLY (#!ps)
# =============================================================================
#!ps
#timeout=300000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u='https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss'); $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.0.3'); $script=[Text.Encoding]::UTF8.GetString($wc.DownloadData($u)); & ([scriptblock]::Create($script)) -Exit

# =============================================================================
# COMMANDS tab — SILENT UPDATE (#!ps)
# =============================================================================
#!ps
#timeout=600000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u='https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss'); $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.0.3'); $script=[Text.Encoding]::UTF8.GetString($wc.DownloadData($u)); & ([scriptblock]::Create($script)) -Update -Exit

# =============================================================================
# COMMANDS tab — CHECK ONLY (#!pwsh)
# =============================================================================
#!pwsh
#timeout=300000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; $u='https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss'); $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.0.3'); $script=[Text.Encoding]::UTF8.GetString($wc.DownloadData($u)); & ([scriptblock]::Create($script)) -Exit

# =============================================================================
# COMMANDS tab — SILENT UPDATE (#!pwsh)
# =============================================================================
#!pwsh
#timeout=600000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; $u='https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss'); $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.0.3'); $script=[Text.Encoding]::UTF8.GetString($wc.DownloadData($u)); & ([scriptblock]::Create($script)) -Update -Exit
