# SentinelOne silent install for ScreenConnect.
# Paste a real -SiteToken at run time (ScToolLauncher). Never commit tokens.
# v1.0.1: MSI URLs (fileType=.msi) and MSI-as-.exe are auto-detected → msiexec.

# EXE already on disk (default path); quiet install
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','SentinelOneInstall-bootstrap/1.0.1'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/SentinelOneInstall/Install-SentinelOneAgent.ps1?ref=main'); & ([scriptblock]::Create($script)) -SiteToken 'YOUR_SITE_TOKEN' -InstallerPath 'C:\Windows\Temp\SentinelOneInstaller.exe' -Quiet -Exit

# MSI download URL (e.g. Barracuda/XDR fileType=.msi) — path may be .exe; script corrects to msiexec
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','SentinelOneInstall-bootstrap/1.0.1'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/SentinelOneInstall/Install-SentinelOneAgent.ps1?ref=main'); & ([scriptblock]::Create($script)) -SiteToken 'YOUR_SITE_TOKEN' -InstallerPath 'C:\Windows\Temp\SentinelOneInstaller.msi' -InstallerUrl 'https://example.com/downloads/sentinelone?os=windows&fileType=.msi' -Exit
