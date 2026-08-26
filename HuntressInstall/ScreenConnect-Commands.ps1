# Huntress silent install for ScreenConnect.
# Paste real -AccountKey / -OrgKey at run time (ScToolLauncher). Never commit keys.
# Uses official /ACCT_KEY= (not /ACCOUNT_KEY=).

#!ps
#timeout=600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HuntressInstall-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HuntressInstall/Install-HuntressAgent.ps1?ref=main'); & ([scriptblock]::Create($script)) -AccountKey 'YOUR_ACCOUNT_KEY' -OrgKey 'YOUR_ORG_KEY' -Exit
