# Windows Update — quality (non-feature) and feature. Prefer elevated.
# Default install does not reboot. -Reboot restarts when required.

# Quality scan
#!ps
#timeout=600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsUpdate-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsUpdate/Invoke-WindowsUpdate.ps1?ref=main'); & ([scriptblock]::Create($script)) -Quality -CheckOnly -Exit

# Quality install, no reboot
#!ps
#timeout=3600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsUpdate-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsUpdate/Invoke-WindowsUpdate.ps1?ref=main'); & ([scriptblock]::Create($script)) -Quality -Exit

# Quality install, auto reboot
#!ps
#timeout=3600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsUpdate-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsUpdate/Invoke-WindowsUpdate.ps1?ref=main'); & ([scriptblock]::Create($script)) -Quality -Reboot -Exit

# Feature scan
#!ps
#timeout=600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsUpdate-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsUpdate/Invoke-WindowsUpdate.ps1?ref=main'); & ([scriptblock]::Create($script)) -Feature -CheckOnly -Exit

# Feature install, no reboot
#!ps
#timeout=14400000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsUpdate-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsUpdate/Invoke-WindowsUpdate.ps1?ref=main'); & ([scriptblock]::Create($script)) -Feature -Exit

# Feature install, auto reboot
#!ps
#timeout=14400000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsUpdate-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsUpdate/Invoke-WindowsUpdate.ps1?ref=main'); & ([scriptblock]::Create($script)) -Feature -Reboot -Exit
