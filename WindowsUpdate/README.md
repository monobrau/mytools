# Windows Update (quality + feature + BIOS/firmware)

Scan or install **quality** (non-feature) Windows Updates, upgrade to the
latest stable Windows 11 from ISO, or install **BIOS / system firmware**
only. Quality and firmware use the Windows Update Agent COM API (no extra
module). A feature upgrade downloads the latest stable Windows 11 ISO from
Microsoft (the download link is resolved by the latest Fido release),
caches it under `C:\Temp\WindowsFeatureISO`, copies the media to a local
folder (setup launched from a mounted ISO can exit `0x8007007F`), and runs
`setup.exe /Auto Upgrade /Quiet /NoReboot` from there. It does not wait for
Windows Update to offer the version upgrade.

Firmware mode searches driver updates and keeps titles or driver classes that
are BIOS, UEFI, or system firmware. Other drivers are listed and skipped.
A BIOS that is not published to Windows Update will not appear.

Default install does **not** reboot. `-Reboot` restarts when the installer
reports `RebootRequired` (ScreenConnect session will drop). Firmware staged
this way does not load until that restart.

Windows Server and domain controllers exit immediately (`5`) and do not
change services or search. The launcher adds `-AllowServer` only when
**Allow Windows Server** is checked and the copy confirmation is accepted.

## Pre-check

Scan and Apply always run a pre-check:

- System-drive free space (quality: fail under 8 GB; feature: fail under 20 GB)
- Recovery / WinRE partition size (fail under 250 MB; warn under 500 / 750 MB)
- WinRE enabled (`reagentc /info`); Disabled is Fail for feature, Warn for quality
- `wuauserv`, `bits`, `TrustedInstaller`, `cryptsvc` not Disabled
- `DisableWindowsUpdateAccess` and broken WSUS (`UseWUServer=1` with empty URL)
- Pending reboot (CBS / WU / file rename)
- Feature only: under 4 GB RAM is Fail
- Feature only: SentinelOne installed is Fail. Its protected files fail
  the Safe OS phase (`0x80070005`) and roll the upgrade back. Uninstall it
  normally (SentinelOne console, or Programs and Features with the site
  passphrase), reboot, rerun, and reinstall it after the upgrade. `-Force`
  does not bypass this gate.

Apply stops on Fail unless `-Force`. Critical disk (under 5 GB quality / 10 GB
feature) always stops.

## Windows Update service

Apply (not a scan) sets `wuauserv`, `bits`, `dosvc`, `UsoSvc`, and
`WaaSMedicSvc` to Manual and starts them, unless `DisableWindowsUpdateAccess`
is set. A Disabled startup type is why search and install return
`0x8024001E` (the service stopped). Apply starts the service again and retries
that search or install once.

A download that finishes with errors installs only the updates that actually
downloaded. The rest are listed and skipped.

## Windows 11 23H2 (build 22631)

Version upgrades from build 22631 fail more often than later builds. Apply
(not a scan) on that build:

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
| `-Feature` | Upgrade to the latest stable Windows 11 from ISO (pending cumulative/driver updates still install via Windows Update first) |
| `-Firmware` | BIOS, UEFI, and system-firmware drivers only |
| `-Reboot` | Auto-reboot when required |
| `-Force` | Include Preview; continue after non-critical pre-check Fail |
| `-AllowServer` | Run on Windows Server / domain controller. Omitted snippets exit `5` |
| `-NoExit` | Keep the host open (Backstage). Accepted so the launcher does not fail |
| `-Exit` | Exit with a status code (Commands) |

## Progress

`Get-WindowsUpdateProgress.ps1` only reports status for Windows Update downloads. It does not start a download and it does not walk the download tree. During an ISO feature upgrade, watch `HKLM:\SYSTEM\Setup\MoSetup\Volatile` (`SetupProgress`) and `C:\$WINDOWS.~BT\Sources\Panther\setupact.log` instead.

`OSDownloadSize` 0 and `TaskCount` 0 mean the OS image is not downloading. A new timestamp on `ActionList.xml` only means Windows Update rewrote the plan. `-WatchSeconds 90` takes a second sample and says whether those counters increased.

Exit `0` means setup is running or the OS download grew. Exit `1` means a feature folder exists and the image is not downloading. Exit `2` means no feature download is in progress.

## ScreenConnect

Use ScToolLauncher (**Software updates** → Windows Update quality / feature / BIOS).
Scan first. Prefer elevated. Feature installs can take hours — use Backstage
or a long Commands timeout (4 hours). Reload the launcher after pull (`1.1.2`). Servers need Allow Windows Server, then Yes on the copy prompt.

A feature install installs pending driver updates first. It will not start
a second copy while setup is already running. `setup.exe` stages the
upgrade with `/NoReboot`; `-Reboot` restarts the PC only after staging
succeeds. Leave that switch off to stop and report `PENDING_REBOOT`
without restarting.

Two things that cost real time in testing:

- `setup.exe` cannot run in session 0. From Backstage it exits
  `-2147024769` (`0x8007007F`, automation initialization) within seconds.
  The script detects session 0 and launches setup in the signed-in user's
  session through a scheduled task, then waits for the result. A user must
  be signed in at the desktop; `/Quiet` still applies, so nothing pops up.
- The ISO language must match the PC's UI language or setup returns
  `0xC1900204` (migration choice blocked). Fido's default pick can choose
  English International on an en-US PC, so the script requests the host's
  language explicitly (`^English$` for en-US).
