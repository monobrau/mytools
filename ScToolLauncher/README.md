# SC Tool Launcher

AutoHotkey v2 hotkey picker for **any** ScreenConnect-ready tool shortcut — remediation, cleanup, discovery, IR helpers, and more — not limited to vulnerability tools.

Copies a ready-to-paste Commands `#!ps` (or PowerShell one-liner) bootstrap onto the clipboard. The remote host downloads/runs the script from GitHub.

- Hotkey: **Ctrl+Shift+Alt+S** (edit `HotkeySpec` / `HotkeyLabel` at the top of the script; Win+Alt combos are often reserved by Windows/OEM)
- Tray: default AutoHotkey v2 icon and menu (includes **Reload Script**); plus **Open SC Tool Launcher**
- After editing `ScToolLauncher.ahk`, use GUI **Reload**, tray **Reload Script**, or exit and re-run. The hotkey alone does **not** reload the catalog from disk.
- Layout: **two columns** — tool tree on the left, mode/options/actions on the right (fits shorter screens)
- Formats: Commands tab `#!ps` (default) or PowerShell one-liner
- Modes/options depend on the tool (Scan, Update/Remediate/Delete, Force, etc.)
- Tool list is a **TreeView** grouped by category
- Each selection shows a short **About** blurb and **Open docs in browser** (GitHub README / folder)

## Catalog (GUI groups)

Categories start **collapsed**. Labels list what is under each group:

### Software updates — vuln catalog, M365, .NET, HPSA, Teams

| Tool | Source |
| --- | --- |
| Vulnerable software updater (catalog) | mytools |
| Microsoft 365 Apps (Click-to-Run) | mytools |
| .NET runtime / SDK patches | mytools |
| Visual C++ 2005-2013 redistributables | mytools `VisualCppUpdate` — last security build per installed year |
| HP Support Assistant | mytools |
| Classic Teams remnants | mytools |
| Windows Update (quality) | mytools `WindowsUpdate` — pre-check + CU/security/SSU. Default no reboot; optional auto reboot |
| Windows Update (feature) | mytools `WindowsUpdate` — pre-check + feature/enablement. 4h timeout. Default no reboot |

### ScreenConnect — GPO/MSI finder, temp cleanup

