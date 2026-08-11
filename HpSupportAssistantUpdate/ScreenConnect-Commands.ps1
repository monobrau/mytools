# ScreenConnect Commands — paste ONE block into the Commands tab.
# Each block downloads Update-HpSupportAssistant.ps1 from GitHub and runs it.

# =============================================================================
# CHECK ONLY
# =============================================================================
#!ps
#timeout=300000
#maxlength=100000
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$repo = 'monobrau/mytools'
$url = "https://raw.githubusercontent.com/$repo/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?$(Get-Date -Format yyyyMMddHHmmss)"
$script = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
& ([ScriptBlock]::Create($script))

# =============================================================================
# SILENT UPDATE — paste this block instead of the check block
# =============================================================================
#!ps
#timeout=600000
#maxlength=100000
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$repo = 'monobrau/mytools'
$url = "https://raw.githubusercontent.com/$repo/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?$(Get-Date -Format yyyyMMddHHmmss)"
$script = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
& ([ScriptBlock]::Create($script)) -Update
