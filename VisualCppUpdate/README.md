# Visual C++ 2005-2013 redistributable updates

Silently patch **already installed** Visual C++ 2005, 2008, 2010, 2012, and 2013
redistributables (x86 and x64) to the last Microsoft security build for that year.

- Does **not** install a year that is missing
- Does **not** touch Visual C++ 2015-2022 (use [VulnSoftwareUpdate](../VulnSoftwareUpdate/) `VcRedistX64` / `VcRedistX86` via winget)

Also wired into VulnSoftwareUpdate as catalog id `VcRedistLegacy`.

| Year | Final build | Notes |
| --- | --- | --- |
| 2005 | 8.0.50727.6195 | KB2538242 |
| 2008 | 9.0.30729.5677 | KB2538243 |
| 2010 | 10.0.40219 | KB2565063 |
| 2012 | 11.0.61030.0 | Update 4 |
| 2013 | 12.0.40649.5 | Last 2013 redist |

## ScreenConnect (`#!ps`)

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Prefer elevated / SYSTEM.

```
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','VisualCppUpdate-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/VisualCppUpdate/Update-VisualCppRedistributables.ps1?ref=main'); & ([scriptblock]::Create($script)) -CheckOnly -Exit
```

Update (no `-CheckOnly`):

```
#!ps
#timeout=1800000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','VisualCppUpdate-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/VisualCppUpdate/Update-VisualCppRedistributables.ps1?ref=main'); & ([scriptblock]::Create($script)) -Exit
```

Exit: `0` none installed or all current / updated, `2` check found updates or reboot still needed, `1` error.

## Local

```powershell
.\Update-VisualCppRedistributables.ps1 -CheckOnly
.\Update-VisualCppRedistributables.ps1
.\Update-VisualCppRedistributables.ps1 -Year 2010,2013
.\Update-VisualCppRedistributables.ps1 -Force
```
