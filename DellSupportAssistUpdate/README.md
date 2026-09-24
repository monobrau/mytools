# Dell SupportAssist update

Updates **Dell SupportAssist** when it is already installed. Does not install it on a PC that does not have it. Does not change OS Recovery, Remediation, or TechHub.

The installer is Dell's current bootstrapper (`SupportAssistInstaller.exe /S`) from `downloads.dell.com`. The built-in target is **5.2.0.1519** (August 2026). Override with `-LatestVersion`.

| Switch | Action |
| --- | --- |
| _(none)_ | Update when installed and older than the target |
| `-CheckOnly` | Report the installed version. Exit `2` when it is behind |
| `-Force` | Run the installer even when the version is already at the target |

Not installed exits `0`. Result codes: `0` current or updated, `2` check-only and behind, `1` error, `3010` / `1641` reboot required.

## ScreenConnect

See [`ScreenConnect-Commands.ps1`](ScreenConnect-Commands.ps1). Prefer elevated PowerShell. The bootstrapper needs HTTPS to Dell.
