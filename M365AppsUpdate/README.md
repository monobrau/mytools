# M365AppsUpdate

Silently check or update **Microsoft 365 Apps** via **Click-to-Run** (`OfficeC2RClient.exe`). Not winget.

Designed so the person running the script gets a clear **UP TO DATE** / **UPDATES NEEDED** verdict, without disrupting open Office apps by default.

## Behavior

| Mode | What happens |
| --- | --- |
| **Default** | Compare installed build to Microsoft channel latest. If current → announce **no updates needed** and stop. If behind → start **silent** update with `forceappshutdown=false` (apps stay open). |
| `-CheckOnly` | Verdict only; never starts an update. |
| `-ForceAppShutdown` | Opt-in: close Word/Excel/Outlook/etc. so the update can finish immediately (disruptive). |
| `-Force` | Start silent update even when the host already looks current. |

Exit codes:

| Code | Meaning |
| --- | --- |
| `0` | Up to date / no action needed (or update completed to current) |
| `2` | Updates available, or update started but not yet confirmed current |
| `1` | Error / could not verify (check-only) / C2R missing |

## Verdict (what you’ll see)

```
======== M365 APPS UPDATE STATUS: UP TO DATE — NO UPDATES NEEDED ========
No updates needed. Local 16.0.x >= channel latest 16.0.x (Current).
================================================
```

or

```
======== M365 APPS UPDATE STATUS: UPDATE AVAILABLE — UPDATES NEEDED ========
Updates needed. Local 16.0.x < channel latest 16.0.x (Current).
================================================
```

Channel latest comes from Microsoft’s Office Releases API (`clients.config.office.net`), matched to the host CDN / channel.

## ScreenConnect

Copy from [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1):

- **Backstage:** one-liners only
- **Commands tab:** `#!ps` blocks

Prefer **CHECK ONLY** first on a live user session; use default for silent remediate. Use `-ForceAppShutdown` only when coordinated with the user.

## Notes

- Non-disruptive updates may stay pending until Office apps are closed later — re-run `-CheckOnly` to confirm.
- If `UpdatesEnabled` is False, policy may block updates.
- Changing update channel (Current vs Monthly Enterprise, etc.) is a separate Intune / deployment decision.

## Local run

```powershell
.\Update-M365Apps.ps1 -CheckOnly
.\Update-M365Apps.ps1
.\Update-M365Apps.ps1 -ForceAppShutdown   # disruptive; ask the user first
```
