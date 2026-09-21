# Dell TechHub cleanup for ScreenConnect.

# Scan
#!ps
#timeout=180000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','DellTechHubCleanup-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/DellTechHubCleanup/Remove-DellTechHub.ps1?ref=main'); & ([scriptblock]::Create($script)) -CheckOnly -Exit

# Remove
#!ps
#timeout=300000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','DellTechHubCleanup-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/DellTechHubCleanup/Remove-DellTechHub.ps1?ref=main'); & ([scriptblock]::Create($script)) -Remediate -Exit
