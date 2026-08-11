# HP Support Assistant Update

Checks the installed **HP Support Assistant** version, resolves the latest SoftPaq from the public [winget-pkgs](https://github.com/microsoft/winget-pkgs) manifest (`HPInc.HPSupportAssistant`), and silently updates when needed.

Built for **ConnectWise ScreenConnect**:

- **Backstage** (runs as SYSTEM)
- **Commands** tab with `#!ps`

Check-only by default. Pass `-Update` to install.

## Behavior

1. Read installed version from Programs and Features (uninstall registry)
2. Resolve latest SoftPaq URL + version from the public winget-pkgs GitHub manifest (`HPInc.HPSupportAssistant`), with `winget show` as fallback
3. Compare versions
4. With `-Update`: download SoftPaq to `%ProgramData%\HpSupportAssistantUpdate`, verify SHA256 when published, silent install (`/s`, with extract + `InstallHPSA.exe /S /v/qn` fallback)

GitHub is preferred because `winget` is often unavailable or flaky as SYSTEM in ScreenConnect Backstage.

## Parameters

| Parameter | Meaning |
| --- | --- |
| _(none)_ | Check only; exit `2` if update needed, `0` if current |
| `-Update` | Install when older or missing |
| `-Force` | Reinstall even if current (implies `-Update`) |
| `-SoftPaqUrl` | Override SoftPaq URL |
| `-LatestVersion` | Override version string used for comparison |
| `-WorkingDirectory` | Download folder (default `%ProgramData%\HpSupportAssistantUpdate`) |

## Backstage (SYSTEM)

In Backstage PowerShell (already SYSTEM), either copy `Update-HpSupportAssistant.ps1` to the endpoint or pull from GitHub:

**Check only**

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$repo = 'monobrau/mytools'
$url = "https://raw.githubusercontent.com/$repo/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1"
$script = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
& ([ScriptBlock]::Create($script))
```

**Update**

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$repo = 'monobrau/mytools'
$url = "https://raw.githubusercontent.com/$repo/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?$(Get-Date -Format yyyyMMddHHmmss)"
$script = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
& ([ScriptBlock]::Create($script)) -Update
```

## ScreenConnect Commands (`#!ps`)

Paste into the **Commands** tab. Run check first, then update.

### Check only

```powershell
#!ps
#timeout=300000
#maxlength=100000
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$repo = 'monobrau/mytools'
$url = "https://raw.githubusercontent.com/$repo/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?$(Get-Date -Format yyyyMMddHHmmss)"
$script = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
& ([ScriptBlock]::Create($script))
```

### Silent update

```powershell
#!ps
#timeout=600000
#maxlength=100000
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$repo = 'monobrau/mytools'
$url = "https://raw.githubusercontent.com/$repo/main/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?$(Get-Date -Format yyyyMMddHHmmss)"
$script = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
& ([ScriptBlock]::Create($script)) -Update
```

Use a long timeout — SoftPaq download + install often exceeds two minutes.

## Requirements

- Windows PowerShell 5.1+ (or PowerShell 7)
- Elevation / SYSTEM for `-Update`
- Outbound HTTPS to `raw.githubusercontent.com`, `api.github.com`, and `ftp.hp.com`

## Notes

- Latest resolution tracks the winget-pkgs repo, not a hardcoded SoftPaq number.
- Exit `3010` means success with reboot required.
- This updates Support Assistant only; it does not remove HP Touchpoint Analytics (see `hp-touchpointanalytics-cleanup` if that is the goal).
