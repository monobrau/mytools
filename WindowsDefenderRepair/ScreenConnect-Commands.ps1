# Windows Defender RTP check / repair — Backstage only.
# ScreenConnect Commands does not reliably run Set-MpPreference / Get-MpComputerStatus.
# Use ScToolLauncher with Paste format forced to Backstage, or paste a one-liner below
# into an elevated Backstage PowerShell prompt.

# Check services + RTP + tamper (no changes)
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsDefenderRepair-bootstrap/1.0.8'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsDefenderRepair/Repair-WindowsDefender.ps1?ref=main'); & ([scriptblock]::Create($script)) -CheckOnly

# Re-enable RTP + start WinDefend / WdNisSvc
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsDefenderRepair-bootstrap/1.0.8'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsDefenderRepair/Repair-WindowsDefender.ps1?ref=main'); & ([scriptblock]::Create($script))

# Nuclear: MpCmdRun -ResetPlatform, then the same RTP repair
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsDefenderRepair-bootstrap/1.0.8'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsDefenderRepair/Repair-WindowsDefender.ps1?ref=main'); & ([scriptblock]::Create($script)) -ResetPlatform
