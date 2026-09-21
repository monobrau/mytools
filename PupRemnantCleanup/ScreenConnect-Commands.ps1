# PUP remnant cleanup for ScreenConnect.
# BACKSTAGE: one-liners only (multi-line paste is often reversed).
# Default: dry-run every catalog family; report what is present.

# =============================================================================
# BACKSTAGE — SCAN (default AskToolbar)
# =============================================================================
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','PupRemnantCleanup-bootstrap/1.3.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/PupRemnantCleanup/Invoke-PupRemnantCleanup.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script)) -NoExit

# =============================================================================
# BACKSTAGE — REMOVE AskToolbar remnants
# =============================================================================
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','PupRemnantCleanup-bootstrap/1.3.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/PupRemnantCleanup/Invoke-PupRemnantCleanup.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script)) -Remove -NoExit

# =============================================================================
# COMMANDS tab — SCAN (#!ps)
# =============================================================================
#!ps
#timeout=180000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','PupRemnantCleanup-bootstrap/1.3.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/PupRemnantCleanup/Invoke-PupRemnantCleanup.ps1?ref=main'); & ([scriptblock]::Create($script)) -CheckOnly -Exit

# =============================================================================
# COMMANDS tab — REMOVE (#!ps)
# =============================================================================
#!ps
#timeout=300000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','PupRemnantCleanup-bootstrap/1.3.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/PupRemnantCleanup/Invoke-PupRemnantCleanup.ps1?ref=main'); & ([scriptblock]::Create($script)) -Remove -Exit
