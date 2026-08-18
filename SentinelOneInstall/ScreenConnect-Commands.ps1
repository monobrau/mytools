# SentinelOne silent install for ScreenConnect.
# Paste a real -SiteToken at run time (ScToolLauncher). Never commit tokens.

# EXE already on disk (default path); quiet install
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','SentinelOneInstall-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/SentinelOneInstall/Install-SentinelOneAgent.ps1?ref=main'); & ([scriptblock]::Create($script)) -SiteToken 'YOUR_SITE_TOKEN' -InstallerPath 'C:\Windows\Temp\SentinelOneInstaller.exe' -Quiet -Exit

# Optional: download then install (paste InstallerUrl)
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','SentinelOneInstall-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/SentinelOneInstall/Install-SentinelOneAgent.ps1?ref=main'); & ([scriptblock]::Create($script)) -SiteToken 'YOUR_SITE_TOKEN' -InstallerPath 'C:\Windows\Temp\SentinelOneInstaller.exe' -InstallerUrl 'https://example.com/path/to/SentinelOneInstaller.exe' -Quiet -Exit
