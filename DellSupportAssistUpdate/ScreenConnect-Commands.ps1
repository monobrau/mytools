# ScreenConnect paste helpers for DellSupportAssistUpdate.
# BACKSTAGE: one line only. Commands tab: the #!ps block.

# =============================================================================
# BACKSTAGE — UPDATE
# =============================================================================
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','DellSupportAssistUpdate-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/DellSupportAssistUpdate/Update-DellSupportAssist.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script))

# =============================================================================
# BACKSTAGE — CHECK ONLY
# =============================================================================
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','DellSupportAssistUpdate-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/DellSupportAssistUpdate/Update-DellSupportAssist.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script)) -CheckOnly

# =============================================================================
# COMMANDS tab — UPDATE (#!ps)
# =============================================================================
#!ps
#timeout=600000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','DellSupportAssistUpdate-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/DellSupportAssistUpdate/Update-DellSupportAssist.ps1?ref=main'); & ([scriptblock]::Create($script)) -Exit

# =============================================================================
# COMMANDS tab — CHECK ONLY (#!ps)
# =============================================================================
#!ps
#timeout=300000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','DellSupportAssistUpdate-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/DellSupportAssistUpdate/Update-DellSupportAssist.ps1?ref=main'); & ([scriptblock]::Create($script)) -CheckOnly -Exit
