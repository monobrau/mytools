# Stale Windows user profiles on a shared lab PC.
# Scan lists what would be removed. -Remediate removes only that list.
# Does not delete user accounts. Default cutoff is 2 calendar months.

# =============================================================================
# COMMANDS tab — SCAN (#!ps)
# =============================================================================
#!ps
#timeout=300000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','StaleUserProfile-bootstrap/1.2.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/StaleUserProfile/Remove-StaleUserProfile.ps1?ref=main'); if ($script -match '(?i)<html|github.com/login|&redirect') { throw 'Download returned HTML, not a script.' }; & ([scriptblock]::Create($script)) -CheckOnly -Months 2 -Exit

# =============================================================================
# COMMANDS tab — REMOVE (#!ps)
# =============================================================================
#!ps
#timeout=600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','StaleUserProfile-bootstrap/1.2.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/StaleUserProfile/Remove-StaleUserProfile.ps1?ref=main'); if ($script -match '(?i)<html|github.com/login|&redirect') { throw 'Download returned HTML, not a script.' }; & ([scriptblock]::Create($script)) -Remediate -Months 2 -Exit
