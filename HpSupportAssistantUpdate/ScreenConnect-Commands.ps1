# ScreenConnect paste helpers for HpSupportAssistantUpdate.
#
# BACKSTAGE: use ONE-LINERS only (multi-line paste is often reversed).
# Downloads via GitHub Contents API (avoids stale raw.githubusercontent.com CDN cache).
#
# On Windows 10, prefer -Uninstall for v-scan remediation (patched SoftPaq ~9.47 often will not install).

# =============================================================================
# BACKSTAGE — CHECK / VULN STATUS (one line)
# =============================================================================
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.1.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script))

# =============================================================================
# BACKSTAGE — SILENT UNINSTALL / V-SCAN REMEDIATION (one line)
# =============================================================================
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.1.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script)) -Uninstall

# =============================================================================
# BACKSTAGE — SILENT UPDATE (Win11 / patched SoftPaq only; Win10 usually refused)
# =============================================================================
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.1.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script)) -Update

# =============================================================================
# COMMANDS tab — CHECK (#!ps)
# =============================================================================
#!ps
#timeout=300000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.1.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?ref=main'); & ([scriptblock]::Create($script)) -Exit

# =============================================================================
# COMMANDS tab — UNINSTALL (#!ps)
# =============================================================================
#!ps
#timeout=600000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.1.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?ref=main'); & ([scriptblock]::Create($script)) -Uninstall -Exit

# =============================================================================
# COMMANDS tab — UPDATE (#!ps)
# =============================================================================
#!ps
#timeout=600000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.1.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?ref=main'); & ([scriptblock]::Create($script)) -Update -Exit
