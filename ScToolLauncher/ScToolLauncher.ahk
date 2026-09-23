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
; Flags: CheckOnly Force ForceAppShutdown IncludeBrowsers Uninstall Detailed Remediate Product ProductList
;        NoExit Delete BlockReinstall RemoveSupportAssistant Vendor
;        ScanOnly RunOnly PositionalDry Domain CacheBust RebootAdvisory AlwaysNote ConnectSecure
;        SkipIfRunning ResetPlatform SentinelOneInstall HuntressInstall AutomateGpo WebrootUninstallGpo BackupsOnlyDefault ClearAllBackupContent
;        BackstageOnly AutoReboot Help
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
    "ScreenConnect — GPO/MSI finder, temp cleanup",
    "OEM cleanup — HP Touchpoint, HP bloat, Dell SARemediation",
    "AV — Defender repair, Cylance/Webroot, McAfee remnants",
    "Agents — SentinelOne, ConnectSecure, Huntress",
    "IR / forensics — event logs, Sysinternals, ADWCleaner",
    "M365 / Exchange — Inky/IPW transport rules (EXO admin)",
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
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/VulnSoftwareUpdate",
        "Fetch", "Contents",
        "Path", "VulnSoftwareUpdate",
        "Script", "Update-VulnSoftware.ps1",
        "UaPrefix", "VulnSoftwareUpdate-bootstrap",
        "UaVer", "1.4.6",
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
        "Name", "HP Support Assistant",
        "Summary", "Win10: uninstall HPSA by default (vuln SoftPaqs). Win11: update. Scan-only available.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/HpSupportAssistantUpdate",
        "Fetch", "Contents",
        "Path", "HpSupportAssistantUpdate",
        "Script", "Update-HpSupportAssistant.ps1",
        "UaPrefix", "HpSupportAssistantUpdate-bootstrap",
        "UaVer", "1.2.0",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 600000,
        "Flags", "CheckOnly Uninstall Force NoExit"
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
        "UaVer", "1.0.0",
        "TimeoutScan", 600000,
        "TimeoutUpdate", 3600000,
        "DefaultArgs", "-Quality",
        "Folder", "Windows Update",
        "Flags", "CheckOnly Force AutoReboot NoExit",
        "Note", "Pre-check: disk, WinRE/recovery size, WU services/policy, pending reboot. Feature updates are a separate tool. Reload launcher after pull."
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
        "UaVer", "1.0.0",
        "TimeoutScan", 600000,
        "TimeoutUpdate", 14400000,
        "DefaultArgs", "-Feature",
        "Flags", "CheckOnly Force AutoReboot NoExit",
        "Note", "Needs ~20+ GB free and a 750+ MB recovery/WinRE partition. Use PowerShell or a 4-hour Commands timeout. Session drops if Auto reboot is checked."
    ),
    ; --- ScreenConnect ---
    Map(
        "Category", "ScreenConnect — GPO/MSI finder, temp cleanup",
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
        "Category", "ScreenConnect — GPO/MSI finder, temp cleanup",
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
        "Category", "AV — Defender repair, Cylance/Webroot, McAfee remnants",
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
        "Category", "Agents — SentinelOne, ConnectSecure, Huntress",
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
        "Category", "Agents — SentinelOne, ConnectSecure, Huntress",
        "Folder", "ConnectSecure",
        "Name", "ConnectSecure silent install",
        "Summary", "Download Windows agent from ConnectSecure agentlink API, then silent install with -c/-e/-j/-i. Paste IDs/token at copy time — never stored.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/ConnectSecureInstall",
        "Fetch", "Contents",
        "Path", "ConnectSecureInstall",
        "Script", "Install-ConnectSecureAgent.ps1",
        "UaPrefix", "ConnectSecureInstall-bootstrap",
        "UaVer", "1.0.8",
        "TimeoutScan", 600000,
        "TimeoutUpdate", 600000,
        "Flags", "RunOnly ConnectSecure SkipIfRunning AlwaysNote",
        "Note", "Needs Company ID (-c), Environment ID (-e), and Install Token (-j). Default: skip if CyberCNSAgent is Running (fleet / scan-prep). Prefer elevated PowerShell.",
        "ClipboardNote", "NOTE: Install token is embedded in this clipboard snippet only. Do not paste into tickets/git. Prefer elevated PowerShell."
    ),
    Map(
        "Category", "Agents — SentinelOne, ConnectSecure, Huntress",
        "Folder", "ConnectSecure",
        "Name", "ConnectSecure agent repair + reinstall",
        "Summary", "Wipe leftover agent (uninstall.bat + service registry), then reinstall. Paste company/env/token at copy time — never stored.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/ConnectSecureAgentRepair",
        "Fetch", "Contents",
        "Path", "ConnectSecureAgentRepair",
        "Script", "Repair-CyberCNSAgent.ps1",
        "UaPrefix", "ConnectSecureAgentRepair-bootstrap",
        "UaVer", "1.0.9",
        "TimeoutScan", 120000,
        "TimeoutUpdate", 600000,
        "Flags", "CheckOnly Remediate ConnectSecure SkipIfRunning AlwaysNote",
        "Note", "Default: skip if CyberCNSAgent is Running (fleet / scan-prep). Uncheck to always wipe + reinstall. Needs Company ID, Environment ID, and Install Token. Prefer PowerShell.",
        "ClipboardNote", "NOTE: Install token is embedded in this clipboard snippet only. Do not paste into tickets/git. Prefer elevated PowerShell."
    ),
    Map(
        "Category", "Agents — SentinelOne, ConnectSecure, Huntress",
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
        "Category", "Agents — SentinelOne, ConnectSecure, Huntress",
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
        "Category", "Agents — SentinelOne, ConnectSecure, Huntress",
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
        "Category", "Agents — SentinelOne, ConnectSecure, Huntress",
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
        "Note", "Run elevated as Domain Admin on the client DC or RSAT box, not on a workstation. Token is not saved. Startup scripts run at boot. Prefer elevated PowerShell.",
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
        "UaVer", "3.1.2",
        "TimeoutScan", 900000,
        "TimeoutUpdate", 900000,
        "Flags", "ScanOnly CacheBust AlwaysNote",
        "DefaultArgs", '-OutputPath "C:\SecurityReports"',
        "Note", "Sysinternals + all-user Downloads/Desktop + prefetch/tasks/users + EVTX. Reports → C:\SecurityReports. Elevate. VT off in this one-liner. Long-running.",
        "ClipboardNote", "NOTE: Reports under C:\SecurityReports (CSV + EventLogs + Artifacts + zip.sha256). Zone.ID, PS history, hives, browser History, admins/RMM, Defender included. Prefer elevated. No VirusTotal."
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
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/PupRemnantCleanup",
        "Fetch", "Contents",
        "Path", "PupRemnantCleanup",
        "Script", "Invoke-PupRemnantCleanup.ps1",
        "UaPrefix", "PupRemnantCleanup-bootstrap",
        "UaVer", "1.3.0",
        "TimeoutScan", 180000,
        "TimeoutUpdate", 300000,
        "Flags", "CheckOnly Remediate ProductList NoExit",
        "ProductList", "All on host|AskToolbar|MediaArena|AppSuitePdf|WaveBrowser|OneLaunch|FakePdfConverter|BrowserAssistant",
        "Note", "Prefer elevated PowerShell. Scan first. Family list is the catalog. All on host = every family that is actually present.",
        "ClipboardNote", "NOTE: Family dropdown — All on host scans the whole catalog. Pick one id to limit. Scan is dry-run. Remove deletes folders/tasks/registry; browser prefs stay report-only."
    ),
    ; --- M365 / Exchange ---
    Map(
        "Category", "M365 / Exchange — Inky/IPW transport rules (EXO admin)",
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
    ; --- Untested (move here until validated) ---
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
    RefreshOptionEnable()
}

