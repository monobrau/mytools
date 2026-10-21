# ScreenConnect paste helpers for Get-PhpUse.
# BACKSTAGE: one-liners only (multi-line paste is often reversed).
# Read-only. Reports whether this PC is using PHP, and whether php.exe is installed.
# The host downloads the script from GitHub main. Push this folder before using the paste.

# =============================================================================
# BACKSTAGE — CHECK
# =============================================================================
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','PhpUse-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/PhpUse/Get-PhpUse.ps1?ref=main'); if ($script -match '(?i)<html|github.com/login|&redirect') { throw 'Download returned HTML, not a script.' }; & ([scriptblock]::Create($script)) -NoExit

# =============================================================================
# COMMANDS tab — CHECK (#!ps)
# =============================================================================
#!ps
#timeout=300000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','PhpUse-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/PhpUse/Get-PhpUse.ps1?ref=main'); if ($script -match '(?i)<html|github.com/login|&redirect') { throw 'Download returned HTML, not a script.' }; & ([scriptblock]::Create($script)) -Exit
