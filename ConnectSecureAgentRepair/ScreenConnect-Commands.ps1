# ConnectSecure (CyberCNS) agent check / repair for ScreenConnect.

# Scan only
#!ps
#timeout=120000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','ConnectSecureAgentRepair-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/ConnectSecureAgentRepair/Repair-CyberCNSAgent.ps1?ref=main'); & ([scriptblock]::Create($script)) -CheckOnly -Exit

# Remediate + reinstall (paste real -CompanyId / -EnvironmentId / -InstallToken; never commit tokens)
#!ps
#timeout=600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','ConnectSecureAgentRepair-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/ConnectSecureAgentRepair/Repair-CyberCNSAgent.ps1?ref=main'); & ([scriptblock]::Create($script)) -Remediate -CompanyId 'YOUR_COMPANY_ID' -EnvironmentId 'YOUR_ENVIRONMENT_ID' -InstallToken 'YOUR_INSTALL_TOKEN' -Exit
