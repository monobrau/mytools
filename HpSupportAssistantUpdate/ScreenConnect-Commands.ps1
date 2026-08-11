# ScreenConnect paste helpers for HpSupportAssistantUpdate.
#
# BACKSTAGE: use ONE-LINERS only (multi-line paste is often reversed).
# Downloads via GitHub Contents API (avoids stale raw.githubusercontent.com CDN cache).

# =============================================================================
# BACKSTAGE — CHECK ONLY (one line)
# =============================================================================
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.0.3'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script))

# =============================================================================
# BACKSTAGE — SILENT UPDATE (one line)
# =============================================================================
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.0.3'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script)) -Update

# =============================================================================
# COMMANDS tab — CHECK ONLY (#!ps)
# =============================================================================
#!ps
#timeout=300000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.0.3'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?ref=main'); & ([scriptblock]::Create($script)) -Exit

# =============================================================================
# COMMANDS tab — SILENT UPDATE (#!ps)
# =============================================================================
#!ps
#timeout=600000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.0.3'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?ref=main'); & ([scriptblock]::Create($script)) -Update -Exit

# =============================================================================
# COMMANDS tab — CHECK ONLY (#!pwsh)
# =============================================================================
#!pwsh
#timeout=300000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.0.3'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?ref=main'); & ([scriptblock]::Create($script)) -Exit

# =============================================================================
# COMMANDS tab — SILENT UPDATE (#!pwsh)
# =============================================================================
#!pwsh
#timeout=600000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.0.3'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?ref=main'); & ([scriptblock]::Create($script)) -Update -Exit
