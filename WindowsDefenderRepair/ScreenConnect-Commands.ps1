# Re-enable Windows Defender real-time protection and start WinDefend / WdNisSvc.

#!ps
#timeout=120000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsDefenderRepair-bootstrap/1.0.1'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsDefenderRepair/Repair-WindowsDefender.ps1?ref=main'); & ([scriptblock]::Create($script)) -Exit

# Nuclear: MpCmdRun -ResetPlatform, then the same RTP repair
#!ps
#timeout=300000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsDefenderRepair-bootstrap/1.0.1'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsDefenderRepair/Repair-WindowsDefender.ps1?ref=main'); & ([scriptblock]::Create($script)) -ResetPlatform -Exit
