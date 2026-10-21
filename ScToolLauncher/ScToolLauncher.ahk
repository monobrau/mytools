#Requires AutoHotkey v2.0
; ScToolLauncher — hotkey picker for any ScreenConnect-ready tool shortcut (not vuln-only).
; Copies a GitHub bootstrap #!ps / PowerShell one-liner to the clipboard.
; Hotkey: Ctrl+Shift+Alt+S (change HotkeySpec below). Prefer Commands tab #!ps.
; Commands snippets relaunch Windows PowerShell 5.1 when #!ps is the v2 engine
; (Tls12 enum is missing; GitHub then fails). TLS uses numeric 3072, not ::Tls12.
; Catalog: mytools (Contents API) + other monobrau repos (raw.githubusercontent.com).

#SingleInstance Force
Persistent

; --- config ---
; Ctrl+Shift+Alt+S — Win+Alt+* is often eaten by Windows / GPU overlays.
HotkeySpec := "^+!s"
HotkeyLabel := "Ctrl+Shift+Alt+S"
AppName := "SC Tool Launcher"
TrayLabel := AppName " (" HotkeyLabel ")"
DefaultOwner := "monobrau"
DefaultRepo := "mytools"
DefaultRef := "main"
MaxLength := "200000"
; Huntress account key is permanent for this tenant. local-defaults.ini can override.
LocalDefaultsPath := A_ScriptDir "\local-defaults.ini"
HuntressAccountKeyDefault := "fddd1009b6541feb66431b905f6fc870"

