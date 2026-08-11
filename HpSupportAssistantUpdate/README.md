# HP Support Assistant Update

Checks the installed **HP Support Assistant** version, resolves the latest SoftPaq from the public [winget-pkgs](https://github.com/microsoft/winget-pkgs) manifest (`HPInc.HPSupportAssistant`), and silently updates when needed.

Built for **ConnectWise ScreenConnect**:

- **Backstage** (runs as SYSTEM)
- **Commands** tab with `#!ps` (Windows PowerShell 5.1) or `#!pwsh` (PowerShell 7+)

Compatible with **Windows PowerShell 5.1** and **PowerShell 7+ (pwsh)**. Check-only by default; pass `-Update` to install.

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

Works in either host. Paste into Backstage PowerShell:

**Check only**

```powershell
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
$wc.Headers['User-Agent'] = 'HpSupportAssistantUpdate-bootstrap/1.0.1'
$script = $wc.DownloadString($url)
if ($script.Length -gt 0 -and [int][char]$script[0] -eq 0xFEFF) { $script = $script.Substring(1) }
& ([scriptblock]::Create($script))
```

**Update** — same bootstrap, last line:

```powershell
& ([scriptblock]::Create($script)) -Update
```

## ScreenConnect Commands

Paste **one** block into the **Commands** tab. Full copies also live in [`ScreenConnect-Commands.ps1`](ScreenConnect-Commands.ps1).

### Check only (`#!ps` — Windows PowerShell 5.1)

```powershell
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
$wc.Headers['User-Agent'] = 'HpSupportAssistantUpdate-bootstrap/1.0.1'
$script = $wc.DownloadString($url)
if ($script.Length -gt 0 -and [int][char]$script[0] -eq 0xFEFF) { $script = $script.Substring(1) }
& ([scriptblock]::Create($script))
```

### Silent update (`#!ps`)

Same as check, but `#timeout=600000` and:

```powershell
& ([scriptblock]::Create($script)) -Update
```

### PowerShell 7+ (`#!pwsh`)

Same body as above; change the shebang to `#!pwsh` (TLS lines are optional on pwsh). Use when the endpoint has PowerShell 7 installed and ScreenConnect should run that host.

Use a long timeout — SoftPaq download + install often exceeds two minutes.

## Requirements

- Windows PowerShell **5.1+** or PowerShell **7+** (`pwsh`)
- Elevation / SYSTEM for `-Update`
- Outbound HTTPS to `raw.githubusercontent.com`, `api.github.com`, and `ftp.hp.com`

## Notes

- Bootstrap uses `WebClient.DownloadString` so the downloaded script is always a .NET string on both 5.1 and pwsh (avoids `Invoke-WebRequest` content-type differences).
- Latest resolution tracks the winget-pkgs repo, not a hardcoded SoftPaq number.
- Exit `3010` means success with reboot required.
- This updates Support Assistant only; it does not remove HP Touchpoint Analytics.
