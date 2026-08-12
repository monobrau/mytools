# DotNetUpdate

Silently patch installed **.NET 6+** components to the latest **same-major** security release.

- Updates: `Microsoft.NETCore.App`, `Microsoft.WindowsDesktop.App`, `Microsoft.AspNetCore.App`, SDK
- **Does not** jump majors (no 6→8, no 8→9)
- **Does not** install majors that are not already present
- **Does not** manage .NET Framework (Windows Update / other tooling)

Uses Microsoft release-metadata installer URLs (fallback `aka.ms/dotnet/{major}.0/dotnet-runtime-...` etc.) with `/install /quiet /norestart`.

Also wired into [VulnSoftwareUpdate](../VulnSoftwareUpdate/) as catalog id `DotNet`.

## ScreenConnect (`#!ps`)

```
#!ps
#timeout=1800000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','DotNetUpdate-bootstrap/1.0.1'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/DotNetUpdate/Update-DotNetRuntimes.ps1?ref=main'); & ([scriptblock]::Create($script)) -CheckOnly -Exit
```

Update (no `-CheckOnly`):

```
#!ps
#timeout=1800000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','DotNetUpdate-bootstrap/1.0.1'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/DotNetUpdate/Update-DotNetRuntimes.ps1?ref=main'); & ([scriptblock]::Create($script)) -Exit
```

Exit: `0` up to date / nothing installed, `2` updates needed or still behind, `1` error.

## Local

```powershell
.\Update-DotNetRuntimes.ps1 -CheckOnly
.\Update-DotNetRuntimes.ps1
```

## Note vs old `dotnet-updater`

The older standalone `dotnet-updater` repo could jump majors (e.g. 7/8 → 9). This tool intentionally stays on the installed major and only applies security patches.
