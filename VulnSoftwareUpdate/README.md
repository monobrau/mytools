# VulnSoftwareUpdate

Orchestrator for ConnectSecure-style **Vulnerability Remediation** software updates (ScreenConnect Commands `#!ps`).

Checks what’s installed, prints a clear per-product verdict, and can silently update common findings. Reuses existing mytools handlers where they already exist.

## Ticket products covered

| Finding (approx.) | Catalog Id | Method |
| --- | --- | --- |
| Microsoft 365 Apps for business / enterprise | `M365Apps` | Delegates to [M365AppsUpdate](../M365AppsUpdate/) (Click-to-Run, not winget) |
| HP Support Assistant (extra) | `HpSupportAssistant` | Delegates to [HpSupportAssistantUpdate](../HpSupportAssistantUpdate/) |
| .NET 6+ Runtime / Desktop / ASP.NET / SDK | `DotNet` | Delegates to [DotNetUpdate](../DotNetUpdate/) (same-major security patches only) |
| ShareX | `ShareX` | winget `ShareX.ShareX` |
| Adobe Acrobat (64-bit) / Reader | `AdobeAcrobat` | winget Reader 64-bit or Acrobat Pro (auto-picked) |
| Visual Studio Code (User) | `VSCode` | winget `Microsoft.VisualStudioCode` (user-scope may need a logged-on user) |
| Git | `Git` | winget `Git.Git` |
| GIMP | `GIMP` | winget `GIMP.GIMP` |
| Winamp | `Winamp` | winget `Winamp.Winamp` |
| Greenshot | `Greenshot` | winget `Greenshot.Greenshot` |
| Microsoft Teams Network Assessment Tool | `TeamsNetworkAssessment` | **Manual** (no reliable winget package) |
| WinRAR | `WinRAR` | winget `RARLab.WinRAR` |
| Foxit PDF Reader | `FoxitReader` | winget `Foxit.FoxitReader` |
| 7-Zip | `SevenZip` | winget `7zip.7zip` |
| Notepad++ | `NotepadPlusPlus` | winget `Notepad++.Notepad++` |
| Visual C++ 2015+ Redistributable (x64) | `VcRedistX64` | winget `Microsoft.VCRedist.2015+.x64` |
| Visual C++ 2015+ Redistributable (x86) | `VcRedistX86` | winget `Microsoft.VCRedist.2015+.x86` |
| PuTTY | `PuTTY` | winget `PuTTY.PuTTY` |
| WinSCP | `WinSCP` | winget `WinSCP.WinSCP` |
| VLC | `VLC` | winget `VideoLAN.VLC` |
| Edge WebView2 Runtime | `WebView2` | winget `Microsoft.EdgeWebView2Runtime` |
| PowerShell 7 | `PowerShell7` | winget `Microsoft.PowerShell` |
| FileZilla | `FileZilla` | winget `FileZilla.FileZilla` |

Not installed on the host → `SKIPPED_NOT_INSTALLED` (not a failure).

Browsers, Zoom/Slack/Teams, VPN, Java, EDR, Duo Proxy, and GPU drivers stay out of scope (session/service risk).

## Modes

| Mode | Behavior |
| --- | --- |
| `-CheckOnly` | Verdicts only |
| Default | Update installed products that look behind |
| `-Product Id1,Id2` | Limit scope (e.g. `-Product ShareX,Git`) |
| `-List` | Print catalog IDs |
| `-ForceAppShutdown` | Passed to M365 C2R (closes Office apps; opt-in) |

Exit codes: `0` clean / all current or skipped, `2` updates still needed / manual / unknown, `1` hard error.

## ScreenConnect

Prefer **Commands tab** (`#!ps`) — see [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1).

**Check only (start here):**

```
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','VulnSoftwareUpdate-bootstrap/1.2.1'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/VulnSoftwareUpdate/Update-VulnSoftware.ps1?ref=main'); & ([scriptblock]::Create($script)) -CheckOnly -Exit
```

## Notes

- Requires **winget** on the endpoint for most third-party apps (SYSTEM context can be flaky; machine-scope installs work best).
- **M365 Apps** stays on Click-to-Run (same non-disruptive defaults as M365AppsUpdate).
- **.NET** stays on the installed major (e.g. 8.0.x → latest 8.0.y); it will not jump to a newer major.
- Duo Authentication Proxy is intentionally out of scope (use the dedicated Duo tooling if needed).
- Add new products by extending the catalog in `Update-VulnSoftware.ps1`.

## Local

```powershell
.\Update-VulnSoftware.ps1 -List
.\Update-VulnSoftware.ps1 -CheckOnly
.\Update-VulnSoftware.ps1 -Product Git,ShareX
```
