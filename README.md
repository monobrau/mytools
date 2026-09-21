# mytools

Public collection of work tools and scripts.

## Tools

| Tool | Description |
| --- | --- |
| [DellTechHubCleanup](DellTechHubCleanup/) | Scan/remove Dell TechHub (`DellTechHub` service, `techhub.dll`) — common SentinelOne false positive |
| [DotNetUpdate](DotNetUpdate/) | Patch installed .NET 6+ Runtime/Desktop/ASP.NET/SDK to latest same-major security release |
| [ForensicInvestigator](ForensicInvestigator/) | Sysinternals + Harkins EVTX + all-user Downloads (Zone.ID), PS history, hives, browser History, admins/RMM, Defender; `C:\SecurityReports` |
| [HpSupportAssistantUpdate](HpSupportAssistantUpdate/) | Check / uninstall (Win10 v-scan remediation) / update HP Support Assistant (ScreenConnect Backstage + `#!ps`) |
| [M365AppsUpdate](M365AppsUpdate/) | Silent M365 Apps Click-to-Run check/update; clear up-to-date verdict; does not close Office apps by default |
| [PupRemnantCleanup](PupRemnantCleanup/) | Definition-driven PUP leftover sweep (Ask Toolbar, MediaArena/PDF converters, AppSuite, Wave, OneLaunch, Browser Assistant). Dry-run by default; `-Remove` deletes remnants |
| [ScToolLauncher](ScToolLauncher/) | AutoHotkey v2 hotkey GUI — ScreenConnect tool shortcuts (any workflow): pick tool/mode and copy `#!ps` / Backstage bootstrap to clipboard |
| [TeamsClassicRemnantCheck](TeamsClassicRemnantCheck/) | Post-cleanup check for Classic / per-user Microsoft Teams remnants (vuln-scan evidence; GitHub + ScreenConnect) |
| [VulnSoftwareUpdate](VulnSoftwareUpdate/) | Multi-product vuln remediation updater (M365/HPSA/DotNet/VC++ 2005-2013 delegates + winget; ScreenConnect `#!ps`) |
| [VisualCppUpdate](VisualCppUpdate/) | Patch installed Visual C++ 2005-2013 redistributables to the last security build for that year |
| [WindowsDefenderRepair](WindowsDefenderRepair/) | Re-enable Defender real-time protection and start WinDefend / WdNisSvc |
| [WindowsUpdate](WindowsUpdate/) | Scan/install quality or feature Windows Updates; pre-check for disk, WinRE, WU policy; default no reboot |
| [ClientSpecific](ClientSpecific/) | Per-client campaign tools (ScToolLauncher: Client-specific → client name) |

## Layout

Tools live as subfolders under this repo. Prefer clear, self-contained directories with their own short README when a tool is more than a single script.
