# HP Support Assistant Update / Uninstall

ScreenConnect tool to **check**, **uninstall** (v-scan remediation), or **update** HP Support Assistant.

## Security / Windows 10

Recent HP advisories include local privilege-escalation issues fixed only in newer 9.4x builds:

| CVE / family | Fixed around |
| --- | --- |
| [CVE-2025-10578](https://nvd.nist.gov/vuln/detail/CVE-2025-10578) | **9.47.41.0** |
| [CVE-2025-43019](https://nvd.nist.gov/vuln/detail/CVE-2025-43019) | **9.46.17.0** |
| [CVE-2025-43026](https://nvd.nist.gov/vuln/detail/CVE-2025-43026) / [HPSBGN04022](https://support.hp.com/us-en/document/ish_12617979-12618008-16/hpsbgn04022) | **9.44.18.0+** |

The SoftPaq that carries those fixes (**9.47 / sp171501**) often **will not install on Windows 10** (“incompatible with your operating system”). Win10-installable SoftPaqs such as **9.39** / **8.8** remain **below** the patched minimum, so they are still in the vulnerable range for vuln-scan purposes.

**Recommendation:** on Windows 10, use **`-Uninstall`** (HPSA + Support Solutions Framework) for remediation. On Windows 11, `-Update` to winget latest (≥ 9.47) is viable when the SoftPaq installs.

## Behavior

1. Detect HPSA (ARP name starting with `HP Support Assistant`; Framework is companion-only for version compare)
2. Flag **VULNERABLE** if installed version &lt; `9.47.41.0`
3. **`-Uninstall`**: stop related services, run `UninstallHPSA.exe` when present, ARP/msiexec fallbacks, AppX + residual cleanup
4. **`-Update`**: OS-aware SoftPaq install; **refused** when the OS-appropriate SoftPaq is still below the patched minimum (typical Win10 path) — use `-Uninstall` instead

## Parameters

| Parameter | Meaning |
| --- | --- |
| _(none)_ | Check / vuln status; `2` if vulnerable or update candidate |
| `-Uninstall` | Silent removal (preferred Win10 v-scan remediation) |
| `-Update` | Install OS-appropriate SoftPaq when it is in the patched range |
| `-Force` | With update: reinstall; with uninstall: cleanup even if not detected |
| `-SoftPaqUrl` / `-LatestVersion` | Override package resolution |
| `-NoExit` / `-Exit` | Host lifecycle for Backstage vs Commands |

## Backstage (SYSTEM) one-liners

Paste **one entire line** (Backstage often reverses multi-line paste).

**Check / vuln status**

```powershell
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.1.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script))
```

**Silent uninstall (v-scan remediation)**

```powershell
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','HpSupportAssistantUpdate-bootstrap/1.1.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/HpSupportAssistantUpdate/Update-HpSupportAssistant.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script)) -Uninstall
```

Expect `HpSupportAssistantUpdate 1.1.0` and `Vuln status: VULNERABLE` on Win10 hosts still running 8.x / 9.39.

## ScreenConnect Commands

See [`ScreenConnect-Commands.ps1`](ScreenConnect-Commands.ps1) for `#!ps` / `#!pwsh` check, uninstall, and update blocks.

## Requirements

- Windows PowerShell **5.1+** or PowerShell **7+**
- Elevation / SYSTEM for `-Uninstall` / `-Update`
- Outbound HTTPS to `api.github.com` (bootstrap); `ftp.hp.com` only if updating

## Notes

- Result codes: `0` OK / not present, `2` vulnerable or update candidate, `3` refused vulnerable update, `1` error, `3010` reboot required
- Uninstall removes HPSA and Support Solutions Framework residuals when possible; it is not a full HP bloatware scrub (Touchpoint Analytics etc. are separate)