; Fetch: Contents (api.github.com + Accept raw) | Raw (raw.githubusercontent.com?v=)
;        Inline (Body is the snippet; no GitHub download)
;        IrmOutFile (Process Bypass + irm -OutFile + & run — for unsigned remote .ps1)
;        DownloadExe (IWR vendor EXE + Start-Process -Wait)
;        Url (optional) overrides the constructed GitHub raw URL — use for gists
; Category: groups tools in the TreeView (order = CategoryOrder below)
; Folder: optional subfolder under Category (same as Client= for Client-specific)
;        CheckOnly Force ForceAppShutdown IncludeBrowsers Uninstall Detailed Remediate Reinstall Product ProductList
;        NoExit Delete BlockReinstall RemoveSupportAssistant Vendor
;        ScanOnly RunOnly PositionalDry Domain CacheBust RebootAdvisory AlwaysNote ConnectSecure
;        SkipIfRunning ResetPlatform SentinelOneInstall SentinelOneUnload HuntressInstall AutomateGpo ScreenConnectGpo WebrootUninstallGpo BackupsOnlyDefault ClearAllBackupContent
;        PowerIdle FastStartup EolAudit EolAuditGpo PupBlock
;        BackstageOnly AutoReboot AllowServer Help
HelpIntroText := Format("
(
SC Tool Launcher copies a ScreenConnect-ready snippet to the clipboard.

Hotkey: {1}
Use {1} to open or hide this window. Tray Open also works.

How to use
1. Expand a category (and any subfolder) on the left.
2. Select a tool.
3. Choose Scan vs Apply, options, and paste format.
4. Copy to clipboard.
5. Paste into ScreenConnect Commands (recommended) or PowerShell.

Tips
- Untested means the tool has not been validated yet.
- After you edit this script, use Reload. {1} does not reload the catalog.
- Tokens and keys are only in the snippet you copy — they are not saved here.
)", HotkeyLabel)
CategoryOrder := [
    "Software updates — vuln catalog, M365, .NET, HPSA, Teams",
    "ScreenConnect — rogue IDs, GPO/MSI finder, temp cleanup",
    "OEM cleanup — HP Touchpoint, HP bloat, Dell SARemediation",
    "AV — Defender repair, Cylance/Webroot, McAfee remnants",
    "Agents — SentinelOne, ConnectSecure, Huntress, Automate",
    "Power — plugged-in sleep, hibernate, Fast Startup",
    "IR / forensics — event logs, Sysinternals, ADWCleaner",
    "M365 / Exchange — admin PC (Inky rules, vendor apps)",
    "Untested",
    "Client-specific"
]

; TreeView (left) / options column (right) — side-by-side so short screens fit
UiTreeW := 360
UiContentW := 440
UiColGap := 16
UiTreeRows := 24

Tools := [
    Map(
        "Category", "Help",
        "Name", "Help",
        "Summary", "Intro and basic instructions for this launcher.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/ScToolLauncher",
        "Fetch", "Inline",
        "Body", "",
        "Flags", "Help"
    ),
    ; --- Software updates ---
    Map(
        "Category", "Software updates — vuln catalog, M365, .NET, HPSA, Teams",
        "Name", "Vulnerable software updater (catalog)",
        "Summary", "Checks/updates common third-party apps (winget + M365/HPSA/.NET/VC++ 2005-2013 delegates). Browsers are opt-in.",
        "Affects", "
(Join`r`n
Scan skips anything not installed. Apply updates only what is installed and behind.
Microsoft 365 Apps (Click-to-Run)
HP Support Assistant (Windows 10 uninstall, Windows 11 update)
Dell SupportAssist (update only when already installed)
.NET 6+ Runtime / Desktop / ASP.NET / SDK (same major only)
Visual C++ 2005-2013 redistributables
ShareX
Adobe Acrobat / Reader
Visual Studio Code
Git
GIMP (stays on 2.x)
Winamp
Greenshot
Teams Network Assessment Tool (report only)
WinRAR
Foxit PDF Reader
7-Zip (update, then remove every older copy)
Notepad++
Visual C++ 2015+ x64 and x86
PuTTY
WinSCP
VLC
Edge WebView2 Runtime
PowerShell 7
FileZilla
KeePass
KeePassXC
SumatraPDF
Azure CLI
GitHub CLI
TreeSize Free
PowerToys
Windows Terminal
AWS CLI
Sysinternals Suite
UltraVNC
Python 3.13 (stays on 3.13; does not jump to 3.14)
---
Opt-in only, when Include browsers is checked:
Google Chrome
Microsoft Edge
Mozilla Firefox
)",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/VulnSoftwareUpdate",
        "Fetch", "Contents",
        "Path", "VulnSoftwareUpdate",
        "Script", "Update-VulnSoftware.ps1",
        "UaPrefix", "VulnSoftwareUpdate-bootstrap",
        "UaVer", "1.4.8",
        "TimeoutScan", 900000,
        "TimeoutUpdate", 1800000,
        "Flags", "CheckOnly Force ForceAppShutdown IncludeBrowsers Product NoExit"
    ),
    Map(
        "Category", "Software updates — vuln catalog, M365, .NET, HPSA, Teams",
        "Name", "Microsoft 365 Apps (Click-to-Run)",
        "Summary", "Silent M365 Apps Click-to-Run check/update. Does not close Office unless you opt in.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/M365AppsUpdate",
        "Fetch", "Contents",
        "Path", "M365AppsUpdate",
        "Script", "Update-M365Apps.ps1",
        "UaPrefix", "M365AppsUpdate-bootstrap",
        "UaVer", "1.1.1",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 600000,
        "Flags", "CheckOnly Force ForceAppShutdown NoExit"
    ),
    Map(
        "Category", "Software updates — vuln catalog, M365, .NET, HPSA, Teams",
        "Name", ".NET runtime / SDK patches",
        "Summary", "Patches installed .NET 6+ Runtime/Desktop/ASP.NET/SDK to the latest same-major security release only.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/DotNetUpdate",
        "Fetch", "Contents",
        "Path", "DotNetUpdate",
        "Script", "Update-DotNetRuntimes.ps1",
        "UaPrefix", "DotNetUpdate-bootstrap",
        "UaVer", "1.0.1",
        "TimeoutScan", 900000,
        "TimeoutUpdate", 1800000,
        "Flags", "CheckOnly Force NoExit"
    ),
    Map(
        "Category", "Software updates — vuln catalog, M365, .NET, HPSA, Teams",
        "Name", "Visual C++ 2005-2013 redistributables",
        "Summary", "Patches installed VC++ 2005/2008/2010/2012/2013 to the last security build. Does not add missing years. 2015+ stays on the vuln catalog winget IDs.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/VisualCppUpdate",
        "Fetch", "Contents",
        "Path", "VisualCppUpdate",
        "Script", "Update-VisualCppRedistributables.ps1",
        "UaPrefix", "VisualCppUpdate-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 900000,
        "TimeoutUpdate", 1800000,
        "Flags", "CheckOnly Force NoExit"
    ),
    Map(
        "Category", "Software updates — vuln catalog, M365, .NET, HPSA, Teams",
        "Name", "EOL dependency use",
        "Summary", "Reports whether out-of-support runtimes are loaded (VC++ 2005-2013, .NET 3.1/5/6/7, Silverlight, old SQL client). Scan only measures the Security log. Apply audits sentinel DLLs and keeps process hit counts.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/EolDependencyAudit",
        "Fetch", "Contents",
        "Path", "EolDependencyAudit",
        "Script", "Invoke-EolDependencyAudit.ps1",
        "UaPrefix", "EolDependencyAudit-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 600000,
        "TimeoutUpdate", 600000,
        "Flags", "EolAudit Force NoExit",
        "Note", "Scan does not change auditing. Apply turns on File System success auditing and an execute audit on each sentinel DLL, then records which process loaded it. Event text is not saved. Apply stops if 4663 traffic is already over 64 MB/day unless Force is checked. Add a dependency by extending the catalog. Private DLL copies outside the catalog paths are not seen."
    ),
    Map(
        "Category", "Software updates — vuln catalog, M365, .NET, HPSA, Teams",
        "Name", "EOL dependency audit GPO",
        "Summary", "On a domain controller: downloads the audit script, stages it on NETLOGON, and creates the GPO. The task audits sentinel DLLs and keeps process hit counts.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/EolDependencyAudit",
        "Fetch", "Contents",
        "Path", "EolDependencyAudit",
        "Script", "Install-EolDependencyAuditGpo.ps1",
        "UaPrefix", "EolDependencyAuditGpo-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 600000,
        "Flags", "EolAuditGpo AlwaysNote",
        "Note", "Run elevated on the domain controller. Scan is a dry run. Apply downloads the audit script from GitHub, stages it on NETLOGON, and creates the GPO. Blank domain uses this DC. Put an OU DN in to pilot. Link at the domain root includes servers. The task stops if 4663 traffic is already over 64 MB/day.",
        "ClipboardNote", "NOTE: Run elevated on the domain controller. Apply downloads the audit script and creates the GPO. Pilot an OU before linking at the domain root. Servers are included. Event text is not saved."
    ),
    Map(
        "Category", "Software updates — vuln catalog, M365, .NET, HPSA, Teams",
        "Name", "HP Support Assistant",
        "Summary", "Win10: uninstall HPSA by default (vuln SoftPaqs). Win11: update. Scan-only available.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/HpSupportAssistantUpdate",
        "Fetch", "Contents",
        "Path", "HpSupportAssistantUpdate",
        "Script", "Update-HpSupportAssistant.ps1",
        "UaPrefix", "HpSupportAssistantUpdate-bootstrap",
        "UaVer", "1.2.1",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 600000,
        "Flags", "CheckOnly Uninstall Force NoExit"
    ),
    Map(
        "Category", "Software updates — vuln catalog, M365, .NET, HPSA, Teams",
        "Name", "HP Image Assistant",
        "Summary", "HP PCs only. Downloads HPIA, then installs SoftPaqs that can install unattended. Skips updates that need a person. Default does not reboot.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/HpImageAssistant",
        "Fetch", "Contents",
        "Path", "HpImageAssistant",
        "Script", "Invoke-HpImageAssistant.ps1",
        "UaPrefix", "HpImageAssistant-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 900000,
        "TimeoutUpdate", 7200000,
        "Flags", "CheckOnly Force AutoReboot NoExit",
        "Note", "Non-HP PCs exit without changes. Apply uses /InstallType:AutoInstallable (SSM only). A silent BIOS package can still restart on its own. Leave Auto reboot off to stop on exit 3010. 2-hour timeout. Reload launcher after pull."
    ),
    Map(
        "Category", "Software updates — vuln catalog, M365, .NET, HPSA, Teams",
        "Name", "Dell SupportAssist",
        "Summary", "Updates Dell SupportAssist when it is already installed. Does not install it, and does not touch OS Recovery, Remediation, or TechHub.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/DellSupportAssistUpdate",
        "Fetch", "Contents",
        "Path", "DellSupportAssistUpdate",
        "Script", "Update-DellSupportAssist.ps1",
        "UaPrefix", "DellSupportAssistUpdate-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 600000,
        "Flags", "CheckOnly Force NoExit"
    ),
    Map(
        "Category", "Software updates — vuln catalog, M365, .NET, HPSA, Teams",
        "Name", "Classic Teams remnants",
        "Summary", "Finds leftover Classic / per-user Teams after cleanup; can remediate remnants.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/TeamsClassicRemnantCheck",
        "Fetch", "Contents",
        "Path", "TeamsClassicRemnantCheck",
        "Script", "Test-ClassicTeamsRemnants.ps1",
        "UaPrefix", "TeamsClassicRemnantCheck-bootstrap",
        "UaVer", "1.2.0",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 600000,
        "Flags", "Detailed Remediate NoExit"
    ),
    Map(
        "Category", "Software updates — vuln catalog, M365, .NET, HPSA, Teams",
        "Name", "Windows Update (quality)",
        "Summary", "Pre-check then scan/install quality updates (CU, security, SSU). Default does not reboot.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/WindowsUpdate",
        "Fetch", "Contents",
        "Path", "WindowsUpdate",
        "Script", "Invoke-WindowsUpdate.ps1",
        "UaPrefix", "WindowsUpdate-bootstrap",
        "UaVer", "1.1.2",
        "TimeoutScan", 600000,
        "TimeoutUpdate", 3600000,
        "DefaultArgs", "-Quality",
        "Folder", "Windows Update",
        "Flags", "CheckOnly Force AutoReboot AllowServer NoExit",
        "Note", "Pre-check: disk, WinRE/recovery size, WU services/policy, pending reboot. Servers are skipped unless Allow Windows Server is checked and confirmed on Copy. Reload launcher after pull."
    ),
    Map(
        "Category", "Software updates — vuln catalog, M365, .NET, HPSA, Teams",
        "Folder", "Windows Update",
        "Name", "Windows Update (feature)",
        "Summary", "Pre-check then scan/install feature updates / enablement packages. Hours. Default does not reboot.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/WindowsUpdate",
        "Fetch", "Contents",
        "Path", "WindowsUpdate",
        "Script", "Invoke-WindowsUpdate.ps1",
        "UaPrefix", "WindowsUpdate-bootstrap",
        "UaVer", "1.1.2",
        "TimeoutScan", 600000,
        "TimeoutUpdate", 14400000,
        "DefaultArgs", "-Feature",
        "Flags", "CheckOnly Force AutoReboot AllowServer NoExit",
        "Note", "Backstage is fine. No desktop login. Driver updates install first. Auto reboot restarts only when Windows Update requires it; leave it off to stop instead. Servers are skipped unless Allow Windows Server is checked and confirmed on Copy. Do not start a second run while one is in progress. 4-hour timeout."
    ),
    Map(
        "Category", "Software updates — vuln catalog, M365, .NET, HPSA, Teams",
        "Folder", "Windows Update",
        "Name", "Windows Update (BIOS / firmware)",
        "Summary", "Pre-check then scan/install BIOS, UEFI, and system-firmware drivers only. Other drivers stay. Default does not reboot.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/WindowsUpdate",
        "Fetch", "Contents",
        "Path", "WindowsUpdate",
        "Script", "Invoke-WindowsUpdate.ps1",
        "UaPrefix", "WindowsUpdate-bootstrap",
        "UaVer", "1.1.2",
        "TimeoutScan", 600000,
        "TimeoutUpdate", 3600000,
        "DefaultArgs", "-Firmware",
        "Flags", "CheckOnly Force AutoReboot AllowServer NoExit",
        "Note", "Only firmware published to Windows Update. Leave Auto reboot off to stage the capsule and stop. The new BIOS does not load until the next restart. Servers are skipped unless Allow Windows Server is checked and confirmed on Copy. A BIOS that is not in Windows Update will not appear."
    ),
    ; --- ScreenConnect ---
    Map(
        "Category", "ScreenConnect — rogue IDs, GPO/MSI finder, temp cleanup",
        "Name", "Rogue instance IDs",
        "Summary", "Read-only. Prints each distinct ScreenConnect instance ID once and flags IDs that are not on the allow list.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/ScreenConnectRogueHunt",
        "Fetch", "Contents",
        "Path", "ScreenConnectRogueHunt",
        "Script", "Find-RogueScreenConnect.ps1",
        "UaPrefix", "ScreenConnectRogueHunt-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 300000,
        "Flags", "ScanOnly NoExit"
    ),
    Map(
        "Category", "ScreenConnect — rogue IDs, GPO/MSI finder, temp cleanup",
        "Name", "GPO / MSI finder",
        "Summary", "Finds GPOs that deploy ScreenConnect/Control and related MSI share paths (domain join helpful).",
        "DocsUrl", "https://github.com/monobrau/screenconnect-gpo-msi-finder",
        "Fetch", "Raw",
        "Owner", "monobrau",
        "Repo", "screenconnect-gpo-msi-finder",
        "Script", "Find-ScreenConnectGPO.ps1",
        "UaVer", "1.0.0",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 300000,
        "Flags", "ScanOnly Domain"
    ),
    Map(
        "Category", "Untested",
        "Name", "Deploy ScreenConnect client via GPO",
        "Summary", "Stage a ScreenConnect client MSI on NETLOGON and install it with a workstation Immediate Task. Skips PCs that already have the client service.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/ScreenConnectGpoDeploy",
        "Fetch", "Contents",
        "Path", "ScreenConnectGpoDeploy",
        "Script", "Install-ScreenConnectGPO.ps1",
        "UaPrefix", "ScreenConnectGpoDeploy-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 600000,
        "Flags", "ScreenConnectGpo AlwaysNote",
        "Note", "Run elevated as Domain Admin on the client DC or RSAT box. Use the MSI from your ScreenConnect instance. Dry-run first. Pilot an OU before a domain link.",
        "ClipboardNote", "NOTE: Run on a DC/RSAT box as Domain Admin. Dry-run first. The MSI path is on that machine. Workstations install at the next gpupdate when the client service is missing."
    ),
    Map(
        "Category", "ScreenConnect — rogue IDs, GPO/MSI finder, temp cleanup",
        "Name", "Temp file cleanup",
        "Summary", "Removes stale ScreenConnect temp leftovers; reports CVE-2026-84869 client version; cleans Huntress staging IOCs. Dry-run first.",
        "DocsUrl", "https://github.com/monobrau/screenconnect-temp-cleanup",
        "Fetch", "Raw",
        "Owner", "monobrau",
        "Repo", "screenconnect-temp-cleanup",
        "Script", "Remove-ScreenConnectTempCopies.ps1",
        "UaVer", "1.7.1",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 300000,
        "Flags", "Delete Force CacheBust"
    ),
    ; --- OEM cleanup ---
    Map(
        "Category", "OEM cleanup — HP Touchpoint, HP bloat, Dell SARemediation",
        "Folder", "HP",
        "Name", "HP Touchpoint Analytics",
        "Summary", "Detects/removes HP Touchpoint (Insights) Analytics service, tasks, and driver package. Dry-run first.",
        "DocsUrl", "https://github.com/monobrau/hp-touchpointanalytics-cleanup",
        "Fetch", "Raw",
        "Owner", "monobrau",
        "Repo", "hp-touchpointanalytics-cleanup",
        "Script", "Remove-HPTouchpointAnalytics.ps1",
        "UaVer", "1.2.0",
        "TimeoutScan", 120000,
        "TimeoutUpdate", 180000,
        "Flags", "Delete BlockReinstall RemoveSupportAssistant CacheBust"
    ),
    Map(
        "Category", "OEM cleanup — HP Touchpoint, HP bloat, Dell SARemediation",
        "Folder", "HP",
        "Name", "HP bloat / Wolf (mark05e gist)",
        "Summary", "Downloads mark05e's Remove-HPbloatware.ps1 from GitHub gist and runs it. Removes HP AppX + Wolf / Sure Click / Sure Run / HPSA AppX. No dry-run.",
        "Affects", "
(Join`r`n
No dry-run. One run removes:
HP AppX / bloat packages the gist targets
HP Wolf Security
Sure Click
Sure Run
HP Support Assistant AppX
)",
        "DocsUrl", "https://gist.github.com/mark05e/a79221b4245962a477a49eb281d97388",
        "Fetch", "IrmOutFile",
        "Url", "https://gist.githubusercontent.com/mark05e/a79221b4245962a477a49eb281d97388/raw/Remove-HPbloatware.ps1",
        "Script", "Remove-HPbloatware.ps1",
        "TempName", "Remove-HPbloatware.ps1",
        "UaVer", "1.0.0",
        "TimeoutScan", 600000,
        "TimeoutUpdate", 600000,
        "Flags", "RunOnly CacheBust RebootAdvisory AlwaysNote",
        "Note", "Third-party gist (mark05e). Runs immediately — no scan/dry-run. Prefer elevated PowerShell. Reboot after Wolf uninstall, then Defender repair if Huntress still shows Defender Disabled.",
        "ClipboardNote", "NOTE: mark05e HP bloat gist. No dry-run. Prefer elevated PowerShell. Reboot after. Then Defender repair if Wolf leftovers remain."
    ),
    Map(
        "Category", "OEM cleanup — HP Touchpoint, HP bloat, Dell SARemediation",
        "Folder", "Dell",
        "Name", "Dell SARemediation Backup (CW/SC)",
        "Summary", "Scan/remove ScreenConnect/ConnectWise-like files from Dell Snapshots\\Backup (S1 revoked-cert hygiene). Pair with SC temp cleanup. Does not uninstall Dell software.",
        "DocsUrl", "https://github.com/monobrau/dell-saremediation-cleanup",
        "Fetch", "Raw",
        "Owner", "monobrau",
        "Repo", "dell-saremediation-cleanup",
        "Script", "Remove-DellSARemediation.ps1",
        "UaVer", "1.4.4",
        "TimeoutScan", 3600000,
        "TimeoutUpdate", 3600000,
        "Flags", "Delete CacheBust RebootAdvisory BackupsOnlyDefault ClearAllBackupContent",
        "Note", "Always -BackupsOnly. v1.4.4: EnumerateFiles + skip any VersionInfo-identified non-CW PE; 64KB IndexOf peek. Banner must say v1.4.4. 60 min timeout. Huge trees: optional Clear all Backup content.",
        "ClipboardNote", "NOTE: Backup cleanup only. Must show v1.4.4. 60 min timeout. PENDING_REBOOT = reboot to finish. Then SC temp cleanup."
    ),
    Map(
        "Category", "OEM cleanup — HP Touchpoint, HP bloat, Dell SARemediation",
        "Folder", "Dell",
        "Name", "Dell TechHub",
        "Summary", "Scan or remove Dell TechHub, DTP, and SupportAssist. Common SentinelOne false positive on techhub.dll. Dell Update stays.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/DellTechHubCleanup",
        "Fetch", "Contents",
        "Path", "DellTechHubCleanup",
        "Script", "Remove-DellTechHub.ps1",
        "UaPrefix", "DellTechHubCleanup-bootstrap",
        "UaVer", "1.1.0",
        "TimeoutScan", 180000,
        "TimeoutUpdate", 300000,
        "Flags", "CheckOnly Remediate",
        "Note", "Prefer elevated PowerShell. Scan first. Apply removes TechHub, DTP, and SupportAssist. Dell Update stays."
    ),
    ; --- AV ---
    Map(
        "Category", "AV — Defender repair, Cylance/Webroot, McAfee remnants",
        "Name", "Windows Defender repair",
        "Summary", "Check or repair Defender RTP. Scan reports services, real-time protection, and tamper protection. Apply re-enables RTP and starts WinDefend / WdNisSvc.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/WindowsDefenderRepair",
        "Fetch", "Contents",
        "Path", "WindowsDefenderRepair",
        "Script", "Repair-WindowsDefender.ps1",
        "UaPrefix", "WindowsDefenderRepair-bootstrap",
        "UaVer", "1.0.9",
        "TimeoutScan", 120000,
        "TimeoutUpdate", 300000,
        "Flags", "CheckOnly ResetPlatform BackstageOnly",
        "Note", "PowerShell / SYSTEM only. Scan = services + RTP + tamper. Apply: enable disabled services, clear Disable* / PassiveMode policy, start WinDefend family, Set-MpPreference, retry once. Nuclear optional.",
        "ClipboardNote", "NOTE: Elevated PowerShell / SYSTEM only. Scan does not change anything. Apply is a full RTP repair (services + policy + preferences)."
    ),
    Map(
        "Category", "Untested",
        "Folder", "Webroot",
        "Name", "Webroot uninstall GPO",
        "Summary", "Create a GPO Immediate Task: optional silent WRSA /autouninstall, then leftover sweep (services, folders, registry, drivers). Run on the client DC or RSAT box.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/WebrootUninstallGpo",
        "Fetch", "Contents",
        "Path", "WebrootUninstallGpo",
        "Script", "New-WebrootUninstallGpo.ps1",
        "UaPrefix", "WebrootUninstallGpo-bootstrap",
        "UaVer", "1.1.0",
        "TimeoutScan", 180000,
        "TimeoutUpdate", 900000,
        "Flags", "WebrootUninstallGpo AlwaysNote",
        "Note", "Run elevated as Domain Admin on the client DC or RSAT box. Optional site key is written into SYSVOL (domain computers can read it). Immediate Task also sweeps leftovers. Prefer elevated PowerShell.",
        "ClipboardNote", "NOTE: Run on a DC/RSAT box as Domain Admin. Dry-run first. Apply updates the existing Uninstall Webroot GPO. On a test PC: gpupdate /force. Reboot if a driver is locked."
    ),
    Map(
        "Category", "AV — Defender repair, Cylance/Webroot, McAfee remnants",
        "Folder", "Webroot",
        "Name", "Webroot fleet status",
        "Summary", "From a DC/RSAT box: load AD computers (lastLogonTimestamp), query WRSVC via SCM, and check C$ in parallel (20 threads, 400ms ping) for WRSA.exe, WRData, and the GPO log.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/WebrootUninstallGpo",
        "Fetch", "Contents",
        "Path", "WebrootUninstallGpo",
        "Script", "Get-WebrootFleetStatus.ps1",
        "UaPrefix", "WebrootUninstallGpo-bootstrap",
        "UaVer", "1.1.4",
        "TimeoutScan", 900000,
        "TimeoutUpdate", 900000,
        "Flags", "ScanOnly Domain AlwaysNote",
        "Note", "Run on the DC or RSAT box as Domain Admin. Optional AD DNS name. CSV: C:\\Windows\\Temp\\Webroot-Fleet-Status.csv. LastLogon is AD lastLogonTimestamp (can lag 9-14 days). WrsvcStatus is SCM, not C$. Do not delete computer accounts from no-ping alone.",
        "ClipboardNote", "NOTE: Run on a DC/RSAT box. Writes C:\\Windows\\Temp\\Webroot-Fleet-Status.csv. Admin share access required."
    ),
    Map(
        "Category", "AV — Defender repair, Cylance/Webroot, McAfee remnants",
        "Name", "McAfee remnant cleanup",
        "Summary", "Detects leftover McAfee AppX + Program Files\McAfee; Remediate kills processes and removes remnants.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/McAfeeRemnantCleanup",
        "Fetch", "Contents",
        "Path", "McAfeeRemnantCleanup",
        "Script", "Remove-McAfeeRemnants.ps1",
        "UaPrefix", "McAfeeRemnantCleanup-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 180000,
        "TimeoutUpdate", 300000,
        "Flags", "CheckOnly Remediate",
        "Note", "Prefer elevated PowerShell. Scan first; Remediate removes AppX + folder."
    ),
    ; --- Agents ---
    Map(
        "Category", "Agents — SentinelOne, ConnectSecure, Huntress, Automate",
        "Name", "SentinelOne silent install",
        "Summary", "Paste site/group token → silent install for SC Commands or PowerShell. Optional download URL; else installer must already be on disk.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/SentinelOneInstall",
        "Fetch", "Contents",
        "Path", "SentinelOneInstall",
        "Script", "Install-SentinelOneAgent.ps1",
        "UaPrefix", "SentinelOneInstall-bootstrap",
        "UaVer", "1.0.1",
        "TimeoutScan", 900000,
        "TimeoutUpdate", 900000,
        "Flags", "RunOnly SentinelOneInstall AlwaysNote",
        "Note", "Token + path (and optional URL) below are not saved. Barracuda/XDR MSI download URLs (fileType=.msi) auto-use msiexec even if path ends in .exe. Prefer elevated PowerShell.",
        "ClipboardNote", "NOTE: Site token is embedded in this clipboard snippet only. Do not paste into tickets/git. Prefer elevated PowerShell. v1.0.1 auto-detects MSI downloads."
    ),
    Map(
        "Category", "Agents — SentinelOne, ConnectSecure, Huntress, Automate",
        "Name", "SentinelOne unload (passphrase)",
        "Summary", "Find SentinelCtl.exe and run unload -slam with the uninstall passphrase. The passphrase is not saved.",
        "Fetch", "Inline",
        "TimeoutScan", 180000,
        "TimeoutUpdate", 180000,
        "Flags", "RunOnly SentinelOneUnload AlwaysNote",
        "Note", "Passphrase below is not saved. Prefer elevated PowerShell. This unloads the agent with SentinelCtl unload -slam.",
        "ClipboardNote", "NOTE: Uninstall passphrase is embedded in this clipboard snippet only. Do not paste into tickets/git. Prefer elevated PowerShell."
    ),
    Map(
        "Category", "Agents — SentinelOne, ConnectSecure, Huntress, Automate",
        "Folder", "ConnectSecure",
        "Name", "ConnectSecure silent install",
        "Summary", "Silent install with -c/-e/-j/-i. Paste the portal install script; company, environment, and token are read from it and are not saved. Windows is the default. Mac, Linux, ARM, and ARM-32 copy the portal shell command.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/ConnectSecureInstall",
        "Fetch", "Contents",
        "Path", "ConnectSecureInstall",
        "Script", "Install-ConnectSecureAgent.ps1",
        "UaPrefix", "ConnectSecureInstall-bootstrap",
        "UaVer", "1.0.8",
        "TimeoutScan", 600000,
        "TimeoutUpdate", 600000,
        "Flags", "RunOnly ConnectSecure SkipIfRunning AlwaysNote",
        "Note", "Paste the official install script. Company ID (-c), environment ID (-e), and install token (-j) are filled from it and are not saved. Windows skips if CyberCNSAgent is Running. Mac, Linux, ARM, and ARM-32 are root shell commands.",
        "ClipboardNote", "NOTE: Install token is embedded in this clipboard snippet only. Do not paste into tickets/git. Prefer elevated PowerShell."
    ),
    Map(
        "Category", "Agents — SentinelOne, ConnectSecure, Huntress, Automate",
        "Folder", "ConnectSecure",
        "Name", "ConnectSecure agent repair + reinstall",
        "Summary", "Wipe leftover agent (uninstall.bat + service registry), then reinstall. Paste the same official install script; company, environment, and token are read from it and are not saved.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/ConnectSecureAgentRepair",
        "Fetch", "Contents",
        "Path", "ConnectSecureAgentRepair",
        "Script", "Repair-CyberCNSAgent.ps1",
        "UaPrefix", "ConnectSecureAgentRepair-bootstrap",
        "UaVer", "1.0.9",
        "TimeoutScan", 120000,
        "TimeoutUpdate", 600000,
        "Flags", "CheckOnly Remediate ConnectSecure SkipIfRunning AlwaysNote",
        "Note", "Default: skip if CyberCNSAgent is Running (fleet / scan-prep). Uncheck to always wipe + reinstall. Paste the official install script to fill company, environment, and token. Prefer PowerShell.",
        "ClipboardNote", "NOTE: Install token is embedded in this clipboard snippet only. Do not paste into tickets/git. Prefer elevated PowerShell."
    ),
    Map(
        "Category", "Agents — SentinelOne, ConnectSecure, Huntress, Automate",
        "Folder", "Huntress",
        "Name", "Huntress silent install",
        "Summary", "Download HuntressInstaller.exe and silent-install with /ACCT_KEY + /ORG_KEY /S. Account key is built in. Org key is per-client. Force = rip and replace. Uses official /ACCT_KEY (not /ACCOUNT_KEY).",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/HuntressInstall",
        "Fetch", "Contents",
        "Path", "HuntressInstall",
        "Script", "Install-HuntressAgent.ps1",
        "UaPrefix", "HuntressInstall-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 900000,
        "TimeoutUpdate", 900000,
        "Flags", "RunOnly HuntressInstall Force AutoReboot AlwaysNote",
        "Note", "Prefer elevated PowerShell. Cancel a scheduled reboot if needed.",
        "ClipboardNote", "NOTE: Account/org keys are embedded in this clipboard snippet. Do not paste into tickets/git. Prefer elevated PowerShell. Uses /ACCT_KEY=. PS2-safe inline download."
    ),
    Map(
        "Category", "Agents — SentinelOne, ConnectSecure, Huntress, Automate",
        "Folder", "Huntress",
        "Name", "Verify scheduled reboot",
        "Summary", "Read-only: host time, recent User32 1074 shutdown initiations, and HuntressSC task status.",
        "Fetch", "Inline",
        "Body", "Write-Output ('Host now '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')); Write-Output '--- Recent shutdown initiations (User32 1074) ---'; $logs=@(Get-EventLog -LogName System -Source User32 -Newest 40 -EA SilentlyContinue | Where-Object { $_.EventID -eq 1074 } | Select-Object -First 5); if(-not $logs){ Write-Output 'None found' } else { foreach($e in $logs){ Write-Output '---'; Write-Output ($e.TimeGenerated.ToString('yyyy-MM-dd HH:mm:ss')+' '+(($e.Message -replace '\r?\n',' | '))) } }; Write-Output '--- Huntress SC tasks ---'; foreach($tn in @('HuntressSC-Install','HuntressSC-Cleanup')){ Write-Output ('Query '+$tn); schtasks.exe /Query /TN $tn /FO LIST }",
        "TimeoutScan", 120000,
        "TimeoutUpdate", 120000,
        "Flags", "ScanOnly",
        "Note", "Read-only. Prefer elevated PowerShell."
    ),
    Map(
        "Category", "Agents — SentinelOne, ConnectSecure, Huntress, Automate",
        "Folder", "Huntress",
        "Name", "Cancel scheduled reboot",
        "Summary", "Aborts a pending shutdown.exe reboot countdown on the endpoint.",
        "Fetch", "Inline",
        "Body", "shutdown.exe /a",
        "TimeoutScan", 30000,
        "TimeoutUpdate", 30000,
        "Flags", "RunOnly",
        "Note", "Prefer elevated PowerShell if the reboot was armed as SYSTEM."
    ),
    Map(
        "Category", "Agents — SentinelOne, ConnectSecure, Huntress, Automate",
        "Folder", "Automate",
        "Name", "Automate agent uninstall",
        "Summary", "Scan or remove the ConnectWise Automate (LabTech) remote agent. ScreenConnect and the Automate Control Center stay. Probe agents need Force.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/AutomateUninstall",
        "Fetch", "Contents",
        "Path", "AutomateUninstall",
        "Script", "Uninstall-AutomateAgent.ps1",
        "UaPrefix", "AutomateUninstall-bootstrap",
        "UaVer", "1.1.0",
        "TimeoutScan", 180000,
        "TimeoutUpdate", 600000,
        "Flags", "CheckOnly Remediate Force AlwaysNote",
        "Note", "Prefer elevated PowerShell. Scan first. Apply removes LTService / LTSvc / the remote-agent ARP entry only. ScreenConnect stays. Force is required for a probe agent.",
        "ClipboardNote", "NOTE: Removes the Automate/LabTech agent only. ScreenConnect stays. Probe agents need Force. Reboot and run again if leftovers remain."
    ),
    Map(
        "Category", "Agents — SentinelOne, ConnectSecure, Huntress, Automate",
        "Folder", "Automate",
        "Name", "Automate agent reinstall",
        "Summary", "Reinstall the Automate agent from the server, location, and cached MSI already on this PC. No installer token. ScreenConnect stays. The new check-in gets a new agent ID in the same location.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/AutomateUninstall",
        "Fetch", "Contents",
        "Path", "AutomateUninstall",
        "Script", "Uninstall-AutomateAgent.ps1",
        "UaPrefix", "AutomateUninstall-bootstrap",
        "UaVer", "1.1.0",
        "TimeoutScan", 180000,
        "TimeoutUpdate", 900000,
        "Flags", "CheckOnly Reinstall Force AlwaysNote",
        "Note", "Prefer elevated PowerShell. Scan shows the server, location, and cached MSI. Apply copies that MSI (or downloads one from the recorded server), uninstalls, then installs with the same server and location. Nothing is removed if no installer can be found. Probe agents need Force.",
        "ClipboardNote", "NOTE: Reinstalls from this PC only. No token. New agent ID, same location. ScreenConnect stays. Probe agents need Force."
    ),
    Map(
        "Category", "Untested",
        "Name", "Automate GPO deploy",
        "Summary", "Download the location MSI+MST, bake the transform, stage on NETLOGON, and create a startup-script GPO. Run on the client DC or RSAT box.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/AutomateGpoDeploy",
        "Fetch", "Contents",
        "Path", "AutomateGpoDeploy",
        "Script", "Install-AutomateGPO.ps1",
        "UaPrefix", "AutomateGpoDeploy-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 900000,
        "TimeoutUpdate", 900000,
        "Flags", "AutomateGpo AlwaysNote",
        "Note", "Paste deployment ticket reads the clipboard and fills the server, location, client, and Windows MSI token. Nothing is saved. Run elevated as Domain Admin on the client DC or RSAT box, not on a workstation.",
        "ClipboardNote", "NOTE: Installer token is in this snippet. Do not paste into tickets/git. Run on a DC/RSAT box as Domain Admin. Dry-run first. Clients need a reboot after the GPO is linked."
    ),
    ; --- IR / forensics ---
    Map(
        "Category", "IR / forensics — event logs, Sysinternals, ADWCleaner",
        "Name", "HarkinsCollector (event logs)",
        "Summary", "IR event-log + artifact collector (ExceedingLife). Writes zip under C:\ForensicLogs. Needs elevation; Process Bypass for the downloaded script.",
        "DocsUrl", "https://github.com/ExceedingLife/HarkinsCollector",
        "Fetch", "IrmOutFile",
        "Owner", "ExceedingLife",
        "Repo", "HarkinsCollector",
        "Script", "HarkinsCollectorV2.ps1",
        "TempName", "HarkinsCollectorV2.ps1",
        "UaVer", "1.0.0",
        "TimeoutScan", 900000,
        "TimeoutUpdate", 900000,
        "Flags", "ScanOnly CacheBust AlwaysNote",
        "Note", "Collects EVTX + artifacts to C:\ForensicLogs\<host>_<stamp>.zip. Prefer elevated PowerShell. Long-running.",
        "ClipboardNote", "NOTE: Output zip under C:\ForensicLogs\. Prefer elevated session. Collection can take several minutes."
    ),
    Map(
        "Category", "IR / forensics — event logs, Sysinternals, ADWCleaner",
        "Name", "Forensic Investigator (Sysinternals)",
        "Summary", "Sysinternals + Harkins EVTX + all-user Downloads (Zone.ID) + PS history, hives, browser History, admins/RMM, Defender. C:\\SecurityReports.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/ForensicInvestigator",
        "Fetch", "IrmOutFile",
        "Owner", "monobrau",
        "Repo", "mytools",
        "Script", "ForensicInvestigator/Invoke-ForensicAnalysis.ps1",
        "TempName", "Invoke-ForensicAnalysis.ps1",
        "UaVer", "3.1.3",
        "TimeoutScan", 900000,
        "TimeoutUpdate", 900000,
        "Flags", "ScanOnly CacheBust AlwaysNote",
        "DefaultArgs", '-OutputPath "C:\SecurityReports"',
        "Note", "Sysinternals + all-user Downloads/Desktop + prefetch/tasks/users + EVTX. Reports → C:\SecurityReports. Elevate. VT off in this one-liner. Long-running.",
        "ClipboardNote", "NOTE: One zip plus .sha256 under C:\SecurityReports. Loose CSVs and EventLogs/Artifacts folders are deleted after the zip is written. Prefer elevated. No VirusTotal."
    ),
    Map(
        "Category", "IR / forensics — event logs, Sysinternals, ADWCleaner",
        "Name", "Malwarebytes ADWCleaner",
        "Summary", "Downloads ADWCleaner and runs a silent clean (/eula /clean /noreboot). Prefer elevated PowerShell.",
        "DocsUrl", "https://www.malwarebytes.com/adwcleaner",
        "Fetch", "DownloadExe",
        "Url", "https://downloads.malwarebytes.com/file/adwcleaner",
        "OutFile", "C:\Windows\Temp\adwcleaner.exe",
        "ExeArgList", '"/eula", "/clean", "/noreboot"',
        "TimeoutScan", 600000,
        "TimeoutUpdate", 600000,
        "Flags", "RunOnly AlwaysNote",
        "Note", "Silent adware/PUA clean. /noreboot — schedule reboot yourself if needed. EDR may alert on the download or run.",
        "ClipboardNote", "NOTE: ADWCleaner /eula /clean /noreboot. Does not reboot. Prefer elevated session. Check EDR alerts if the download is blocked."
    ),
    Map(
        "Category", "IR / forensics — event logs, Sysinternals, ADWCleaner",
        "Name", "PUP remnant cleanup",
        "Summary", "Dry-run the catalog (Ask Toolbar, MediaArena, AppSuite PDF, Wave, OneLaunch, fake PDF installers, Browser Assistant) and report what is on the host. Clean up deletes all matched remnants. Chromium/Firefox prefs are reported only. Family dropdown limits to one catalog id.",
        "Affects", "
(Join`r`n
Scan reports matches. Remove deletes folders, tasks, services, uninstall entries, and leftover installers. Browser preference files are reported only.
Ask Toolbar — Ask.com / Ask Toolbar / APN
MediaArena — PdfPower, PdfMagic, Blazer Browser, and related converters
AppSuite PDF — AppSuite-PDF, PDF Editor, ManualFinder (not Foxit or Adobe)
Wave Browser
OneLaunch / OneStart / OneBUpdate
Fake PDF converters — ConvertMate, Easy2Convert, UpdateRetriever, PDFConvertSetup
Browser Assistant — Blaze Media helper, updater, BAv MSI
)",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/PupRemnantCleanup",
        "Fetch", "Contents",
        "Path", "PupRemnantCleanup",
        "Script", "Invoke-PupRemnantCleanup.ps1",
        "UaPrefix", "PupRemnantCleanup-bootstrap",
        "UaVer", "1.3.2",
        "TimeoutScan", 180000,
        "TimeoutUpdate", 300000,
        "Flags", "CheckOnly Remediate ProductList NoExit",
        "ProductList", "All on host|AskToolbar|MediaArena|AppSuitePdf|WaveBrowser|OneLaunch|FakePdfConverter|BrowserAssistant",
        "Note", "Prefer elevated PowerShell. Scan first. Family list is the catalog. All on host = every family that is actually present.",
        "ClipboardNote", "NOTE: Family dropdown — All on host scans the whole catalog. Pick one id to limit. Scan is dry-run. Remove deletes folders/tasks/registry; browser prefs stay report-only."
    ),
    Map(
        "Category", "IR / forensics — event logs, Sysinternals, ADWCleaner",
        "Name", "PUP install block",
        "Summary", "Stops the catalog installers from running and shows the person a warning. Uses the same families as PUP remnant cleanup. Re-apply after a family is added.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/PupRemnantCleanup",
        "Fetch", "Contents",
        "Path", "PupRemnantCleanup",
        "Script", "Install-PupInstallBlock.ps1",
        "UaPrefix", "PupInstallBlock-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 180000,
        "TimeoutUpdate", 180000,
        "Flags", "PupBlock ProductList NoExit",
        "ProductList", "All catalog|AskToolbar|MediaArena|AppSuitePdf|WaveBrowser|OneLaunch|FakePdfConverter|BrowserAssistant",
        "Note", "Prefer elevated PowerShell. Scan lists the program names and changes nothing. Apply blocks those .exe names. The person who opens one sees a warning and the program does not start. Re-apply after adding a family to the cleanup catalog. A renamed installer is not blocked. EDR may alert on the block entries.",
        "ClipboardNote", "NOTE: Same catalog as PUP remnant cleanup. Scan lists names only. Apply blocks them and shows a warning. Re-apply after a new family is added. Renamed installers are not blocked."
    ),
    ; --- M365 / Exchange ---
    Map(
        "Category", "M365 / Exchange — admin PC (Inky rules, vendor apps)",
        "Name", "Inky / IPW transport rules",
        "Summary", "List or remove EXO transport rules matching IPW|Inky|IOC Strip. Requires Connect-ExchangeOnline first (admin PC, not endpoint SC).",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/InkyTransportRuleCleanup",
        "Fetch", "Contents",
        "Path", "InkyTransportRuleCleanup",
        "Script", "Remove-InkyTransportRules.ps1",
        "UaPrefix", "InkyTransportRuleCleanup-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 300000,
        "Flags", "CheckOnly Delete AlwaysNote",
        "Note", "Run after Connect-ExchangeOnline on an admin workstation. Scan lists; Delete removes with no Read-Host prompt.",
        "ClipboardNote", "NOTE: Requires Connect-ExchangeOnline in this session. Delete has no interactive confirm — Scan first."
    ),
    Map(
        "Category", "M365 / Exchange — admin PC (Inky rules, vendor apps)",
        "Name", "INKY / usecure / Skout enterprise apps",
        "Summary", "Find and delete those vendor enterprise apps in the signed-in Entra tenant. Matched by name, because the app id differs per tenant.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/EntraVendorAppRemoval",
        "Fetch", "Contents",
        "Path", "EntraVendorAppRemoval",
        "Script", "Remove-VendorEnterpriseApps.ps1",
        "UaPrefix", "EntraVendorAppRemoval-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 600000,
        "Flags", "CheckOnly Delete AlwaysNote BackstageOnly",
        "Note", "Paste the PowerShell one-liner into Backstage or a local window on this PC, not a client session. Scan lists matches. Apply opens the picker; type DELETE to remove the ones you select. Needs Microsoft.Graph and Application Administrator.",
        "ClipboardNote", "NOTE: Admin PC Backstage PowerShell. Scan lists only. Apply opens the picker. Type DELETE to remove. App ids differ per tenant."
    ),
    Map(
        "Category", "M365 / Exchange — admin PC (Inky rules, vendor apps)",
        "Name", "Entra users, service accounts, BitLocker",
        "Summary", "Export the Entra authorized-user list, likely service accounts, and Intune BitLocker status per workstation. Saves under OneDrive.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/EntraIntuneEvidence",
        "Fetch", "Contents",
        "Path", "EntraIntuneEvidence",
        "Script", "Get-EntraIntuneEvidence.ps1",
        "UaPrefix", "EntraIntuneEvidence-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 600000,
        "Flags", "RunOnly AlwaysNote BackstageOnly",
        "Note", "Paste the PowerShell one-liner into Backstage or a local window on this PC, not a client session. Signs into Microsoft Graph and writes AuthorizedUsers.csv, ServiceAccounts.csv, and BitLocker-Workstations.csv under OneDrive\EntraIntuneEvidence. Review the service-account file before you send it.",
        "ClipboardNote", "NOTE: Admin PC Backstage PowerShell. Exports authorized users, likely service accounts, and BitLocker per workstation to OneDrive. Review ServiceAccounts.csv before sending."
    ),
    ; --- Untested (move here until validated) ---
    Map(
        "Category", "Untested",
        "Name", "PHP use",
        "Summary", "Read-only, for workstations and Windows Server. Reports whether PHP is running or set up to run (IIS, Apache, nginx, a service, or a scheduled task), and whether php.exe is installed. Servers are not skipped.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/PhpUse",
        "Fetch", "Contents",
        "Path", "PhpUse",
        "Script", "Get-PhpUse.ps1",
        "UaPrefix", "PhpUse-bootstrap",
        "UaVer", "1.0.1",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 300000,
        "Flags", "ScanOnly NoExit AlwaysNote",
        "Note", "Read-only on workstations and Windows Server. Servers are not skipped. USING PHP means a process, IIS, Apache, nginx, a service, or a scheduled task is set up to run it. INSTALLED means the program was found. IIS site folders outside inetpub are included. A copy in an unusual folder with nothing pointing at it is not listed.",
        "ClipboardNote", "NOTE: Read-only. USING PHP means it is running or set up to run. INSTALLED means the program files were found. The Note line says what was not searched."
    ),
    Map(
        "Category", "Untested",
        "Name", "Outlook disable local cache",
        "Summary", "Force classic Outlook online-only for every profile on a shared lab PC, including the Default profile. Clean up also deletes .ost and .nst files. PST archives stay.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/OutlookDisableCache",
        "Fetch", "Contents",
        "Path", "OutlookDisableCache",
        "Script", "Disable-OutlookLocalCache.ps1",
        "UaPrefix", "OutlookDisableCache-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 600000,
        "Flags", "CheckOnly Remediate NoExit",
        "Note", "Prefer elevated PowerShell. Scan lists each profile and the cache size. Clean up writes the online-mode policy and deletes .ost/.nst. Classic Outlook closes first. A domain GPO that turns Cached Exchange Mode back on will overwrite this.",
        "ClipboardNote", "NOTE: Scan is dry-run. Clean up forces online mode and deletes .ost/.nst. PST archives are kept. Run elevated."
    ),
    Map(
        "Category", "Untested",
        "Name", "WinVerifyTrust padding check",
        "Summary", "Enable the CVE-2013-3900 Authenticode padding check. Writes EnableCertPaddingCheck=1 in the 64-bit and 32-bit registry views. Does not restart the PC.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/WinVerifyTrustPadding",
        "Fetch", "Contents",
        "Path", "WinVerifyTrustPadding",
        "Script", "Enable-WinVerifyTrustPaddingCheck.ps1",
        "UaPrefix", "WinVerifyTrustPadding-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 120000,
        "TimeoutUpdate", 120000,
        "Flags", "CheckOnly Remediate NoExit",
        "Note", "Prefer elevated PowerShell. Scan reports both registry views. Apply writes DWORD 1 where it is missing. Restart before the check takes effect. Signed installers with extra signature data are treated as unsigned after that restart.",
        "ClipboardNote", "NOTE: Scan is dry-run. Apply sets EnableCertPaddingCheck. Does not reboot. Restart before the stricter check is active."
    ),
    Map(
        "Category", "Untested",
        "Name", "Speculative Store Bypass",
        "Summary", "Enable the Windows CVE-2018-3639 SSBD mitigation by OR-ing bit 8 into FeatureSettingsOverride. Other mitigation bits stay. Does not install updates or reboot.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/SpeculativeStoreBypass",
        "Fetch", "Contents",
        "Path", "SpeculativeStoreBypass",
        "Script", "Enable-SpeculativeStoreBypass.ps1",
        "UaPrefix", "SpeculativeStoreBypass-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 120000,
        "TimeoutUpdate", 120000,
        "Flags", "CheckOnly Remediate NoExit",
        "Note", "Prefer elevated PowerShell. Scan reports the registry bits and a microcode hint. Apply does not install Windows updates or OEM firmware, and it does not reboot. A finding that still says Updates Required needs the Windows Update quality tool and the PC maker firmware.",
        "ClipboardNote", "NOTE: Scan is dry-run. Apply sets the SSBD registry bits only. Does not install updates or reboot."
    ),
    Map(
        "Category", "Untested",
        "Name", "Disable PowerShell 2.0",
        "Summary", "Disable the Windows PowerShell 2.0 optional features (MicrosoftWindowsPowerShellV2 and V2Root). Apply only. Does not restart the PC.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/PowerShellV2Disable",
        "Fetch", "Contents",
        "Path", "PowerShellV2Disable",
        "Script", "Disable-PowerShellV2.ps1",
        "UaPrefix", "PowerShellV2Disable-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 300000,
        "Flags", "RunOnly NoExit AlwaysNote",
        "Note", "Prefer elevated PowerShell. No scan/dry-run. DISM disable, no reboot. Already disabled or missing counts as done. Restart later if a scanner finding stays open.",
        "ClipboardNote", "NOTE: Disables PowerShell 2.0 optional features. Does not reboot. Restart later if the scanner still shows the finding. Prefer elevated PowerShell."
    ),
    Map(
        "Category", "Untested",
        "Name", "Cylance / Webroot cleanup",
        "Summary", "Offboarding / leftover cleanup after migrating off Cylance or Webroot (OpenText CEP). Uninstall + residual sweep. Dry-run first; elevated delete. Prefer PowerShell/SYSTEM.",
        "DocsUrl", "https://github.com/monobrau/windows-av-cleanup",
        "Fetch", "Contents",
        "Owner", "monobrau",
        "Repo", "windows-av-cleanup",
        "Script", "Remove-Antivirus.ps1",
        "UaPrefix", "windows-av-cleanup-bootstrap",
        "UaVer", "1.1.1",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 300000,
        "Flags", "Delete Force Vendor",
        "Note", "Use when offboarding the vendor or cleaning remnants after cutover — not for managing an active AV install. Prefer deactivate in the vendor console first. Delete needs elevation (PowerShell/SYSTEM). Password/keycode only if Vendor is Cylance or Webroot (not All). Reboot if drivers stay locked."
    ),
    Map(
        "Category", "Untested",
        "Folder", "RemoteOps",
        "Name", "RemoteOps enroll (token)",
        "Summary", "Connect the client host to the RemoteOps WireGuard tunnel with a one-time token from the portal. The portal then shows its Peer IP.",
        "Fetch", "Inline",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 300000,
        "Flags", "RunOnly RemoteOpsEnroll AlwaysNote",
        "Note", "Issue a token on the RemoteOps portal first. It is single-use, valid 1 hour, and not saved here. Set Portal= under [RemoteOps] in local-defaults.ini to prefill the URL.",
        "ClipboardNote", "NOTE: RemoteOps token is single-use and only in this snippet. Do not paste it into tickets or git."
    ),
    Map(
        "Category", "Untested",
        "Folder", "RemoteOps",
        "Name", "RemoteOps remove",
        "Summary", "Disconnect the host from RemoteOps: stop the transport, delete the peer, and remove WireGuard and the firewall exceptions when no other tunnels exist.",
        "Fetch", "Inline",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 300000,
        "Flags", "RunOnly RemoteOpsRemove",
        "Note", "Runs remoteops-remove.ps1 from the portal. If the portal is unreachable, it runs the copy in C:\ProgramData\RemoteOps instead."
    ),
    Map(
        "Category", "Untested",
        "Folder", "RemoteOps",
        "Name", "Active Directory review (over tunnel)",
        "Summary", "Read-only AD review of an enrolled host's domain from this PC over WinRM: DCs, privileged groups, stale and never-expiring accounts, krbtgt age, trusts.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/ActiveDirectoryReview",
        "Fetch", "Contents",
        "Path", "ActiveDirectoryReview",
        "Script", "Invoke-ADReview.ps1",
        "UaPrefix", "ActiveDirectoryReview-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 600000,
        "TimeoutUpdate", 600000,
        "Flags", "RunOnly BackstageOnly AdReview",
        "Note", "Paste into an elevated PowerShell window on this PC, not a client session. Enroll the host in RemoteOps first. Prompts for DOMAIN\user. Writes CSVs and Summary.txt under Documents\ADReview."
    ),
    ; --- Client-specific campaigns ---
    Map(
        "Category", "Client-specific",
        "Client", "Naviant",
        "Name", "Acrobat XI removal (EOL)",
        "Summary", "Scan or uninstall Adobe Acrobat XI (11.x). Reports Foxit Reader/Editor. Skips uninstall if Foxit is missing unless Force.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/ClientSpecific/Naviant/AcrobatXiRemoval",
        "Fetch", "Contents",
        "Path", "ClientSpecific/Naviant/AcrobatXiRemoval",
        "Script", "Remove-AcrobatXi.ps1",
        "UaPrefix", "AcrobatXiRemoval-bootstrap",
        "UaVer", "1.0.1",
        "TimeoutScan", 180000,
        "TimeoutUpdate", 1200000,
        "Flags", "CheckOnly Remediate Force AlwaysNote",
        "Note", "Client campaign. Scan first. Apply uninstalls XI only (10+ min). Waits for MSI mutex; retries 1618. Force = uninstall even if Foxit is missing. Prefer elevated PowerShell. Do not rerun or Force while msiexec is running.",
        "ClipboardNote", "NOTE: Scan first. Uninstall can take 10+ minutes — do not rerun or Force while it runs. Default skips hosts with no Foxit. Prefer elevated PowerShell. Log: C:\\Windows\\Temp\\AcrobatXi-uninstall.log"
    ),
    Map(
        "Category", "Power — plugged-in sleep, hibernate, Fast Startup",
        "Name", "No sleep or hibernate while plugged in",
        "Summary", "Sets the active power plan so a plugged-in PC does not sleep or hibernate on idle. Battery, display, lid, and power buttons stay as they are.",
        "Fetch", "Inline",
        "ScanBody", "$scheme=(powercfg /getactivescheme) -join ' '; Write-Output $scheme; foreach($a in @(@('STANDBYIDLE','Sleep'),@('HIBERNATEIDLE','Hibernate'))){ $raw=powercfg /q SCHEME_CURRENT SUB_SLEEP $a[0] 2>&1 | Out-String; $m=[regex]::Match($raw,'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)'); if(-not $m.Success){ Write-Output ($a[1]+' on AC: not in this plan') } else { $n=[Convert]::ToInt32($m.Groups[1].Value,16); Write-Output ($a[1]+' on AC: '+$(if($n -eq 0){'Never'}else{[string]$n+' min'})) } }; Write-Output 'No changes. Battery, display, lid, and power buttons were not read for a change.'",
        "ApplyBody", "foreach($pair in @(@('standby-timeout-ac','Sleep'),@('hibernate-timeout-ac','Hibernate'))){ $err=powercfg /change $pair[0] 0 2>&1 | Out-String; if($LASTEXITCODE -ne 0){ Write-Output ($pair[1]+' on AC was not changed: '+$err.Trim()) } }; $scheme=(powercfg /getactivescheme) -join ' '; Write-Output $scheme; foreach($a in @(@('STANDBYIDLE','Sleep'),@('HIBERNATEIDLE','Hibernate'))){ $raw=powercfg /q SCHEME_CURRENT SUB_SLEEP $a[0] 2>&1 | Out-String; $m=[regex]::Match($raw,'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)'); if(-not $m.Success){ Write-Output ($a[1]+' on AC: not in this plan') } else { $n=[Convert]::ToInt32($m.Groups[1].Value,16); Write-Output ($a[1]+' on AC: '+$(if($n -eq 0){'Never'}else{[string]$n+' min'})) } }; Write-Output 'Battery, display, lid, and power buttons were left alone.'",
        "TimeoutScan", 60000,
        "TimeoutUpdate", 60000,
        "Flags", "PowerIdle AlwaysNote",
        "Note", "Prefer elevated PowerShell. Show first. Apply changes only the active plan: plugged-in sleep and hibernate idle become Never. A domain power policy can put the timeouts back.",
        "ClipboardNote", "NOTE: Active plan only. Plugged-in sleep and hibernate idle set to Never. Battery, display, lid, and buttons are unchanged. A domain power policy can overwrite this."
    ),
    Map(
        "Category", "Power — plugged-in sleep, hibernate, Fast Startup",
        "Name", "Turn Fast Startup off",
        "Summary", "Sets HiberbootEnabled to 0 so shutdown does a full shutdown. Does not turn hibernate off and does not remove the hibernation file.",
        "Fetch", "Inline",
        "ScanBody", "$p='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; $v=(Get-ItemProperty -LiteralPath $p -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled; if($null -eq $v){ Write-Output 'HiberbootEnabled: missing (Fast Startup off)' } elseif([int]$v -eq 0){ Write-Output 'HiberbootEnabled: 0 (Fast Startup off)' } else { Write-Output ('HiberbootEnabled: '+[string]([int]$v)+' (Fast Startup on)') }; Write-Output 'Hibernate was not turned off.'",
        "ApplyBody", "$p='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; if(-not (Test-Path -LiteralPath $p)){ New-Item -Path $p -Force | Out-Null }; New-ItemProperty -LiteralPath $p -Name HiberbootEnabled -PropertyType DWord -Value 0 -Force | Out-Null; $v=[int](Get-ItemProperty -LiteralPath $p -Name HiberbootEnabled).HiberbootEnabled; Write-Output ('HiberbootEnabled: '+[string]$v+' (Fast Startup '+$(if($v -eq 0){'off'}else{'still on'})+')'); Write-Output 'Takes effect on the next shutdown. Hibernate was not turned off.'",
        "TimeoutScan", 60000,
        "TimeoutUpdate", 60000,
        "Flags", "FastStartup AlwaysNote",
        "Note", "Prefer elevated PowerShell. Show first. Apply writes HiberbootEnabled 0 only. Hibernate stays available. The next shutdown is a full shutdown. A domain policy can turn Fast Startup back on.",
        "ClipboardNote", "NOTE: HiberbootEnabled set to 0. Hibernate stays available. Takes effect on the next shutdown. A domain policy can turn Fast Startup back on."
    ),
]

gToolByNode := Map()   ; TreeView item id -> Tools index (1-based)
gLastToolIndex := 1     ; last real tool selection (survives category collapse)
gFlowKeys := []         ; control stack order for ReflowGui
gPupFamilySource := ""  ; last ProductList loaded into the PUP family dropdown

; --- tray / identity ---
; Keep the default AHK v2 tray icon + menu (includes Reload Script / Edit / Exit).
; Only add an Open item; do not Delete() the stock menu or override the icon.
DetectHiddenWindows(true)
try WinSetTitle(TrayLabel, "ahk_class AutoHotkey ahk_pid " ProcessExist())
A_IconTip := TrayLabel
A_TrayMenu.Insert("1&", "Open " AppName, (*) => ShowGui())
A_TrayMenu.Default := "Open " AppName
A_TrayMenu.ClickCount := 1

Hotkey(HotkeySpec, (*) => ToggleGui())

gGui := 0
gCtrls := Map()
for arg in A_Args {
    if (arg = "/show") {
        ShowGui()
        break
    }
}

; Restart this script in-place (avoids a second tray icon from a naive Reload + leftover instance).
; /show reopens the window; a cold start stays in the tray.
ReloadScToolLauncher(*) {
    Run(Format('"{1}" /restart "{2}" /show', A_AhkPath, A_ScriptFullPath))
    ExitApp
}

ToggleGui(*) {
    global gGui
    if gGui && WinExist("ahk_id " gGui.Hwnd) {
        if WinActive("ahk_id " gGui.Hwnd)
            gGui.Hide()
        else {
            gGui.Show()
            WinActivate("ahk_id " gGui.Hwnd)
        }
        return
    }
    ShowGui()
}

PopulateToolTree(tv) {
    global Tools, CategoryOrder, gToolByNode, gLastToolIndex
    gToolByNode := Map()
    catNodes := Map()
    folderNodes := Map()
    parentByName := Map()
    helpLeaf := 0
    firstCatNode := 0
    ; Help is a root leaf so first open shows the intro with every category collapsed.
    for i, t in Tools {
        if !ToolHasFlag(t, "Help")
            continue
        node := tv.Add(t["Name"], 0)
        gToolByNode[node] := i
        parentByName[t["Name"]] := node
        helpLeaf := node
    }
    for cat in CategoryOrder
        catNodes[cat] := tv.Add(cat, 0, "Bold")

    for i, t in Tools {
        if ToolHasFlag(t, "Help")
            continue
        cat := ToolGet(t, "Category", "Other")
        if !catNodes.Has(cat)
            catNodes[cat] := tv.Add(cat, 0, "Bold")
        parent := catNodes[cat]
        folder := ToolGet(t, "Folder", "")
        if (folder = "")
            folder := ToolGet(t, "Client", "")
        if (folder != "") {
            fk := cat "|" folder
            if !folderNodes.Has(fk)
                folderNodes[fk] := tv.Add(folder, parent)
            parent := folderNodes[fk]
        }
        parentName := ToolGet(t, "Parent", "")
        if (parentName != "" && parentByName.Has(parentName))
            parent := parentByName[parentName]
        node := tv.Add(t["Name"], parent)
        gToolByNode[node] := i
        parentByName[t["Name"]] := node
        if !firstCatNode && catNodes.Has(cat)
            firstCatNode := catNodes[cat]
    }
    gLastToolIndex := 1
    if helpLeaf
        tv.Modify(helpLeaf, "Select Vis")
    else if firstCatNode
        tv.Modify(firstCatNode, "Select")
}

; Only refresh when a tool leaf is selected. Category collapse moves selection to the
; parent header — do not auto-select a child (that re-expands the group).
OnToolTreeSelect(*) {
    global gCtrls, gToolByNode, gLastToolIndex
    node := gCtrls["ToolTree"].GetSelection()
    if !(node && gToolByNode.Has(node))
        return
    idx := gToolByNode[node]
    if (idx = gLastToolIndex)
        return
    gLastToolIndex := idx
    if gCtrls.Has("AllowServer")
        gCtrls["AllowServer"].Value := 0
    RefreshOptionEnable()
}

ShowGui(*) {
    global gGui, gCtrls, Tools, gFlowKeys, UiContentW, UiTreeW, UiTreeRows, TrayLabel, HotkeyLabel

    if gGui {
        try gGui.Destroy()
        gGui := 0
    }

    ; OwnDialogs keeps the "needs company/token" box in front of this always-on-top window.
    gGui := Gui("+AlwaysOnTop -MinimizeBox +OwnDialogs", TrayLabel)
    gGui.OnEvent("Close", (*) => gGui.Hide())
    gGui.OnEvent("Escape", (*) => gGui.Hide())
    gGui.SetFont("s9", "Segoe UI")
    gGui.MarginX := 12
    gGui.MarginY := 10

    ; Left column: tool tree. Right column: options. Positions set in ReflowGui.
    gCtrls["LblTools"] := gGui.Add("Text", "w" UiTreeW, "Tool (expand a category)")
    tv := gGui.Add("TreeView", "w" UiTreeW " r" UiTreeRows " vToolTree")
    tv.OnEvent("ItemSelect", OnToolTreeSelect)
    gCtrls["ToolTree"] := tv
    PopulateToolTree(tv)

    gCtrls["LblAbout"] := gGui.Add("Text", "Section", "About this tool")
    gCtrls["Summary"] := gGui.Add("Text", "w" UiContentW " h52 vToolSummary", "")
    gCtrls["HelpBody"] := gGui.Add("Edit", "w" UiContentW " r16 ReadOnly vHelpBody", HelpIntroText)
    gCtrls["BtnDocs"] := gGui.Add("Button", "w200", "Open docs in browser")
    gCtrls["BtnDocs"].OnEvent("Click", (*) => OpenSelectedToolDocs())
    gCtrls["BtnAffects"] := gGui.Add("Button", "w200", "What this affects")
    gCtrls["BtnAffects"].OnEvent("Click", (*) => ShowAffectsPopup())

    gCtrls["LblMode"] := gGui.Add("Text", "Section", "Mode")
    ; Group: first radio in each set — required so Mode and Paste format stay separate
    ; when intervening option checkboxes are hidden (otherwise Win32 merges the radios).
    gCtrls["ModeScan"] := gGui.Add("Radio", "Group Checked vModeScan", "Scan only (no changes)")
    gCtrls["ModeUpdate"] := gGui.Add("Radio", "vModeUpdate", "Apply changes (update / remove)")
    gCtrls["ModeScan"].OnEvent("Click", (*) => RefreshOptionEnable())
    gCtrls["ModeUpdate"].OnEvent("Click", (*) => RefreshOptionEnable())

    gCtrls["LblOptions"] := gGui.Add("Text", "Section", "Options")
    gCtrls["Force"] := gGui.Add("Checkbox", "vOptForce", "Force (skip soft guards / re-run)")
    gCtrls["Force"].OnEvent("Click", OnForceOptClick)
    gCtrls["ForceAppShutdown"] := gGui.Add("Checkbox", "vOptForceAppShutdown", "Close Office apps (Word, Excel, Outlook, …)")
    gCtrls["IncludeBrowsers"] := gGui.Add("Checkbox", "vOptIncludeBrowsers", "Include browsers (Chrome, Edge, Firefox)")
    gCtrls["Uninstall"] := gGui.Add("Checkbox", "vOptUninstall", "Uninstall HP Support Assistant")
    gCtrls["Detailed"] := gGui.Add("Checkbox", "vOptDetailed", "Detailed Teams check (shortcuts count as fail)")
    gCtrls["BlockReinstall"] := gGui.Add("Checkbox", "vOptBlockReinstall", "Block Windows Update reinstall")
    gCtrls["RemoveSupportAssistant"] := gGui.Add("Checkbox", "vOptRemoveSupportAssistant", "Also remove HP Support Assistant")
    gCtrls["ClearAllBackupContent"] := gGui.Add("Checkbox", "vOptClearAllBackupContent", "Clear entire Backup folder contents (not just CW/SC)")
    gCtrls["ClearAllBackupContent"].OnEvent("Click", (*) => RefreshOptionEnable())
    gCtrls["SkipIfRunning"] := gGui.Add("Checkbox", "Checked vOptSkipIfRunning", "Only if agent is not running (fleet / scan-prep)")
    gCtrls["ResetPlatform"] := gGui.Add("Checkbox", "vOptResetPlatform", "Nuclear: MpCmdRun -ResetPlatform")
    gCtrls["AutoReboot"] := gGui.Add("Checkbox", "vOptAutoReboot", "Auto reboot when required")
    gCtrls["AutoReboot"].OnEvent("Click", OnAutoRebootOptClick)
    gCtrls["AllowServer"] := gGui.Add("Checkbox", "vOptAllowServer", "Allow Windows Server (asks before copy)")
    gCtrls["LblHuntressRebootAt"] := gGui.Add("Text", "Section", "Reboot at (endpoint local time)")
    gCtrls["HuntressRebootAt"] := gGui.Add("DateTime", "w220 vHuntressRebootAt", "yyyy-MM-dd HH:mm")
    gCtrls["HuntressRebootAt"].Value := DefaultHuntressRebootAt()

    gCtrls["LblProduct"] := gGui.Add("Text", "Section", "Product filter (e.g. DotNet, ShareX)")
    gCtrls["Product"] := gGui.Add("Edit", "w" UiContentW " vProduct", "")
    gCtrls["LblPupFamily"] := gGui.Add("Text", "Section", "PUP family")
    gCtrls["PupFamily"] := gGui.Add("DropDownList", "w" UiContentW " vPupFamily", ["All on host"])

    gCtrls["LblVendor"] := gGui.Add("Text", "Section", "Antivirus vendor")
    gCtrls["Vendor"] := gGui.Add("DropDownList", "w160 vVendor", ["All", "Cylance", "Webroot"])
    gCtrls["Vendor"].Choose(1)
    gCtrls["LblAvSecret"] := gGui.Add("Text", , "Password/keycode (only if Vendor is Cylance or Webroot — not All)")
    gCtrls["AvSecret"] := gGui.Add("Edit", "w" UiContentW " vAvSecret", "")

    gCtrls["LblDomainController"] := gGui.Add("Text", "Section", "Domain controller (optional)")
    gCtrls["DomainController"] := gGui.Add("Edit", "w" UiContentW " vDomainController", "")
    gCtrls["LblDomain"] := gGui.Add("Text", , "AD domain (optional)")
    gCtrls["Domain"] := gGui.Add("Edit", "w" UiContentW " vDomain", "")

    gCtrls["LblCsOs"] := gGui.Add("Text", "Section", "Operating system")
    gCtrls["CsOs"] := gGui.Add("DropDownList", "w" UiContentW " vCsOs", ["Windows", "Mac", "Linux", "ARM", "ARM-32"])
    gCtrls["CsOs"].Choose(1)
    gCtrls["CsOs"].OnEvent("Change", (*) => RefreshOptionEnable())

    gCtrls["LblCsScript"] := gGui.Add("Text", "Section", "Paste the official install script (reads -c, -e, and -j)")
    gCtrls["CsInstallScript"] := gGui.Add("Edit", "w" UiContentW " r4 WantReturn vCsInstallScript", "")
    gCtrls["CsInstallScript"].OnEvent("Change", (*) => ApplyConnectSecureInstallScript(false))
    gCtrls["LblCsCompany"] := gGui.Add("Text", , "ConnectSecure company ID (-c)")
    gCtrls["CsCompanyId"] := gGui.Add("Edit", "w" UiContentW " vCsCompanyId", "")
    gCtrls["LblCsEnv"] := gGui.Add("Text", , "ConnectSecure environment ID (-e)")
    gCtrls["CsEnvironmentId"] := gGui.Add("Edit", "w" UiContentW " vCsEnvironmentId", "")
    gCtrls["LblCsToken"] := gGui.Add("Text", , "ConnectSecure install token (-j) — not saved")
    gCtrls["CsInstallToken"] := gGui.Add("Edit", "w" UiContentW " Password vCsInstallToken", "")

    gCtrls["LblS1Token"] := gGui.Add("Text", "Section", "SentinelOne site/group token — not saved; paste each time")
    gCtrls["S1Token"] := gGui.Add("Edit", "w" UiContentW " Password vS1Token", "")
    gCtrls["LblS1Path"] := gGui.Add("Text", , "Installer path on endpoint (EXE or MSI)")
    gCtrls["S1InstallerPath"] := gGui.Add("Edit", "w" UiContentW " vS1InstallerPath", "C:\Windows\Temp\SentinelOneInstaller.exe")
    gCtrls["LblS1Url"] := gGui.Add("Text", , "Optional download URL (blank = use path already on disk)")
    gCtrls["S1InstallerUrl"] := gGui.Add("Edit", "w" UiContentW " vS1InstallerUrl", "")
    gCtrls["S1Quiet"] := gGui.Add("Checkbox", "Checked vS1Quiet", "Quiet (-q) for EXE installers (older agents)")
    gCtrls["LblS1Pass"] := gGui.Add("Text", "Section", "SentinelOne uninstall passphrase — not saved")
    gCtrls["S1Passphrase"] := gGui.Add("Edit", "w" UiContentW " Password vS1Passphrase", "")

    huntressAcctDefault := LoadHuntressAccountKey()
    huntressAcctLabel := "Huntress account key (built in; rarely change)"
    gCtrls["LblHuntressAcct"] := gGui.Add("Text", "Section", huntressAcctLabel)
    gCtrls["HuntressAccountKey"] := gGui.Add("Edit", "w" UiContentW " Password vHuntressAccountKey", huntressAcctDefault)
    gCtrls["LblHuntressOrg"] := gGui.Add("Text", , "Huntress organization key (client short name)")
    gCtrls["HuntressOrgKey"] := gGui.Add("Edit", "w" UiContentW " vHuntressOrgKey", "")
    gCtrls["LblHuntressTags"] := gGui.Add("Text", , "Optional tags (comma-separated)")
    gCtrls["HuntressTags"] := gGui.Add("Edit", "w" UiContentW " vHuntressTags", "")

    automateServerDefault := LoadAutomateServer()
    gCtrls["BtnAutomateTicket"] := gGui.Add("Button", "w240", "Paste deployment ticket")
    gCtrls["BtnAutomateTicket"].OnEvent("Click", (*) => PasteAutomateTicket())
    gCtrls["LblAutomateServer"] := gGui.Add("Text", "Section", "Automate server hostname")
    gCtrls["AutomateServer"] := gGui.Add("Edit", "w" UiContentW " vAutomateServer", automateServerDefault)
    gCtrls["LblAutomateLocationId"] := gGui.Add("Text", , "Location ID (from the deployment ticket)")
    gCtrls["AutomateLocationId"] := gGui.Add("Edit", "w" UiContentW " vAutomateLocationId", "")
    gCtrls["LblAutomateToken"] := gGui.Add("Text", , "Windows MSI installer token — not saved; paste each time")
    gCtrls["AutomateToken"] := gGui.Add("Edit", "w" UiContentW " Password vAutomateToken", "")
    gCtrls["LblAutomateClient"] := gGui.Add("Text", , "Client name (GPO / NETLOGON folder)")
    gCtrls["AutomateClientName"] := gGui.Add("Edit", "w" UiContentW " vAutomateClientName", "")
    gCtrls["LblAutomateLocation"] := gGui.Add("Text", , "Location name")
    gCtrls["AutomateLocationName"] := gGui.Add("Edit", "w" UiContentW " vAutomateLocationName", "Main")
    gCtrls["LblAutomateDomain"] := gGui.Add("Text", , "AD DNS name (blank = current domain on the DC)")
    gCtrls["AutomateDomain"] := gGui.Add("Edit", "w" UiContentW " vAutomateDomain", "")
    gCtrls["LblAutomateOu"] := gGui.Add("Text", , "Target OU DN (optional; overrides domain-root link)")
    gCtrls["AutomateTargetOu"] := gGui.Add("Edit", "w" UiContentW " vAutomateTargetOu", "")
    gCtrls["AutomateLinkToDomain"] := gGui.Add("Checkbox", "Checked vAutomateLinkToDomain", "Link at domain root + workstation WMI filter")
    gCtrls["LblWebrootKeyCode"] := gGui.Add("Text", , "Optional Webroot keycode (written to SYSVOL if set)")
    gCtrls["WebrootKeyCode"] := gGui.Add("Edit", "w" UiContentW " Password vWebrootKeyCode", "")

    gCtrls["LblRoPortal"] := gGui.Add("Text", "Section", "RemoteOps portal URL (prefill: local-defaults.ini [RemoteOps] Portal=)")
    gCtrls["RoPortal"] := gGui.Add("Edit", "w" UiContentW " vRoPortal", LoadRemoteOpsPortal())
    gCtrls["LblRoToken"] := gGui.Add("Text", , "One-time token from the portal — not saved; paste each time")
    gCtrls["RoToken"] := gGui.Add("Edit", "w" UiContentW " Password vRoToken", "")

    gCtrls["LblAdTarget"] := gGui.Add("Text", "Section", "Target tunnel address (Peer IP on the RemoteOps portal)")
    gCtrls["AdTarget"] := gGui.Add("Edit", "w" UiContentW " vAdTarget", "")
    gCtrls["LblAdInactiveDays"] := gGui.Add("Text", , "Stale after this many days without a logon")
    gCtrls["AdInactiveDays"] := gGui.Add("Edit", "w" UiContentW " Number vAdInactiveDays", "90")

    gCtrls["LblPaste"] := gGui.Add("Text", "Section", "Paste format")
    gCtrls["FmtCommands"] := gGui.Add("Radio", "Group Checked vFmtCommands", "ScreenConnect Commands (recommended)")
    gCtrls["FmtBackstage"] := gGui.Add("Radio", "vFmtBackstage", "PowerShell (one line)")

    gCtrls["Note"] := gGui.Add("Text", "w" UiContentW " h48 cBlue vToolNote", "")
    gCtrls["Status"] := gGui.Add("Text", "w" UiContentW " h36 vStatus", HotkeyLabel " toggles this window. Expand a category, select a tool, then Copy.")

    gCtrls["BtnCopy"] := gGui.Add("Button", "w220 Default", "Copy to clipboard")
    gCtrls["BtnCopy"].OnEvent("Click", (*) => DoCopy())
    gCtrls["BtnReload"] := gGui.Add("Button", "w100", "Reload")
    gCtrls["BtnReload"].OnEvent("Click", (*) => ReloadScToolLauncher())
    gCtrls["BtnCancel"] := gGui.Add("Button", "w100", "Cancel")
    gCtrls["BtnCancel"].OnEvent("Click", (*) => gGui.Hide())

    ; Right-column stack order (only Visible controls advance Y). Left = tool tree.
    gFlowKeys := [
        "LblAbout", "Summary", "HelpBody", "BtnDocs", "BtnAffects",
        "LblMode", "ModeScan", "ModeUpdate",
        "LblOptions", "Force", "ForceAppShutdown", "IncludeBrowsers", "Uninstall", "Detailed",
        "BlockReinstall", "RemoveSupportAssistant", "ClearAllBackupContent", "SkipIfRunning", "ResetPlatform",
        "AutoReboot", "AllowServer", "LblHuntressRebootAt", "HuntressRebootAt",
        "LblProduct", "Product",
        "LblPupFamily", "PupFamily",
        "LblVendor", "Vendor", "LblAvSecret", "AvSecret",
        "LblDomainController", "DomainController", "LblDomain", "Domain",
        "LblCsOs", "CsOs",
        "LblCsScript", "CsInstallScript",
        "LblCsCompany", "CsCompanyId", "LblCsEnv", "CsEnvironmentId", "LblCsToken", "CsInstallToken",
        "LblS1Token", "S1Token", "LblS1Path", "S1InstallerPath", "LblS1Url", "S1InstallerUrl", "S1Quiet",
        "LblS1Pass", "S1Passphrase",
        "LblHuntressAcct", "HuntressAccountKey", "LblHuntressOrg", "HuntressOrgKey", "LblHuntressTags", "HuntressTags",
        "BtnAutomateTicket",
        "LblAutomateServer", "AutomateServer", "LblAutomateLocationId", "AutomateLocationId", "LblAutomateToken", "AutomateToken",
        "LblAutomateClient", "AutomateClientName", "LblAutomateLocation", "AutomateLocationName",
        "LblAutomateDomain", "AutomateDomain", "LblAutomateOu", "AutomateTargetOu", "AutomateLinkToDomain",
        "LblWebrootKeyCode", "WebrootKeyCode",
        "LblRoPortal", "RoPortal", "LblRoToken", "RoToken",
        "LblAdTarget", "AdTarget", "LblAdInactiveDays", "AdInactiveDays",
        "LblPaste", "FmtCommands", "FmtBackstage",
        "Note", "Status"
    ]

    RefreshOptionEnable()
    gGui.Show("AutoSize")
}

SetCtrlShown(ctrl, shown) {
    ctrl.Visible := shown
    ctrl.Enabled := shown
}

CtrlActive(ctrl) {
    return ctrl.Visible && ctrl.Enabled
}

; Two-column layout: tool tree on the left, options/actions on the right.
ReflowGui() {
    global gGui, gCtrls, gFlowKeys, UiContentW, UiTreeW, UiColGap
    marginX := 12
    marginY := 10
    marginBottom := 12
    gap := 3
    sectionGap := 8
    contentW := UiContentW
    treeW := UiTreeW
    colGap := UiColGap
    leftX := marginX
    rightX := marginX + treeW + colGap

    ; Freeze paint while moving controls (avoids ghosting when the window shrinks).
    try DllCall("SendMessage", "ptr", gGui.Hwnd, "uint", 0x000B, "ptr", 0, "ptr", 0) ; WM_SETREDRAW false

    ; --- Right column (measure first so the tree can match height) ---
    y := marginY
    firstVisible := true
    for key in gFlowKeys {
        ctrl := gCtrls[key]
        if !ctrl.Visible {
            ctrl.Move(-2000, -2000)
            continue
        }
        if (InStr(key, "Lbl") = 1 && !firstVisible)
            y += sectionGap - gap
        firstVisible := false

        ch := 18
        cw := contentW
        if (key = "CsInstallScript")
            ch := 72
        else if (key = "Summary")
            ch := 52
        else if (key = "HelpBody")
            ch := 280
        else if (key = "Note")
            ch := 48
        else if (key = "Status")
            ch := 36
        else if (key = "BtnDocs" || key = "BtnAffects" || key = "BtnAutomateTicket") {
            ch := 26
            cw := 200
        }
        else if (key = "Product" || key = "PupFamily" || key = "AvSecret" || key = "DomainController" || key = "Domain" || key = "Vendor"
            || key = "CsOs" || key = "CsCompanyId" || key = "CsEnvironmentId" || key = "CsInstallToken"
            || key = "S1Token" || key = "S1InstallerPath" || key = "S1InstallerUrl" || key = "S1Passphrase"
            || key = "HuntressAccountKey" || key = "HuntressOrgKey" || key = "HuntressTags"
            || key = "HuntressRebootAt"
            || key = "AutomateServer" || key = "AutomateLocationId" || key = "AutomateToken"
            || key = "AutomateClientName" || key = "AutomateLocationName" || key = "AutomateDomain"
            || key = "AutomateTargetOu" || key = "WebrootKeyCode"
            || key = "RoPortal" || key = "RoToken" || key = "AdTarget" || key = "AdInactiveDays")
            ch := 22
        else if (InStr(key, "Lbl") = 1)
            ch := 16
        else if (InStr(key, "Mode") = 1 || InStr(key, "Fmt") = 1 || key = "Force" || key = "ForceAppShutdown"
            || key = "IncludeBrowsers" || key = "Uninstall" || key = "Detailed" || key = "BlockReinstall"
            || key = "RemoveSupportAssistant" || key = "ClearAllBackupContent" || key = "SkipIfRunning"
            || key = "ResetPlatform" || key = "AutoReboot" || key = "AllowServer"
            || key = "S1Quiet" || key = "AutomateLinkToDomain")
            ch := 20

        ctrl.Move(rightX, y, cw, ch)
        y += ch + gap
    }

    btnH := 28
    gCtrls["BtnCopy"].Move(rightX, y, 180, btnH)
    gCtrls["BtnReload"].Move(rightX + 188, y, 90, btnH)
    gCtrls["BtnCancel"].Move(rightX + 286, y, 90, btnH)
    y += btnH + marginBottom
    rightBottom := y

    ; --- Left column: label + tree sized to right column ---
    lblH := 16
    gCtrls["LblTools"].Move(leftX, marginY, treeW, lblH)
    treeTop := marginY + lblH + gap
    minTreeH := 280
    treeH := rightBottom - treeTop - marginBottom
    if (treeH < minTreeH)
        treeH := minTreeH
    gCtrls["ToolTree"].Move(leftX, treeTop, treeW, treeH)
    leftBottom := treeTop + treeH + marginBottom
    if (leftBottom > rightBottom)
        rightBottom := leftBottom

    clientW := rightX + contentW + marginX
    clientH := rightBottom

    gGui.GetPos(,, &winW, &winH)
    gGui.GetClientPos(,, &cliW, &cliH)
    chromeW := winW - cliW
    chromeH := winH - cliH
    if (chromeW < 0)
        chromeW := 16
    if (chromeH < 0)
        chromeH := 40
    gGui.Move(,, clientW + chromeW, clientH + chromeH)

    try DllCall("SendMessage", "ptr", gGui.Hwnd, "uint", 0x000B, "ptr", 1, "ptr", 0) ; WM_SETREDRAW true
    try DllCall("RedrawWindow", "ptr", gGui.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x0585)
    ; RDW_INVALIDATE|RDW_ERASE|RDW_FRAME|RDW_ALLCHILDREN|RDW_UPDATENOW
}

LoadHuntressAccountKey() {
    global LocalDefaultsPath, HuntressAccountKeyDefault
    if FileExist(LocalDefaultsPath) {
        ini := Trim(IniRead(LocalDefaultsPath, "Huntress", "AccountKey", ""))
        if (ini != "")
            return ini
    }
    return HuntressAccountKeyDefault
}

LoadAutomateServer() {
    global LocalDefaultsPath
    default := "river-run.hostedrmm.com"
    if FileExist(LocalDefaultsPath) {
        ini := Trim(IniRead(LocalDefaultsPath, "Automate", "Server", ""))
        if (ini != "")
            return ini
    }
    return default
}

; Official portal script: cybercnsagent.exe -c COMPANY -e ENVIRONMENT -j TOKEN -i
; Nothing from this paste is written to disk.
ParseConnectSecureInstallScript(text) {
    company := ""
    envId := ""
    token := ""
    ; \x22 and \x27 are quote characters. AutoHotkey does not treat a doubled quote as an escape here.
    if RegExMatch(text, "i)(?:^|[\s;])-c(?:=|\s+)[\x22\x27]?(\d+)", &mCompany)
        company := mCompany[1]
    if RegExMatch(text, "i)(?:^|[\s;])-e(?:=|\s+)[\x22\x27]?(\d+)", &mEnv)
        envId := mEnv[1]
    if RegExMatch(text, "i)(?:^|[\s;])-j(?:=|\s+)[\x22\x27]?([^\s\x22\x27;]+)", &mToken)
        token := mToken[1]
    return Map("company", company, "env", envId, "token", token)
}

ApplyConnectSecureInstallScript(requireComplete) {
    global gCtrls
    raw := gCtrls["CsInstallScript"].Value
    if (Trim(raw) = "")
        return !requireComplete
    parsed := ParseConnectSecureInstallScript(raw)
    if (parsed["company"] = "" || parsed["env"] = "" || parsed["token"] = "")
        return false
    gCtrls["CsCompanyId"].Value := parsed["company"]
    gCtrls["CsEnvironmentId"].Value := parsed["env"]
    gCtrls["CsInstallToken"].Value := parsed["token"]
    gCtrls["Status"].Value := "Parsed company " parsed["company"] ", environment " parsed["env"] ", token set. Not saved."
    return true
}

ParseAutomateDeploymentTicket(text) {
    server := "", locId := "", token := "", client := "", locName := ""
    section := ""
    for line in StrSplit(text, "`n", "`r") {
        line := Trim(line)
        if (line = "")
            continue
        heading := Trim(RegExReplace(line, "[#*]+"))
        if RegExMatch(line, "i)^Client:\s*(.+)$", &mClient)
            client := Trim(mClient[1])
        else if RegExMatch(line, "i)^Location:\s*(.+?)\s*\((\d+)\)\s*$", &mLoc) {
            locName := Trim(mLoc[1])
            locId := mLoc[2]
        }
        else if RegExMatch(heading, "i)^MSI$")
            section := "msi"
        else if RegExMatch(heading, "i)^(Linux|Mac)\b")
            section := "other"
        else if (section = "msi" && token = "" && RegExMatch(line, "i)^https?://([^/\s]+)/\S*InstallerToken=([0-9A-Fa-f]+)", &mUrl)) {
            server := mUrl[1]
            token := mUrl[2]
        }
    }
    if (server = "" && RegExMatch(text, "i)-Server\s+'([^']+)'", &mServer))
        server := mServer[1]
    if (server = "" && RegExMatch(text, 'i)-Server\s+"([^"]+)"', &mServer))
        server := mServer[1]
    if (locId = "" && RegExMatch(text, "i)-LocationID\s+(\d+)", &mId))
        locId := mId[1]
    if (token = "" && RegExMatch(text, "i)-Token\s+'([0-9A-Fa-f]+)'", &mTok))
        token := mTok[1]
    if (token = "" && RegExMatch(text, 'i)-Token\s+"([0-9A-Fa-f]+)"', &mTok))
        token := mTok[1]
    return Map("server", server, "locationId", locId, "token", token, "client", client, "locationName", locName)
}

PasteAutomateTicket() {
    global gCtrls, AppName
    text := ""
    try text := A_Clipboard
    if (Trim(text) = "") {
        MsgBox("Copy the deployment ticket first.", AppName, "Icon!")
        return
    }
    parsed := ParseAutomateDeploymentTicket(text)
    if (parsed["server"] = "" || parsed["locationId"] = "" || parsed["token"] = "") {
        MsgBox("That clipboard text is not a deployment ticket.`nIt needs the MSI installer link, or an Install-Automate line with the server, location ID, and token.", AppName, "Icon!")
        return
    }
    gCtrls["AutomateServer"].Value := parsed["server"]
    gCtrls["AutomateLocationId"].Value := parsed["locationId"]
    gCtrls["AutomateToken"].Value := parsed["token"]
    if (parsed["client"] != "")
        gCtrls["AutomateClientName"].Value := parsed["client"]
    if (parsed["locationName"] != "")
        gCtrls["AutomateLocationName"].Value := parsed["locationName"]
    who := parsed["client"]
    if (who = "")
        who := "client not in ticket"
    where := parsed["locationName"]
    if (where = "")
        where := "location"
    gCtrls["Status"].Value := "Ticket: " who " / " where " (" parsed["locationId"] "). Windows MSI token set. Not saved."
}

LoadRemoteOpsPortal() {
    global LocalDefaultsPath
    if FileExist(LocalDefaultsPath)
        return Trim(IniRead(LocalDefaultsPath, "RemoteOps", "Portal", ""))
    return ""
}

ToolHasFlag(tool, flag) {
    return InStr(" " tool["Flags"] " ", " " flag " ")
}

ToolGet(tool, key, default := "") {
    if tool.Has(key)
        return tool[key]
    return default
}

FillPupFamilyList(tool) {
    global gCtrls, gPupFamilySource
    raw := ToolGet(tool, "ProductList", "")
    if (raw = gPupFamilySource)
        return
    gPupFamilySource := raw
    items := []
    for part in StrSplit(raw, "|") {
        p := Trim(part)
        if (p != "")
            items.Push(p)
    }
    gCtrls["PupFamily"].Delete()
    if items.Length
        gCtrls["PupFamily"].Add(items)
    if items.Length
        gCtrls["PupFamily"].Choose(1)
}

SelectedTool() {
    global Tools, gCtrls, gToolByNode, gLastToolIndex
    node := gCtrls["ToolTree"].GetSelection()
    if node && gToolByNode.Has(node) {
        gLastToolIndex := gToolByNode[node]
        return Tools[gLastToolIndex]
    }
    ; Category header (e.g. after collapse): keep last tool; never re-select a child.
    if (gLastToolIndex < 1 || gLastToolIndex > Tools.Length)
        gLastToolIndex := 1
    return Tools[gLastToolIndex]
}

OnForceOptClick(*) {
    global gCtrls
    if ToolHasFlag(SelectedTool(), "HuntressInstall") && gCtrls["Force"].Value
        gCtrls["AutoReboot"].Value := 0
    RefreshOptionEnable()
}

OnAutoRebootOptClick(*) {
    global gCtrls
    if ToolHasFlag(SelectedTool(), "HuntressInstall") && gCtrls["AutoReboot"].Value
        gCtrls["Force"].Value := 0
    RefreshOptionEnable()
}

RefreshOptionEnable(*) {
    global gGui, gCtrls, HelpIntroText, HotkeyLabel
    t := SelectedTool()

    if ToolHasFlag(t, "Help") {
        gCtrls["LblAbout"].Text := "SC Tool Launcher"
        gCtrls["HelpBody"].Value := HelpIntroText
        SetCtrlShown(gCtrls["LblAbout"], true)
        SetCtrlShown(gCtrls["HelpBody"], true)
        SetCtrlShown(gCtrls["Summary"], false)
        SetCtrlShown(gCtrls["BtnDocs"], ToolDocsUrl(t) != "")
        gCtrls["BtnDocs"].Text := "Open launcher docs"
        hideKeys := [
            "LblMode", "ModeScan", "ModeUpdate", "LblOptions",
            "Force", "ForceAppShutdown", "IncludeBrowsers", "Uninstall", "Detailed",
            "BlockReinstall", "RemoveSupportAssistant", "ClearAllBackupContent", "SkipIfRunning",
            "ResetPlatform", "AutoReboot", "AllowServer", "LblHuntressRebootAt", "HuntressRebootAt",
            "LblProduct", "Product", "LblPupFamily", "PupFamily",
            "LblVendor", "Vendor", "LblAvSecret", "AvSecret",
            "LblDomainController", "DomainController", "LblDomain", "Domain",
            "LblCsOs", "CsOs",
            "LblCsScript", "CsInstallScript",
            "LblCsCompany", "CsCompanyId", "LblCsEnv", "CsEnvironmentId", "LblCsToken", "CsInstallToken",
            "LblS1Token", "S1Token", "LblS1Path", "S1InstallerPath", "LblS1Url", "S1InstallerUrl", "S1Quiet",
            "LblS1Pass", "S1Passphrase",
            "LblHuntressAcct", "HuntressAccountKey", "LblHuntressOrg", "HuntressOrgKey", "LblHuntressTags", "HuntressTags",
            "BtnAutomateTicket",
            "LblAutomateServer", "AutomateServer", "LblAutomateLocationId", "AutomateLocationId",
            "LblAutomateToken", "AutomateToken", "LblAutomateClient", "AutomateClientName",
            "LblAutomateLocation", "AutomateLocationName", "LblAutomateDomain", "AutomateDomain",
            "LblAutomateOu", "AutomateTargetOu", "AutomateLinkToDomain", "LblWebrootKeyCode", "WebrootKeyCode",
            "LblRoPortal", "RoPortal", "LblRoToken", "RoToken",
            "LblAdTarget", "AdTarget", "LblAdInactiveDays", "AdInactiveDays",
            "LblPaste", "FmtCommands", "FmtBackstage", "Note", "BtnAffects"
        ]
        for key in hideKeys
            SetCtrlShown(gCtrls[key], false)
        SetCtrlShown(gCtrls["BtnCopy"], false)
        gCtrls["Status"].Value := HotkeyLabel " toggles this window. Expand a category, select a tool, then Copy."
        ReflowGui()
        return
    }

    gCtrls["LblAbout"].Text := "About this tool"
    gCtrls["BtnDocs"].Text := "Open docs in browser"
    SetCtrlShown(gCtrls["HelpBody"], false)
    SetCtrlShown(gCtrls["BtnCopy"], true)
    SetCtrlShown(gCtrls["LblMode"], true)
    SetCtrlShown(gCtrls["LblPaste"], true)
    SetCtrlShown(gCtrls["FmtCommands"], true)
    SetCtrlShown(gCtrls["FmtBackstage"], true)

    showForce := ToolHasFlag(t, "Force")
    showForceApp := ToolHasFlag(t, "ForceAppShutdown")
    showBrowsers := ToolHasFlag(t, "IncludeBrowsers")
    showUninstall := ToolHasFlag(t, "Uninstall")
    showDetailed := ToolHasFlag(t, "Detailed")
    showBlock := ToolHasFlag(t, "BlockReinstall")
    showRmHpsa := ToolHasFlag(t, "RemoveSupportAssistant")
    showClearAllBackup := ToolHasFlag(t, "ClearAllBackupContent")
    showProduct := ToolHasFlag(t, "Product")
    showPupFamily := ToolHasFlag(t, "ProductList")
    showVendor := ToolHasFlag(t, "Vendor")
    showDomain := ToolHasFlag(t, "Domain")
    showConnectSecure := ToolHasFlag(t, "ConnectSecure")
    showCsOs := showConnectSecure && ToolHasFlag(t, "RunOnly")
    csOs := ""
    if (showCsOs)
        csOs := gCtrls["CsOs"].Text
    csOsShell := showCsOs && (csOs != "" && csOs != "Windows")
    showSkipIfRunning := ToolHasFlag(t, "SkipIfRunning") && !csOsShell
    showResetPlatform := ToolHasFlag(t, "ResetPlatform")
    if InStr(ToolGet(t, "Path", ""), "WindowsDefender") && gCtrls["ModeScan"].Value
        showResetPlatform := false
    ; RunOnly tools (Huntress) keep ModeScan checked until later in this function,
    ; so do not require Apply mode to show the schedule/reboot checkbox.
    showAutoReboot := ToolHasFlag(t, "AutoReboot") && (ToolHasFlag(t, "RunOnly") || !gCtrls["ModeScan"].Value)
    showAllowServer := ToolHasFlag(t, "AllowServer")
    showSentinelOne := ToolHasFlag(t, "SentinelOneInstall")
    showSentinelOneUnload := ToolHasFlag(t, "SentinelOneUnload")
    showHuntress := ToolHasFlag(t, "HuntressInstall")
    showAutomate := ToolHasFlag(t, "AutomateGpo")
    showScGpo := ToolHasFlag(t, "ScreenConnectGpo")
    showWebrootGpo := ToolHasFlag(t, "WebrootUninstallGpo")
    showEolGpo := ToolHasFlag(t, "EolAuditGpo")
    scanOnly := ToolHasFlag(t, "ScanOnly")

    if (showHuntress) {
        gCtrls["Force"].Text := "Rip and replace (wipe leftover Huntress, then install now; no reboot)"
        gCtrls["AutoReboot"].Text := "Schedule SYSTEM install + cleanup + reboot at chosen time"
    } else if ToolHasFlag(t, "Reinstall") {
        gCtrls["Force"].Text := "Force (reinstall a probe agent)"
        gCtrls["AutoReboot"].Text := "Auto reboot when required"
    } else if InStr(ToolGet(t, "Path", ""), "AutomateUninstall") {
        gCtrls["Force"].Text := "Force (uninstall a probe agent)"
        gCtrls["AutoReboot"].Text := "Auto reboot when required"
    } else if InStr(ToolGet(t, "Path", ""), "HpImageAssistant") {
        gCtrls["Force"].Text := "Re-download HPIA"
        gCtrls["AutoReboot"].Text := "Auto reboot when required"
    } else {
        gCtrls["Force"].Text := "Force (skip soft guards / re-run)"
        gCtrls["AutoReboot"].Text := "Auto reboot when required"
    }
    SetCtrlShown(gCtrls["Force"], showForce)
    SetCtrlShown(gCtrls["ForceAppShutdown"], showForceApp)
    SetCtrlShown(gCtrls["IncludeBrowsers"], showBrowsers)
    SetCtrlShown(gCtrls["Uninstall"], showUninstall)
    SetCtrlShown(gCtrls["Detailed"], showDetailed)
    SetCtrlShown(gCtrls["BlockReinstall"], showBlock)
    SetCtrlShown(gCtrls["RemoveSupportAssistant"], showRmHpsa)
    SetCtrlShown(gCtrls["ClearAllBackupContent"], showClearAllBackup)
    if !showClearAllBackup
        gCtrls["ClearAllBackupContent"].Value := 0
    SetCtrlShown(gCtrls["SkipIfRunning"], showSkipIfRunning)
    SetCtrlShown(gCtrls["ResetPlatform"], showResetPlatform)
    SetCtrlShown(gCtrls["AutoReboot"], showAutoReboot)
    SetCtrlShown(gCtrls["AllowServer"], showAllowServer)
    if !showAllowServer
        gCtrls["AllowServer"].Value := 0
    if (showHuntress) {
        if gCtrls["Force"].Value && gCtrls["AutoReboot"].Value
            gCtrls["AutoReboot"].Value := 0
        if gCtrls["Force"].Value
            gCtrls["AutoReboot"].Enabled := false
        if gCtrls["AutoReboot"].Value
            gCtrls["Force"].Enabled := false
    }
    showHuntressRebootAt := showHuntress && showAutoReboot && gCtrls["AutoReboot"].Value
    SetCtrlShown(gCtrls["LblHuntressRebootAt"], showHuntressRebootAt)
    SetCtrlShown(gCtrls["HuntressRebootAt"], showHuntressRebootAt)
    SetCtrlShown(gCtrls["LblProduct"], showProduct)
    SetCtrlShown(gCtrls["Product"], showProduct)
    if showPupFamily {
        if ToolHasFlag(t, "PupBlock")
            gCtrls["LblPupFamily"].Text := "PUP family (All catalog = every family)"
        else
            gCtrls["LblPupFamily"].Text := "PUP family (All on host = whatever is present)"
        FillPupFamilyList(t)
    }
    SetCtrlShown(gCtrls["LblPupFamily"], showPupFamily)
    SetCtrlShown(gCtrls["PupFamily"], showPupFamily)
    SetCtrlShown(gCtrls["LblVendor"], showVendor)
    SetCtrlShown(gCtrls["Vendor"], showVendor)
    SetCtrlShown(gCtrls["LblAvSecret"], showVendor)
    SetCtrlShown(gCtrls["AvSecret"], showVendor)
    SetCtrlShown(gCtrls["LblDomainController"], showDomain)
    SetCtrlShown(gCtrls["DomainController"], showDomain)
    SetCtrlShown(gCtrls["LblDomain"], showDomain)
    SetCtrlShown(gCtrls["Domain"], showDomain)
    ; ConnectSecure IDs/token: always for silent install (RunOnly); repair only in Apply mode.
    ; OS list is install-only. Repair stays the Windows wipe script.
    showCsFields := showConnectSecure && (ToolHasFlag(t, "RunOnly") || !gCtrls["ModeScan"].Value)
    SetCtrlShown(gCtrls["LblCsOs"], showCsOs)
    SetCtrlShown(gCtrls["CsOs"], showCsOs)
    SetCtrlShown(gCtrls["LblCsScript"], showCsFields)
    SetCtrlShown(gCtrls["CsInstallScript"], showCsFields)
    SetCtrlShown(gCtrls["LblCsCompany"], showCsFields)
    SetCtrlShown(gCtrls["CsCompanyId"], showCsFields)
    SetCtrlShown(gCtrls["LblCsEnv"], showCsFields)
    SetCtrlShown(gCtrls["CsEnvironmentId"], showCsFields)
    SetCtrlShown(gCtrls["LblCsToken"], showCsFields)
    SetCtrlShown(gCtrls["CsInstallToken"], showCsFields)
    SetCtrlShown(gCtrls["LblS1Token"], showSentinelOne)
    SetCtrlShown(gCtrls["S1Token"], showSentinelOne)
    SetCtrlShown(gCtrls["LblS1Path"], showSentinelOne)
    SetCtrlShown(gCtrls["S1InstallerPath"], showSentinelOne)
    SetCtrlShown(gCtrls["LblS1Url"], showSentinelOne)
    SetCtrlShown(gCtrls["S1InstallerUrl"], showSentinelOne)
    SetCtrlShown(gCtrls["S1Quiet"], showSentinelOne)
    SetCtrlShown(gCtrls["LblS1Pass"], showSentinelOneUnload)
    SetCtrlShown(gCtrls["S1Passphrase"], showSentinelOneUnload)
    SetCtrlShown(gCtrls["LblHuntressAcct"], showHuntress)
    SetCtrlShown(gCtrls["HuntressAccountKey"], showHuntress)
    SetCtrlShown(gCtrls["LblHuntressOrg"], showHuntress)
    SetCtrlShown(gCtrls["HuntressOrgKey"], showHuntress)
    SetCtrlShown(gCtrls["LblHuntressTags"], showHuntress)
    SetCtrlShown(gCtrls["HuntressTags"], showHuntress)
    SetCtrlShown(gCtrls["BtnAutomateTicket"], showAutomate)
    SetCtrlShown(gCtrls["LblAutomateServer"], showAutomate)
    SetCtrlShown(gCtrls["AutomateServer"], showAutomate)
    SetCtrlShown(gCtrls["LblAutomateLocationId"], showAutomate)
    SetCtrlShown(gCtrls["AutomateLocationId"], showAutomate)
    gCtrls["LblAutomateToken"].Text := "Windows MSI installer token — not saved; paste each time"
    gCtrls["LblAutomateClient"].Text := "Client name (GPO / NETLOGON folder)"
    if (showScGpo) {
        gCtrls["LblAutomateToken"].Text := "Path to the ScreenConnect client MSI on this DC"
        gCtrls["LblAutomateClient"].Text := "Name for the GPO and NETLOGON folder"
    }
    SetCtrlShown(gCtrls["LblAutomateToken"], showAutomate || showScGpo)
    SetCtrlShown(gCtrls["AutomateToken"], showAutomate || showScGpo)
    SetCtrlShown(gCtrls["LblAutomateClient"], showAutomate || showScGpo)
    SetCtrlShown(gCtrls["AutomateClientName"], showAutomate || showScGpo)
    SetCtrlShown(gCtrls["LblAutomateLocation"], showAutomate)
    SetCtrlShown(gCtrls["AutomateLocationName"], showAutomate)
    showGpoDomain := showAutomate || showScGpo || showWebrootGpo || showEolGpo
    SetCtrlShown(gCtrls["LblAutomateDomain"], showGpoDomain)
    SetCtrlShown(gCtrls["AutomateDomain"], showGpoDomain)
    SetCtrlShown(gCtrls["LblAutomateOu"], showGpoDomain)
    SetCtrlShown(gCtrls["AutomateTargetOu"], showGpoDomain)
    showGpoLink := showGpoDomain && !gCtrls["ModeScan"].Value
    if (showEolGpo)
        gCtrls["AutomateLinkToDomain"].Text := "Link at the domain root (includes servers)"
    else
        gCtrls["AutomateLinkToDomain"].Text := "Link at domain root + workstation WMI filter"
    SetCtrlShown(gCtrls["AutomateLinkToDomain"], showGpoLink)
    SetCtrlShown(gCtrls["LblWebrootKeyCode"], showWebrootGpo)
    SetCtrlShown(gCtrls["WebrootKeyCode"], showWebrootGpo)
    showRoPortal := ToolHasFlag(t, "RemoteOpsEnroll") || ToolHasFlag(t, "RemoteOpsRemove")
    showRoToken := ToolHasFlag(t, "RemoteOpsEnroll")
    showAdReview := ToolHasFlag(t, "AdReview")
    SetCtrlShown(gCtrls["LblRoPortal"], showRoPortal)
    SetCtrlShown(gCtrls["RoPortal"], showRoPortal)
    SetCtrlShown(gCtrls["LblRoToken"], showRoToken)
    SetCtrlShown(gCtrls["RoToken"], showRoToken)
    SetCtrlShown(gCtrls["LblAdTarget"], showAdReview)
    SetCtrlShown(gCtrls["AdTarget"], showAdReview)
    SetCtrlShown(gCtrls["LblAdInactiveDays"], showAdReview)
    SetCtrlShown(gCtrls["AdInactiveDays"], showAdReview)

    anyOpt := showForce || showForceApp || showBrowsers || showUninstall || showDetailed
        || showBlock || showRmHpsa || showClearAllBackup || showSkipIfRunning || showResetPlatform
        || showAutoReboot || showGpoLink
    SetCtrlShown(gCtrls["LblOptions"], anyOpt)

    ; Find-only tools: hide "Apply" mode entirely
    ; Run-only tools (e.g. ADWCleaner): hide Scan, force Apply
    runOnly := ToolHasFlag(t, "RunOnly")
    SetCtrlShown(gCtrls["ModeUpdate"], !scanOnly)
    SetCtrlShown(gCtrls["ModeScan"], !runOnly)
    if scanOnly {
        gCtrls["ModeScan"].Value := 1
        gCtrls["ModeUpdate"].Value := 0
    } else if runOnly {
        gCtrls["ModeScan"].Value := 0
        gCtrls["ModeUpdate"].Value := 1
    }

    if ToolHasFlag(t, "Remediate") {
        gCtrls["ModeScan"].Text := "Scan only (report leftovers)"
        gCtrls["ModeUpdate"].Text := "Clean up / remediate"
    } else if ToolHasFlag(t, "Delete") && ToolHasFlag(t, "BackupsOnlyDefault") {
        gCtrls["ModeScan"].Text := "Scan CW/SC files in Backup"
        gCtrls["ModeUpdate"].Text := "Remove CW/SC files from Backup"
        if gCtrls["ClearAllBackupContent"].Value
            gCtrls["ModeUpdate"].Text := "Clear entire Backup contents"
    } else if ToolHasFlag(t, "Delete") || ToolHasFlag(t, "PositionalDry") {
        gCtrls["ModeScan"].Text := "Scan only (dry-run)"
        gCtrls["ModeUpdate"].Text := "Remove matched items"
    } else if runOnly && ToolHasFlag(t, "SentinelOneInstall") {
        gCtrls["ModeUpdate"].Text := "Silent install (token)"
    } else if runOnly && ToolHasFlag(t, "SentinelOneUnload") {
        gCtrls["ModeUpdate"].Text := "Unload agent (passphrase)"
    } else if runOnly && ToolHasFlag(t, "HuntressInstall") {
        gCtrls["ModeUpdate"].Text := "Silent install (/ACCT_KEY)"
    } else if runOnly && (ToolGet(t, "Fetch", "") = "Inline") {
        gCtrls["ModeUpdate"].Text := "Run command"
    } else if runOnly && showConnectSecure {
        if (csOsShell)
            gCtrls["ModeUpdate"].Text := "Silent install (shell)"
        else
            gCtrls["ModeUpdate"].Text := "Silent install (-c/-e/-j)"
    } else if runOnly && InStr(ToolGet(t, "TempName", ""), "HPbloatware") {
        gCtrls["ModeUpdate"].Text := "Remove HP bloat / Wolf"
    } else if runOnly {
        gCtrls["ModeUpdate"].Text := "Download and run"
    } else if ToolHasFlag(t, "PowerIdle") {
        gCtrls["ModeScan"].Text := "Show plugged-in sleep and hibernate"
        gCtrls["ModeUpdate"].Text := "Set plugged-in sleep and hibernate to Never"
    } else if ToolHasFlag(t, "FastStartup") {
        gCtrls["ModeScan"].Text := "Show Fast Startup"
        gCtrls["ModeUpdate"].Text := "Turn Fast Startup off"
    } else if ToolHasFlag(t, "EolAudit") {
        gCtrls["ModeScan"].Text := "Measure log space (no audit changes)"
        gCtrls["ModeUpdate"].Text := "Audit sentinel DLLs"
    } else if ToolHasFlag(t, "EolAuditGpo") {
        gCtrls["ModeScan"].Text := "Dry-run (no download, no GPO)"
        gCtrls["ModeUpdate"].Text := "Download script and create GPO"
    } else if ToolHasFlag(t, "PupBlock") {
        gCtrls["ModeScan"].Text := "List program names (no block)"
        gCtrls["ModeUpdate"].Text := "Block these programs and warn"
    } else if scanOnly && (ToolGet(t, "Fetch", "") = "Inline") {
        gCtrls["ModeScan"].Text := "Check pending reboot"
    } else if scanOnly {
        gCtrls["ModeScan"].Text := "Find / report"
    } else {
        gCtrls["ModeScan"].Text := "Scan only (no changes)"
        gCtrls["ModeUpdate"].Text := "Apply updates"
    }

    if ToolHasFlag(t, "ConnectSecure") && ToolHasFlag(t, "Remediate") {
        gCtrls["ModeScan"].Text := "Check agent health"
        gCtrls["ModeUpdate"].Text := "Repair + reinstall"
    }
    if ToolHasFlag(t, "BackstageOnly") {
        gCtrls["FmtBackstage"].Value := 1
        gCtrls["FmtCommands"].Value := 0
        SetCtrlShown(gCtrls["FmtCommands"], false)
        gCtrls["LblPaste"].Text := "Paste format (PowerShell only)"
    } else {
        SetCtrlShown(gCtrls["FmtCommands"], true)
        gCtrls["LblPaste"].Text := "Paste format"
    }
    if (csOsShell)
        gCtrls["FmtBackstage"].Text := "Terminal (one line)"
    else
        gCtrls["FmtBackstage"].Text := "PowerShell (one line)"

    if InStr(ToolGet(t, "Path", ""), "WindowsDefender") {
        gCtrls["ModeScan"].Text := "Check RTP + services"
        gCtrls["ModeUpdate"].Text := "Re-enable Defender RTP"
    }
    if InStr(ToolGet(t, "Path", ""), "AcrobatXiRemoval") {
        gCtrls["ModeScan"].Text := "Scan Acrobat XI + Foxit"
        gCtrls["ModeUpdate"].Text := "Uninstall Acrobat XI"
    }
    if ToolHasFlag(t, "Reinstall") {
        gCtrls["ModeScan"].Text := "Scan server, location, cached MSI"
        gCtrls["ModeUpdate"].Text := "Reinstall from this PC"
    } else if InStr(ToolGet(t, "Path", ""), "AutomateUninstall") {
        gCtrls["ModeScan"].Text := "Scan Automate agent"
        gCtrls["ModeUpdate"].Text := "Uninstall Automate agent"
    }
    if InStr(ToolGet(t, "Path", ""), "WindowsUpdate") {
        if InStr(ToolGet(t, "DefaultArgs", ""), "-Firmware") {
            gCtrls["ModeScan"].Text := "Scan BIOS / firmware"
            gCtrls["ModeUpdate"].Text := "Install firmware (no reboot unless option)"
        } else {
            gCtrls["ModeScan"].Text := "Scan pending updates + pre-check"
            gCtrls["ModeUpdate"].Text := "Install (no reboot unless option)"
        }
    }
    if InStr(ToolGet(t, "Path", ""), "HpImageAssistant") {
        gCtrls["ModeScan"].Text := "List unattended SoftPaqs"
        gCtrls["ModeUpdate"].Text := "Install unattended SoftPaqs"
    }
    if InStr(ToolGet(t, "Path", ""), "OutlookDisableCache") {
        gCtrls["ModeScan"].Text := "Scan profiles and cache size"
        gCtrls["ModeUpdate"].Text := "Force online mode and delete cache"
    }
    if InStr(ToolGet(t, "Path", ""), "WinVerifyTrustPadding") {
        gCtrls["ModeScan"].Text := "Check padding registry"
        gCtrls["ModeUpdate"].Text := "Enable strict signature check"
    }
    if InStr(ToolGet(t, "Path", ""), "SpeculativeStoreBypass") {
        gCtrls["ModeScan"].Text := "Check SSBD mitigation"
        gCtrls["ModeUpdate"].Text := "Enable SSBD mitigation"
    }
    if InStr(ToolGet(t, "Path", ""), "PowerShellV2Disable") {
        gCtrls["ModeUpdate"].Text := "Disable PowerShell 2.0"
    }
    if InStr(ToolGet(t, "Path", ""), "PhpUse") {
        gCtrls["ModeScan"].Text := "Check whether this host uses PHP"
    }
    if ToolHasFlag(t, "Delete") && InStr(ToolGet(t, "Path", ""), "Inky") {
        gCtrls["ModeScan"].Text := "List matching rules"
        gCtrls["ModeUpdate"].Text := "Delete matching rules"
    }
    if ToolHasFlag(t, "Delete") && InStr(ToolGet(t, "Path", ""), "EntraVendorAppRemoval") {
        gCtrls["ModeScan"].Text := "List matching apps"
        gCtrls["ModeUpdate"].Text := "Pick apps and delete"
    }
    if ToolHasFlag(t, "RunOnly") && InStr(ToolGet(t, "Path", ""), "EntraIntuneEvidence") {
        gCtrls["ModeUpdate"].Text := "Export to OneDrive"
    }
    if ToolHasFlag(t, "AdReview") {
        gCtrls["ModeUpdate"].Text := "Review AD over the tunnel"
    }
    if ToolHasFlag(t, "AutomateGpo") {
        gCtrls["ModeScan"].Text := "Dry-run (transform only)"
        gCtrls["ModeUpdate"].Text := "Stage MSI + create GPO"
    }
    if ToolHasFlag(t, "ScreenConnectGpo") {
        gCtrls["ModeScan"].Text := "Dry-run (no SYSVOL write)"
        gCtrls["ModeUpdate"].Text := "Stage MSI + create GPO"
    }
    if ToolHasFlag(t, "WebrootUninstallGpo") {
        gCtrls["ModeScan"].Text := "Dry-run (print startup script)"
        gCtrls["ModeUpdate"].Text := "Create uninstall GPO"
    }

    summary := ToolGet(t, "Summary", "")
    gCtrls["Summary"].Value := summary
    SetCtrlShown(gCtrls["LblAbout"], true)
    SetCtrlShown(gCtrls["Summary"], true)
    SetCtrlShown(gCtrls["BtnDocs"], ToolDocsUrl(t) != "")
    SetCtrlShown(gCtrls["BtnAffects"], ToolGet(t, "Affects", "") != "")

    note := ToolGet(t, "Note", "")
    if (csOsShell)
        note := csOs " copies the ConnectSecure portal shell command. Paste the Windows install script above; company, environment, and token are read from it and are not saved. Run as root."
    gCtrls["Note"].Value := note
    SetCtrlShown(gCtrls["Note"], note != "")

    ReflowGui()
}

ToolDocsUrl(tool) {
    global DefaultOwner, DefaultRepo
    explicit := ToolGet(tool, "DocsUrl", "")
    if (explicit != "")
        return explicit
    if (ToolGet(tool, "Fetch", "Contents") = "Contents") {
        path := ToolGet(tool, "Path", "")
        if (path != "")
            return "https://github.com/" DefaultOwner "/" DefaultRepo "/tree/main/" path
    }
    owner := ToolGet(tool, "Owner", DefaultOwner)
    repo := ToolGet(tool, "Repo", "")
    if (repo != "")
        return "https://github.com/" owner "/" repo
    return ""
}

ShowAffectsPopup(*) {
    global gGui, gCtrls, AppName
    tool := SelectedTool()
    body := Trim(ToolGet(tool, "Affects", ""))
    if (body = "")
        return
    scope := ""
    if ToolHasFlag(tool, "Product") && CtrlActive(gCtrls["Product"]) {
        prod := Trim(gCtrls["Product"].Value)
        if (prod != "")
            scope .= "This copy is limited to catalog id(s): " prod "`r`n`r`n"
    }
    if ToolHasFlag(tool, "ProductList") && CtrlActive(gCtrls["PupFamily"]) {
        fam := Trim(gCtrls["PupFamily"].Text)
        if (fam != "" && fam != "All on host" && fam != "All catalog")
            scope .= "This copy is limited to family: " fam "`r`n`r`n"
    }
    if ToolHasFlag(tool, "IncludeBrowsers") {
        if CtrlActive(gCtrls["IncludeBrowsers"]) && gCtrls["IncludeBrowsers"].Value
            scope .= "Include browsers is checked, so Chrome, Edge, and Firefox are in this copy.`r`n`r`n"
        else
            scope .= "Include browsers is off, so Chrome, Edge, and Firefox are not in this copy.`r`n`r`n"
    }
    pop := Gui("+Owner" gGui.Hwnd " +AlwaysOnTop", ToolGet(tool, "Name", AppName))
    pop.SetFont("s9", "Segoe UI")
    pop.Add("Edit", "w520 r24 ReadOnly", scope body)
    btn := pop.Add("Button", "Default w80", "OK")
    btn.OnEvent("Click", (*) => pop.Destroy())
    pop.OnEvent("Escape", (*) => pop.Destroy())
    pop.OnEvent("Close", (*) => pop.Destroy())
    pop.Show()
}

OpenSelectedToolDocs(*) {
    global AppName
    url := ToolDocsUrl(SelectedTool())
    if (url = "") {
        MsgBox("No documentation URL for this tool.", AppName, "Icon!")
        return
    }
    Run(url)
}

BuildSwitches(tool, isScan, isCommands) {
    global gCtrls
    sw := []

    if ToolHasFlag(tool, "PositionalDry") {
        ; sccleaner: positional dry | 1
        if isScan
            sw.Push("dry")
        else
            sw.Push("1")
        ; no -Exit on this script
        out := ""
        for s in sw
            out .= " " s
        return out
    }

    if ToolHasFlag(tool, "CheckOnly") && isScan
        sw.Push("-CheckOnly")
    if ToolHasFlag(tool, "PupBlock") {
        if isScan
            sw.Push("-CheckOnly")
        else
            sw.Push("-Enable")
    }
    if ToolHasFlag(tool, "EolAudit") {
        if isScan
            sw.Push("-Action Measure")
        else
            sw.Push("-Action Watch")
    }
    if ToolHasFlag(tool, "EolAuditGpo") {
        sw.Push("-Action Watch")
        domain := Trim(gCtrls["AutomateDomain"].Value)
        targetOu := Trim(gCtrls["AutomateTargetOu"].Value)
        if (domain != "")
            sw.Push("-Domain '" StrReplace(domain, "'", "''") "'")
        if isScan
            sw.Push("-DryRun")
        else if (targetOu != "")
            sw.Push("-TargetOU '" StrReplace(targetOu, "'", "''") "'")
        else if CtrlActive(gCtrls["AutomateLinkToDomain"]) && gCtrls["AutomateLinkToDomain"].Value
            sw.Push("-LinkToDomain")
    }

    if ToolHasFlag(tool, "Remediate") && !isScan
        sw.Push("-Remediate")
    if ToolHasFlag(tool, "Reinstall") && !isScan
        sw.Push("-Reinstall")
    if CtrlActive(gCtrls["Detailed"]) && gCtrls["Detailed"].Value
        sw.Push("-Detailed")

    if ToolHasFlag(tool, "Delete") && !isScan
        sw.Push("-Delete")

    if ToolHasFlag(tool, "BackupsOnlyDefault") {
        sw.Push("-BackupsOnly")
        if CtrlActive(gCtrls["ClearAllBackupContent"]) && gCtrls["ClearAllBackupContent"].Value
            sw.Push("-ClearAllBackupContent")
    }

    if CtrlActive(gCtrls["Force"]) && gCtrls["Force"].Value
        sw.Push("-Force")
    if CtrlActive(gCtrls["ForceAppShutdown"]) && gCtrls["ForceAppShutdown"].Value
        sw.Push("-ForceAppShutdown")
    if CtrlActive(gCtrls["IncludeBrowsers"]) && gCtrls["IncludeBrowsers"].Value
        sw.Push("-IncludeBrowsers")
    if CtrlActive(gCtrls["Uninstall"]) && gCtrls["Uninstall"].Value
        sw.Push("-Uninstall")
    if CtrlActive(gCtrls["BlockReinstall"]) && gCtrls["BlockReinstall"].Value
        sw.Push("-BlockReinstall")
    if CtrlActive(gCtrls["RemoveSupportAssistant"]) && gCtrls["RemoveSupportAssistant"].Value
        sw.Push("-RemoveSupportAssistant")

    if ToolHasFlag(tool, "Vendor") && CtrlActive(gCtrls["Vendor"]) {
        vendor := gCtrls["Vendor"].Text
        if (vendor != "" && vendor != "All")
            sw.Push("-Vendor " vendor)
        secret := Trim(gCtrls["AvSecret"].Value)
        if (secret != "") {
            esc := StrReplace(secret, "'", "''")
            ; Password/keycode only applies when a single vendor is selected (not All).
            if (vendor = "Cylance")
                sw.Push("-CylancePassword '" esc "'")
            else if (vendor = "Webroot")
                sw.Push("-WebrootKeyCode '" esc "'")
        }
        if !isScan {
            hasForce := false
            for s in sw {
                if (s = "-Force") {
                    hasForce := true
                    break
                }
            }
            if !hasForce
                sw.Push("-Force")
        }
    }

    if ToolHasFlag(tool, "Product") && CtrlActive(gCtrls["Product"]) {
        prod := Trim(gCtrls["Product"].Value)
        if (prod != "") {
            if InStr(prod, " ") || InStr(prod, "+")
                sw.Push('-Product "' prod '"')
            else
                sw.Push("-Product " prod)
        }
    }

    if ToolHasFlag(tool, "ProductList") && CtrlActive(gCtrls["PupFamily"]) {
        fam := Trim(gCtrls["PupFamily"].Text)
        if (fam != "" && fam != "All on host" && fam != "All catalog")
            sw.Push("-Name " fam)
    }

    if ToolHasFlag(tool, "Domain") && CtrlActive(gCtrls["DomainController"]) {
        dc := Trim(gCtrls["DomainController"].Value)
        dom := Trim(gCtrls["Domain"].Value)
        if (dc != "")
            sw.Push("-DomainController '" StrReplace(dc, "'", "''") "'")
        if (dom != "")
            sw.Push("-Domain '" StrReplace(dom, "'", "''") "'")
    }

    if ToolHasFlag(tool, "ConnectSecure") && !isScan {
        company := Trim(gCtrls["CsCompanyId"].Value)
        envId := Trim(gCtrls["CsEnvironmentId"].Value)
        token := Trim(gCtrls["CsInstallToken"].Value)
        if (company != "")
            sw.Push("-CompanyId '" StrReplace(company, "'", "''") "'")
        if (envId != "")
            sw.Push("-EnvironmentId '" StrReplace(envId, "'", "''") "'")
        if (token != "")
            sw.Push("-InstallToken '" StrReplace(token, "'", "''") "'")
    }
    if ToolHasFlag(tool, "SkipIfRunning") && CtrlActive(gCtrls["SkipIfRunning"]) && gCtrls["SkipIfRunning"].Value
        sw.Push("-SkipIfRunning")
    if ToolHasFlag(tool, "ResetPlatform") && !isScan && CtrlActive(gCtrls["ResetPlatform"]) && gCtrls["ResetPlatform"].Value
        sw.Push("-ResetPlatform")
    if ToolHasFlag(tool, "AutoReboot") && !isScan && CtrlActive(gCtrls["AutoReboot"]) && gCtrls["AutoReboot"].Value
        sw.Push("-Reboot")
    if ToolHasFlag(tool, "AllowServer") && CtrlActive(gCtrls["AllowServer"]) && gCtrls["AllowServer"].Value
        sw.Push("-AllowServer")

    if ToolHasFlag(tool, "SentinelOneInstall") {
        token := Trim(gCtrls["S1Token"].Value)
        path := Trim(gCtrls["S1InstallerPath"].Value)
        url := Trim(gCtrls["S1InstallerUrl"].Value)
        if (token != "")
            sw.Push("-SiteToken '" StrReplace(token, "'", "''") "'")
        if (path != "")
            sw.Push("-InstallerPath '" StrReplace(path, "'", "''") "'")
        if (url != "")
            sw.Push("-InstallerUrl '" StrReplace(url, "'", "''") "'")
        if CtrlActive(gCtrls["S1Quiet"]) && gCtrls["S1Quiet"].Value
            sw.Push("-Quiet")
    }

    if ToolHasFlag(tool, "HuntressInstall") {
        acct := Trim(gCtrls["HuntressAccountKey"].Value)
        org := Trim(gCtrls["HuntressOrgKey"].Value)
        tags := Trim(gCtrls["HuntressTags"].Value)
        if (acct != "")
            sw.Push("-AccountKey '" StrReplace(acct, "'", "''") "'")
        if (org != "")
            sw.Push("-OrgKey '" StrReplace(org, "'", "''") "'")
        if (tags != "")
            sw.Push("-Tags '" StrReplace(tags, "'", "''") "'")
    }

    if ToolHasFlag(tool, "AutomateGpo") {
        server := Trim(gCtrls["AutomateServer"].Value)
        locId := Trim(gCtrls["AutomateLocationId"].Value)
        token := Trim(gCtrls["AutomateToken"].Value)
        client := Trim(gCtrls["AutomateClientName"].Value)
        locName := Trim(gCtrls["AutomateLocationName"].Value)
        domain := Trim(gCtrls["AutomateDomain"].Value)
        targetOu := Trim(gCtrls["AutomateTargetOu"].Value)
        if (server != "")
            sw.Push("-Server '" StrReplace(server, "'", "''") "'")
        if (locId != "")
            sw.Push("-LocationID " locId)
        if (token != "")
            sw.Push("-Token '" StrReplace(token, "'", "''") "'")
        if (client != "")
            sw.Push("-ClientName '" StrReplace(client, "'", "''") "'")
        if (locName != "")
            sw.Push("-LocationName '" StrReplace(locName, "'", "''") "'")
        if (domain != "")
            sw.Push("-Domain '" StrReplace(domain, "'", "''") "'")
        if isScan
            sw.Push("-DryRun")
        else if (targetOu != "")
            sw.Push("-TargetOU '" StrReplace(targetOu, "'", "''") "'")
        else if CtrlActive(gCtrls["AutomateLinkToDomain"]) && gCtrls["AutomateLinkToDomain"].Value
            sw.Push("-LinkToDomain")
    }

    if ToolHasFlag(tool, "ScreenConnectGpo") {
        msi := Trim(gCtrls["AutomateToken"].Value)
        client := Trim(gCtrls["AutomateClientName"].Value)
        domain := Trim(gCtrls["AutomateDomain"].Value)
        targetOu := Trim(gCtrls["AutomateTargetOu"].Value)
        if (msi != "")
            sw.Push("-MsiPath '" StrReplace(msi, "'", "''") "'")
        if (client != "")
            sw.Push("-ClientName '" StrReplace(client, "'", "''") "'")
        if (domain != "")
            sw.Push("-Domain '" StrReplace(domain, "'", "''") "'")
        if isScan
            sw.Push("-DryRun")
        else if (targetOu != "")
            sw.Push("-TargetOU '" StrReplace(targetOu, "'", "''") "'")
        else if CtrlActive(gCtrls["AutomateLinkToDomain"]) && gCtrls["AutomateLinkToDomain"].Value
            sw.Push("-LinkToDomain")
    }

    if ToolHasFlag(tool, "WebrootUninstallGpo") {
        domain := Trim(gCtrls["AutomateDomain"].Value)
        targetOu := Trim(gCtrls["AutomateTargetOu"].Value)
        keyCode := Trim(gCtrls["WebrootKeyCode"].Value)
        if (domain != "")
            sw.Push("-Domain '" StrReplace(domain, "'", "''") "'")
        if (keyCode != "")
            sw.Push("-KeyCode '" StrReplace(keyCode, "'", "''") "'")
        if isScan
            sw.Push("-DryRun")
        else if (targetOu != "")
            sw.Push("-TargetOU '" StrReplace(targetOu, "'", "''") "'")
        else if CtrlActive(gCtrls["AutomateLinkToDomain"]) && gCtrls["AutomateLinkToDomain"].Value
            sw.Push("-LinkToDomain")
    }

    if ToolHasFlag(tool, "AdReview") {
        target := Trim(gCtrls["AdTarget"].Value)
        days := Trim(gCtrls["AdInactiveDays"].Value)
        if (target != "")
            sw.Push("-ComputerName '" StrReplace(target, "'", "''") "'")
        if (days != "")
            sw.Push("-InactiveDays " days)
    }

    fetch := ToolGet(tool, "Fetch", "Contents")
    if (fetch = "Contents") {
        if isCommands
            sw.Push("-Exit")
        else if ToolHasFlag(tool, "NoExit")
            sw.Push("-NoExit")
    }

    out := ""
    for s in sw
        out .= " " s
    return out
}

; TLS 1.2 as numeric 3072 — [Net.SecurityProtocolType]::Tls12 is $null on PS 2.0
; (.NET only exposes Ssl3, Tls), which throws and leaves GitHub on TLS 1.0.
BootstrapTls() {
    return "try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}"
}

; ScreenConnect #!ps is often the 32-bit v2 engine. System32\powershell.exe then
; Wow64-redirects to the same 2.0 host. Probe SysNative (64-bit) first, then
; System32 / SysWOW64, and only relaunch an exe that reports Major >= 5.
BootstrapPs5Relaunch() {
    return "if($PSVersionTable.PSVersion.Major -lt 5){$exe=$null; foreach($c in @(`"$env:SystemRoot\SysNative\WindowsPowerShell\v1.0\powershell.exe`",`"$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe`",`"$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe`")){if(Test-Path -LiteralPath $c){try{$v=& $c -NoProfile -Command '$PSVersionTable.PSVersion.Major'}catch{$v=0}; if(($v -as [int]) -ge 5){$exe=$c; break}}}; if(-not $exe){throw 'PowerShell 5.1 required (this host has only 2.0). Install WMF 5.1.'}; & $exe -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path; exit $LASTEXITCODE}; "
}

DefaultHuntressRebootAt() {
    today1730 := SubStr(A_Now, 1, 8) "173000"
    if (DateDiff(today1730, A_Now, "Minutes") >= 5)
        return today1730
    return DateAdd(today1730, 1, "Days")
}

FormatHuntressRebootAt() {
    global gCtrls
    return FormatTime(gCtrls["HuntressRebootAt"].Value, "yyyy-MM-dd HH:mm")
}

BuildHuntressBody(isCommands) {
    global gCtrls
    if (CtrlActive(gCtrls["AutoReboot"]) && gCtrls["AutoReboot"].Value)
        return BuildHuntressScheduleBody(isCommands)
    return BuildHuntressInlineBody(isCommands)
}

BuildHuntressInlineBody(isCommands) {
    global gCtrls
    acct := StrReplace(Trim(gCtrls["HuntressAccountKey"].Value), "'", "''")
    if (acct = "")
        acct := StrReplace(LoadHuntressAccountKey(), "'", "''")
    org := StrReplace(Trim(gCtrls["HuntressOrgKey"].Value), "'", "''")
    tags := StrReplace(Trim(gCtrls["HuntressTags"].Value), "'", "''")
    force := CtrlActive(gCtrls["Force"]) && gCtrls["Force"].Value
    endSkip := isCommands ? "exit 0" : "return"
    endOk := isCommands ? "exit $p.ExitCode" : ""
    tls := BootstrapTls()
    wipe := ""
    skip := "if($svc){Write-Output ('Service HuntressAgent: '+[string]$svc.Status); Write-Output 'Huntress agent already present. Skipping. Check Rip and replace.'; " endSkip "}; Write-Output 'Service HuntressAgent: not found'; foreach($e in $exes){if($e -and (Test-Path -LiteralPath $e)){Write-Output ('Leftover '+$e+' (no service; continuing install)')}}; "
    if (force) {
        wipe := "Write-Output '=== Rip and replace (no reboot) ==='; foreach($n in @('HuntressRio','HuntressUpdater','HuntressAgent','Huntmon')){ Stop-Service $n -Force -EA SilentlyContinue }; $tk= if(Test-Path -LiteralPath ($env:SystemRoot+'\SysNative\taskkill.exe')){ $env:SystemRoot+'\SysNative\taskkill.exe' } else { $env:SystemRoot+'\System32\taskkill.exe' }; foreach($im in @('HuntressInstaller.exe','HuntressAgent.exe','HuntressUpdater.exe','HuntressRio.exe','Huntmon.exe')){ Write-Output ($tk+' /F /T /IM '+$im); & $tk /F /T /IM $im }; $dirs=@((Join-Path $env:ProgramFiles 'Huntress'),(Join-Path ${env:ProgramFiles(x86)} 'Huntress')); foreach($d in $dirs){ $u=Join-Path $d 'Uninstall.exe'; if(Test-Path -LiteralPath $u){ Write-Output ('Running '+$u+' /S'); $up=Start-Process -FilePath $u -ArgumentList '/S' -PassThru; $w=0; while($up -and -not $up.HasExited -and $w -lt 45){ Start-Sleep -Seconds 3; $w+=3; try{$up.Refresh()}catch{} } } }; Start-Sleep -Seconds 2; foreach($im in @('HuntressInstaller.exe','HuntressAgent.exe','HuntressUpdater.exe','HuntressRio.exe')){ & $tk /F /T /IM $im | Out-Null }; $left=@(Get-Process | Where-Object { $_.Name -like '*Huntress*' -and -not $_.HasExited }); if($left.Count -gt 0){ $left | ForEach-Object { Write-Output ('STILL ALIVE '+$_.Name+' PID '+[string]$_.Id) }; Write-Output 'Live Huntress process still running; install may hang. Use Schedule option or reboot.' }; foreach($d in $dirs){ if(Test-Path -LiteralPath $d){ Remove-Item -LiteralPath $d -Recurse -Force -EA SilentlyContinue; Write-Output ('Removed '+$d) } }; foreach($k in @('HKLM:\SOFTWARE\Huntress Labs','HKLM:\SOFTWARE\WOW6432Node\Huntress Labs')){ if(Test-Path $k){ Remove-Item $k -Recurse -Force -EA SilentlyContinue; Write-Output ('Removed '+$k) } }; foreach($n in @('HuntressRio','HuntressUpdater','HuntressAgent','Huntmon')){ sc.exe delete $n | Out-Null }; Write-Output 'Wipe done; installing in this session (no reboot)'; "
        skip := "if($svc){Write-Output ('Service HuntressAgent: '+[string]$svc.Status+' (will wipe)')}; "
    }
    head := tls "; $acct='" acct "'; $org='" org "'; $tags='" tags "'; if(-not $acct -or $acct.Length -ne 32){throw ('Bad Huntress account key length '+[string]$acct.Length+' (need 32).')}; $svc=Get-Service -Name HuntressAgent -EA SilentlyContinue; $exes=@((Join-Path $env:ProgramFiles 'Huntress\HuntressAgent.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Huntress\HuntressAgent.exe')); "
    install := "$out=Join-Path $env:TEMP 'HuntressInstaller.exe'; Write-Output ('Downloading Huntress installer (update.huntress.io, key length '+[string]$acct.Length+')'); $wc=New-Object Net.WebClient; $wc.DownloadFile(('https://update.huntress.io/download/'+$acct+'/HuntressInstaller.exe'),$out); if(-not(Test-Path -LiteralPath $out) -or ((Get-Item -LiteralPath $out).Length -eq 0)){throw 'Huntress download failed or 0 bytes'}; Write-Output ('Downloaded '+[string]((Get-Item -LiteralPath $out).Length)+' bytes'); $q=[char]34; $a=('/ACCT_KEY='+$q+$acct+$q+' /ORG_KEY='+$q+$org+$q); if($tags){$a+=' /TAGS='+$q+$tags+$q}; $a+=' /S'; Write-Output 'Installing with official /ACCT_KEY= (heartbeat every 10s; no reboot)'; $p=Start-Process -FilePath $out -ArgumentList $a -PassThru; if(-not $p){throw 'Start-Process returned no installer process'}; Write-Output ('Installer PID '+[string]$p.Id); $n=0; while(-not $p.HasExited -and $n -lt 240){ Start-Sleep -Seconds 10; $n+=10; try{$p.Refresh()}catch{}; Write-Output ('Installing... '+[string]$n+'s PID '+[string]$p.Id) }; $log='C:\Windows\Temp\HuntressInstaller.log'; if(-not $p.HasExited){ Write-Output 'Installer still running after 240s (not killed). Check services and log.'; if(Test-Path -LiteralPath $log){ Write-Output ('--- '+$log+' ---'); Get-Content -LiteralPath $log | Select-Object -Last 20 | ForEach-Object { Write-Output $_ } }; Get-Service -Name HuntressAgent -EA SilentlyContinue | ForEach-Object { Write-Output ('Service HuntressAgent: '+[string]$_.Status) }; "
    tail := " }; Write-Output ('Installer exit '+[string]$p.ExitCode); if(Test-Path -LiteralPath $log){ Write-Output ('--- '+$log+' ---'); Get-Content -LiteralPath $log | Select-Object -Last 15 | ForEach-Object { Write-Output $_ } }; Get-Service -Name HuntressAgent -EA SilentlyContinue | ForEach-Object { Write-Output ('Service HuntressAgent: '+[string]$_.Status) }; Remove-Item -LiteralPath $out -Force -EA SilentlyContinue; "
    return head wipe skip install endSkip tail endOk
}

BuildHuntressScheduleBody(isCommands) {
    global gCtrls
    acct := StrReplace(Trim(gCtrls["HuntressAccountKey"].Value), "'", "''")
    if (acct = "")
        acct := StrReplace(LoadHuntressAccountKey(), "'", "''")
    org := StrReplace(Trim(gCtrls["HuntressOrgKey"].Value), "'", "''")
    tags := StrReplace(Trim(gCtrls["HuntressTags"].Value), "'", "''")
    ; Schedule is exclusive of the Force checkbox; the SYSTEM job always wipes.
    forceLit := "$true"
    rebootAt := StrReplace(FormatHuntressRebootAt(), "'", "''")
    end := isCommands ? "exit 0" : "return"
    tls := BootstrapTls()
    ; No nested double-quotes — AHK v2 treats "" as string end.
    p := tls
    p .= "; $acct='" acct "'; $org='" org "'; $tags='" tags "'; $force=" forceLit
    p .= "; $rebootAt='" rebootAt "'"
    p .= "; if(-not $acct -or $acct.Length -ne 32){throw 'Bad Huntress account key length'}"
    p .= "; if(-not $rebootAt){throw 'Set $rebootAt to host-local yyyy-MM-dd HH:mm'}"
    p .= "; $when=Get-Date $rebootAt"
    p .= "; $sec=[int][math]::Ceiling(($when-(Get-Date)).TotalSeconds)"
    p .= "; if($sec -lt 60){throw ('Reboot time is in the past or <60s: '+$rebootAt+' host now '+(Get-Date -Format 'yyyy-MM-dd HH:mm'))}"
    p .= "; if(-not $force){ $svc=Get-Service -Name HuntressAgent -EA SilentlyContinue; if($svc){Write-Output ('Already installed: '+[string]$svc.Status); " end "} }"
    p .= "; $job='C:\Windows\Temp\Huntress-SC-Install.ps1'; $clean='C:\Windows\Temp\Huntress-SC-Cleanup.ps1'"
    p .= "; $L=@()"
    p .= "; $L+='try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}'"
    p .= "; $L+='function L($m){ Add-Content -LiteralPath C:\Windows\Temp\Huntress-SC-Install.log -Value ((Get-Date -Format s)+'' ''+$m) }'"
    p .= "; $L+='L ''Huntress-SC-Install start'''"
    p .= "; $L+=('$acct='''+$acct+'''')"
    p .= "; $L+=('$org='''+$org+'''')"
    p .= "; $L+=('$tags='''+$tags+'''')"
    p .= "; $L+=" Chr(39) "$force=" forceLit Chr(39)
    p .= "; $L+='if($force){ L ''wipe''; foreach($n in @(''HuntressRio'',''HuntressUpdater'',''HuntressAgent'',''Huntmon'')){ Stop-Service $n -Force -EA SilentlyContinue }; $tk= if(Test-Path ($env:SystemRoot+''\SysNative\taskkill.exe'')){ $env:SystemRoot+''\SysNative\taskkill.exe'' } else { $env:SystemRoot+''\System32\taskkill.exe'' }; foreach($im in @(''HuntressInstaller.exe'',''HuntressAgent.exe'',''HuntressUpdater.exe'',''HuntressRio.exe'')){ & $tk /F /T /IM $im }; foreach($d in @((Join-Path $env:ProgramFiles ''Huntress''),(Join-Path ${env:ProgramFiles(x86)} ''Huntress''))){ $u=Join-Path $d ''Uninstall.exe''; if(Test-Path $u){ Start-Process $u -ArgumentList ''/S'' -Wait -EA SilentlyContinue }; if(Test-Path $d){ Remove-Item $d -Recurse -Force -EA SilentlyContinue } }; foreach($k in @(''HKLM:\SOFTWARE\Huntress Labs'',''HKLM:\SOFTWARE\WOW6432Node\Huntress Labs'')){ if(Test-Path $k){ Remove-Item $k -Recurse -Force -EA SilentlyContinue } }; foreach($n in @(''HuntressRio'',''HuntressUpdater'',''HuntressAgent'',''Huntmon'')){ sc.exe delete $n | Out-Null }; L ''wipe done'' }'"
    p .= "; $L+='$out=Join-Path $env:TEMP ''HuntressInstaller.exe'''"
    p .= "; $L+='L ''download'''"
    p .= "; $L+='$wc=New-Object Net.WebClient'"
    p .= "; $L+='$wc.DownloadFile((''https://update.huntress.io/download/''+$acct+''/HuntressInstaller.exe''),$out)'"
    p .= "; $L+='if(-not(Test-Path $out) -or ((Get-Item $out).Length -eq 0)){ L ''download failed''; exit 4 }'"
    p .= "; $L+='L (''downloaded ''+[string]((Get-Item $out).Length))'"
    p .= "; $L+='$q=[char]34; $a=(''/ACCT_KEY=''+$q+$acct+$q+'' /ORG_KEY=''+$q+$org+$q); if($tags){$a+='' /TAGS=''+$q+$tags+$q}; $a+='' /S'''"
    p .= "; $L+='L ''start installer'''"
    p .= "; $L+='$p=Start-Process -FilePath $out -ArgumentList $a -PassThru'"
    p .= "; $L+='$n=0; while($p -and -not $p.HasExited -and $n -lt 900){ Start-Sleep 15; $n+=15; try{$p.Refresh()}catch{}; L (''installing ''+[string]$n+''s'') }'"
    p .= "; $L+='if($p -and -not $p.HasExited){ L ''installer still running after 900s'' } elseif($p){ L (''installer exit ''+[string]$p.ExitCode) }'"
    p .= "; $L+='Get-Service HuntressAgent -EA SilentlyContinue | ForEach-Object { L (''service ''+[string]$_.Status) }'"
    p .= "; $L+='L ''Huntress-SC-Install end'''"
    p .= "; Set-Content -LiteralPath $job -Value $L -Encoding ASCII"
    p .= "; $C=@('Start-Sleep -Seconds 1800','Get-Process HuntressInstaller -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue','Remove-Item -LiteralPath C:\Windows\Temp\HuntressInstaller.exe -Force -EA SilentlyContinue','Remove-Item -LiteralPath C:\Windows\Temp\Huntress-SC-Install.ps1 -Force -EA SilentlyContinue','schtasks.exe /Delete /TN HuntressSC-Install /F','schtasks.exe /Delete /TN HuntressSC-Cleanup /F','Remove-Item -LiteralPath C:\Windows\Temp\Huntress-SC-Cleanup.ps1 -Force -EA SilentlyContinue')"
    p .= "; Set-Content -LiteralPath $clean -Value $C -Encoding ASCII"
    p .= "; $ps= if(Test-Path -LiteralPath ($env:SystemRoot+'\SysNative\WindowsPowerShell\v1.0\powershell.exe')){ $env:SystemRoot+'\SysNative\WindowsPowerShell\v1.0\powershell.exe' } else { $env:SystemRoot+'\System32\WindowsPowerShell\v1.0\powershell.exe' }"
    p .= "; $trInstall=($ps+' -NoProfile -ExecutionPolicy Bypass -File '+$job)"
    p .= "; $trClean=($ps+' -NoProfile -ExecutionPolicy Bypass -File '+$clean)"
    p .= "; schtasks.exe /Create /TN HuntressSC-Install /RU SYSTEM /RL HIGHEST /SC ONCE /ST 23:59 /F /TR $trInstall"
    p .= "; schtasks.exe /Create /TN HuntressSC-Cleanup /RU SYSTEM /RL HIGHEST /SC ONCE /ST 23:59 /F /TR $trClean"
    p .= "; schtasks.exe /Run /TN HuntressSC-Install"
    p .= "; schtasks.exe /Run /TN HuntressSC-Cleanup"
    p .= "; shutdown.exe /r /t $sec /c ('Huntress SC reboot '+$rebootAt)"
    p .= "; Write-Output ('Scheduled HuntressSC-Install + Cleanup (+30 min). Reboot at '+$rebootAt+' (in '+[string]$sec+'s). Abort: shutdown /a. Log: C:\Windows\Temp\Huntress-SC-Install.log'); "
    p .= end
    return p
}

SentinelOnePassphraseOk(pass) {
    return Trim(pass) != ""
}

BuildSentinelOneUnloadBody() {
    global gCtrls
    pass := RegExReplace(Trim(gCtrls["S1Passphrase"].Value), "\s+", " ")
    pass := StrReplace(pass, "'", "''")
    return "$ctl=$null; $svc=Get-CimInstance Win32_Service -Filter " Chr(34) "Name='SentinelAgent'" Chr(34) " -EA SilentlyContinue; if($svc.PathName){ $raw=$svc.PathName; if($raw.StartsWith([char]34)){ $exe=$raw.Split([char]34)[1] } else { $exe=($raw -split ' ')[0] }; $cand=Join-Path (Split-Path -Parent $exe) 'SentinelCtl.exe'; if(Test-Path -LiteralPath $cand){ $ctl=Get-Item -LiteralPath $cand } }; if(-not $ctl){ $ctl=Get-ChildItem -LiteralPath 'C:\Program Files\SentinelOne' -Filter SentinelCtl.exe -Recurse -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }; if(-not $ctl){ throw 'SentinelCtl.exe was not found' }; & $ctl.FullName unload -slam -k '" pass "'; if($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0){ exit $LASTEXITCODE }"
}

BuildRemoteOpsBody(tool, ps5, tls) {
    global gCtrls
    portal := StrReplace(RTrim(Trim(gCtrls["RoPortal"].Value), "/"), "'", "''")
    if ToolHasFlag(tool, "RemoteOpsEnroll") {
        token := StrReplace(Trim(gCtrls["RoToken"].Value), "'", "''")
        return ps5 tls "; irm '" portal "/s.ps1' | iex; Start-RemoteOps -Token '" token "'"
    }
    return ps5 tls "; $f=Join-Path $env:ProgramData 'RemoteOps\remoteops-remove.ps1'; try{$s=irm '" portal "/remoteops-remove.ps1'}catch{$s=$null}; if($s){iex $s} elseif(Test-Path -LiteralPath $f){& $f} else {throw 'Portal unreachable and no local remoteops-remove.ps1'}"
}

ShellSingleQuote(value) {
    return "'" StrReplace(value, "'", "'\''") "'"
}

; Portal shell commands for Mac / Linux / ARM / ARM-32. Windows stays on the
; PowerShell installer. IDs and the install token are quoted; nothing is stored.
BuildConnectSecureShellSnippet(isCommands) {
    global gCtrls, MaxLength
    os := gCtrls["CsOs"].Text
    company := ShellSingleQuote(Trim(gCtrls["CsCompanyId"].Value))
    envId := ShellSingleQuote(Trim(gCtrls["CsEnvironmentId"].Value))
    token := ShellSingleQuote(Trim(gCtrls["CsInstallToken"].Value))
    install := " -c " company " -e " envId " -j " token " -i"
    if (os = "Mac")
        body := "macurl=$(curl -L -s -g `"https://configuration.myconnectsecure.com/api/v4/configuration/agentlink?ostype=darwinpkg`" | tr -d '`"'); sudo curl $macurl -o cybercnsagent_darwin.pkg; sudo installer -pkg ./cybercnsagent_darwin.pkg -target /; sudo /opt/install.sh" install
    else if (os = "Linux")
        body := "linuxurl=$(curl -L -s -g `"https://configuration.myconnectsecure.com/api/v4/configuration/agentlink?ostype=linux`" | tr -d '`"'); curl $linuxurl -o cybercnsagent_linux; chmod +x cybercnsagent_linux; sudo ./cybercnsagent_linux" install
    else if (os = "ARM-32")
        body := "armurl=$(curl -L -s -g `"https://configuration.myconnectsecure.com/api/v4/configuration/agentlink?ostype=arm32`" | tr -d '`"'); curl $armurl -o cybercnsagent_arm; chmod +x cybercnsagent_arm; sudo ./cybercnsagent_arm" install
    else
        body := "armurl=$(curl -L -s -g `"https://configuration.myconnectsecure.com/api/v4/configuration/agentlink?ostype=arm`" | tr -d '`"'); curl $armurl -o cybercnsagent_arm; chmod +x cybercnsagent_arm; sudo ./cybercnsagent_arm" install
    if isCommands
        return "#!sh`n#timeout=600000`n#maxlength=" MaxLength "`n" body "`n# NOTE: Install token is embedded in this clipboard snippet only. Do not paste into tickets/git. Run as root."
    return body
}

BuildSnippet(tool, isScan, isCommands) {
    global DefaultOwner, DefaultRepo, DefaultRef, MaxLength, gCtrls
    if ToolHasFlag(tool, "ConnectSecure") && ToolHasFlag(tool, "RunOnly") {
        csOs := gCtrls["CsOs"].Text
        if (csOs != "" && csOs != "Windows")
            return BuildConnectSecureShellSnippet(isCommands)
    }
    timeout := isScan ? tool["TimeoutScan"] : tool["TimeoutUpdate"]
    fetch := ToolGet(tool, "Fetch", "Contents")
    tls := BootstrapTls()
    ps5 := isCommands ? BootstrapPs5Relaunch() : ""

    ; Huntress: no GitHub / no #Requires 5.1. Download the vendor EXE with
    ; WebClient so ScreenConnect's v2 engine can still install the agent.
    if ToolHasFlag(tool, "HuntressInstall") {
        body := BuildHuntressBody(isCommands)
    } else if ToolHasFlag(tool, "SentinelOneUnload") {
        body := BuildSentinelOneUnloadBody()
    } else if ToolHasFlag(tool, "RemoteOpsEnroll") || ToolHasFlag(tool, "RemoteOpsRemove") {
        body := BuildRemoteOpsBody(tool, ps5, tls)
    } else if (fetch = "Inline") {
        scanBody := ToolGet(tool, "ScanBody", "")
        applyBody := ToolGet(tool, "ApplyBody", "")
        if isScan && (scanBody != "")
            body := scanBody
        else if !isScan && (applyBody != "")
            body := applyBody
        else
            body := ToolGet(tool, "Body", "")
    } else if (fetch = "DownloadExe") {
        url := ToolGet(tool, "Url", "")
        outFile := ToolGet(tool, "OutFile", "C:\Windows\Temp\tool.exe")
        argList := ToolGet(tool, "ExeArgList", "")
        body := ps5 "$ProgressPreference='SilentlyContinue'; " tls "; $url='" url "'; $out='" outFile "'; Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing; Start-Process -FilePath $out -ArgumentList " argList " -Wait"
    } else {
        switches := BuildSwitches(tool, isScan, isCommands)
        defaultArgs := ToolGet(tool, "DefaultArgs", "")
        if (defaultArgs != "")
            switches .= " " defaultArgs

        if (fetch = "IrmOutFile") {
            ; Download to %TEMP% and run with a one-time Process-scoped execution policy exception.
            owner := ToolGet(tool, "Owner", DefaultOwner)
            repo := ToolGet(tool, "Repo", "")
            script := tool["Script"]
            tempName := ToolGet(tool, "TempName", script)
            ver := ToolGet(tool, "UaVer", "1.0.0")
            url := ToolGet(tool, "Url", "")
            if (url = "")
                url := "https://raw.githubusercontent.com/" owner "/" repo "/main/" script
            if ToolHasFlag(tool, "CacheBust")
                url .= "?v=" ver
            body := ps5 "Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force; " tls "; $ProgressPreference='SilentlyContinue'; $out=Join-Path $env:TEMP '" tempName "'; Invoke-RestMethod -Uri '" url "' -OutFile $out; & $out" switches
        } else if (fetch = "Raw") {
            owner := ToolGet(tool, "Owner", DefaultOwner)
            repo := ToolGet(tool, "Repo", "")
            script := tool["Script"]
            ver := ToolGet(tool, "UaVer", "1.0.0")
            url := ToolGet(tool, "Url", "")
            if (url = "")
                url := "https://raw.githubusercontent.com/" owner "/" repo "/main/" script
            if ToolHasFlag(tool, "CacheBust")
                url .= "?v=" ver
            body := ps5 tls "; $url='" url "'; $script=(Invoke-WebRequest -Uri $url -UseBasicParsing).Content; & ([ScriptBlock]::Create($script))" switches
        } else {
            uaPrefix := ToolGet(tool, "UaPrefix", "")
            if (uaPrefix = "")
                uaPrefix := ToolGet(tool, "Repo", DefaultRepo)
            ua := uaPrefix "/" ToolGet(tool, "UaVer", "1.0.0")
            owner := ToolGet(tool, "Owner", DefaultOwner)
            repo := ToolGet(tool, "Repo", DefaultRepo)
            if (repo = "")
                repo := DefaultRepo
            path := ToolGet(tool, "Path", "")
            script := tool["Script"]
            if (path != "")
                url := "https://api.github.com/repos/" owner "/" repo "/contents/" path "/" script "?ref=" DefaultRef
            else
                url := "https://api.github.com/repos/" owner "/" repo "/contents/" script "?ref=" DefaultRef
            body := ps5 "$ProgressPreference='SilentlyContinue'; " tls "; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','" ua "'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('" url "'); if ($script -match '(?i)<html|github.com/login|&redirect') { throw 'Download returned HTML, not a script.' }; & ([scriptblock]::Create($script))" switches
        }
    }

    noteLine := ""
    clipNote := ToolGet(tool, "ClipboardNote", "")
    ; Commands #!ps can take a trailing # comment. The PowerShell one-liner is a single PS
    ; line — a long NOTE wraps in the console and gets mashed into the prompt.
    if isCommands && (clipNote != "") {
        if ToolHasFlag(tool, "AlwaysNote")
            noteLine := "`n# " clipNote
        else if ToolHasFlag(tool, "RebootAdvisory") && !isScan
            noteLine := "`n# " clipNote
    }

    if isCommands
        return "#!ps`n#timeout=" timeout "`n#maxlength=" MaxLength "`n" body noteLine
    return body
}

DescribeSelection(tool, isScan) {
    global gCtrls
    mode := "Scan only"
    if ToolHasFlag(tool, "RunOnly") {
        if ToolHasFlag(tool, "SentinelOneInstall")
            mode := "Silent install"
        else if ToolHasFlag(tool, "SentinelOneUnload")
            mode := "Unload agent (passphrase)"
        else if ToolHasFlag(tool, "HuntressInstall") {
            if (CtrlActive(gCtrls["AutoReboot"]) && gCtrls["AutoReboot"].Value)
                mode := "Scheduled install + reboot " FormatHuntressRebootAt()
            else if (CtrlActive(gCtrls["Force"]) && gCtrls["Force"].Value)
                mode := "Rip and replace"
            else
                mode := "Silent install"
        }
        else if ToolHasFlag(tool, "ConnectSecure") {
            if (CtrlActive(gCtrls["CsOs"]) && gCtrls["CsOs"].Text != "" && gCtrls["CsOs"].Text != "Windows")
                mode := "Silent install (" gCtrls["CsOs"].Text ")"
            else
                mode := "Silent install"
        }
        else if (ToolGet(tool, "Fetch", "") = "Inline")
            mode := "Run command"
        else if InStr(ToolGet(tool, "TempName", ""), "HPbloatware")
            mode := "Remove HP bloat"
        else if InStr(ToolGet(tool, "Path", ""), "EntraIntuneEvidence")
            mode := "Export evidence"
        else if ToolHasFlag(tool, "AdReview")
            mode := "AD review of " Trim(gCtrls["AdTarget"].Value)
        else
            mode := "Download and run"
    } else if ToolHasFlag(tool, "ScanOnly") && (ToolGet(tool, "Fetch", "") = "Inline")
        mode := "Check pending reboot"
    else if ToolHasFlag(tool, "ScanOnly") && (ToolGet(tool, "Fetch", "") = "IrmOutFile")
        mode := "Collect / run"
    else if isScan && ToolHasFlag(tool, "EolAudit")
        mode := "Measure log space"
    if !isScan && !ToolHasFlag(tool, "RunOnly") {
        if ToolHasFlag(tool, "EolAudit")
            mode := "Audit sentinels"
        else if ToolHasFlag(tool, "Delete") || ToolHasFlag(tool, "PositionalDry")
            mode := "Remove"
        else if ToolHasFlag(tool, "Remediate")
            mode := "Clean up"
        else
            mode := "Apply updates"
    }
    if InStr(ToolGet(tool, "Path", ""), "WindowsDefender") {
        if isScan
            mode := "Check RTP + services"
        else
            mode := "Repair Defender"
    }
    if InStr(ToolGet(tool, "Path", ""), "WindowsUpdate") {
        if InStr(ToolGet(tool, "DefaultArgs", ""), "-Firmware") {
            if isScan
                mode := "Scan BIOS / firmware"
            else
                mode := "Install firmware"
        } else {
            if isScan
                mode := "Scan + pre-check"
            else
                mode := "Install"
        }
    }
    if InStr(ToolGet(tool, "Path", ""), "HpImageAssistant") {
        if isScan
            mode := "List unattended SoftPaqs"
        else
            mode := "Install unattended SoftPaqs"
    }
    if InStr(ToolGet(tool, "Path", ""), "OutlookDisableCache") {
        if isScan
            mode := "Scan profiles and cache"
        else
            mode := "Force online mode and delete cache"
    }
    if InStr(ToolGet(tool, "Path", ""), "WinVerifyTrustPadding") {
        if isScan
            mode := "Check padding registry"
        else
            mode := "Enable strict signature check"
    }
    if InStr(ToolGet(tool, "Path", ""), "SpeculativeStoreBypass") {
        if isScan
            mode := "Check SSBD mitigation"
        else
            mode := "Enable SSBD mitigation"
    }
    if InStr(ToolGet(tool, "Path", ""), "PowerShellV2Disable") {
        mode := "Disable PowerShell 2.0"
    }
    if ToolHasFlag(tool, "PowerIdle") {
        if isScan
            mode := "Show plugged-in sleep and hibernate"
        else
            mode := "Never sleep or hibernate on AC"
    }
    if ToolHasFlag(tool, "FastStartup") {
        if isScan
            mode := "Show Fast Startup"
        else
            mode := "Turn Fast Startup off"
    }
    if ToolHasFlag(tool, "Reinstall") {
        if isScan
            mode := "Scan local config"
        else
            mode := "Reinstall from this PC"
    } else if InStr(ToolGet(tool, "Path", ""), "AutomateUninstall") {
        if isScan
            mode := "Scan agent"
        else
            mode := "Uninstall agent"
    }
    if ToolHasFlag(tool, "AutomateGpo") {
        if isScan
            mode := "Dry-run transform"
        else if (Trim(gCtrls["AutomateTargetOu"].Value) != "")
            mode := "Stage + GPO to OU"
        else if CtrlActive(gCtrls["AutomateLinkToDomain"]) && gCtrls["AutomateLinkToDomain"].Value
            mode := "Stage + GPO (domain link)"
        else
            mode := "Stage + create GPO (unlinked)"
    }
    if ToolHasFlag(tool, "WebrootUninstallGpo") {
        if isScan
            mode := "Dry-run GPO script"
        else if (Trim(gCtrls["AutomateTargetOu"].Value) != "")
            mode := "Create GPO to OU"
        else if CtrlActive(gCtrls["AutomateLinkToDomain"]) && gCtrls["AutomateLinkToDomain"].Value
            mode := "Create GPO (domain link)"
        else
            mode := "Create GPO (unlinked)"
    }
    if ToolHasFlag(tool, "PupBlock") {
        if isScan
            mode := "List program names"
        else
            mode := "Block programs and warn"
    }
    if ToolHasFlag(tool, "EolAuditGpo") {
        if isScan
            mode := "Dry-run GPO"
        else if (Trim(gCtrls["AutomateTargetOu"].Value) != "")
            mode := "Download + GPO to OU"
        else if CtrlActive(gCtrls["AutomateLinkToDomain"]) && gCtrls["AutomateLinkToDomain"].Value
            mode := "Download + GPO (domain link)"
        else
            mode := "Download + create GPO (unlinked)"
    }
    parts := [tool["Name"], mode]
    if CtrlActive(gCtrls["Force"]) && gCtrls["Force"].Value
        parts.Push("Force")
    if CtrlActive(gCtrls["ForceAppShutdown"]) && gCtrls["ForceAppShutdown"].Value
        parts.Push("Close Office")
    if CtrlActive(gCtrls["IncludeBrowsers"]) && gCtrls["IncludeBrowsers"].Value
        parts.Push("Browsers")
    if CtrlActive(gCtrls["Uninstall"]) && gCtrls["Uninstall"].Value
        parts.Push("Uninstall HPSA")
    if CtrlActive(gCtrls["Detailed"]) && gCtrls["Detailed"].Value
        parts.Push("Detailed")
    if CtrlActive(gCtrls["ClearAllBackupContent"]) && gCtrls["ClearAllBackupContent"].Value
        parts.Push("Clear all Backup")
    if CtrlActive(gCtrls["BlockReinstall"]) && gCtrls["BlockReinstall"].Value
        parts.Push("Block reinstall")
    if CtrlActive(gCtrls["RemoveSupportAssistant"]) && gCtrls["RemoveSupportAssistant"].Value
        parts.Push("Remove HPSA too")
    if CtrlActive(gCtrls["SkipIfRunning"]) && gCtrls["SkipIfRunning"].Value
        parts.Push("Only if not running")
    if CtrlActive(gCtrls["ResetPlatform"]) && gCtrls["ResetPlatform"].Value
        parts.Push("ResetPlatform")
    if CtrlActive(gCtrls["AutoReboot"]) && gCtrls["AutoReboot"].Value && !ToolHasFlag(tool, "HuntressInstall")
        parts.Push("Auto reboot")
    if CtrlActive(gCtrls["AllowServer"]) && gCtrls["AllowServer"].Value
        parts.Push("Allow Server")
    if ToolHasFlag(tool, "BackupsOnlyDefault") {
        if CtrlActive(gCtrls["ClearAllBackupContent"]) && gCtrls["ClearAllBackupContent"].Value
            parts.Push("All Backup content")
        else
            parts.Push("CW/SC in Backup")
    }
    if CtrlActive(gCtrls["Vendor"])
        parts.Push(gCtrls["Vendor"].Text)
    if CtrlActive(gCtrls["Product"]) {
        prod := Trim(gCtrls["Product"].Value)
        if prod != ""
            parts.Push("Product=" prod)
    }
    if CtrlActive(gCtrls["PupFamily"]) {
        fam := Trim(gCtrls["PupFamily"].Text)
        if (fam != "")
            parts.Push("Family=" fam)
    }
    if CtrlActive(gCtrls["CsOs"])
        parts.Push(gCtrls["CsOs"].Text)
    if ToolHasFlag(tool, "SentinelOneInstall") && CtrlActive(gCtrls["S1InstallerUrl"]) {
        if (Trim(gCtrls["S1InstallerUrl"].Value) != "")
            parts.Push("Download+install")
    }
    text := ""
    for i, p in parts {
        if i > 1
            text .= " · "
        text .= p
    }
    return text
}

DoCopy(*) {
    global gCtrls, AppName, gGui
    if gGui
        gGui.Opt("+OwnDialogs")
    tool := SelectedTool()
    if ToolHasFlag(tool, "Help") {
        gCtrls["Status"].Value := "Select a tool from a category, then Copy."
        return
    }
    if ToolHasFlag(tool, "AllowServer") && CtrlActive(gCtrls["AllowServer"]) && gCtrls["AllowServer"].Value {
        answer := MsgBox("This command will run Windows Update on a Windows Server or domain controller.`n`nWithout this confirmation the script exits and changes nothing on a server.`n`nCopy it with -AllowServer?", AppName, "YesNo Icon! Default2")
        if (answer != "Yes") {
            gCtrls["Status"].Value := "Not copied. Server confirmation was declined."
            return
        }
    }
    if ToolHasFlag(tool, "ScanOnly")
        gCtrls["ModeScan"].Value := 1
    if ToolHasFlag(tool, "RunOnly")
        gCtrls["ModeUpdate"].Value := 1
    isScan := gCtrls["ModeScan"].Value
    isCommands := gCtrls["FmtCommands"].Value
    if ToolHasFlag(tool, "BackstageOnly")
        isCommands := false

    if ToolHasFlag(tool, "ConnectSecure") && !isScan {
        if (Trim(gCtrls["CsInstallScript"].Value) != "" && !ApplyConnectSecureInstallScript(true)) {
            gCtrls["Status"].Value := "Not copied. Could not read -c, -e, and -j from the install script."
            MsgBox("Could not find -c, -e, and -j in that install script.`nPaste the portal PowerShell command, or clear the script box and fill the three fields.", AppName, "Icon!")
            return
        }
        if (Trim(gCtrls["CsCompanyId"].Value) = "" || Trim(gCtrls["CsEnvironmentId"].Value) = "" || Trim(gCtrls["CsInstallToken"].Value) = "") {
            gCtrls["Status"].Value := "Not copied. Needs Company ID, Environment ID, and Install Token."
            MsgBox("Paste the official install script, or fill Company ID, Environment ID, and Install Token.`nNothing is saved in the launcher.", AppName, "Icon!")
            return
        }
    }
    if ToolHasFlag(tool, "SentinelOneUnload") {
        if !SentinelOnePassphraseOk(gCtrls["S1Passphrase"].Value) {
            MsgBox("Enter the SentinelOne uninstall passphrase (nothing is saved), then copy again.", AppName, "Icon!")
            return
        }
    }
    if ToolHasFlag(tool, "SentinelOneInstall") {
        if (Trim(gCtrls["S1Token"].Value) = "") {
            MsgBox("Paste the SentinelOne site/group token (nothing is saved), then copy again.", AppName, "Icon!")
            return
        }
        if (Trim(gCtrls["S1InstallerPath"].Value) = "") {
            MsgBox("Set the installer path on the endpoint (EXE or MSI).", AppName, "Icon!")
            return
        }
    }
    if ToolHasFlag(tool, "HuntressInstall") {
        acct := Trim(gCtrls["HuntressAccountKey"].Value)
        if (acct = "")
            acct := LoadHuntressAccountKey()
        if (acct = "" || StrLen(acct) != 32 || Trim(gCtrls["HuntressOrgKey"].Value) = "") {
            MsgBox("Needs a 32-character Huntress Account Key and an Organization Key.`nAccount key is built in; set the org key (client short name).", AppName, "Icon!")
            return
        }
        if (CtrlActive(gCtrls["AutoReboot"]) && gCtrls["AutoReboot"].Value && DateDiff(gCtrls["HuntressRebootAt"].Value, A_Now, "Seconds") < 60) {
            MsgBox("Pick a reboot date/time at least 1 minute in the future (endpoint local time).", AppName, "Icon!")
            return
        }
    }
    if ToolHasFlag(tool, "AutomateGpo") {
        server := Trim(gCtrls["AutomateServer"].Value)
        locId := Trim(gCtrls["AutomateLocationId"].Value)
        token := Trim(gCtrls["AutomateToken"].Value)
        client := Trim(gCtrls["AutomateClientName"].Value)
        if (server = "" || locId = "" || !RegExMatch(locId, "^\d+$") || token = "") {
            MsgBox("Needs Automate server hostname, numeric Location ID, and the Windows MSI installer token.`nNothing is saved in the launcher.", AppName, "Icon!")
            return
        }
        if !isScan && (client = "") {
            MsgBox("Set the client name so the GPO and NETLOGON folder are identifiable.", AppName, "Icon!")
            return
        }
    }
    if ToolHasFlag(tool, "RemoteOpsEnroll") || ToolHasFlag(tool, "RemoteOpsRemove") {
        if !RegExMatch(Trim(gCtrls["RoPortal"].Value), "i)^https://[^\s'/]+/?$") {
            MsgBox("Set the RemoteOps portal URL (https://host). Put it under [RemoteOps] Portal= in local-defaults.ini to prefill it.", AppName, "Icon!")
            return
        }
        if ToolHasFlag(tool, "RemoteOpsEnroll") && (Trim(gCtrls["RoToken"].Value) = "") {
            MsgBox("Paste the one-time token from the RemoteOps portal (nothing is saved), then copy again.", AppName, "Icon!")
            return
        }
    }
    if ToolHasFlag(tool, "AdReview") {
        target := Trim(gCtrls["AdTarget"].Value)
        days := Trim(gCtrls["AdInactiveDays"].Value)
        if (target = "" || RegExMatch(target, "[\s']")) {
            MsgBox("Set the target's tunnel address (Peer IP on the RemoteOps portal).", AppName, "Icon!")
            return
        }
        if !RegExMatch(days, "^\d+$") || (Integer(days) < 1) || (Integer(days) > 3650) {
            MsgBox("Inactive days must be a number from 1 to 3650.", AppName, "Icon!")
            return
        }
    }

    try {
        snippet := BuildSnippet(tool, isScan, isCommands)
        if (snippet = "")
            throw Error("Copy produced an empty snippet.")
        A_Clipboard := snippet
        if !ClipWait(1)
            throw Error("Clipboard did not accept the snippet.")
    } catch as e {
        gCtrls["Status"].Value := "Copy failed: " e.Message
        MsgBox("Copy failed.`n`n" e.Message, AppName, "Icon!")
        return
    }
    desc := DescribeSelection(tool, isScan)
    gCtrls["Status"].Value := "Copied (" StrLen(snippet) " chars): " desc
    TrayTip("Copied to clipboard", desc, "Iconi")
    SetTimer(() => TrayTip(), -2500)
}
