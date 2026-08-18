# Inky / IPW Exchange Online transport rule cleanup.
# Run in a PowerShell session after Connect-ExchangeOnline (admin workstation).

# List only
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','InkyTransportRuleCleanup-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/InkyTransportRuleCleanup/Remove-InkyTransportRules.ps1?ref=main'); & ([scriptblock]::Create($script)) -CheckOnly

# Remove (no interactive confirm)
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','InkyTransportRuleCleanup-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/InkyTransportRuleCleanup/Remove-InkyTransportRules.ps1?ref=main'); & ([scriptblock]::Create($script)) -Delete
