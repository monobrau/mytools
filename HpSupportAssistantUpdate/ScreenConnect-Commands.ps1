# ScreenConnect Commands — paste ONE block into the Commands tab.
# Each block downloads Update-HpSupportAssistant.ps1 from GitHub and runs it.
# Works on Windows PowerShell 5.1 (#!ps) and PowerShell 7+ (#!pwsh).

# =============================================================================
# CHECK ONLY  (#!ps = Windows PowerShell 5.1)
# =============================================================================
#!ps
#timeout=300000
#maxlength=100000
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = (
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    )
} catch {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
}
$repo = 'monobrau/mytools'
$url = "https://raw.githubusercontent.com/$repo/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?$(Get-Date -Format yyyyMMddHHmmss)"
$wc = New-Object System.Net.WebClient
$wc.Encoding = [System.Text.Encoding]::UTF8
$wc.Headers['User-Agent'] = 'HpSupportAssistantUpdate-bootstrap/1.0.2'
$script = $wc.DownloadString($url)
if ($script.Length -gt 0 -and [int][char]$script[0] -eq 0xFEFF) { $script = $script.Substring(1) }
# -Exit so ScreenConnect gets a process exit code (2 = update needed).
& ([scriptblock]::Create($script)) -Exit

# =============================================================================
# SILENT UPDATE  (#!ps = Windows PowerShell 5.1)
# =============================================================================
#!ps
#timeout=600000
#maxlength=100000
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = (
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    )
} catch {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
}
$repo = 'monobrau/mytools'
$url = "https://raw.githubusercontent.com/$repo/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?$(Get-Date -Format yyyyMMddHHmmss)"
$wc = New-Object System.Net.WebClient
$wc.Encoding = [System.Text.Encoding]::UTF8
$wc.Headers['User-Agent'] = 'HpSupportAssistantUpdate-bootstrap/1.0.2'
$script = $wc.DownloadString($url)
if ($script.Length -gt 0 -and [int][char]$script[0] -eq 0xFEFF) { $script = $script.Substring(1) }
& ([scriptblock]::Create($script)) -Update -Exit

# =============================================================================
# CHECK ONLY  (#!pwsh = PowerShell 7+)
# =============================================================================
#!pwsh
#timeout=300000
#maxlength=100000
$ProgressPreference = 'SilentlyContinue'
$repo = 'monobrau/mytools'
$url = "https://raw.githubusercontent.com/$repo/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?$(Get-Date -Format yyyyMMddHHmmss)"
$wc = New-Object System.Net.WebClient
$wc.Encoding = [System.Text.Encoding]::UTF8
$wc.Headers['User-Agent'] = 'HpSupportAssistantUpdate-bootstrap/1.0.2'
$script = $wc.DownloadString($url)
if ($script.Length -gt 0 -and [int][char]$script[0] -eq 0xFEFF) { $script = $script.Substring(1) }
& ([scriptblock]::Create($script)) -Exit

# =============================================================================
# SILENT UPDATE  (#!pwsh = PowerShell 7+)
# =============================================================================
#!pwsh
#timeout=600000
#maxlength=100000
$ProgressPreference = 'SilentlyContinue'
$repo = 'monobrau/mytools'
$url = "https://raw.githubusercontent.com/$repo/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?$(Get-Date -Format yyyyMMddHHmmss)"
$wc = New-Object System.Net.WebClient
$wc.Encoding = [System.Text.Encoding]::UTF8
$wc.Headers['User-Agent'] = 'HpSupportAssistantUpdate-bootstrap/1.0.2'
$script = $wc.DownloadString($url)
if ($script.Length -gt 0 -and [int][char]$script[0] -eq 0xFEFF) { $script = $script.Substring(1) }
& ([scriptblock]::Create($script)) -Update -Exit
