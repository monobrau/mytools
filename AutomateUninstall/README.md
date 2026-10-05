# ConnectWise Automate agent uninstall / reinstall

Scan, remove, or reinstall the **ConnectWise Automate** (LabTech) remote agent.
ScreenConnect, ConnectWise Control, and the Automate Control Center stay installed.

`-Reinstall` does not ask for an installer token. It uses the server and location
already in `HKLM\SOFTWARE\LabTech\Service`, and the agent MSI Windows cached at
install time. If that cache is gone, it downloads an MSI from that same server.
Nothing is removed when no installer can be found. The new agent checks in with
a **new agent ID** in the same location.

## What it touches

| Item | Action |
| --- | --- |
| Services `LTSvcMon`, `LabVNC`, `LTService` | Stop, then `sc.exe delete` |
| Processes under `%windir%\LTSvc` (`LTSvc`, `LTTray`, …) | Kill |
| ARP "LabTech / ConnectWise Automate Remote Agent" | `msiexec /x {guid} /qn` |
| `Agent_Uninstall.exe` | Download from the server on the agent, then the public ConnectWise copy, and run it |
| `%windir%\LTSvc`, `%windir%\Temp\_ltupdate` | Delete |
| `HKLM\SOFTWARE\LabTech\Service`, `LabVNC`, `LabTechMSP` (and Wow6432Node copies) | Delete |
| `HKCU\SOFTWARE\LabTech\Service` and `LabVNC` | Delete only when Automate Control Center is not installed |
| Scheduled tasks whose action is under `LTSvc` | Unregister |
| Cached or downloaded agent MSI | On `-Reinstall`, `msiexec /i` with the same `SERVERADDRESS` and `LOCATION` |

A **probe** agent (`Probe=1` in the service key) is reported and left in place unless `-Force`.

Exit codes: `0` absent, removed, or reinstalled, `1` present (scan), `2` leftovers remain or the service did not return, `3` probe blocked, `4` action without elevation, `5` reinstall stopped because no installer was available.

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Prefer elevated
PowerShell. Or use ScToolLauncher (**Agents** → Automate). Scan first.
Reload the launcher after updating `ScToolLauncher.ahk`.
