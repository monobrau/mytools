# HP Support Assistant Update / Uninstall

ScreenConnect tool for HP Support Assistant remediation.

## Defaults

| OS | Default action (no switches) |
| --- | --- |
| **Windows 11** | **Update** to patched SoftPaq (≥ 9.47 via winget-pkgs) |
| **Windows 10** | **Uninstall** HPSA + Support Solutions Framework |

Optional flags: `-CheckOnly`, `-Uninstall` (also on Win11), `-Update` (refused on Win10).

## Security / Windows 10

Recent HP advisories include local privilege-escalation issues fixed only in newer 9.4x builds:

| CVE / family | Fixed around |
| --- | --- |
| [CVE-2025-10578](https://nvd.nist.gov/vuln/detail/CVE-2025-10578) | **9.47.41.0** |
| [CVE-2025-43019](https://nvd.nist.gov/vuln/detail/CVE-2025-43019) | **9.46.17.0** |
| [CVE-2025-43026](https://nvd.nist.gov/vuln/detail/CVE-2025-43026) | **9.44.18.0+** |

The SoftPaq that carries those fixes (**9.47**) often **will not install on Windows 10**. Win10 SoftPaqs such as **9.39** / **8.8** remain vulnerable, and installs have been seen to crash .NET Framework on 22H2. Hence **uninstall by default on Windows 10**.

### If .NET crashed after an HPSA install (Win10)

1. Run the default one-liner (uninstall) or `-Uninstall`.
2. Reboot.
3. Repair .NET (Microsoft .NET Framework Repair Tool, or `DISM /Online /Cleanup-Image /RestoreHealth` + `sfc /scannow`).
4. Do **not** reinstall HPSA on Win10 for vuln remediation.

## Parameters

| Parameter | Meaning |
| --- | --- |
| _(none)_ | OS default: Win11 update, Win10 uninstall |
| `-CheckOnly` | Detect / vuln status only |
| `-Uninstall` | Silent removal (optional override on Win11) |
| `-Update` | SoftPaq update (Win11; refused on Win10) |
| `-Force` | Force reinstall (update) or cleanup when not detected (uninstall) |
| `-SoftPaqUrl` / `-LatestVersion` | Override package resolution |
| `-NoExit` / `-Exit` | Host lifecycle for Backstage vs Commands |

## Backstage (SYSTEM) one-liners

Paste **one entire line**.

**Default (recommended)**

```powershell
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.2.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script))
```

Expect `HpSupportAssistantUpdate 1.2.0` and either `Default action (Windows 11): Update` or `Default action (Windows 10): Uninstall`.

**Check only** — append `-CheckOnly`  
**Force uninstall on Win11** — append `-Uninstall`

## ScreenConnect Commands

See [`ScreenConnect-Commands.ps1`](ScreenConnect-Commands.ps1).

## Requirements

- Windows PowerShell **5.1+** or PowerShell **7+**
- Elevation / SYSTEM for update or uninstall
- Outbound HTTPS to `api.github.com`; `ftp.hp.com` for Win11 updates

## Notes

- Result codes: `0` OK, `2` vulnerable / update candidate (check-only), `3` refused update, `1` error, `3010` reboot required
- Update path: SoftPaq extract + `InstallHPSA.exe /S /v"/qn ..."` with `CreateNoWindow` (best-effort silent)
- Uninstall removes HPSA and Support Solutions Framework when possible; not a full HP bloatware scrub
