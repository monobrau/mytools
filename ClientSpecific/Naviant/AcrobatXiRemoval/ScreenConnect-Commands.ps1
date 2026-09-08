# Client-specific: Adobe Acrobat XI (EOL) scan / uninstall. Confirm Foxit Reader or Editor.
# Uninstall timeout is 20 minutes — msiexec is often silent for 10+ minutes. Do not rerun or Force while it runs.

# Scan only
#!ps
#timeout=180000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','AcrobatXiRemoval-bootstrap/1.0.1'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/ClientSpecific/Naviant/AcrobatXiRemoval/Remove-AcrobatXi.ps1?ref=main'); & ([scriptblock]::Create($script)) -CheckOnly -Exit

# Uninstall Acrobat XI (skipped if Foxit Reader/Editor is missing)
#!ps
#timeout=1200000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','AcrobatXiRemoval-bootstrap/1.0.1'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/ClientSpecific/Naviant/AcrobatXiRemoval/Remove-AcrobatXi.ps1?ref=main'); & ([scriptblock]::Create($script)) -Uninstall -Exit

# Uninstall Acrobat XI even if Foxit is not installed
#!ps
#timeout=1200000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','AcrobatXiRemoval-bootstrap/1.0.1'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/ClientSpecific/Naviant/AcrobatXiRemoval/Remove-AcrobatXi.ps1?ref=main'); & ([scriptblock]::Create($script)) -Uninstall -Force -Exit
