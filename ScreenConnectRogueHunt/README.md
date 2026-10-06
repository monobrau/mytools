# ScreenConnect instance ID hunt

Read-only scan for ScreenConnect (ConnectWise Control) instance IDs. Prints **each distinct ID once**, with the product version when one was found.

| Verdict | Meaning |
| --- | --- |
| Authorized | ID is on the allow list |
| ROGUE | ID was found and is not on the allow list |
| Review | A service, process, task, or Run key matched ScreenConnect and had no instance ID |

More than one product version on the same ID is printed on that ID's line (`23.9.8.8817, 25.9.4.9291`).

Default allow list is the primary ID `8e1512c8736de3b9` and the ad hoc ID `fb310accf083cff0`. Override with `-AllowedInstanceIds`.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | No IDs, or authorized IDs only (one version each) |
| `1` | Review hits with no ID, or more than one version on an ID |
| `2` | At least one ROGUE ID |

## What it reads

Services registry (including entries hidden from the SCM), uninstall keys (64-bit, 32-bit, loaded user hives), MSI product names, running processes (version resource catches a renamed exe), Program Files, ProgramData, ClickOnce under `AppData\Local\Apps\2.0`, Downloads, Desktop, Temp, scheduled tasks, Run keys, System event 7045, and ScreenConnect event-provider names.

## ScreenConnect

The launcher and [`ScreenConnect-Commands.ps1`](ScreenConnect-Commands.ps1) download this script from GitHub `main`. Reload the AutoHotkey launcher after this folder is on `main`.

```powershell
.\Find-RogueScreenConnect.ps1
.\Find-RogueScreenConnect.ps1 -OutCsv C:\Windows\Temp\sc-ids.csv -EventDays 90
```

Prefer elevated. Without elevation, other users' processes and some profile folders are skipped.
