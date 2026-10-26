# Python cleanup

Uninstalls vulnerable CPython on Windows. A newer Python on the same PC does not keep an older one. ConnectSecure stays open on a leftover `Python 3.13.1 (64-bit)` even when a current 3.13 is also installed.

## What is removed

| Install | Result |
| --- | --- |
| Python 2.x, and 3.0 through 3.10 | End of life. Removed |
| 3.11 older than 3.11.18 | Removed |
| 3.12 older than 3.12.16 | Removed |
| 3.13 older than 3.13.18 | Removed |
| 3.14 older than 3.14.10 | Removed |
| 3.15 older than 3.15.2 | Removed |
| Current build of a supported branch | Kept |
| Python Launcher, Anaconda, Miniconda, Python inside another app | Kept |

Floors are the python.org releases from 2026-10-26. A newer branch that this script does not list is kept.

Apply does not install a replacement. If 3.13.1 is the only Python on the PC, it is uninstalled. Nothing is rebooted.

`-EolOnly` removes 3.10 and older and leaves a behind-patch 3.12 or 3.13 in place.

## ScreenConnect

Prefer the launcher, or the snippets in [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1).

Scan lists targets. Remove uninstalls them. Run elevated so per-user installs under other profiles are included.

## Local

```powershell
.\Uninstall-VulnerablePython.ps1 -CheckOnly
.\Uninstall-VulnerablePython.ps1 -Remediate
.\Uninstall-VulnerablePython.ps1 -Remediate -EolOnly
```

Exit `0` when nothing vulnerable remains, `1` when a scan still finds one, `2` when a remove fails or is not elevated.
