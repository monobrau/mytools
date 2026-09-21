# Dell TechHub cleanup

Scan or remove **Dell TechHub** — the shared `DellTechHub` service and
`*TechHub*.dll` files (including `techhub.dll`) that SentinelOne often flags.

Dell Command | Update / Dell Update stay installed. SupportAssist hardware
diagnostics use TechHub and will stop working after removal.

## What it touches

| Item | Action |
| --- | --- |
| Service `DellTechHub` | Stop + delete |
| ARP `Dell TechHub`, `Dell Core Services` | Silent uninstall when a string exists |
| `Program Files\Dell\TechHub`, `Dell\DTP`, `ProgramData\Dell\TechHub` | Delete |
| `*TechHub*.dll` under those Dell trees | Delete |

Does **not** uninstall SupportAssist or Dell Update. If a DLL stays
`LOCKED`, S1 likely still has the file; rerun after it releases, or disable
the service so it stops loading.

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Prefer elevated
Backstage. Or use ScToolLauncher (**OEM cleanup** → Dell TechHub). Scan first.
