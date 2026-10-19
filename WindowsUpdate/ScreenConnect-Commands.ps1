# Windows Update — quality (non-feature), feature, and BIOS/firmware. Prefer elevated.
# Default install does not reboot. -Reboot restarts when required.
# These snippets do not pass -AllowServer. A Windows Server exits 5 and is not changed.
# Add -AllowServer only from the launcher after the confirmation prompt.

# Quality scan
#!ps
#timeout=600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsUpdate-bootstrap/1.1.2'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsUpdate/Invoke-WindowsUpdate.ps1?ref=main'); & ([scriptblock]::Create($script)) -Quality -CheckOnly -Exit

# Quality install, no reboot
#!ps
#timeout=3600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsUpdate-bootstrap/1.1.2'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsUpdate/Invoke-WindowsUpdate.ps1?ref=main'); & ([scriptblock]::Create($script)) -Quality -Exit

# Quality install, auto reboot
#!ps
#timeout=3600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsUpdate-bootstrap/1.1.2'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsUpdate/Invoke-WindowsUpdate.ps1?ref=main'); & ([scriptblock]::Create($script)) -Quality -Reboot -Exit

# Feature scan
#!ps
#timeout=600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsUpdate-bootstrap/1.1.2'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsUpdate/Invoke-WindowsUpdate.ps1?ref=main'); & ([scriptblock]::Create($script)) -Feature -CheckOnly -Exit

# Feature install, no reboot
#!ps
#timeout=14400000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsUpdate-bootstrap/1.1.2'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsUpdate/Invoke-WindowsUpdate.ps1?ref=main'); & ([scriptblock]::Create($script)) -Feature -Exit

# Feature install, auto reboot
#!ps
#timeout=14400000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsUpdate-bootstrap/1.1.2'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsUpdate/Invoke-WindowsUpdate.ps1?ref=main'); & ([scriptblock]::Create($script)) -Feature -Reboot -Exit

# Firmware / BIOS scan
#!ps
#timeout=600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsUpdate-bootstrap/1.1.2'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsUpdate/Invoke-WindowsUpdate.ps1?ref=main'); & ([scriptblock]::Create($script)) -Firmware -CheckOnly -Exit

# Firmware / BIOS install, no reboot
#!ps
#timeout=3600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsUpdate-bootstrap/1.1.2'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsUpdate/Invoke-WindowsUpdate.ps1?ref=main'); & ([scriptblock]::Create($script)) -Firmware -Exit

# Firmware / BIOS install, auto reboot
#!ps
#timeout=3600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsUpdate-bootstrap/1.1.2'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsUpdate/Invoke-WindowsUpdate.ps1?ref=main'); & ([scriptblock]::Create($script)) -Firmware -Reboot -Exit

# Feature progress, second window. Does not start a download.
#!ps
#timeout=180000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','WindowsUpdate-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/WindowsUpdate/Get-WindowsUpdateProgress.ps1?ref=main'); & ([scriptblock]::Create($script)) -WatchSeconds 90 -Exit
