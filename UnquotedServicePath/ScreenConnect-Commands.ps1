# Unquoted service paths. Read-only. Prints a quote command when a user can write a split folder.

# Scan
#!ps
#timeout=180000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','UnquotedServicePath-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/UnquotedServicePath/Get-UnquotedServicePath.ps1?ref=main'); & ([scriptblock]::Create($script)) -Exit
