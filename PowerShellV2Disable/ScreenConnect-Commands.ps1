# Disable Windows PowerShell 2.0 optional features for ScreenConnect.
# BACKSTAGE: one-liners only (multi-line paste is often reversed).
# Apply-only. Does not restart.

# =============================================================================
# BACKSTAGE — DISABLE
# =============================================================================
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','PowerShellV2Disable-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/PowerShellV2Disable/Disable-PowerShellV2.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script)) -NoExit

# =============================================================================
# COMMANDS tab — DISABLE (#!ps)
# =============================================================================
#!ps
#timeout=300000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','PowerShellV2Disable-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/PowerShellV2Disable/Disable-PowerShellV2.ps1?ref=main'); & ([scriptblock]::Create($script)) -Exit