ShowGui(*) {
    global gGui, gCtrls, Tools, gFlowKeys, UiContentW, UiTreeW, UiTreeRows, TrayLabel, HotkeyLabel

    if gGui {
        try gGui.Destroy()
        gGui := 0
    }

    gGui := Gui("+AlwaysOnTop -MinimizeBox", TrayLabel)
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

    gCtrls["LblCsCompany"] := gGui.Add("Text", "Section", "ConnectSecure company ID (-c)")
    gCtrls["CsCompanyId"] := gGui.Add("Edit", "w" UiContentW " vCsCompanyId", "")
    gCtrls["LblCsEnv"] := gGui.Add("Text", , "ConnectSecure environment ID (-e)")
    gCtrls["CsEnvironmentId"] := gGui.Add("Edit", "w" UiContentW " vCsEnvironmentId", "")
    gCtrls["LblCsToken"] := gGui.Add("Text", , "ConnectSecure install token (-j) — not saved; paste each time")
    gCtrls["CsInstallToken"] := gGui.Add("Edit", "w" UiContentW " Password vCsInstallToken", "")

    gCtrls["LblS1Token"] := gGui.Add("Text", "Section", "SentinelOne site/group token — not saved; paste each time")
    gCtrls["S1Token"] := gGui.Add("Edit", "w" UiContentW " Password vS1Token", "")
    gCtrls["LblS1Path"] := gGui.Add("Text", , "Installer path on endpoint (EXE or MSI)")
    gCtrls["S1InstallerPath"] := gGui.Add("Edit", "w" UiContentW " vS1InstallerPath", "C:\Windows\Temp\SentinelOneInstaller.exe")
    gCtrls["LblS1Url"] := gGui.Add("Text", , "Optional download URL (blank = use path already on disk)")
    gCtrls["S1InstallerUrl"] := gGui.Add("Edit", "w" UiContentW " vS1InstallerUrl", "")
    gCtrls["S1Quiet"] := gGui.Add("Checkbox", "Checked vS1Quiet", "Quiet (-q) for EXE installers (older agents)")

    huntressAcctDefault := LoadHuntressAccountKey()
    huntressAcctLabel := "Huntress account key (built in; rarely change)"
    gCtrls["LblHuntressAcct"] := gGui.Add("Text", "Section", huntressAcctLabel)
    gCtrls["HuntressAccountKey"] := gGui.Add("Edit", "w" UiContentW " Password vHuntressAccountKey", huntressAcctDefault)
    gCtrls["LblHuntressOrg"] := gGui.Add("Text", , "Huntress organization key (client short name)")
    gCtrls["HuntressOrgKey"] := gGui.Add("Edit", "w" UiContentW " vHuntressOrgKey", "")
    gCtrls["LblHuntressTags"] := gGui.Add("Text", , "Optional tags (comma-separated)")
    gCtrls["HuntressTags"] := gGui.Add("Edit", "w" UiContentW " vHuntressTags", "")

    automateServerDefault := LoadAutomateServer()
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
        "LblAbout", "Summary", "HelpBody", "BtnDocs",
        "LblMode", "ModeScan", "ModeUpdate",
        "LblOptions", "Force", "ForceAppShutdown", "IncludeBrowsers", "Uninstall", "Detailed",
        "BlockReinstall", "RemoveSupportAssistant", "ClearAllBackupContent", "SkipIfRunning", "ResetPlatform",
        "AutoReboot", "LblHuntressRebootAt", "HuntressRebootAt",
        "LblProduct", "Product",
        "LblPupFamily", "PupFamily",
        "LblVendor", "Vendor", "LblAvSecret", "AvSecret",
        "LblDomainController", "DomainController", "LblDomain", "Domain",
        "LblCsCompany", "CsCompanyId", "LblCsEnv", "CsEnvironmentId", "LblCsToken", "CsInstallToken",
        "LblS1Token", "S1Token", "LblS1Path", "S1InstallerPath", "LblS1Url", "S1InstallerUrl", "S1Quiet",
        "LblHuntressAcct", "HuntressAccountKey", "LblHuntressOrg", "HuntressOrgKey", "LblHuntressTags", "HuntressTags",
        "LblAutomateServer", "AutomateServer", "LblAutomateLocationId", "AutomateLocationId", "LblAutomateToken", "AutomateToken",
        "LblAutomateClient", "AutomateClientName", "LblAutomateLocation", "AutomateLocationName",
        "LblAutomateDomain", "AutomateDomain", "LblAutomateOu", "AutomateTargetOu", "AutomateLinkToDomain",
        "LblWebrootKeyCode", "WebrootKeyCode",
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
        if (key = "Summary")
            ch := 52
        else if (key = "HelpBody")
            ch := 280
        else if (key = "Note")
            ch := 48
        else if (key = "Status")
            ch := 36
        else if (key = "BtnDocs") {
            ch := 26
            cw := 200
        }
        else if (key = "Product" || key = "PupFamily" || key = "AvSecret" || key = "DomainController" || key = "Domain" || key = "Vendor"
            || key = "CsCompanyId" || key = "CsEnvironmentId" || key = "CsInstallToken"
            || key = "S1Token" || key = "S1InstallerPath" || key = "S1InstallerUrl"
            || key = "HuntressAccountKey" || key = "HuntressOrgKey" || key = "HuntressTags"
            || key = "HuntressRebootAt"
            || key = "AutomateServer" || key = "AutomateLocationId" || key = "AutomateToken"
            || key = "AutomateClientName" || key = "AutomateLocationName" || key = "AutomateDomain"
            || key = "AutomateTargetOu" || key = "WebrootKeyCode")
            ch := 22
        else if (InStr(key, "Lbl") = 1)
            ch := 16
        else if (InStr(key, "Mode") = 1 || InStr(key, "Fmt") = 1 || key = "Force" || key = "ForceAppShutdown"
            || key = "IncludeBrowsers" || key = "Uninstall" || key = "Detailed" || key = "BlockReinstall"
            || key = "RemoveSupportAssistant" || key = "ClearAllBackupContent" || key = "SkipIfRunning"
            || key = "ResetPlatform" || key = "AutoReboot"
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
            "ResetPlatform", "AutoReboot", "LblHuntressRebootAt", "HuntressRebootAt",
            "LblProduct", "Product", "LblPupFamily", "PupFamily",
            "LblVendor", "Vendor", "LblAvSecret", "AvSecret",
            "LblDomainController", "DomainController", "LblDomain", "Domain",
            "LblCsCompany", "CsCompanyId", "LblCsEnv", "CsEnvironmentId", "LblCsToken", "CsInstallToken",
            "LblS1Token", "S1Token", "LblS1Path", "S1InstallerPath", "LblS1Url", "S1InstallerUrl", "S1Quiet",
            "LblHuntressAcct", "HuntressAccountKey", "LblHuntressOrg", "HuntressOrgKey", "LblHuntressTags", "HuntressTags",
            "LblAutomateServer", "AutomateServer", "LblAutomateLocationId", "AutomateLocationId",
            "LblAutomateToken", "AutomateToken", "LblAutomateClient", "AutomateClientName",
            "LblAutomateLocation", "AutomateLocationName", "LblAutomateDomain", "AutomateDomain",
            "LblAutomateOu", "AutomateTargetOu", "AutomateLinkToDomain", "LblWebrootKeyCode", "WebrootKeyCode",
            "LblPaste", "FmtCommands", "FmtBackstage", "Note"
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
    showSkipIfRunning := ToolHasFlag(t, "SkipIfRunning")
    showResetPlatform := ToolHasFlag(t, "ResetPlatform")
    if InStr(ToolGet(t, "Path", ""), "WindowsDefender") && gCtrls["ModeScan"].Value
        showResetPlatform := false
    ; RunOnly tools (Huntress) keep ModeScan checked until later in this function,
    ; so do not require Apply mode to show the schedule/reboot checkbox.
    showAutoReboot := ToolHasFlag(t, "AutoReboot") && (ToolHasFlag(t, "RunOnly") || !gCtrls["ModeScan"].Value)
    showSentinelOne := ToolHasFlag(t, "SentinelOneInstall")
    showHuntress := ToolHasFlag(t, "HuntressInstall")
    showAutomate := ToolHasFlag(t, "AutomateGpo")
    showWebrootGpo := ToolHasFlag(t, "WebrootUninstallGpo")
    scanOnly := ToolHasFlag(t, "ScanOnly")

    if (showHuntress) {
        gCtrls["Force"].Text := "Rip and replace (wipe leftover Huntress, then install now; no reboot)"
        gCtrls["AutoReboot"].Text := "Schedule SYSTEM install + cleanup + reboot at chosen time"
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
    ; ConnectSecure IDs/token: always for silent install (RunOnly); repair only in Apply mode
    showCsFields := showConnectSecure && (ToolHasFlag(t, "RunOnly") || !gCtrls["ModeScan"].Value)
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
    SetCtrlShown(gCtrls["LblHuntressAcct"], showHuntress)
    SetCtrlShown(gCtrls["HuntressAccountKey"], showHuntress)
    SetCtrlShown(gCtrls["LblHuntressOrg"], showHuntress)
    SetCtrlShown(gCtrls["HuntressOrgKey"], showHuntress)
    SetCtrlShown(gCtrls["LblHuntressTags"], showHuntress)
    SetCtrlShown(gCtrls["HuntressTags"], showHuntress)
    SetCtrlShown(gCtrls["LblAutomateServer"], showAutomate)
    SetCtrlShown(gCtrls["AutomateServer"], showAutomate)
    SetCtrlShown(gCtrls["LblAutomateLocationId"], showAutomate)
    SetCtrlShown(gCtrls["AutomateLocationId"], showAutomate)
    SetCtrlShown(gCtrls["LblAutomateToken"], showAutomate)
    SetCtrlShown(gCtrls["AutomateToken"], showAutomate)
    SetCtrlShown(gCtrls["LblAutomateClient"], showAutomate)
    SetCtrlShown(gCtrls["AutomateClientName"], showAutomate)
    SetCtrlShown(gCtrls["LblAutomateLocation"], showAutomate)
    SetCtrlShown(gCtrls["AutomateLocationName"], showAutomate)
    showGpoDomain := showAutomate || showWebrootGpo
    SetCtrlShown(gCtrls["LblAutomateDomain"], showGpoDomain)
    SetCtrlShown(gCtrls["AutomateDomain"], showGpoDomain)
    SetCtrlShown(gCtrls["LblAutomateOu"], showGpoDomain)
    SetCtrlShown(gCtrls["AutomateTargetOu"], showGpoDomain)
    showGpoLink := showGpoDomain && !gCtrls["ModeScan"].Value
    SetCtrlShown(gCtrls["AutomateLinkToDomain"], showGpoLink)
    SetCtrlShown(gCtrls["LblWebrootKeyCode"], showWebrootGpo)
    SetCtrlShown(gCtrls["WebrootKeyCode"], showWebrootGpo)

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
    } else if runOnly && ToolHasFlag(t, "HuntressInstall") {
        gCtrls["ModeUpdate"].Text := "Silent install (/ACCT_KEY)"
    } else if runOnly && (ToolGet(t, "Fetch", "") = "Inline") {
        gCtrls["ModeUpdate"].Text := "Run command"
    } else if runOnly && showConnectSecure {
        gCtrls["ModeUpdate"].Text := "Silent install (-c/-e/-j)"
    } else if runOnly && InStr(ToolGet(t, "TempName", ""), "HPbloatware") {
        gCtrls["ModeUpdate"].Text := "Remove HP bloat / Wolf"
    } else if runOnly {
        gCtrls["ModeUpdate"].Text := "Download and run"
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
        gCtrls["FmtCommands"].Enabled := false
        gCtrls["LblPaste"].Text := "Paste format (PowerShell only)"
    } else {
        gCtrls["FmtCommands"].Enabled := true
        gCtrls["LblPaste"].Text := "Paste format"
    }

    if InStr(ToolGet(t, "Path", ""), "WindowsDefender") {
        gCtrls["ModeScan"].Text := "Check RTP + services"
        gCtrls["ModeUpdate"].Text := "Re-enable Defender RTP"
    }
    if InStr(ToolGet(t, "Path", ""), "AcrobatXiRemoval") {
        gCtrls["ModeScan"].Text := "Scan Acrobat XI + Foxit"
        gCtrls["ModeUpdate"].Text := "Uninstall Acrobat XI"
    }
    if InStr(ToolGet(t, "Path", ""), "WindowsUpdate") {
        gCtrls["ModeScan"].Text := "Scan pending updates + pre-check"
        gCtrls["ModeUpdate"].Text := "Install (no reboot unless option)"
    }
    if ToolHasFlag(t, "Delete") && InStr(ToolGet(t, "Path", ""), "Inky") {
        gCtrls["ModeScan"].Text := "List matching rules"
        gCtrls["ModeUpdate"].Text := "Delete matching rules"
    }
    if ToolHasFlag(t, "AutomateGpo") {
        gCtrls["ModeScan"].Text := "Dry-run (transform only)"
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

    note := ToolGet(t, "Note", "")
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

    if ToolHasFlag(tool, "Remediate") && !isScan
        sw.Push("-Remediate")
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
        if (fam != "" && fam != "All on host")
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
    return "if($PSVersionTable.PSVersion.Major -lt 5){$exe=$null; foreach($c in @(`"$env:SystemRoot\SysNative\WindowsPowerShell\v1.0\powershell.exe`",`"$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe`",`"$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe`")){if(Test-Path -LiteralPath $c){try{$v=& $c -NoProfile -Command '$PSVersionTable.PSVersion.Major'}catch{$v=0}; if(($v -as [int]) -ge 5){$exe=$c; break}}}; if(-not $exe){throw 'PowerShell 5.1 required (this host has only 2.0). Install WMF 5.1 or use Huntress inline install.'}; & $exe -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path; exit $LASTEXITCODE}; "
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

BuildSnippet(tool, isScan, isCommands) {
    global DefaultOwner, DefaultRepo, DefaultRef, MaxLength, gCtrls
    timeout := isScan ? tool["TimeoutScan"] : tool["TimeoutUpdate"]
    fetch := ToolGet(tool, "Fetch", "Contents")
    tls := BootstrapTls()
    ps5 := isCommands ? BootstrapPs5Relaunch() : ""

    ; Huntress: no GitHub / no #Requires 5.1. Download the vendor EXE with
    ; WebClient so ScreenConnect's v2 engine can still install the agent.
    if ToolHasFlag(tool, "HuntressInstall") {
        body := BuildHuntressBody(isCommands)
    } else if (fetch = "Inline") {
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
        else if ToolHasFlag(tool, "HuntressInstall") {
            if (CtrlActive(gCtrls["AutoReboot"]) && gCtrls["AutoReboot"].Value)
                mode := "Scheduled install + reboot " FormatHuntressRebootAt()
            else if (CtrlActive(gCtrls["Force"]) && gCtrls["Force"].Value)
                mode := "Rip and replace"
            else
                mode := "Silent install"
        }
        else if ToolHasFlag(tool, "ConnectSecure")
            mode := "Silent install"
        else if (ToolGet(tool, "Fetch", "") = "Inline")
            mode := "Run command"
        else if InStr(ToolGet(tool, "TempName", ""), "HPbloatware")
            mode := "Remove HP bloat"
        else
            mode := "Download and run"
    } else if ToolHasFlag(tool, "ScanOnly") && (ToolGet(tool, "Fetch", "") = "Inline")
        mode := "Check pending reboot"
    else if ToolHasFlag(tool, "ScanOnly") && (ToolGet(tool, "Fetch", "") = "IrmOutFile")
        mode := "Collect / run"
    if !isScan && !ToolHasFlag(tool, "RunOnly") {
        if ToolHasFlag(tool, "Delete") || ToolHasFlag(tool, "PositionalDry")
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
        if isScan
            mode := "Scan + pre-check"
        else
            mode := "Install"
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
    global gCtrls, AppName
    tool := SelectedTool()
    if ToolHasFlag(tool, "Help") {
        gCtrls["Status"].Value := "Select a tool from a category, then Copy."
        return
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
        if (Trim(gCtrls["CsCompanyId"].Value) = "" || Trim(gCtrls["CsEnvironmentId"].Value) = "" || Trim(gCtrls["CsInstallToken"].Value) = "") {
            MsgBox("Needs Company ID, Environment ID, and Install Token.`nFill the fields (nothing is saved in the launcher), then copy again.", AppName, "Icon!")
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

    snippet := BuildSnippet(tool, isScan, isCommands)
    A_Clipboard := snippet
    ClipWait(1)
    desc := DescribeSelection(tool, isScan)
    gCtrls["Status"].Value := "Copied: " desc
    TrayTip("Copied to clipboard", desc, "Iconi")
    SetTimer(() => TrayTip(), -2500)
}
