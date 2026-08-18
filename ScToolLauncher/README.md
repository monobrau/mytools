# SC Tool Launcher

AutoHotkey v2 hotkey picker for **any** ScreenConnect-ready tool shortcut — remediation, cleanup, discovery, IR helpers, and more — not limited to vulnerability tools.

Copies a ready-to-paste Commands `#!ps` (or Backstage one-liner) bootstrap onto the clipboard. The remote host downloads/runs the script from GitHub.

- Hotkey: **Ctrl+Shift+Alt+S** (edit `HotkeySpec` / `HotkeyLabel` at the top of the script; Win+Alt combos are often reserved by Windows/OEM)
- Tray icon tip / menu / GUI title: **SC Tool Launcher (Ctrl+Shift+Alt+S)** — renames the AHK main window so it is not a generic **main** next to other scripts
- Formats: Commands tab `#!ps` (default) or Backstage one-liner
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
| HP Support Assistant | mytools |
| Classic Teams remnants | mytools |

### ScreenConnect — GPO/MSI finder, temp cleanup

| Tool | Repo |
| --- | --- |
| GPO / MSI finder | [screenconnect-gpo-msi-finder](https://github.com/monobrau/screenconnect-gpo-msi-finder) |
| Temp file cleanup | [screenconnect-temp-cleanup](https://github.com/monobrau/screenconnect-temp-cleanup) |

### OEM cleanup — HP Touchpoint, Dell SARemediation

| Tool | Repo |
| --- | --- |
| HP Touchpoint Analytics | [hp-touchpointanalytics-cleanup](https://github.com/monobrau/hp-touchpointanalytics-cleanup) |
| Dell SARemediation Backup (CW/SC) | [dell-saremediation-cleanup](https://github.com/monobrau/dell-saremediation-cleanup) **v1.4.2** — scan-first + timed service stop; Backup CW/SC only; reload AHK for `?v=1.4.2` |

AV passwords/keys are only embedded in the clipboard snippet if you type them — nothing is stored in the script.

### AV offboarding — Cylance/Webroot, McAfee remnants

| Tool | Repo |
| --- | --- |
| Cylance / Webroot cleanup | [windows-av-cleanup](https://github.com/monobrau/windows-av-cleanup) — offboarding / remnant sweep after migration, not day-to-day AV management |
| McAfee remnant cleanup | mytools — AppX + `Program Files\McAfee` leftovers |

AV passwords/keys are only embedded in the clipboard snippet if you type them — nothing is stored in the script.

### Agents — SentinelOne + ConnectSecure

| Tool | Source |
| --- | --- |
| SentinelOne silent install | mytools `SentinelOneInstall` — paste site/group token in GUI; optional URL or on-disk EXE/MSI |
| ConnectSecure silent install | mytools `ConnectSecureInstall` — company/env/install token in GUI; agentlink download then `-c/-e/-j/-i` |
| ConnectSecure (CyberCNS) agent repair | mytools — wipe stuck agent then reinstall (same GUI secrets) |

Tokens/IDs are only embedded in the clipboard snippet when you copy — nothing is stored in the AHK file. Do not paste them into tickets or git.

### IR / forensics — event logs, Sysinternals, ADWCleaner

| Tool | Repo |
| --- | --- |
| HarkinsCollector (event logs) | [ExceedingLife/HarkinsCollector](https://github.com/ExceedingLife/HarkinsCollector) — zip under `C:\ForensicLogs` |
| Forensic Investigator (Sysinternals) | [monobrau/forensicinvestigator](https://github.com/monobrau/forensicinvestigator) — reports under `C:\SecurityReports` |
| Malwarebytes ADWCleaner | [ADWCleaner](https://www.malwarebytes.com/adwcleaner) — silent `/eula /clean /noreboot` |

Harkins / Forensic Investigator use **Process-scoped** `Set-ExecutionPolicy Bypass` plus `Invoke-RestMethod -OutFile` then `&` run. ADWCleaner downloads the vendor EXE and runs `Start-Process -Wait`. Prefer elevated / Backstage.

### M365 / Exchange — Inky/IPW transport rules (EXO admin)

| Tool | Source |
| --- | --- |
| Inky / IPW transport rules | mytools — requires `Connect-ExchangeOnline` on an admin workstation; Scan lists, Delete removes (no `Read-Host`) |

### Dell SARemediation Backup cleanup

Launcher exposes **Backup hygiene only** (no SupportAssist / full SARemediation uninstall — those paths caused SC drops / reboot risk):

- **Default:** `-Delete -BackupsOnly` — remove ScreenConnect/ConnectWise-like files under `Snapshots\Backup`
- **Optional:** clear entire Backup folder contents
- Prefer **Backstage**; then run **ScreenConnect temp cleanup**
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
4. Paste into ScreenConnect **Commands** (`#!ps`) or **Backstage** (one-liner format).

## Bump versions

- **mytools:** update `UaVer` / `UaPrefix` to match each tool’s `ScreenConnect-Commands.ps1`.
- **Raw / IrmOutFile repos:** update `UaVer` to match the `?v=` cache-buster in that repo’s README (flag `CacheBust`).
