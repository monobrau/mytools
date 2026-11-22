# Windows Update (quality + feature + BIOS/firmware)

Scan or install **quality** (non-feature) Windows Updates, upgrade straight
to **Windows 11 26H2** from ISO, or install **BIOS / system firmware**
only. 22H2 and 23H2 skip 24H2 and 25H2. Quality and firmware use the
Windows Update Agent COM API (no extra module). A feature upgrade uses a
build 26300 ISO (Fido when it returns 26H2, otherwise the fallback URL),
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

- System-drive free space (quality: fail under 8 GB; feature: fail under 20 GB; 22H2/23H2 to 26H2: fail under 32 GB)
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
  does not bypass this gate; `-AllowSentinelOne` does, deliberately, and
  prints a warning that the rollback risk remains.

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

## Windows 11 22H2 and 23H2

Builds before 26100 (22H2 and 23H2) upgrade straight to Windows 11 26H2.
24H2 and 25H2 are not installed in between. An ISO whose name is older
than build 26300 is ignored. Apply (not a scan) on those builds:

- Runs `reagentc /enable` when Windows RE is disabled
- Installs pending cumulative and servicing-stack updates before the
  26H2 upgrade, then stops so you can reboot and run `-Feature` again
- Requires about 32 GB free and a recovery partition of about 1 GB
- Stops when a CBS or Windows Update reboot is still pending
- Runs `setup.exe /Compat ScanOnly` and does not start the upgrade when
  that scan reports a hard block
- Turns Dynamic Update on for the upgrade so setup can fetch Safe OS
  and driver fixes
- Prints setup errors and compatibility blocks, then removes a failed
  `C:\$WINDOWS.~BT` so the next run does not reuse it

A feature scan reports those cumulative updates and any safeguard hold
(`GStatus=0`) or red upgrade block, and does not change the PC.
`PendingFileRenameOperations` alone is not treated as a reboot that blocks
the install.

## Parameters

| Switch | Meaning |
| --- | --- |
| `-CheckOnly` | Search and report only |
| `-Quality` | Cumulative / security / SSU (default) |
| `-Feature` | Upgrade straight to Windows 11 26H2 from ISO. 22H2 and 23H2 skip 24H2 and 25H2. Pending cumulative/driver updates still install via Windows Update first |
| `-IsoUrl <url>` | Feature only: download the ISO from this URL instead of asking Microsoft through Fido. A cached ISO is used first only when its name is build 26300 or newer |
| `-IsoFallbackUrl <url>` | Feature only: try Fido first. If Fido cannot be downloaded or returns no URL, download this URL instead. The launcher passes `https://www.famousashtray.com/stuff/Windows11_Client_x64_en-us_26300_9457.iso`. `-IsoUrl` skips Fido and takes priority |
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

- `setup.exe` launched straight out of Backstage exits `-2147024769`
  (`0x8007007F`, automation initialization) within seconds. That is
  Backstage's process environment, not SYSTEM in session 0: from
  Backstage the script launches setup through a one-time scheduled task
  running as SYSTEM (proper service context, works with nobody signed
  in) and waits for its result file. If the SYSTEM task still returns
  `0x8007007F`, it retries in the signed-in user's session when one
  exists. `/Quiet` applies in both cases, so nothing pops up.
- The ISO language must match the PC's UI language or setup returns
  `0xC1900204` (migration choice blocked). Fido's default pick can choose
  English International on an en-US PC, so the script requests the host's
  language explicitly (`^English$` for en-US) and checks `lang.ini`
  against the host before running setup.
- Microsoft's download protection rejects repeated Fido calls from one
  address ("Sentinel marked this request as rejected") and takes a while
  to clear. The launcher passes `-IsoFallbackUrl`, so a feature run that
  gets no URL from Fido downloads `https://www.famousashtray.com/stuff/Windows11_Client_x64_en-us_26300_9457.iso`
  instead. A cached ISO is used without calling Fido only when its name
  is Windows 11 26H2 (build 26300) or newer. Older media, including a
  cached 24H2 or 25H2 ISO, is left on disk and skipped. Extracted media
  is reused only when `media\iso-source.txt` names that same ISO.
