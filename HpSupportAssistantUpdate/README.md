# HP Support Assistant Update

Checks the installed **HP Support Assistant** version, resolves the latest SoftPaq from the public [winget-pkgs](https://github.com/microsoft/winget-pkgs) manifest (`HPInc.HPSupportAssistant`), and silently updates when needed.

Built for **ConnectWise ScreenConnect**:

- **Backstage** (runs as SYSTEM)
- **Commands** tab with `#!ps` (Windows PowerShell 5.1) or `#!pwsh` (PowerShell 7+)

Compatible with **Windows PowerShell 5.1** and **PowerShell 7+ (pwsh)**. Check-only by default; pass `-Update` to install.

**Backstage note:** v1.0.2+ keeps the host open for interactive ScriptBlock runs (older builds called `exit` and closed the console). Result code `2` means update needed, not a crash.

## Behavior

1. Detect **HP Support Assistant** version from ARP (`DisplayName` starting with that product), then file version (8.x–11.x), then AppX. **HP Support Solutions Framework** is logged as a companion only — its 12.x version is never compared to SoftPaq 9.x.
2. Resolve latest SoftPaq URL + version from winget-pkgs (GitHub), with `winget show` as fallback
3. Compare HPSA vs latest SoftPaq
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

Backstage PowerShell often pastes multi-line clipboard **bottom-to-top**, which breaks downloads. Use these **one-liners** (copy the whole line).

**Check only**

```powershell
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u='https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss'); $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.0.3'); $script=[Text.Encoding]::UTF8.GetString($wc.DownloadData($u)); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script))
```

**Silent update**

```powershell
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u='https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss'); $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.0.3'); $script=[Text.Encoding]::UTF8.GetString($wc.DownloadData($u)); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script)) -Update
```

You should see `Downloaded #### chars` (thousands, not 0), then `HpSupportAssistantUpdate 1.0.2`, then `Done. ResultCode=...` with the console still open.

## ScreenConnect Commands

Paste **one** block into the **Commands** tab. Full copies: [`ScreenConnect-Commands.ps1`](ScreenConnect-Commands.ps1).

### Check only (`#!ps`)

```powershell
#!ps
#timeout=300000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u='https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss'); $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.0.3'); $script=[Text.Encoding]::UTF8.GetString($wc.DownloadData($u)); & ([scriptblock]::Create($script)) -Exit
```

### Silent update (`#!ps`)

```powershell
#!ps
#timeout=600000
#maxlength=100000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u='https://raw.githubusercontent.com/monobrau/mytools/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss'); $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.0.3'); $script=[Text.Encoding]::UTF8.GetString($wc.DownloadData($u)); & ([scriptblock]::Create($script)) -Update -Exit
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
