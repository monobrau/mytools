# EOL dependency use

See whether an out-of-support runtime is actually loaded, and which process loads it, before removing it.

The check follows the same idea as [Microsoft's VC++ runtime auditing](https://learn.microsoft.com/en-us/cpp/windows/redist-version-auditing): File System success auditing plus an execute audit on specific DLLs, which writes Security event 4663. This script audits a few sentinel files per family, reads only the process and file name, and stores hit counts. It does not export the event message.

Run it elevated from PowerShell or ScreenConnect, or push the same script with `Install-EolDependencyAuditGpo.ps1`. Both take `-Dependency`, `-Action`, and `-MaxDailyLogMB`.

## What it records

| Kept | Not kept |
| --- | --- |
| Family, process path, sentinel file name, hit count, first and last time | Event message, user, access mask, handle |

The hit list is overwritten at `C:\ProgramData\EolDependencyAudit\usage.csv`. `budget.txt` is the Security-log size and the current 4663 pace. `runs.log` keeps the last 200 lines.

## Log space

Each sentinel load writes one 4663. A record is often about 1–2 KB. Auditing every DLL under `dotnet` or SQL Server is what fills the log. This script does not do that.

Measure prints:

- Security log size, maximum, and mode (Circular, Retain, or AutoBackup)
- How many 4663 events landed in the last hour, and the MB/day that pace would use
- Whether File System success auditing is already on
- How many sentinel files the selected families have on this PC

The read stops at 20,000 events. If it hits that cap, the pace is a floor and Enable/Watch will not arm auditing unless `-Force` is set.

Enable and Watch also refuse when the log is not Circular, or when that current pace is over `-MaxDailyLogMB` (default 64). They then remove this script's execute-audit rule so a later noisy day turns itself down. `-Force` arms anyway.

`-SampleMinutes 10` with Measure arms the sentinels, prints log growth each minute, projects a full day, and then removes the rules. That is the added-cost check. The GPO does not schedule a sample, because an Immediate Task would repeat it on every refresh. Run the sample on one PC from ScreenConnect first.

A family marked NOT USED means no 4663 for its sentinels in the window. If the event read hit the cap, that family is UNKNOWN instead.

## Families

Omit `-Dependency` for the EOL set. `-Dependency VC2012,DotNet5` limits the run. `-Dependency All` also includes .NET 8.

| Name | EOL by default | Sentinel |
| --- | --- | --- |
| VC2005, VC2008 | yes | `msvcr` / `msvcp` under `WinSxS\Fusion` |
| VC2010, VC2012, VC2013 | yes | `msvcr` / `msvcp` in System32 and SysWOW64 |
| DotNet31, DotNet5, DotNet6, DotNet7 | yes | `coreclr.dll` in that shared framework folder |
| DotNet8 | no | same, only when named |
| Silverlight | yes | `npctrl.dll` or `coreclr.dll` |
| Sql2008, Sql2012 | yes | `sqlncli10.dll`, `sqlncli11.dll` |
| SqlCompact | yes | `sqlceqp40.dll` |

A DLL sitting next to an application is not seen unless you add that folder. Copy `dependencies.example.csv`, add a row, and pass `-CatalogPath`. `Kind` is `File` (exact names in those folders), `Version` (child folder prefix, then the file), or `Walk` (recurse, name is a regex). Roots are separated with `|`. A drive root, `Windows`, `WinSxS`, or `Program Files` itself is rejected.

```powershell
.\Invoke-EolDependencyAudit.ps1 -Action Measure -Dependency VC2012
.\Invoke-EolDependencyAudit.ps1 -Action Measure -SampleMinutes 10 -Dependency VC2012
.\Invoke-EolDependencyAudit.ps1 -Action Watch -Dependency VC2012,DotNet5 -MaxDailyLogMB 64
.\Invoke-EolDependencyAudit.ps1 -Action Disable -Dependency VC2012
```

Exit `0` means nothing selected was loaded. Exit `1` means something was. Exit `2` is an error. Exit `3` means auditing was not left on because of the log cap.

The launcher scan copies Measure. Apply copies Watch. Force adds `-Force`.

## GPO

Run elevated as a Domain Admin on a DC or RSAT box. The script copies `Invoke-EolDependencyAudit.ps1` to `\\<domain>\NETLOGON\EolDependencyAudit\` and creates an Immediate Task that runs as SYSTEM at the next Group Policy refresh. Pass the same `-Action`, `-Dependency`, and `-MaxDailyLogMB` the endpoint script uses.

Watch and Enable also write the Advanced Audit Policy "Audit File System / Success" into that GPO. Measure does not. Disable removes the sentinel rules and does not turn File System auditing off, because other files may use it.

Pilot an OU before the domain root. Servers are included unless the OU leaves them out. A domain controller's Security log is a poor place to discover this.

```powershell
.\Install-EolDependencyAuditGpo.ps1 -Action Measure -Dependency VC2012 -DryRun
.\Install-EolDependencyAuditGpo.ps1 -Action Watch -Dependency VC2012,DotNet5 -MaxDailyLogMB 64 -TargetOU 'OU=Workstations,DC=contoso,DC=com'
.\Install-EolDependencyAuditGpo.ps1 -Action Disable -TargetOU 'OU=Workstations,DC=contoso,DC=com'
```

If `dependencies.csv` sits next to the installer, it is staged and passed as `-CatalogPath`. The example file is not applied on its own.

Task log: `C:\ProgramData\EolDependencyAudit\gpo-task.log`.
