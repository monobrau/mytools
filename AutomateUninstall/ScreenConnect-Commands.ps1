# ConnectWise Automate agent uninstall for ScreenConnect.
# Removes the LabTech / Automate RMM agent only. ScreenConnect stays.

# Scan
#!ps
#timeout=180000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','AutomateUninstall-bootstrap/1.1.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/AutomateUninstall/Uninstall-AutomateAgent.ps1?ref=main'); & ([scriptblock]::Create($script)) -CheckOnly -Exit

# Uninstall
#!ps
#timeout=600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','AutomateUninstall-bootstrap/1.1.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/AutomateUninstall/Uninstall-AutomateAgent.ps1?ref=main'); & ([scriptblock]::Create($script)) -Remediate -Exit

# Uninstall a probe agent
#!ps
#timeout=600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','AutomateUninstall-bootstrap/1.1.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/AutomateUninstall/Uninstall-AutomateAgent.ps1?ref=main'); & ([scriptblock]::Create($script)) -Remediate -Force -Exit

# Reinstall from the server, location, and cached MSI already on this PC
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','AutomateUninstall-bootstrap/1.1.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/AutomateUninstall/Uninstall-AutomateAgent.ps1?ref=main'); & ([scriptblock]::Create($script)) -Reinstall -Exit

# Reinstall a probe agent from this PC
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','AutomateUninstall-bootstrap/1.1.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/AutomateUninstall/Uninstall-AutomateAgent.ps1?ref=main'); & ([scriptblock]::Create($script)) -Reinstall -Force -Exit
