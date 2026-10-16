# ScreenConnect paste helpers for HpImageAssistant.
# BACKSTAGE: one line only. Commands tab: the #!ps block.
# Non-HP PCs exit 0. Apply installs only unattended (SSM) SoftPaqs.

# =============================================================================
# BACKSTAGE — INSTALL UNATTENDED (no reboot)
# =============================================================================
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpImageAssistant-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpImageAssistant/Invoke-HpImageAssistant.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script))

# =============================================================================
# BACKSTAGE — CHECK ONLY
# =============================================================================
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpImageAssistant-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpImageAssistant/Invoke-HpImageAssistant.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script)) -CheckOnly

# =============================================================================
# COMMANDS tab — INSTALL UNATTENDED (#!ps, no reboot)
# =============================================================================
#!ps
#timeout=7200000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpImageAssistant-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpImageAssistant/Invoke-HpImageAssistant.ps1?ref=main'); & ([scriptblock]::Create($script)) -Exit

# =============================================================================
# COMMANDS tab — CHECK ONLY (#!ps)
# =============================================================================
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpImageAssistant-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpImageAssistant/Invoke-HpImageAssistant.ps1?ref=main'); & ([scriptblock]::Create($script)) -CheckOnly -Exit

# =============================================================================
# COMMANDS tab — INSTALL + REBOOT WHEN REQUIRED (#!ps)
# =============================================================================
#!ps
#timeout=7200000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpImageAssistant-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpImageAssistant/Invoke-HpImageAssistant.ps1?ref=main'); & ([scriptblock]::Create($script)) -Reboot -Exit
