# ScreenConnect paste helpers for DotNetUpdate.
# Prefer Commands tab #!ps. Same-major .NET 6+ security patches only.

# =============================================================================
# COMMANDS tab — CHECK ONLY (#!ps)
# =============================================================================
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','DotNetUpdate-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/DotNetUpdate/Update-DotNetRuntimes.ps1?ref=main'); & ([scriptblock]::Create($script)) -CheckOnly -Exit

# =============================================================================
# COMMANDS tab — UPDATE (#!ps)
# =============================================================================
#!ps
#timeout=1800000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','DotNetUpdate-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/DotNetUpdate/Update-DotNetRuntimes.ps1?ref=main'); & ([scriptblock]::Create($script)) -Exit
