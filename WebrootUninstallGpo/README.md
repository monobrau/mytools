# Webroot uninstall GPO

Create an AD GPO whose **Immediate Task** (Group Policy Preferences, Windows 7+)
silently uninstalls Webroot SecureAnywhere / OpenText Core Endpoint Protection
when `WRSA.exe` is present.

The task runs as **SYSTEM at the next `gpupdate`**. No reboot is required to
start. Webroot may still need a reboot to finish driver/service removal.

Native **Software Installation** cannot remove Webroot unless that same MSI was
originally assigned by GPO. Cloud and EXE installs have no matching package.

One machine right now (no GPO): ScToolLauncher **AV → Cylance / Webroot cleanup**.

## ScreenConnect (client DC)

Prefer **ScToolLauncher → AV → Webroot uninstall GPO**. Set the AD DNS name
(or leave blank for the current domain on the DC). Dry-run prints the cmd;
Apply creates the GPO.

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Run elevated as
Domain Admin on a DC or RSAT box. Do not commit a live client domain or keycode.

`#!ps` and `#timeout=900000` must be the first lines in Commands.

## What it does

1. Creates or updates `Uninstall Webroot`
2. Enables **Always wait for the network**
3. Publishes `Uninstall-Webroot.cmd` in the GPO SYSVOL folder
4. Registers a computer **Immediate Task** that runs that cmd as SYSTEM
   - Exit if `WRSA.exe` is missing
   - `"...\Webroot\WRSA.exe" -uninstall -silent`
   - Optional keycode retry if you passed `-KeyCode`
   - After WRSA is gone, delete `%ProgramData%\WRData` and `WRCore`
5. Optional `-LinkToDomain` plus a workstation-only WMI filter (`ProductType = 1`)

On a test PC: `gpupdate /force`, then check
`C:\Windows\Temp\Webroot-GPO-Uninstall.log`. Background refresh is up to ~90
minutes if you do not force.

This GPO does **not** reboot the PC and does **not** do a full remnant sweep.
Leftovers (drivers, `WRSVC`): [windows-av-cleanup](https://github.com/monobrau/windows-av-cleanup)
`-Delete -Vendor Webroot`.

A `-KeyCode` value is written into SYSVOL and is readable by domain computers.
Leave it blank unless uninstall fails without it.

## Parameters

| Parameter | Purpose |
| --- | --- |
| `-Domain` | AD DNS name (default: current domain) |
| `-TargetOU` | Link to this OU DN |
| `-LinkToDomain` | Link at domain root + workstation WMI filter |
| `-SkipWmiFilter` | Do not attach the WMI filter |
| `-SkipLink` | Create the GPO but do not link it |
| `-GpoName` | Override the GPO name |
| `-KeyCode` | Optional; written to SYSVOL |
| `-DryRun` | Print the uninstall cmd only |

Pilot by security-filtering the GPO to a test computer group; leave
**Authenticated Users** with **Read** (MS16-072).
