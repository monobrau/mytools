# ScreenConnect paste helpers for TeamsClassicRemnantCheck.
# BACKSTAGE: one-liners only (multi-line paste is often reversed).
# Default: verify Classic / per-user Teams remnants are gone after cleanup.

# =============================================================================
# BACKSTAGE — CHECK (default)
# =============================================================================
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','TeamsClassicRemnantCheck-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/TeamsClassicRemnantCheck/Test-ClassicTeamsRemnants.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script))

# =============================================================================
# BACKSTAGE — DETAILED CHECK (shortcuts count as fail)
# =============================================================================
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','TeamsClassicRemnantCheck-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/TeamsClassicRemnantCheck/Test-ClassicTeamsRemnants.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script)) -Detailed

# =============================================================================
# COMMANDS tab — CHECK (#!ps)
# =============================================================================
#!ps
#timeout=300000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','TeamsClassicRemnantCheck-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/TeamsClassicRemnantCheck/Test-ClassicTeamsRemnants.ps1?ref=main'); & ([scriptblock]::Create($script)) -Exit

# =============================================================================
# COMMANDS tab — DETAILED (#!ps)
# =============================================================================
#!ps
#timeout=300000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','TeamsClassicRemnantCheck-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/TeamsClassicRemnantCheck/Test-ClassicTeamsRemnants.ps1?ref=main'); & ([scriptblock]::Create($script)) -Detailed -Exit
