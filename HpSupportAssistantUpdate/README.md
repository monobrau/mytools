# HP Support Assistant Update

Checks the installed **HP Support Assistant** version, resolves the latest SoftPaq from the public [winget-pkgs](https://github.com/microsoft/winget-pkgs) manifest (`HPInc.HPSupportAssistant`), and silently updates when needed.

Built for **ConnectWise ScreenConnect**:

- **Backstage** (runs as SYSTEM)
- **Commands** tab with `#!ps` (Windows PowerShell 5.1) or `#!pwsh` (PowerShell 7+)

Compatible with **Windows PowerShell 5.1** and **PowerShell 7+ (pwsh)**. Check-only by default; pass `-Update` to install.

**Backstage note:** v1.0.2+ keeps the host open for interactive ScriptBlock runs (older builds called `exit` and closed the console). Result code `2` means update needed, not a crash.

## Behavior

1. Read installed version from Programs and Features (uninstall registry)
2. Resolve latest SoftPaq URL + version from winget-pkgs (GitHub), with `winget show` as fallback
3. Compare versions
4. With `-Update`: download SoftPaq to `%ProgramData%\HpSupportAssistantUpdate`, verify SHA256 when published, silent install (`/s`, with extract + `InstallHPSA.exe /S /v/qn` fallback)

## Parameters

| Parameter | Meaning |
| --- | --- |
| _(none)_ | Check only; result `2` if update needed, `0` if current |
| `-Update` | Install when older or missing |
| `-Force` | Reinstall even if current (implies `-Update`) |
| `-SoftPaqUrl` | Override SoftPaq URL |
| `-LatestVersion` | Override version string used for comparison |
| `-WorkingDirectory` | Download folder (default `%ProgramData%\HpSupportAssistantUpdate`) |
| `-NoExit` | Keep the PowerShell host open (Backstage) |
| `-Exit` | Always `exit` with the result code (Commands / automation) |

## Backstage (SYSTEM)

Paste the **entire** block at once (top → bottom). Do not paste lines in reverse.

**Check only**

```powershell
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$url = 'https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?' + (Get-Date -Format 'yyyyMMddHHmmss')
$wc = New-Object System.Net.WebClient
$wc.Headers.Add('User-Agent', 'HpSupportAssistantUpdate-bootstrap/1.0.3')
$script = [System.Text.Encoding]::UTF8.GetString($wc.DownloadData($url))
if ($script.Length -gt 0 -and [int][char]$script[0] -eq 0xFEFF) { $script = $script.Substring(1) }
Write-Host ("Downloaded {0} chars from GitHub" -f $script.Length)
& ([scriptblock]::Create($script))
```

**Update** — same block, last line:

```powershell
& ([scriptblock]::Create($script)) -Update
```

You should see `Downloaded #### chars from GitHub`, then `HpSupportAssistantUpdate 1.0.2`, then `Done. ResultCode=...` with the console still open.

## ScreenConnect Commands

Paste **one** block into the **Commands** tab. Full copies: [`ScreenConnect-Commands.ps1`](ScreenConnect-Commands.ps1).

### Check only (`#!ps`)

```powershell
#!ps
#timeout=300000
#maxlength=100000
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$url = 'https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?' + (Get-Date -Format 'yyyyMMddHHmmss')
$wc = New-Object System.Net.WebClient
$wc.Headers.Add('User-Agent', 'HpSupportAssistantUpdate-bootstrap/1.0.3')
$script = [System.Text.Encoding]::UTF8.GetString($wc.DownloadData($url))
if ($script.Length -gt 0 -and [int][char]$script[0] -eq 0xFEFF) { $script = $script.Substring(1) }
& ([scriptblock]::Create($script)) -Exit
```

### Silent update (`#!ps`)

Same as check, `#timeout=600000`, last line:

```powershell
& ([scriptblock]::Create($script)) -Update -Exit
```

### PowerShell 7+ (`#!pwsh`)

Same body; change shebang to `#!pwsh`.

## Requirements

- Windows PowerShell **5.1+** or PowerShell **7+** (`pwsh`)
- Elevation / SYSTEM for `-Update`
- Outbound HTTPS to `raw.githubusercontent.com`, `api.github.com`, and `ftp.hp.com`

## Notes

- Bootstrap uses `WebClient.DownloadData` + UTF-8 decode (avoids `WebClient.Encoding`, which fails in some Backstage hosts).
- Result codes: `0` current, `2` update needed, `1` error, `3010` success + reboot required.
- This updates Support Assistant only; it does not remove HP Touchpoint Analytics.
