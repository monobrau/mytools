# Windows Update (quality + feature)

Scan or install **quality** (non-feature) Windows Updates, or **feature**
updates / enablement packages. Uses the Windows Update Agent COM API (no
extra module).

Default install does **not** reboot. `-Reboot` restarts when the installer
reports `RebootRequired` (ScreenConnect session will drop).

## Pre-check

Scan and Apply always run a pre-check:

- System-drive free space (quality: fail under 8 GB; feature: fail under 20 GB)
- Recovery / WinRE partition size (fail under 250 MB; warn under 500 / 750 MB)
- WinRE enabled (`reagentc /info`); Disabled is Fail for feature, Warn for quality
- `wuauserv`, `bits`, `TrustedInstaller`, `cryptsvc` not Disabled
- `DisableWindowsUpdateAccess` and broken WSUS (`UseWUServer=1` with empty URL)
- Pending reboot (CBS / WU / file rename)
- Feature only: under 4 GB RAM is Fail

Apply stops on Fail unless `-Force`. Critical disk (under 5 GB quality / 10 GB
feature) always stops.

## Parameters

| Switch | Meaning |
| --- | --- |
| `-CheckOnly` | Search and report only |
| `-Quality` | Cumulative / security / SSU (default) |
| `-Feature` | Feature Update / Enablement Package only |
| `-Reboot` | Auto-reboot when required |
| `-Force` | Include Preview; continue after non-critical pre-check Fail |
| `-NoExit` | Keep the host open (Backstage). Accepted so the launcher does not fail |
| `-Exit` | Exit with a status code (Commands) |

## ScreenConnect

Use ScToolLauncher (**Software updates** → Windows Update quality / feature).
Scan first. Prefer elevated. Feature installs can take hours — use Backstage
or a long Commands timeout (4 hours). Reload the launcher after pull (`1.0.0`).
