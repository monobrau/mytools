# Forensic Investigator

Combines the Sysinternals risk scan from `Invoke-ForensicAnalysis` with Harkins-style host artifacts and event-log export. Inventories **every user** `Downloads` and `Desktop` (plus `Public`).

Reports default to `C:\SecurityReports` from ScreenConnect.

## What it collects

| Source | Output |
|--------|--------|
| Sysinternals autorunsc + services + TCP + processes | CSV with SHA256, signature, optional VirusTotal, risk level |
| **All-user Downloads and Desktop** | CSV with hash/signature plus **Zone.Identifier** (ZoneId, ReferrerUrl, HostUrl) on hashed files |
| Per-user PowerShell history / transcripts | `Artifacts_*/PowerShell/` + `PowerShellHistory` CSV |
| Amcache.hve + SYSTEM hive (and LOG files) | `Artifacts_*/Hives/` — copy only, parse offline |
| Chrome / Edge / Brave `History` SQLite | `Artifacts_*/BrowserHistory/` — copied with share-read, not queried live |
| Local Administrators (SID S-1-5-32-544) + RMM inventory | CSVs |
| Defender detections + DetectionHistory folder | `DefenderDetections` CSV + `Artifacts_*/Defender/` |
| Prefetch, scheduled tasks, installed software, local users, logged-on users, DNS cache, ARP | CSVs |
| `systeminfo` | `{HOST}_SystemInfo_{stamp}.txt` |
| Harkins EVTX set | `EventLogs_{stamp}\` |
| Manifest + zip hash | `{HOST}_ForensicAnalysis_{stamp}.zip` and `{zip}.sha256`. Loose CSVs, `EventLogs_{stamp}`, and `Artifacts_{stamp}` are deleted after the zip is written |

Does **not** enable extra Windows logs (Harkins does; that changes the host). It only exports logs that already exist.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-OutputPath` | `.\ForensicReports` | Report directory (launcher uses `C:\SecurityReports`) |
| `-ToolsPath` | `.\SysinternalsTools` | Sysinternals download folder |
| `-CleanupTools` | off | Delete tools after the scan |
| `-EnableVirusTotal` | off | Hash lookup (needs a key; no `Read-Host` in ScreenConnect) |
| `-VirusTotalApiKey` | empty | VT API key — never commit |
| `-ExportXLSX` / `-CombinedWorkbook` | off | Excel (requires Excel) |
| `-SkipDownloads` | off | Skip all-user Downloads/Desktop inventory |
| `-SkipHostArtifacts` | off | Skip prefetch/tasks/users/software/DNS/ARP |
| `-SkipEventLogs` | off | Skip EVTX export |

Needs **Administrator** and PowerShell 5.1+. Downloads tools from `live.sysinternals.com`.

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Or ScToolLauncher (**IR / forensics** → Forensic Investigator). Prefer elevated / Backstage. Timeout 15 minutes.

Without VirusTotal, Sysinternals + Downloads + artifacts is usually several minutes. EVTX export adds time. VT on a busy host can take 30–60+ minutes.

## Local usage

```powershell
.\Invoke-ForensicAnalysis.ps1 -OutputPath "C:\SecurityReports"
.\Invoke-ForensicAnalysis.ps1 -OutputPath "C:\SecurityReports" -SkipEventLogs
.\Invoke-ForensicAnalysis.ps1 -EnableVirusTotal -VirusTotalApiKey $env:VT_API_KEY
```

## Safety

- Does not uninstall software or stop services
- Does not enable Windows event logs
- Never commit a VirusTotal API key
- Gmail/credential wrappers from the old standalone repo are not included
