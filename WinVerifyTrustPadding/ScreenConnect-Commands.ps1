# WinVerifyTrust CVE-2013-3900 for ScreenConnect.
# BACKSTAGE: one-liners only (multi-line paste is often reversed).
# Default: dry run. -Remediate writes EnableCertPaddingCheck. Does not restart.

# =============================================================================
# BACKSTAGE — SCAN
# =============================================================================
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WinVerifyTrustPadding-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WinVerifyTrustPadding/Enable-WinVerifyTrustPaddingCheck.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script)) -CheckOnly -NoExit

# =============================================================================
# BACKSTAGE — APPLY
# =============================================================================
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WinVerifyTrustPadding-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WinVerifyTrustPadding/Enable-WinVerifyTrustPaddingCheck.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script)) -Remediate -NoExit

# =============================================================================
# COMMANDS tab — SCAN (#!ps)
# =============================================================================
#!ps
#timeout=120000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WinVerifyTrustPadding-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WinVerifyTrustPadding/Enable-WinVerifyTrustPaddingCheck.ps1?ref=main'); & ([scriptblock]::Create($script)) -CheckOnly -Exit

# =============================================================================
# COMMANDS tab — APPLY (#!ps)
# =============================================================================
#!ps
#timeout=120000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WinVerifyTrustPadding-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WinVerifyTrustPadding/Enable-WinVerifyTrustPaddingCheck.ps1?ref=main'); & ([scriptblock]::Create($script)) -Remediate -Exit
