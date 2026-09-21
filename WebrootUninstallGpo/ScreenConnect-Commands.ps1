# WebrootUninstallGpo for ScreenConnect (run on the client DC / RSAT box).
# #!ps + #timeout must be first or SC defaults to 60s.
# Set $domain from the client AD DNS name. Do not commit live domains or keycodes.

# Create GPO, link at domain (workstation WMI filter)
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'
try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}
$domain='contoso.com'
$linkToDomain=$true
$keyCode=''
$wc=New-Object Net.WebClient
$wc.Headers.Add('User-Agent','WebrootUninstallGpo-bootstrap/1.1.0')
$wc.Headers.Add('Accept','application/vnd.github.raw')
$script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WebrootUninstallGpo/New-WebrootUninstallGpo.ps1?ref=main')
$params=@{ Domain=$domain }
if($linkToDomain){ $params.LinkToDomain=$true }
if($keyCode){ $params.KeyCode=$keyCode }
& ([scriptblock]::Create($script)) @params

# Dry-run (print Immediate Task cmd, no AD/SYSVOL writes)
#!ps
#timeout=180000
#maxlength=200000
$ProgressPreference='SilentlyContinue'
try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}
$wc=New-Object Net.WebClient
$wc.Headers.Add('User-Agent','WebrootUninstallGpo-bootstrap/1.1.0')
$wc.Headers.Add('Accept','application/vnd.github.raw')
$script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WebrootUninstallGpo/New-WebrootUninstallGpo.ps1?ref=main')
& ([scriptblock]::Create($script)) -Domain 'contoso.com' -DryRun

# Fleet status via AD + C$ admin shares (run on DC / RSAT)
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'
try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}
$domain=''
$wc=New-Object Net.WebClient
$wc.Headers.Add('User-Agent','WebrootUninstallGpo-bootstrap/1.1.2')
$wc.Headers.Add('Accept','application/vnd.github.raw')
$script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WebrootUninstallGpo/Get-WebrootFleetStatus.ps1?ref=main')
$params=@{}
if($domain){ $params.Domain=$domain }
& ([scriptblock]::Create($script)) @params
