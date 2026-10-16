# HP Image Assistant

Downloads [HP Image Assistant](https://ftp.hp.com/pub/caps-softpaq/cmit/HPIA.html) (5.3.7) and runs it on **HP PCs only**. Non-HP computers exit `0` and do not download anything.

Apply installs only SoftPaqs HPIA marks as auto-installable (SSM-compliant): the ones that can install with nobody at the keyboard. Updates that need a click are not selected.

```
HPImageAssistant.exe /Operation:Analyze /Action:Install /Category:All /InstallType:AutoInstallable /Silent
```

`/Category:All` includes BIOS, drivers, software, firmware, and accessories. A BIOS package that supports silent install can still restart the PC by itself. This script does not reboot on its own unless `-Reboot` is set, and then only when HPIA returns `3010`.

Cache, reports, and SoftPaq downloads stay under `%ProgramData%\HpImageAssistant`. A later run reuses the extracted app until `-Force` or the installer file name changes.

| Switch | Action |
| --- | --- |
| _(none)_ | Download HPIA if needed, then install unattended SoftPaqs. No reboot |
| `-CheckOnly` | List unattended recommendations. Exit `2` when any are found |
| `-Reboot` | Restart after exit `3010` |
| `-Force` | Download and extract HPIA again |

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Not HP, nothing unattended, or install finished with no reboot |
| `1` | Not elevated, download/extract failed, or another hard error |
| `2` | Check-only and unattended recommendations exist |
| `3010` | Installed. Restart required. The script did not reboot |
| `3011` | A SoftPaq was skipped because it is not unattended |
| `3020` | One or more SoftPaq installs failed |
| `4096` | HP model is not in the HPIA platform list |
| `4098` | No internet connection |

## ScreenConnect

ScToolLauncher: **Software updates** → **HP Image Assistant**. Scan first. Prefer elevated. Apply can take a long time (2-hour Commands timeout). Reload the launcher after pull (`1.0.0`).

See [`ScreenConnect-Commands.ps1`](ScreenConnect-Commands.ps1).
