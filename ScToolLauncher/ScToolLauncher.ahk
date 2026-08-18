#Requires AutoHotkey v2.0
; ScToolLauncher — hotkey picker for any ScreenConnect-ready tool shortcut (not vuln-only).
; Copies a GitHub bootstrap #!ps / Backstage one-liner to the clipboard.
; Hotkey: Ctrl+Shift+Alt+S (change HotkeySpec below). Prefer Commands tab #!ps.
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

; Fetch: Contents (api.github.com + Accept raw) | Raw (raw.githubusercontent.com?v=)
;        IrmOutFile (Process Bypass + irm -OutFile + & run — for unsigned remote .ps1)
;        DownloadExe (IWR vendor EXE + Start-Process -Wait)
; Category: groups tools in the TreeView (order = CategoryOrder below)
; Flags: CheckOnly Force ForceAppShutdown IncludeBrowsers Uninstall Detailed Remediate Product
;        NoExit Delete BlockReinstall RemoveSupportAssistant Vendor
;        ScanOnly RunOnly PositionalDry Domain CacheBust RebootAdvisory AlwaysNote ConnectSecure
;        SentinelOneInstall BackupsOnlyDefault ClearAllBackupContent
CategoryOrder := [
    "Software updates — vuln catalog, M365, .NET, HPSA, Teams",
    "ScreenConnect — GPO/MSI finder, temp cleanup",
    "OEM cleanup — HP Touchpoint, Dell SARemediation",
    "AV offboarding — Cylance/Webroot, McAfee remnants",
    "Agents — SentinelOne + ConnectSecure",
    "IR / forensics — event logs, Sysinternals, ADWCleaner",
    "M365 / Exchange — Inky/IPW transport rules (EXO admin)"
]

; TreeView / content column width (also used by ReflowGui)
UiContentW := 480
UiTreeRows := 22

