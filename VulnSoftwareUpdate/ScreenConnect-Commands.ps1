# ScreenConnect paste helpers for VulnSoftwareUpdate.
# BACKSTAGE paste is unreliable on some hosts - prefer Commands tab #!ps.
# Default: check installed catalog products and silently update those that are behind.

# =============================================================================
# COMMANDS tab — CHECK ONLY (#!ps)
# =============================================================================
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','VulnSoftwareUpdate-bootstrap/1.4.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/VulnSoftwareUpdate/Update-VulnSoftware.ps1?ref=main'); & ([scriptblock]::Create($script)) -CheckOnly -Exit

# =============================================================================
# COMMANDS tab — UPDATE INSTALLED / OUTDATED (#!ps)
# =============================================================================
#!ps
#timeout=1800000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','VulnSoftwareUpdate-bootstrap/1.4.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/VulnSoftwareUpdate/Update-VulnSoftware.ps1?ref=main'); & ([scriptblock]::Create($script)) -Exit

# =============================================================================
# COMMANDS tab — LIST CATALOG (#!ps)
# =============================================================================
#!ps
#timeout=120000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','VulnSoftwareUpdate-bootstrap/1.4.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/VulnSoftwareUpdate/Update-VulnSoftware.ps1?ref=main'); & ([scriptblock]::Create($script)) -List -Exit

# =============================================================================
# COMMANDS tab — SINGLE PRODUCT (example: ShareX check) (#!ps)
# =============================================================================
#!ps
#timeout=600000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','VulnSoftwareUpdate-bootstrap/1.4.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/VulnSoftwareUpdate/Update-VulnSoftware.ps1?ref=main'); & ([scriptblock]::Create($script)) -Product ShareX -CheckOnly -Exit

# =============================================================================
# COMMANDS tab — M365 ONLY update (non-disruptive C2R) (#!ps)
# =============================================================================
#!ps
#timeout=600000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','VulnSoftwareUpdate-bootstrap/1.4.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/VulnSoftwareUpdate/Update-VulnSoftware.ps1?ref=main'); & ([scriptblock]::Create($script)) -Product M365Apps -Exit

# =============================================================================
# COMMANDS tab — DOTNET ONLY check (#!ps)
# =============================================================================
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','VulnSoftwareUpdate-bootstrap/1.4.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/VulnSoftwareUpdate/Update-VulnSoftware.ps1?ref=main'); & ([scriptblock]::Create($script)) -Product DotNet -CheckOnly -Exit

# =============================================================================
# COMMANDS tab — BROWSERS check (Chrome/Edge/Firefox) (#!ps)
# NOTE: update (without -CheckOnly) may close open browser sessions.
# =============================================================================
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','VulnSoftwareUpdate-bootstrap/1.4.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/VulnSoftwareUpdate/Update-VulnSoftware.ps1?ref=main'); & ([scriptblock]::Create($script)) -Product Chrome,Edge,Firefox -CheckOnly -Exit

# =============================================================================
# COMMANDS tab — BROWSERS update (#!ps) — may close open browser sessions
# =============================================================================
#!ps
#timeout=1800000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','VulnSoftwareUpdate-bootstrap/1.4.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/VulnSoftwareUpdate/Update-VulnSoftware.ps1?ref=main'); & ([scriptblock]::Create($script)) -Product Chrome,Edge,Firefox -Exit
