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

## Windows 11 23H2 (build 22631)

Version upgrades from build 22631 fail more often than later builds. Apply
(not a scan) on that build:

- Sets `wuauserv`, `bits`, `dosvc`, `UsoSvc`, and `WaaSMedicSvc` to Manual and
  starts them, unless `DisableWindowsUpdateAccess` is set
- Runs `reagentc /enable` when Windows RE is disabled
- Installs pending cumulative and servicing-stack updates before a feature
  update, then stops so you can reboot and run `-Feature` again
- Prints the Windows Update `HResult` when a download or install fails.
  `0x80070643` on this build is usually WinRE

A feature scan reports those cumulative updates and any safeguard hold
(`GStatus=0`) or red upgrade block, and does not change the PC.
`PendingFileRenameOperations` alone is not treated as a reboot that blocks
the install.

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

A feature install from Backstage does not need someone signed in at the desktop.
It installs pending driver updates first, because those keep the version upgrade
at "Downloading 0%". It will not start a second copy while one is already in
progress. `-Reboot` restarts the PC only when Windows Update sets
`RebootRequired`. Leave that switch off to stop and report a required reboot
without restarting.
