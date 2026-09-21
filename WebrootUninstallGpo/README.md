# Webroot uninstall GPO

Create an AD GPO whose **Immediate Task** (Group Policy Preferences, Windows 7+)
silently uninstalls Webroot SecureAnywhere / OpenText Core Endpoint Protection
when `WRSA.exe` is present.

The task runs as **SYSTEM at the next `gpupdate`**. No reboot is required to
start. Webroot may still need a reboot to finish driver/service removal.

Native **Software Installation** cannot remove Webroot unless that same MSI was
originally assigned by GPO. Cloud and EXE installs have no matching package.

One machine right now (no GPO): ScToolLauncher **AV → Cylance / Webroot cleanup**.

Fleet check from the DC (no ScreenConnect on the PCs): **AV → Webroot fleet status**
or `Get-WebrootFleetStatus.ps1`. It pulls AD computer names and probes `C$`
for `WRSA.exe`, `ProgramData\WRData`, and the GPO log. CSV:
`C:\Windows\Temp\Webroot-Fleet-Status.csv`. Unreachable / no admin$ is not
proof Webroot is gone.

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
3. Publishes `Uninstall-Webroot.ps1` in the GPO SYSVOL folder
4. Registers a computer **Immediate Task** that runs that script as SYSTEM
   - If a keycode is available (endpoint registry or `-KeyCode`), run
     `WRSA.exe /autouninstall=<keycode> /silent`. `WRSA.exe -uninstall` opens a GUI
     and is not used
   - Always sweep leftovers: WRSA/WRSVC processes, WR* services, scheduled
     tasks, Run keys, ARP, `HKLM\SOFTWARE\WR*`, `Program Files*\Webroot`,
     `ProgramData\WRData` / `WRCore`, and `WRkrn.sys` / related drivers
5. Optional `-LinkToDomain` plus a workstation-only WMI filter (`ProductType = 1`)

On a test PC: `gpupdate /force`, then check
`C:\Windows\Temp\Webroot-GPO-Uninstall.log`. Background refresh is up to ~90
minutes if you do not force. Reboot if a driver is locked, then gpupdate again.

`-KeyCode` is written into the script on SYSVOL (readable by domain computers).
That is OK for a site uninstall key if you choose to pass it at apply time.
Do not commit the key to git.

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
