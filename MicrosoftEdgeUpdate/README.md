# Microsoft Edge update

Checks or updates **installed Microsoft Edge stable**. It does not install Edge when Edge is missing. The verdict is for stable Edge only. Microsoft's updater may also refresh other apps it manages, such as WebView2.

The version check uses Microsoft's enterprise release list. Apply runs the updater already on the PC: `MicrosoftEdgeUpdate.exe /update`. Open Edge windows can keep the old version until they close. The script does not reboot.

## Behavior

| Mode | What happens |
| --- | --- |
| **Default** | If Edge is behind the current stable release, start the updater and watch the version. If it already matches, stop. |
| `-CheckOnly` | Verdict only. Does not start the updater. |
| `-Force` | Start the updater even when Edge already matches. |

Exit codes:

| Code | Meaning |
| --- | --- |
| `0` | Up to date, or the updater brought Edge to the current stable release |
| `2` | Update available, or the updater started and the version was not confirmed yet |
| `1` | Edge is not installed, policy blocks updates, or the updater could not be verified |

## ScreenConnect

Copy from [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1), or use ScToolLauncher (**Updates** → Microsoft Edge). Prefer elevated. Scan first.

## Local run

```powershell
.\Update-MicrosoftEdge.ps1 -CheckOnly
.\Update-MicrosoftEdge.ps1
```
