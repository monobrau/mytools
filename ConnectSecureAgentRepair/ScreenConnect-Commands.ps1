# ConnectSecure (CyberCNS) agent check / repair for ScreenConnect.

# Scan only
#!ps
#timeout=120000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','ConnectSecureAgentRepair-bootstrap/1.0.9'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/ConnectSecureAgentRepair/Repair-CyberCNSAgent.ps1?ref=main'); & ([scriptblock]::Create($script)) -CheckOnly -SkipIfRunning -Exit

# Fleet / scan-prep: remediates only if CyberCNSAgent is not Running
#!ps
#timeout=600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','ConnectSecureAgentRepair-bootstrap/1.0.9'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/ConnectSecureAgentRepair/Repair-CyberCNSAgent.ps1?ref=main'); & ([scriptblock]::Create($script)) -Remediate -SkipIfRunning -CompanyId 'YOUR_COMPANY_ID' -EnvironmentId 'YOUR_ENVIRONMENT_ID' -InstallToken 'YOUR_INSTALL_TOKEN' -Exit

# Force wipe + reinstall even if Running (paste real IDs/token; never commit tokens)
#!ps
#timeout=600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','ConnectSecureAgentRepair-bootstrap/1.0.9'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/ConnectSecureAgentRepair/Repair-CyberCNSAgent.ps1?ref=main'); & ([scriptblock]::Create($script)) -Remediate -CompanyId 'YOUR_COMPANY_ID' -EnvironmentId 'YOUR_ENVIRONMENT_ID' -InstallToken 'YOUR_INSTALL_TOKEN' -Exit
