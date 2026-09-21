# Dell TechHub / SupportAssist cleanup

Scan or remove **Dell TechHub**, **DTP**, and **SupportAssist**. SentinelOne
often flags `techhub.dll`; TechHub/DTP are SupportAssist’s diagnostics stack,
so Apply removes the app too.

Dell Command | Update and the SupportAssist **OS Recovery plugin** stay
installed.

## What it touches

| Item | Action |
| --- | --- |
| Services under TechHub/DTP/SupportAssist | Stop + delete |
| Processes under those trees | Kill |
| ARP `Dell TechHub`, `Dell Core Services`, `Dell SupportAssist` | Silent uninstall |
| `Program Files\Dell\TechHub`, `Dell\DTP`, `Dell\SupportAssist`, `Dell\SupportAssistAgent` | Delete |

Does **not** uninstall Dell Update, Command | Update, or the OS Recovery
plugin. Does not delete SARemediation / Dell Remediation.

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Prefer elevated
PowerShell. Or use ScToolLauncher (**OEM cleanup** → Dell TechHub). Scan first.