| Tool | Repo |
| --- | --- |
| GPO / MSI finder | [screenconnect-gpo-msi-finder](https://github.com/monobrau/screenconnect-gpo-msi-finder) |
| Temp file cleanup | [screenconnect-temp-cleanup](https://github.com/monobrau/screenconnect-temp-cleanup) **v1.7.1** — CVE-2026-84869 advisory is report-only; in-use/installed clients are never deleted |

### OEM cleanup — HP Touchpoint, HP bloat, Dell SARemediation

| Tool | Repo |
| --- | --- |
| HP Touchpoint Analytics | [hp-touchpointanalytics-cleanup](https://github.com/monobrau/hp-touchpointanalytics-cleanup) |
| HP bloat / Wolf (mark05e gist) | [gist](https://gist.github.com/mark05e/a79221b4245962a477a49eb281d97388) — downloads `Remove-HPbloatware.ps1` and runs it (no dry-run; Wolf / Sure Click / HP AppX) |
| Dell SARemediation Backup (CW/SC) | [dell-saremediation-cleanup](https://github.com/monobrau/dell-saremediation-cleanup) **v1.4.4** — EnumerateFiles + skip VersionInfo-identified non-CW PEs; 60 min timeout; reload AHK for `?v=1.4.4` |
| Dell TechHub | mytools `DellTechHubCleanup` — scan/remove TechHub, DTP, and SupportAssist (S1 false positive on `techhub.dll`). Dell Update stays |

AV passwords/keys are only embedded in the clipboard snippet if you type them — nothing is stored in the script.

### AV — Defender repair, Cylance/Webroot, McAfee remnants

| Tool | Repo |
| --- | --- |
| Windows Defender repair | mytools `WindowsDefenderRepair` — PowerShell only. Scan: services + RTP + tamper. Apply: full RTP repair (services + policy + PassiveMode + preferences). Optional nuclear: `MpCmdRun -ResetPlatform` |
| Cylance / Webroot cleanup | [windows-av-cleanup](https://github.com/monobrau/windows-av-cleanup) — offboarding / remnant sweep after migration, not day-to-day AV management |
| Webroot uninstall GPO | mytools `WebrootUninstallGpo` — DC/RSAT: Immediate Task optional `/autouninstall` plus leftover sweep (services/folders/registry/drivers). Optional site key is written to SYSVOL |
| McAfee remnant cleanup | mytools — AppX + `Program Files\McAfee` leftovers |

AV passwords/keys are only embedded in the clipboard snippet if you type them — nothing is stored in the script.

### Agents — SentinelOne, ConnectSecure, Huntress

| Tool | Source |
| --- | --- |
| SentinelOne silent install | mytools `SentinelOneInstall` — paste site/group token in GUI; optional URL or on-disk EXE/MSI |
| ConnectSecure silent install | mytools `ConnectSecureInstall` — company/env/install token in GUI; agentlink download then `-c/-e/-j/-i`. Default option: skip if agent is Running (fleet / scan-prep) |
| ConnectSecure agent repair + reinstall | mytools — wipe then reinstall (same GUI secrets). Default option: skip if agent is Running; uncheck to force wipe |
| Huntress silent install | mytools `HuntressInstall` — account key built in; org key in GUI; Force = rip and replace now (no reboot); optional schedule = SYSTEM tasks + cleanup + reboot at a date/time you pick |
| Verify scheduled reboot | Inline — host time, recent User32 1074 shutdown events, HuntressSC task query |
| Cancel scheduled reboot | Inline `shutdown.exe /a` — aborts a pending shutdown.exe countdown (use if Huntress schedule armed a reboot) |
| Automate GPO deploy | mytools `AutomateGpoDeploy` — paste location token on a DC/RSAT box; dry-run bakes MSI only; Apply stages NETLOGON + startup GPO |

Huntress account key is built into the launcher and `HuntressInstall/ScreenConnect-Commands.ps1`. Org keys, ConnectSecure tokens, SentinelOne tokens, and Automate installer tokens stay GUI-only. Do not paste live tokens into tickets or git.

### IR / forensics — event logs, Sysinternals, ADWCleaner, PUP remnants

| Tool | Repo |
| --- | --- |
| HarkinsCollector (event logs) | [ExceedingLife/HarkinsCollector](https://github.com/ExceedingLife/HarkinsCollector) — zip under `C:\ForensicLogs` |
| Forensic Investigator (Sysinternals) | mytools `ForensicInvestigator` **v3.1.0** — plus Zone.ID, PS history, Amcache/SYSTEM, browser History copies, admins/RMM, Defender, hashed manifest |
| Malwarebytes ADWCleaner | [ADWCleaner](https://www.malwarebytes.com/adwcleaner) — silent `/eula /clean /noreboot` |
| PUP remnant cleanup | mytools `PupRemnantCleanup` — family dropdown (All on host, or one catalog id). Dry-run reports what is present; Remediate deletes those families |

Harkins / Forensic Investigator use **Process-scoped** `Set-ExecutionPolicy Bypass` plus `Invoke-RestMethod -OutFile` then `&` run. ADWCleaner downloads the vendor EXE and runs `Start-Process -Wait`. Prefer elevated PowerShell.

### M365 / Exchange — Inky/IPW transport rules (EXO admin)

| Tool | Source |
| --- | --- |
| Inky / IPW transport rules | mytools — requires `Connect-ExchangeOnline` on an admin workstation; Scan lists, Delete removes (no `Read-Host`) |

### Client-specific

Grouped by client name. Campaign tools that are not meant for general use.

| Client | Tool | Source |
| --- | --- | --- |
| Naviant | Acrobat XI removal (EOL) | mytools `ClientSpecific/Naviant/AcrobatXiRemoval` — scan XI + Foxit; uninstall XI (skip if no Foxit unless Force); 20 min timeout; MSI mutex wait / 1618 retry |

### Dell SARemediation Backup cleanup

Launcher exposes **Backup hygiene only** (no SupportAssist / full SARemediation uninstall — those paths caused SC drops / reboot risk):

- **Default:** `-Delete -BackupsOnly` — remove ScreenConnect/ConnectWise-like files under `Snapshots\Backup`
- **Optional:** clear entire Backup folder contents
- Prefer **PowerShell**; then run **ScreenConnect temp cleanup**
- `PENDING_REBOOT` = reboot to finish locked deletes

Upstream script still supports full uninstall switches for rare manual use; they are not offered in this launcher.

## Requirements

- [AutoHotkey v2](https://www.autohotkey.com/) installed

## Run

```text
ScToolLauncher.ahk
```

Double-click the script, or create a shortcut / Startup entry.

## Usage

1. Press **Ctrl+Shift+Alt+S** (or use the tray menu).
2. Select a tool, mode, and options.
3. **Copy to clipboard**.
4. Paste into ScreenConnect **Commands** (`#!ps`) or **PowerShell** (one-liner format).
   Commands snippets set TLS 1.2 via numeric `3072` (not `::Tls12`) and re-launch
   a probed 5.1 host (`SysNative` first — 32-bit SC often Wow64-redirects
   `System32\powershell.exe` back to v2). Huntress is an exception: it downloads
   the vendor EXE inline so a 2.0-only guest can still install.

## Bump versions

- **mytools:** update `UaVer` / `UaPrefix` to match each tool’s `ScreenConnect-Commands.ps1`.
- **Raw / IrmOutFile repos:** update `UaVer` to match the `?v=` cache-buster in that repo’s README (flag `CacheBust`).
