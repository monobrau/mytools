# Dell TechHub cleanup

Scan or remove **Dell TechHub** and **DTP** (the diagnostics plugin host).
SentinelOne often flags `techhub.dll` under `Program Files\Dell\TechHub`.

Dell Update / SupportAssist stay installed, including their own
`Dell.TechHub.*.dll` copies. SupportAssist hardware scans will stop working.

## What it touches

| Item | Action |
| --- | --- |
| Services whose image is under TechHub/DTP (including `DellTechHub`) | Stop + delete |
| Processes under TechHub/DTP (Instrumentation / Analytics / DataManager / Diagnostics) | Kill |
| ARP `Dell TechHub`, `Dell Core Services` | Silent uninstall when a string exists |
| `Program Files\Dell\TechHub`, `Dell\DTP`, `ProgramData\Dell\TechHub` | Delete |

Does **not** delete files under SupportAssist, Dell Update, SARemediation, or
Dell Remediation. If a target folder stays `LOCKED`, a DTP process or S1 still
holds it — reboot and Apply again.

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Prefer elevated
PowerShell. Or use ScToolLauncher (**OEM cleanup** → Dell TechHub). Scan first.
