# ConnectSecure (CyberCNS) silent install for ScreenConnect.
# Paste real -CompanyId / -EnvironmentId / -InstallToken at run time. Never commit tokens.

#!ps
#timeout=600000
#maxlength=200000
# Fresh install (or leftover Stopped agent). Add -SkipIfRunning for fleet / scan-prep
# (exit 0 if CyberCNSAgent is already Running).
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','ConnectSecureInstall-bootstrap/1.0.8'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/ConnectSecureInstall/Install-ConnectSecureAgent.ps1?ref=main'); & ([scriptblock]::Create($script)) -CompanyId 'YOUR_COMPANY_ID' -EnvironmentId 'YOUR_ENVIRONMENT_ID' -InstallToken 'YOUR_INSTALL_TOKEN' -SkipIfRunning -Exit
