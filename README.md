# mytools

Public collection of work tools and scripts.

## Tools

| Tool | Description |
| --- | --- |
| [DotNetUpdate](DotNetUpdate/) | Patch installed .NET 6+ Runtime/Desktop/ASP.NET/SDK to latest same-major security release |
| [HpSupportAssistantUpdate](HpSupportAssistantUpdate/) | Check / uninstall (Win10 v-scan remediation) / update HP Support Assistant (ScreenConnect Backstage + `#!ps`) |
| [M365AppsUpdate](M365AppsUpdate/) | Silent M365 Apps Click-to-Run check/update; clear up-to-date verdict; does not close Office apps by default |
| [ScToolLauncher](ScToolLauncher/) | AutoHotkey v2 hotkey GUI — ScreenConnect tool shortcuts (any workflow): pick tool/mode and copy `#!ps` / Backstage bootstrap to clipboard |
| [TeamsClassicRemnantCheck](TeamsClassicRemnantCheck/) | Post-cleanup check for Classic / per-user Microsoft Teams remnants (vuln-scan evidence; GitHub + ScreenConnect) |
| [VulnSoftwareUpdate](VulnSoftwareUpdate/) | Multi-product vuln remediation updater (M365/HPSA/DotNet delegates + winget; ScreenConnect `#!ps`) |
| [WindowsDefenderRepair](WindowsDefenderRepair/) | Re-enable Defender real-time protection and start WinDefend / WdNisSvc |
| [ClientSpecific](ClientSpecific/) | Per-client campaign tools (ScToolLauncher: Client-specific → client name) |

## Layout

Tools live as subfolders under this repo. Prefer clear, self-contained directories with their own short README when a tool is more than a single script.
