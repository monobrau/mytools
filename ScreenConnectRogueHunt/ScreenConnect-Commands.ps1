# ScreenConnect paste helpers for Find-RogueScreenConnect.
# BACKSTAGE: one-liners only (multi-line paste is often reversed).
# Scan prints each distinct ScreenConnect instance ID once.
# Remove deletes installs whose instance ID is not on the allow list.
# The host downloads the script from GitHub main. Push this folder before using the paste.

# =============================================================================
# BACKSTAGE — SCAN
# =============================================================================
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','ScreenConnectRogueHunt-bootstrap/1.1.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/ScreenConnectRogueHunt/Find-RogueScreenConnect.ps1?ref=main'); if ($script -match '(?i)<html|github.com/login|&redirect') { throw 'Download returned HTML, not a script.' }; & ([scriptblock]::Create($script)) -NoExit

# =============================================================================
# COMMANDS tab — SCAN (#!ps)
# =============================================================================
#!ps
#timeout=300000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','ScreenConnectRogueHunt-bootstrap/1.1.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/ScreenConnectRogueHunt/Find-RogueScreenConnect.ps1?ref=main'); if ($script -match '(?i)<html|github.com/login|&redirect') { throw 'Download returned HTML, not a script.' }; & ([scriptblock]::Create($script)) -Exit

# =============================================================================
# BACKSTAGE — REMOVE
# =============================================================================
if($PSVersionTable.PSVersion.Major -lt 5){$exe=$null; foreach($c in @("$env:SystemRoot\SysNative\WindowsPowerShell\v1.0\powershell.exe","$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe","$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe")){if(Test-Path -LiteralPath $c){try{$v=& $c -NoProfile -Command '$PSVersionTable.PSVersion.Major'}catch{$v=0}; if(($v -as [int]) -ge 5){$exe=$c; break}}}; if(-not $exe){throw 'PowerShell 5.1 required (this host has only 2.0). Install WMF 5.1.'}; & $exe -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path; exit $LASTEXITCODE}; $ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','ScreenConnectRogueHunt-bootstrap/1.1.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/ScreenConnectRogueHunt/Find-RogueScreenConnect.ps1?ref=main'); if ($script -match '(?i)<html|github.com/login|&redirect') { throw 'Download returned HTML, not a script.' }; & ([scriptblock]::Create($script)) -Remediate -NoExit

# =============================================================================
# COMMANDS tab — REMOVE (#!ps)
# =============================================================================
#!ps
#timeout=900000
#maxlength=100000
if($PSVersionTable.PSVersion.Major -lt 5){$exe=$null; foreach($c in @("$env:SystemRoot\SysNative\WindowsPowerShell\v1.0\powershell.exe","$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe","$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe")){if(Test-Path -LiteralPath $c){try{$v=& $c -NoProfile -Command '$PSVersionTable.PSVersion.Major'}catch{$v=0}; if(($v -as [int]) -ge 5){$exe=$c; break}}}; if(-not $exe){throw 'PowerShell 5.1 required (this host has only 2.0). Install WMF 5.1.'}; & $exe -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path; exit $LASTEXITCODE}; $ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','ScreenConnectRogueHunt-bootstrap/1.1.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/ScreenConnectRogueHunt/Find-RogueScreenConnect.ps1?ref=main'); if ($script -match '(?i)<html|github.com/login|&redirect') { throw 'Download returned HTML, not a script.' }; & ([scriptblock]::Create($script)) -Remediate -Exit
