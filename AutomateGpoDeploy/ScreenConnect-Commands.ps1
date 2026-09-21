# AutomateGpoDeploy for ScreenConnect (run on the client DC / RSAT box).
# #!ps + #timeout must be first or SC defaults to 60s.
# Set $token / $locationId / $domain / $clientName from the location deployment ticket.
# Do not commit live installer tokens.

# Create GPO, stage baked MSI, link at domain (workstation WMI filter)
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'
try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}
$server='river-run.hostedrmm.com'
$locationId=1
$token='YOUR_INSTALLER_TOKEN'
$domain=''
$clientName='Contoso'
$locationName='Main'
$linkToDomain=$true
if(-not $token -or $token -eq 'YOUR_INSTALLER_TOKEN'){throw 'Set $token to the Windows MSI installer token from the location ticket.'}
$wc=New-Object Net.WebClient
$wc.Headers.Add('User-Agent','AutomateGpoDeploy-bootstrap/1.0')
$wc.Headers.Add('Accept','application/vnd.github.raw')
$script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/AutomateGpoDeploy/Install-AutomateGPO.ps1?ref=main')
$params=@{ Server=$server; LocationID=$locationId; Token=$token; ClientName=$clientName; LocationName=$locationName }
if($domain){ $params.Domain=$domain }
if($linkToDomain){ $params.LinkToDomain=$true }
& ([scriptblock]::Create($script)) @params

# Dry-run (transform only, no SYSVOL/GPO writes)
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'
try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}
$server='river-run.hostedrmm.com'
$locationId=1
$token='YOUR_INSTALLER_TOKEN'
if(-not $token -or $token -eq 'YOUR_INSTALLER_TOKEN'){throw 'Set $token to the Windows MSI installer token from the location ticket.'}
$wc=New-Object Net.WebClient
$wc.Headers.Add('User-Agent','AutomateGpoDeploy-bootstrap/1.0')
$wc.Headers.Add('Accept','application/vnd.github.raw')
$script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/AutomateGpoDeploy/Install-AutomateGPO.ps1?ref=main')
& ([scriptblock]::Create($script)) -Server $server -LocationID $locationId -Token $token -DryRun