Tools := [
    ; --- Software updates ---
    Map(
        "Category", "Software updates — vuln catalog, M365, .NET, HPSA, Teams",
        "Name", "Vulnerable software updater (catalog)",
        "Summary", "Checks/updates common third-party apps (winget + M365/HPSA/.NET delegates). Browsers are opt-in.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/VulnSoftwareUpdate",
        "Fetch", "Contents",
        "Path", "VulnSoftwareUpdate",
        "Script", "Update-VulnSoftware.ps1",
        "UaPrefix", "VulnSoftwareUpdate-bootstrap",
        "UaVer", "1.4.3",
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
        "Summary", "Removes stale ScreenConnect temp folders, old installers, and Automate package cache leftovers. Dry-run first.",
        "DocsUrl", "https://github.com/monobrau/screenconnect-temp-cleanup",
        "Fetch", "Raw",
        "Owner", "monobrau",
        "Repo", "screenconnect-temp-cleanup",
        "Script", "Remove-ScreenConnectTempCopies.ps1",
        "UaVer", "1.6.0",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 300000,
        "Flags", "Delete Force CacheBust"
    ),
    ; --- OEM cleanup ---
    Map(
        "Category", "OEM cleanup — HP Touchpoint, Dell SARemediation",
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
        "Category", "OEM cleanup — HP Touchpoint, Dell SARemediation",
        "Name", "Dell SARemediation Backup (CW/SC)",
        "Summary", "Scan/remove ScreenConnect/ConnectWise-like files from Dell Snapshots\\Backup (S1 revoked-cert hygiene). Pair with SC temp cleanup. Does not uninstall Dell software.",
        "DocsUrl", "https://github.com/monobrau/dell-saremediation-cleanup",
        "Fetch", "Raw",
        "Owner", "monobrau",
        "Repo", "dell-saremediation-cleanup",
        "Script", "Remove-DellSARemediation.ps1",
        "UaVer", "1.4.2",
        "TimeoutScan", 600000,
        "TimeoutUpdate", 900000,
        "Flags", "Delete CacheBust RebootAdvisory BackupsOnlyDefault ClearAllBackupContent",
        "Note", "Always -BackupsOnly. v1.4.2: scan first, timed service stop (no 20min hang), does not kill ScreenConnect. Banner must say v1.4.2 (CDN: reload AHK / new ?v=).",
        "ClipboardNote", "NOTE: Backup cleanup only. Must show v1.4.2. PENDING_REBOOT = reboot to finish. Then SC temp cleanup."
    ),
    ; --- AV offboarding (not day-to-day AV management) ---
    Map(
        "Category", "AV offboarding — Cylance/Webroot, McAfee remnants",
        "Name", "Cylance / Webroot cleanup",
        "Summary", "Offboarding / leftover cleanup after migrating off Cylance or Webroot (OpenText CEP). Uninstall + residual sweep. Dry-run first; elevated delete. Prefer Backstage/SYSTEM.",
        "DocsUrl", "https://github.com/monobrau/windows-av-cleanup",
        "Fetch", "Raw",
        "Owner", "monobrau",
        "Repo", "windows-av-cleanup",
        "Script", "Remove-Antivirus.ps1",
        "UaVer", "1.1.0",
        "TimeoutScan", 300000,
        "TimeoutUpdate", 300000,
        "Flags", "Delete Force Vendor CacheBust",
        "Note", "Use when offboarding the vendor or cleaning remnants after cutover — not for managing an active AV install. Prefer deactivate in the vendor console first. Delete needs elevation (Backstage/SYSTEM). Password/keycode only if Vendor is Cylance or Webroot (not All). Reboot if drivers stay locked."
    ),
    Map(
        "Category", "AV offboarding — Cylance/Webroot, McAfee remnants",
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
        "Note", "Prefer elevated / Backstage. Scan first; Remediate removes AppX + folder."
    ),
    ; --- Agents ---
    Map(
        "Category", "Agents — SentinelOne + ConnectSecure",
        "Name", "SentinelOne silent install",
        "Summary", "Paste site/group token → silent install for SC Commands or Backstage. Optional download URL; else installer must already be on disk.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/SentinelOneInstall",
        "Fetch", "Contents",
        "Path", "SentinelOneInstall",
        "Script", "Install-SentinelOneAgent.ps1",
        "UaPrefix", "SentinelOneInstall-bootstrap",
        "UaVer", "1.0.1",
        "TimeoutScan", 900000,
        "TimeoutUpdate", 900000,
        "Flags", "RunOnly SentinelOneInstall AlwaysNote",
        "Note", "Token + path (and optional URL) below are not saved. Barracuda/XDR MSI download URLs (fileType=.msi) auto-use msiexec even if path ends in .exe. Prefer elevated / Backstage.",
        "ClipboardNote", "NOTE: Site token is embedded in this clipboard snippet only. Do not paste into tickets/git. Prefer elevated Backstage. v1.0.1 auto-detects MSI downloads."
    ),
    Map(
        "Category", "Agents — SentinelOne + ConnectSecure",
        "Name", "ConnectSecure silent install",
        "Summary", "Download Windows agent from ConnectSecure agentlink API, then silent install with -c/-e/-j/-i. Paste IDs/token at copy time — never stored.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/ConnectSecureInstall",
        "Fetch", "Contents",
        "Path", "ConnectSecureInstall",
        "Script", "Install-ConnectSecureAgent.ps1",
        "UaPrefix", "ConnectSecureInstall-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 600000,
        "TimeoutUpdate", 600000,
        "Flags", "RunOnly ConnectSecure AlwaysNote",
        "Note", "Needs Company ID (-c), Environment ID (-e), and Install Token (-j). Fresh install only (no uninstall). Prefer elevated / Backstage.",
        "ClipboardNote", "NOTE: Install token is embedded in this clipboard snippet only. Do not paste into tickets/git. Prefer elevated Backstage."
    ),
    Map(
        "Category", "Agents — SentinelOne + ConnectSecure",
        "Name", "ConnectSecure (CyberCNS) agent repair",
        "Summary", "If agent+monitor are not both Running: stop/delete services, kill processes, wipe folder, reinstall. Paste company/env/token at copy time — never stored.",
        "DocsUrl", "https://github.com/monobrau/mytools/tree/main/ConnectSecureAgentRepair",
        "Fetch", "Contents",
        "Path", "ConnectSecureAgentRepair",
        "Script", "Repair-CyberCNSAgent.ps1",
        "UaPrefix", "ConnectSecureAgentRepair-bootstrap",
        "UaVer", "1.0.0",
        "TimeoutScan", 120000,
        "TimeoutUpdate", 600000,
        "Flags", "CheckOnly Remediate ConnectSecure AlwaysNote",
        "Note", "Remediate needs Company ID, Environment ID, and Install Token (filled below — not saved in the AHK file). Prefer Backstage. Reboot if services refuse to die.",
        "ClipboardNote", "NOTE: Install token is embedded in this clipboard snippet only. Do not paste into tickets/git. Prefer elevated Backstage."
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
        "Note", "Collects EVTX + artifacts to C:\ForensicLogs\<host>_<stamp>.zip. Prefer elevated / Backstage. Long-running.",
        "ClipboardNote", "NOTE: Output zip under C:\ForensicLogs\. Prefer elevated session. Collection can take several minutes."
    ),
    Map(
        "Category", "IR / forensics — event logs, Sysinternals, ADWCleaner",
        "Name", "Forensic Investigator (Sysinternals)",
        "Summary", "Autoruns/services/network/processes via Sysinternals; optional VT. Saves under C:\SecurityReports by default.",
        "DocsUrl", "https://github.com/monobrau/forensicinvestigator",
        "Fetch", "IrmOutFile",
        "Owner", "monobrau",
        "Repo", "forensicinvestigator",
        "Script", "Invoke-ForensicAnalysis.ps1",
        "TempName", "Invoke-ForensicAnalysis.ps1",
        "UaVer", "1.0.0",
        "TimeoutScan", 600000,
        "TimeoutUpdate", 600000,
        "Flags", "ScanOnly CacheBust AlwaysNote",
        "DefaultArgs", '-OutputPath "C:\SecurityReports"',
        "Note", "Downloads Sysinternals tools, then scans. Reports → C:\SecurityReports (override via DefaultArgs in catalog if needed). Elevate for full coverage. VT not enabled in this one-liner.",
        "ClipboardNote", "NOTE: Reports default to C:\SecurityReports. Sysinternals download required. Prefer elevated session. Without VirusTotal this usually finishes in a few minutes."
    ),
    Map(
        "Category", "IR / forensics — event logs, Sysinternals, ADWCleaner",
        "Name", "Malwarebytes ADWCleaner",
        "Summary", "Downloads ADWCleaner and runs a silent clean (/eula /clean /noreboot). Prefer elevated / Backstage.",
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
]

gToolByNode := Map()   ; TreeView item id -> Tools index (1-based)
gLastToolIndex := 1     ; last real tool selection (survives category collapse)
gFlowKeys := []         ; control stack order for ReflowGui

; --- tray / identity ---
; Rename the hidden AutoHotkey main window so Task Manager / tray hosts do not
; show a generic "main" (same as other AHK scripts). Also set tray tip + menu.
DetectHiddenWindows(true)
try WinSetTitle(TrayLabel, "ahk_class AutoHotkey ahk_pid " ProcessExist())
A_IconTip := TrayLabel
; Distinct from other AHK scripts that often use shell32 index 166 / default AHK icon.
TraySetIcon("shell32.dll", 14)
A_TrayMenu.Delete()
A_TrayMenu.Add(TrayLabel, (*) => ShowGui())
A_TrayMenu.Add("Reload script (pick up catalog changes)", (*) => Reload())
A_TrayMenu.Add("Exit " AppName, (*) => ExitApp())
A_TrayMenu.Default := TrayLabel
A_TrayMenu.ClickCount := 1

Hotkey(HotkeySpec, (*) => ToggleGui())

gGui := 0
gCtrls := Map()

ShowGui()

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
    ; Bold category headers. Expand Agents so install tools are visible without hunting.
    expandCats := Map()
    expandCats["Agents — SentinelOne + ConnectSecure"] := true
    for cat in CategoryOrder
        catNodes[cat] := tv.Add(cat, 0, "Bold")

    agentsNode := 0
    firstCatNode := 0
    for i, t in Tools {
        cat := ToolGet(t, "Category", "Other")
        if !catNodes.Has(cat)
            catNodes[cat] := tv.Add(cat, 0, "Bold")
        node := tv.Add(t["Name"], catNodes[cat])
        gToolByNode[node] := i
        if !firstCatNode && catNodes.Has(cat)
            firstCatNode := catNodes[cat]
        if (cat = "Agents — SentinelOne + ConnectSecure" && !agentsNode)
            agentsNode := catNodes[cat]
    }
    for cat, node in catNodes {
        if expandCats.Has(cat)
            tv.Modify(node, "Expand")
    }
    gLastToolIndex := 1
    ; Prefer Agents category selected/expanded so new install tools are obvious
    if agentsNode {
        tv.Modify(agentsNode, "Expand Select Vis")
    } else if firstCatNode {
        tv.Modify(firstCatNode, "Select")
    }
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
    global gGui, gCtrls, Tools, gFlowKeys, UiContentW, UiTreeRows, TrayLabel, HotkeyLabel

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

    gGui.Add("Text", , "Tool (expand a category)")
    tv := gGui.Add("TreeView", "w" UiContentW " r" UiTreeRows " vToolTree")
    tv.OnEvent("ItemSelect", OnToolTreeSelect)
    gCtrls["ToolTree"] := tv
    PopulateToolTree(tv)

    gCtrls["LblAbout"] := gGui.Add("Text", "xm Section", "About this tool")
    gCtrls["Summary"] := gGui.Add("Text", "xs w" UiContentW " h52 vToolSummary", "")
    gCtrls["BtnDocs"] := gGui.Add("Button", "xs w200", "Open docs in browser")
    gCtrls["BtnDocs"].OnEvent("Click", (*) => OpenSelectedToolDocs())

    gCtrls["LblMode"] := gGui.Add("Text", "xm Section", "Mode")
    ; Group: first radio in each set — required so Mode and Paste format stay separate
    ; when intervening option checkboxes are hidden (otherwise Win32 merges the radios).
    gCtrls["ModeScan"] := gGui.Add("Radio", "xs Group Checked vModeScan", "Scan only (no changes)")
    gCtrls["ModeUpdate"] := gGui.Add("Radio", "xs vModeUpdate", "Apply changes (update / remove)")
    gCtrls["ModeScan"].OnEvent("Click", (*) => RefreshOptionEnable())
    gCtrls["ModeUpdate"].OnEvent("Click", (*) => RefreshOptionEnable())

    gCtrls["LblOptions"] := gGui.Add("Text", "xm Section", "Options")
    gCtrls["Force"] := gGui.Add("Checkbox", "xs vOptForce", "Force (skip soft guards / re-run)")
    gCtrls["ForceAppShutdown"] := gGui.Add("Checkbox", "xs vOptForceAppShutdown", "Close Office apps (Word, Excel, Outlook, …)")
    gCtrls["IncludeBrowsers"] := gGui.Add("Checkbox", "xs vOptIncludeBrowsers", "Include browsers (Chrome, Edge, Firefox)")
    gCtrls["Uninstall"] := gGui.Add("Checkbox", "xs vOptUninstall", "Uninstall HP Support Assistant")
    gCtrls["Detailed"] := gGui.Add("Checkbox", "xs vOptDetailed", "Detailed Teams check (shortcuts count as fail)")
    gCtrls["BlockReinstall"] := gGui.Add("Checkbox", "xs vOptBlockReinstall", "Block Windows Update reinstall")
    gCtrls["RemoveSupportAssistant"] := gGui.Add("Checkbox", "xs vOptRemoveSupportAssistant", "Also remove HP Support Assistant")
    gCtrls["ClearAllBackupContent"] := gGui.Add("Checkbox", "xs vOptClearAllBackupContent", "Clear entire Backup folder contents (not just CW/SC)")
    gCtrls["ClearAllBackupContent"].OnEvent("Click", (*) => RefreshOptionEnable())

    gCtrls["LblProduct"] := gGui.Add("Text", "xm Section", "Product filter (e.g. DotNet, ShareX)")
    gCtrls["Product"] := gGui.Add("Edit", "xs w" UiContentW " vProduct", "")

    gCtrls["LblVendor"] := gGui.Add("Text", "xm Section", "Antivirus vendor")
    gCtrls["Vendor"] := gGui.Add("DropDownList", "xs w160 vVendor", ["All", "Cylance", "Webroot"])
    gCtrls["Vendor"].Choose(1)
    gCtrls["LblAvSecret"] := gGui.Add("Text", "xm", "Password/keycode (only if Vendor is Cylance or Webroot — not All)")
    gCtrls["AvSecret"] := gGui.Add("Edit", "xs w" UiContentW " vAvSecret", "")

    gCtrls["LblDomainController"] := gGui.Add("Text", "xm Section", "Domain controller (optional)")
    gCtrls["DomainController"] := gGui.Add("Edit", "xs w" UiContentW " vDomainController", "")
    gCtrls["LblDomain"] := gGui.Add("Text", "xm", "AD domain (optional)")
    gCtrls["Domain"] := gGui.Add("Edit", "xs w" UiContentW " vDomain", "")

    gCtrls["LblCsCompany"] := gGui.Add("Text", "xm Section", "ConnectSecure company ID (-c)")
    gCtrls["CsCompanyId"] := gGui.Add("Edit", "xs w" UiContentW " vCsCompanyId", "")
    gCtrls["LblCsEnv"] := gGui.Add("Text", "xm", "ConnectSecure environment ID (-e)")
    gCtrls["CsEnvironmentId"] := gGui.Add("Edit", "xs w" UiContentW " vCsEnvironmentId", "")
    gCtrls["LblCsToken"] := gGui.Add("Text", "xm", "ConnectSecure install token (-j) — not saved; paste each time")
    gCtrls["CsInstallToken"] := gGui.Add("Edit", "xs w" UiContentW " Password vCsInstallToken", "")

    gCtrls["LblS1Token"] := gGui.Add("Text", "xm Section", "SentinelOne site/group token — not saved; paste each time")
    gCtrls["S1Token"] := gGui.Add("Edit", "xs w" UiContentW " Password vS1Token", "")
    gCtrls["LblS1Path"] := gGui.Add("Text", "xm", "Installer path on endpoint (EXE or MSI)")
    gCtrls["S1InstallerPath"] := gGui.Add("Edit", "xs w" UiContentW " vS1InstallerPath", "C:\Windows\Temp\SentinelOneInstaller.exe")
    gCtrls["LblS1Url"] := gGui.Add("Text", "xm", "Optional download URL (blank = use path already on disk)")
    gCtrls["S1InstallerUrl"] := gGui.Add("Edit", "xs w" UiContentW " vS1InstallerUrl", "")
    gCtrls["S1Quiet"] := gGui.Add("Checkbox", "xs Checked vS1Quiet", "Quiet (-q) for EXE installers (older agents)")

    gCtrls["LblPaste"] := gGui.Add("Text", "xm Section", "Paste format")
    gCtrls["FmtCommands"] := gGui.Add("Radio", "xs Group Checked vFmtCommands", "ScreenConnect Commands (recommended)")
    gCtrls["FmtBackstage"] := gGui.Add("Radio", "xs vFmtBackstage", "ScreenConnect Backstage (one line)")

    gCtrls["Note"] := gGui.Add("Text", "xm w" UiContentW " h48 cBlue vToolNote", "")
    gCtrls["Status"] := gGui.Add("Text", "xm w" UiContentW " h36 vStatus", HotkeyLabel " toggles this window. Expand a category, select a tool, then Copy.")

    gCtrls["BtnCopy"] := gGui.Add("Button", "xm w220 Default", "Copy to clipboard")
    gCtrls["BtnCopy"].OnEvent("Click", (*) => DoCopy())
    gCtrls["BtnCancel"] := gGui.Add("Button", "x+8 w100", "Cancel")
    gCtrls["BtnCancel"].OnEvent("Click", (*) => gGui.Hide())

    ; Stack order below the TreeView (only Visible controls advance Y).
    gFlowKeys := [
        "LblAbout", "Summary", "BtnDocs",
        "LblMode", "ModeScan", "ModeUpdate",
        "LblOptions", "Force", "ForceAppShutdown", "IncludeBrowsers", "Uninstall", "Detailed",
        "BlockReinstall", "RemoveSupportAssistant", "ClearAllBackupContent",
        "LblProduct", "Product",
        "LblVendor", "Vendor", "LblAvSecret", "AvSecret",
        "LblDomainController", "DomainController", "LblDomain", "Domain",
        "LblCsCompany", "CsCompanyId", "LblCsEnv", "CsEnvironmentId", "LblCsToken", "CsInstallToken",
        "LblS1Token", "S1Token", "LblS1Path", "S1InstallerPath", "LblS1Url", "S1InstallerUrl", "S1Quiet",
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

; Collapse gaps: stack visible controls under the TreeView; park others off-layout.
ReflowGui() {
    global gGui, gCtrls, gFlowKeys, UiContentW
    marginX := 12
    marginBottom := 12
    gap := 3
    sectionGap := 8
    contentW := UiContentW

    ; Freeze paint while moving controls (avoids ghosting when the window shrinks).
    try DllCall("SendMessage", "ptr", gGui.Hwnd, "uint", 0x000B, "ptr", 0, "ptr", 0) ; WM_SETREDRAW false

    tv := gCtrls["ToolTree"]
    tv.GetPos(&tx, &ty, &tw, &th)
    y := ty + th + sectionGap
    x := marginX
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
        else if (key = "Note")
            ch := 48
        else if (key = "Status")
            ch := 36
        else if (key = "BtnDocs") {
            ch := 26
            cw := 200
        }
        else if (key = "Product" || key = "AvSecret" || key = "DomainController" || key = "Domain" || key = "Vendor"
            || key = "CsCompanyId" || key = "CsEnvironmentId" || key = "CsInstallToken"
            || key = "S1Token" || key = "S1InstallerPath" || key = "S1InstallerUrl")
            ch := 22
        else if (InStr(key, "Lbl") = 1)
            ch := 16
        else if (InStr(key, "Mode") = 1 || InStr(key, "Fmt") = 1 || key = "Force" || key = "ForceAppShutdown"
            || key = "IncludeBrowsers" || key = "Uninstall" || key = "Detailed" || key = "BlockReinstall"
            || key = "RemoveSupportAssistant" || key = "ClearAllBackupContent" || key = "S1Quiet")
            ch := 20

        ctrl.Move(x, y, cw, ch)
        y += ch + gap
    }

    btnH := 28
    gCtrls["BtnCopy"].Move(x, y, 220, btnH)
    gCtrls["BtnCancel"].Move(x + 228, y, 100, btnH)
    y += btnH + marginBottom

    gGui.GetPos(,, &winW, &winH)
    gGui.GetClientPos(,, &cliW, &cliH)
    chromeW := winW - cliW
    chromeH := winH - cliH
    if (chromeW < 0)
        chromeW := 16
    if (chromeH < 0)
        chromeH := 40
    gGui.Move(,, contentW + marginX * 2 + chromeW, y + chromeH)

    try DllCall("SendMessage", "ptr", gGui.Hwnd, "uint", 0x000B, "ptr", 1, "ptr", 0) ; WM_SETREDRAW true
    try DllCall("RedrawWindow", "ptr", gGui.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x0585)
    ; RDW_INVALIDATE|RDW_ERASE|RDW_FRAME|RDW_ALLCHILDREN|RDW_UPDATENOW
}

ToolHasFlag(tool, flag) {
    return InStr(" " tool["Flags"] " ", " " flag " ")
}

ToolGet(tool, key, default := "") {
    if tool.Has(key)
        return tool[key]
    return default
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

RefreshOptionEnable(*) {
    global gGui, gCtrls
    t := SelectedTool()

    showForce := ToolHasFlag(t, "Force")
    showForceApp := ToolHasFlag(t, "ForceAppShutdown")
    showBrowsers := ToolHasFlag(t, "IncludeBrowsers")
    showUninstall := ToolHasFlag(t, "Uninstall")
    showDetailed := ToolHasFlag(t, "Detailed")
    showBlock := ToolHasFlag(t, "BlockReinstall")
    showRmHpsa := ToolHasFlag(t, "RemoveSupportAssistant")
    showClearAllBackup := ToolHasFlag(t, "ClearAllBackupContent")
    showProduct := ToolHasFlag(t, "Product")
    showVendor := ToolHasFlag(t, "Vendor")
    showDomain := ToolHasFlag(t, "Domain")
    showConnectSecure := ToolHasFlag(t, "ConnectSecure")
    showSentinelOne := ToolHasFlag(t, "SentinelOneInstall")
    scanOnly := ToolHasFlag(t, "ScanOnly")

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
    SetCtrlShown(gCtrls["LblProduct"], showProduct)
    SetCtrlShown(gCtrls["Product"], showProduct)
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

    anyOpt := showForce || showForceApp || showBrowsers || showUninstall || showDetailed
        || showBlock || showRmHpsa || showClearAllBackup
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
    } else if runOnly && showConnectSecure {
        gCtrls["ModeUpdate"].Text := "Silent install (-c/-e/-j)"
    } else if runOnly {
        gCtrls["ModeUpdate"].Text := "Download and run"
    } else if scanOnly {
        gCtrls["ModeScan"].Text := "Find / report"
    } else {
        gCtrls["ModeScan"].Text := "Scan only (no changes)"
        gCtrls["ModeUpdate"].Text := "Apply updates"
    }

    if ToolHasFlag(t, "ConnectSecure") && ToolHasFlag(t, "Remediate") {
        gCtrls["ModeScan"].Text := "Check agent health"
        gCtrls["ModeUpdate"].Text := "Remediate + reinstall"
    }
    if ToolHasFlag(t, "Delete") && InStr(ToolGet(t, "Path", ""), "Inky") {
        gCtrls["ModeScan"].Text := "List matching rules"
        gCtrls["ModeUpdate"].Text := "Delete matching rules"
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

BuildSnippet(tool, isScan, isCommands) {
    global DefaultOwner, DefaultRepo, DefaultRef, MaxLength
    timeout := isScan ? tool["TimeoutScan"] : tool["TimeoutUpdate"]
    fetch := ToolGet(tool, "Fetch", "Contents")

    if (fetch = "DownloadExe") {
        url := ToolGet(tool, "Url", "")
        outFile := ToolGet(tool, "OutFile", "C:\Windows\Temp\tool.exe")
        argList := ToolGet(tool, "ExeArgList", "")
        body := "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $url='" url "'; $out='" outFile "'; Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing; Start-Process -FilePath $out -ArgumentList " argList " -Wait"
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
            url := "https://raw.githubusercontent.com/" owner "/" repo "/main/" script
            if ToolHasFlag(tool, "CacheBust")
                url .= "?v=" ver
            body := "Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $ProgressPreference='SilentlyContinue'; $out=Join-Path $env:TEMP '" tempName "'; Invoke-RestMethod -Uri '" url "' -OutFile $out; & $out" switches
        } else if (fetch = "Raw") {
            owner := ToolGet(tool, "Owner", DefaultOwner)
            repo := ToolGet(tool, "Repo", "")
            script := tool["Script"]
            ver := ToolGet(tool, "UaVer", "1.0.0")
            url := "https://raw.githubusercontent.com/" owner "/" repo "/main/" script
            if ToolHasFlag(tool, "CacheBust")
                url .= "?v=" ver
            body := "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $url='" url "'; $script=(Invoke-WebRequest -Uri $url -UseBasicParsing).Content; & ([ScriptBlock]::Create($script))" switches
        } else {
            ua := tool["UaPrefix"] "/" tool["UaVer"]
            path := tool["Path"]
            script := tool["Script"]
            url := "https://api.github.com/repos/" DefaultOwner "/" DefaultRepo "/contents/" path "/" script "?ref=" DefaultRef
            body := "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','" ua "'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('" url "'); & ([scriptblock]::Create($script))" switches
        }
    }

    noteLine := ""
    clipNote := ToolGet(tool, "ClipboardNote", "")
    if (clipNote != "") {
        if ToolHasFlag(tool, "AlwaysNote")
            noteLine := "`n# " clipNote
        else if ToolHasFlag(tool, "RebootAdvisory") && !isScan
            noteLine := "`n# " clipNote
    }

    if isCommands
        return "#!ps`n#timeout=" timeout "`n#maxlength=" MaxLength "`n" body noteLine
    return body noteLine
}

DescribeSelection(tool, isScan) {
    global gCtrls
    mode := "Scan only"
    if ToolHasFlag(tool, "RunOnly") {
        if ToolHasFlag(tool, "SentinelOneInstall")
            mode := "Silent install"
        else if ToolHasFlag(tool, "ConnectSecure")
            mode := "Silent install"
        else
            mode := "Download and run"
    } else if ToolHasFlag(tool, "ScanOnly") && (ToolGet(tool, "Fetch", "") = "IrmOutFile")
        mode := "Collect / run"
    if !isScan && !ToolHasFlag(tool, "RunOnly") {
        if ToolHasFlag(tool, "Delete") || ToolHasFlag(tool, "PositionalDry")
            mode := "Remove"
        else if ToolHasFlag(tool, "Remediate")
            mode := "Clean up"
        else
            mode := "Apply updates"
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
    if ToolHasFlag(tool, "ScanOnly")
        gCtrls["ModeScan"].Value := 1
    if ToolHasFlag(tool, "RunOnly")
        gCtrls["ModeUpdate"].Value := 1
    isScan := gCtrls["ModeScan"].Value
    isCommands := gCtrls["FmtCommands"].Value

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

    snippet := BuildSnippet(tool, isScan, isCommands)
    A_Clipboard := snippet
    ClipWait(1)
    desc := DescribeSelection(tool, isScan)
    gCtrls["Status"].Value := "Copied: " desc
    TrayTip("Copied to clipboard", desc, "Iconi")
    SetTimer(() => TrayTip(), -2500)
}
