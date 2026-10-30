# SC Tool Launcher

AutoHotkey v2 hotkey picker for **any** ScreenConnect-ready tool shortcut — remediation, cleanup, discovery, IR helpers, and more — not limited to vulnerability tools.

Copies a ready-to-paste Commands `#!ps` (or PowerShell one-liner) bootstrap onto the clipboard. The remote host downloads/runs the script from GitHub.

- Hotkey: **Ctrl+Shift+Alt+S** (edit `HotkeySpec` / `HotkeyLabel` at the top of the script; Win+Alt combos are often reserved by Windows/OEM)
- Tray: default AutoHotkey v2 icon and menu (includes **Reload Script**); plus **Open SC Tool Launcher**
- After editing `ScToolLauncher.ahk`, use GUI **Reload**, tray **Reload Script**, or exit and re-run. The hotkey alone does **not** reload the catalog from disk.
- On startup, if this checkout is on `main` and GitHub is ahead, a prompt offers `git pull --ff-only` and a restart. Tray **Update launcher** runs the same check. Offline, a missing git repo, or local commits that are not on GitHub are left alone.
- Starts in the tray (window stays hidden until **Open** or the hotkey)
- First open selects **Help** (root item) with intro / how-to on the right; categories stay collapsed
- Layout: **two columns** — tool tree on the left, mode/options/actions on the right (fits shorter screens)
- Formats: Commands tab `#!ps` (default) or PowerShell one-liner
- Modes/options depend on the tool (Scan, Update/Remediate/Delete, Force, etc.)
- Tool list is a **TreeView** grouped by category, with subfolders (Webroot, Huntress, Automate, HP, Dell, …). The Find box above it matches name, client, folder, and category. Ctrl+F focuses it. Escape clears it.
- Each selection shows a short **About** blurb and **Open docs in browser** (GitHub README / folder)

## Catalog (GUI groups)

Categories start **collapsed**. Related tools sit in **subfolders** (Webroot, Huntress, ConnectSecure, Automate, HP, Dell, Windows Update). Labels list what is under each group:

### Updates

| Tool | Source |
| --- | --- |
| Vulnerable software updater (catalog) | mytools |
| Vulnerable Python cleanup | mytools `PythonCleanup` — uninstalls end-of-life CPython and builds older than the current security release. A newer copy does not keep the old one. Does not install a replacement |
| Microsoft 365 Apps (Click-to-Run) | mytools |
| .NET runtime / SDK patches | mytools |
| Visual C++ 2005-2013 redistributables | mytools `VisualCppUpdate` — last security build per installed year |
| EOL dependency use | mytools `EolDependencyAudit` — which processes load EOL runtimes. Scan measures Security-log size; apply audits sentinel DLLs and keeps hit counts |
| EOL dependency audit GPO | mytools `EolDependencyAudit` — run on a DC. Downloads the audit script, stages it on NETLOGON, and creates the GPO |
| HP Support Assistant | mytools |
| HP Image Assistant | mytools `HpImageAssistant` — HP PCs only. Downloads HPIA 5.3.7 and installs unattended (SSM) SoftPaqs. Default no reboot |
| Dell SupportAssist | mytools `DellSupportAssistUpdate` — update only when already installed; leaves OS Recovery, Remediation, and TechHub |
| Classic Teams remnants | mytools |
| Windows Update → quality | mytools `WindowsUpdate` — pre-check + CU/security/SSU. Default no reboot; optional auto reboot. Servers skipped unless Allow Windows Server is confirmed |
| Windows Update → feature | mytools `WindowsUpdate` — pre-check + feature/enablement. 4h timeout. Default no reboot. Servers skipped unless confirmed |
| Windows Update → BIOS / firmware | mytools `WindowsUpdate` — BIOS, UEFI, and system firmware only. Other drivers stay. Default no reboot. Servers skipped unless confirmed |

### ScreenConnect

