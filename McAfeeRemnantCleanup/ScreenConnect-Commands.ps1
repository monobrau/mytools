# McAfee remnant cleanup for ScreenConnect.

# Scan
#!ps
#timeout=180000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','McAfeeRemnantCleanup-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/McAfeeRemnantCleanup/Remove-McAfeeRemnants.ps1?ref=main'); & ([scriptblock]::Create($script)) -CheckOnly -Exit

# Remove
#!ps
#timeout=300000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','McAfeeRemnantCleanup-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/McAfeeRemnantCleanup/Remove-McAfeeRemnants.ps1?ref=main'); & ([scriptblock]::Create($script)) -Remediate -Exit
