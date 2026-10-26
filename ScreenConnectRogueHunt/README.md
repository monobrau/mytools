# ScreenConnect instance ID hunt

Scan for ScreenConnect (ConnectWise Control) instance IDs. Prints **each distinct ID once**, with the product version when one was found. The default is read-only. `-Remediate` removes installs whose instance ID is not on the allow list.

| Verdict | Meaning |
| --- | --- |
| Authorized | ID is on the allow list |
| ROGUE | A live install was found and the ID is not on the allow list |
| History | The ID is only in a service-install event or event-provider name. The client is not installed. |
| Review | A service, process, task, or Run key matched ScreenConnect and had no instance ID |

More than one product version on the same ID is printed on that ID's line (`23.9.8.8817, 25.9.4.9291`).

Default allow list is the primary ID `8e1512c8736de3b9` and the ad hoc ID `fb310accf083cff0`. Override with `-AllowedInstanceIds`.

## Remove

`-Remediate` stops the rogue client, runs its uninstall command quietly, deletes the service, and deletes install folders whose name contains that instance ID. It also removes matching Run values, scheduled tasks, and event-provider keys.

Allow-listed IDs are kept. A folder an allow-listed client still uses is kept. Review hits with no instance ID are left. Event history is left. The script does not reboot.

Run it from the allow-listed session. If this session is the rogue client, removal is handed to the scheduled task `RemoveRogueScClient` so it can finish after that connection drops. The log is `C:\Windows\Temp\Remove-RogueScClient.log`.

`-CheckOnly` wins over `-Remediate`. Removal requires elevation.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | No IDs, or authorized IDs only (one version each). After `-Remediate`, no rogue install left. |
| `1` | Review hits with no ID, more than one version on an ID, or event history only |
| `2` | At least one live ROGUE install. After `-Remediate`, a rogue install is still present or the session is not elevated. |

## What it reads

Services registry (including entries hidden from the SCM), uninstall keys (64-bit, 32-bit, loaded user hives), MSI product names, running processes (version resource catches a renamed exe), Program Files, ProgramData, ClickOnce under `AppData\Local\Apps\2.0`, Downloads, Desktop, Temp, scheduled tasks, Run keys, System event 7045, and ScreenConnect event-provider names.

## ScreenConnect

The launcher and [`ScreenConnect-Commands.ps1`](ScreenConnect-Commands.ps1) download this script from GitHub `main`. Reload the AutoHotkey launcher after this folder is on `main`.

```powershell
.\Find-RogueScreenConnect.ps1
.\Find-RogueScreenConnect.ps1 -Remediate
.\Find-RogueScreenConnect.ps1 -OutCsv C:\Windows\Temp\sc-ids.csv -EventDays 90
```

Prefer elevated. Without elevation, other users' processes and some profile folders are skipped, and `-Remediate` makes no changes.
