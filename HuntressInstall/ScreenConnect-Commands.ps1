# Huntress silent install for ScreenConnect.
# Paste real -AccountKey / -OrgKey at run time (ScToolLauncher). Never commit keys.
# Uses official /ACCT_KEY= (not /ACCOUNT_KEY=).

#!ps
#timeout=600000
#maxlength=200000
if($PSVersionTable.PSVersion.Major -lt 5){if($env:SC_TOOL_PS5){throw 'PowerShell 5.1 required (this host is running 2.0).'}; $env:SC_TOOL_PS5=1; & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path; exit $LASTEXITCODE}
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HuntressInstall-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HuntressInstall/Install-HuntressAgent.ps1?ref=main'); if ($script -match '(?i)<html|github.com/login|&redirect') { throw 'Download returned HTML, not a script.' }; & ([scriptblock]::Create($script)) -AccountKey 'YOUR_ACCOUNT_KEY' -OrgKey 'YOUR_ORG_KEY' -Exit