| Tool | Repo |
| --- | --- |
| Rogue instance IDs | mytools `ScreenConnectRogueHunt` — one line per distinct instance ID; ROGUE if a live install is not on the allow list. Event-only IDs are History |
| Remove rogue ScreenConnect | mytools `ScreenConnectRogueHunt` — uninstall and delete installs that are not on the allow list. Allow-listed IDs stay |
| GPO / MSI finder | [screenconnect-gpo-msi-finder](https://github.com/monobrau/screenconnect-gpo-msi-finder) |
| Temp file cleanup | [screenconnect-temp-cleanup](https://github.com/monobrau/screenconnect-temp-cleanup) **v1.7.1** — CVE-2026-84869 advisory is report-only; in-use/installed clients are never deleted |

### OEM

| Tool | Repo |
| --- | --- |
| HP → Touchpoint Analytics | [hp-touchpointanalytics-cleanup](https://github.com/monobrau/hp-touchpointanalytics-cleanup) |
| HP → bloat / Wolf (mark05e gist) | [gist](https://gist.github.com/mark05e/a79221b4245962a477a49eb281d97388) — downloads `Remove-HPbloatware.ps1` and runs it (no dry-run; Wolf / Sure Click / HP AppX) |
| Dell → SARemediation Backup (CW/SC) | [dell-saremediation-cleanup](https://github.com/monobrau/dell-saremediation-cleanup) **v1.4.4** — EnumerateFiles + skip VersionInfo-identified non-CW PEs; 60 min timeout; reload AHK for `?v=1.4.4` |
| Dell → TechHub | mytools `DellTechHubCleanup` — scan/remove TechHub, DTP, and SupportAssist (S1 false positive on `techhub.dll`). Dell Update stays |

### Antivirus

| Tool | Repo |
| --- | --- |
| Windows Defender repair | mytools `WindowsDefenderRepair` — PowerShell only. Scan: services + RTP + tamper. Apply: full RTP repair (services + policy + PassiveMode + preferences). Optional nuclear: `MpCmdRun -ResetPlatform` |
| Webroot → fleet status | mytools `Get-WebrootFleetStatus.ps1` — DC/RSAT: AD computer list + C$ check for WRSA / WRData / GPO log. CSV in Temp |
| McAfee remnant cleanup | mytools — AppX + `Program Files\McAfee` leftovers |
| Webroot → uninstall GPO | mytools `WebrootUninstallGpo` — DC/RSAT Immediate Task plus leftover sweep |
| Cylance / Webroot cleanup | [windows-av-cleanup](https://github.com/monobrau/windows-av-cleanup) — offboarding / remnant sweep after migration |

AV passwords/keys are only embedded in the clipboard snippet if you type them — nothing is stored in the script.

### Hardening

| Tool | Source |
| --- | --- |
| WinVerifyTrust padding check | mytools `WinVerifyTrustPadding` — CVE-2013-3900 registry check. Apply writes both views. Does not reboot |
| Speculative Store Bypass | mytools `SpeculativeStoreBypass` — CVE-2018-3639 SSBD registry bits. Does not install Windows updates, firmware, or reboot |
| Disable PowerShell 2.0 | mytools `PowerShellV2Disable` — DISM disable of V2 + V2Root. Apply only. Does not reboot |

### Agents

| Tool | Source |
| --- | --- |
| SentinelOne silent install | mytools `SentinelOneInstall` — paste site/group token in GUI; optional URL or on-disk EXE/MSI |
| SentinelOne unload (passphrase) | Inline — finds `SentinelCtl.exe` and runs `unload -slam -k`. Passphrase is GUI-only and is not saved |
| ConnectSecure → silent install | mytools `ConnectSecureInstall` — paste the official install script; `-c`, `-e`, and `-j` are filled from it and are not saved. OS dropdown defaults to Windows (agentlink + leftover cleanup). Mac, Linux, ARM, and ARM-32 copy the portal shell command. Default option on Windows: skip if agent is Running |
| ConnectSecure → agent repair + reinstall | mytools — wipe then reinstall (same pasted script). Default option: skip if agent is Running; uncheck to force wipe |
| Huntress → silent install | mytools `HuntressInstall` — account key built in; org key in GUI; Force = rip and replace now (no reboot); optional schedule = SYSTEM tasks + cleanup + reboot at a date/time you pick |
| Huntress → Verify scheduled reboot | Inline — host time, recent User32 1074 shutdown events, HuntressSC task query |
| Huntress → Cancel scheduled reboot | Inline `shutdown.exe /a` — aborts a pending shutdown.exe countdown (use if Huntress schedule armed a reboot) |
| Automate → agent uninstall | mytools `AutomateUninstall` — scan or remove the LabTech / Automate remote agent. ScreenConnect stays. Force = allow a probe agent |
| Automate → agent reinstall | mytools `AutomateUninstall` — reinstall from the server, location, and cached MSI already on the PC. No token. New agent ID, same location |

Huntress account key is built into the launcher and `HuntressInstall/ScreenConnect-Commands.ps1`. Org keys, ConnectSecure tokens, SentinelOne tokens and uninstall passphrases, Automate installer tokens, and the RemoteOps enroll token stay GUI-only. The RemoteOps portal URL is `[RemoteOps] Portal=` in `local-defaults.ini`. Do not paste live tokens into tickets or git.

### Forensics

| Tool | Repo |
| --- | --- |
| HarkinsCollector (event logs) | [ExceedingLife/HarkinsCollector](https://github.com/ExceedingLife/HarkinsCollector) — zip under `C:\ForensicLogs` |
| Forensic Investigator (Sysinternals) | mytools `ForensicInvestigator` **v3.1.3** — zip under `C:\SecurityReports`, then the loose CSVs and EventLogs/Artifacts folders are deleted |
| Malwarebytes ADWCleaner | [ADWCleaner](https://www.malwarebytes.com/adwcleaner) — silent `/eula /clean /noreboot` |
| PUP remnant cleanup | mytools `PupRemnantCleanup` — family dropdown (All on host, or one catalog id). Dry-run reports what is present; Remediate deletes those families |
| PUP install block | mytools `PupRemnantCleanup` — stops those catalog program names and shows a warning. Re-apply after a family is added |

Harkins / Forensic Investigator use **Process-scoped** `Set-ExecutionPolicy Bypass` plus `Invoke-RestMethod -OutFile` then `&` run. ADWCleaner downloads the vendor EXE and runs `Start-Process -Wait`. Prefer elevated PowerShell.

### Microsoft 365

| Tool | Source |
| --- | --- |
| Inky / IPW transport rules | mytools — requires `Connect-ExchangeOnline` on an admin workstation; Scan lists, Delete removes (no `Read-Host`) |
| INKY / usecure / Skout enterprise apps | mytools `EntraVendorAppRemoval` — PowerShell one-liner only, pasted into Backstage on an admin PC. Scan lists matches. Apply opens the picker. App ids differ per tenant |
| Entra users, service accounts, BitLocker | mytools `EntraIntuneEvidence` — PowerShell one-liner only, pasted into Backstage on an admin PC. One run writes the authorized-user list, likely service accounts, and BitLocker per workstation to OneDrive |

### This PC

Tools pasted into Backstage or a local window on this computer, not a client session.

| Tool | Source |
| --- | --- |
| Pale Moon Portable | mytools `PaleMoonPortable` — Backstage PowerShell on this PC only. No Commands snippet. Official portable build, SHA256 from the Pale Moon download page, files in `C:\ProgramData\PaleMoonPortable` |
| Run Pale Moon Portable | mytools `PaleMoonPortable` — launches that same folder. Does not download |

### Untested

Park tools here until they have been validated on a host. Add `"Category", "Untested"` on the tool Map.

| Tool | Source |
| --- | --- |
| PHP use | mytools `PhpUse` — read-only on workstations and Windows Server. Servers are not skipped. Download is pinned to commit `1c67472` and checked with SHA256 |
| Deploy ScreenConnect client via GPO | mytools `ScreenConnectGpoDeploy` — stage the instance MSI on NETLOGON; Immediate Task installs when the client service is missing |
| Automate GPO deploy | mytools `AutomateGpoDeploy` — bake the location MSI and create the install GPO |
| Unquoted service paths | mytools `UnquotedServicePath` — read-only. Action needed includes the elevated `sc.exe` command that quotes the binary. Defender and Sense are left alone |
| RemoteOps enroll (token) | Inline — one-time portal token in the GUI; paste `#!ps` on the client host |
| RemoteOps remove | Inline — runs `remoteops-remove.ps1` from the portal, or `C:\ProgramData\RemoteOps` if the portal is down |
| Active Directory review (over tunnel) | mytools `ActiveDirectoryReview` — elevated PowerShell on this PC; Peer IP in the GUI; CSVs and `Summary.txt` under `Documents\ADReview` |

### Clients

Grouped by client name. Campaign tools that are not meant for general use.

| Client | Tool | Source |
| --- | --- | --- |
| Naviant | Acrobat XI removal (EOL) | mytools `ClientSpecific/Naviant/AcrobatXiRemoval` — scan XI + Foxit; uninstall XI (skip if no Foxit unless Force); 20 min timeout; MSI mutex wait / 1618 retry |
| St. Francis Seminary | Outlook disable local cache | mytools `OutlookDisableCache` — scan every profile, or force classic Outlook online-only and delete `.ost` / `.nst` |
| St. Francis Seminary | Stale user profiles | mytools `StaleUserProfile` — scan Windows profiles older than the age picked in the launcher (default 2 months), then remove only that list. Accounts stay |

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
