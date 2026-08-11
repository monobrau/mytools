# Teams Classic Remnant Check

Post-cleanup **verification** that Classic Microsoft Teams / per-user Teams leftovers are gone (vuln-scan remediation evidence).

Default is **check only**. Pass **`-Remediate`** to remove **Classic only** (MWI / classic per-user / classic Run keys / Teams Installer folder), then re-scan.

**Safety for real Teams users**
- Never uninstalls **New Teams** (`MSTeams` / `MicrosoftTeams` Appx) or kills `ms-teams`
- Removes classic per-user `%LocalAppData%\Microsoft\Teams` only when New Teams is already on the device (or with `-ForceClassicUserRemoval`)
- Shortcuts are deleted only if they target Classic paths (not WindowsApps / ms-teams)

## What it flags (fail)

| Check | Location |
| --- | --- |
| Teams Machine-Wide Installer | ARP (`Uninstall` keys) |
| Classic Teams ARP | DisplayName `Teams` / `Microsoft Teams` (non-MWI) |
| Teams Installer folder | `%ProgramFiles(x86)%\Teams Installer` |
| Per-user Classic client | `%LocalAppData%\Microsoft\Teams` (`current\Teams.exe`, `Update.exe`, other files) |
| Autorun | HKLM / loaded HKU `Run` values for Teams / squirrel |

## Informational

- **New Teams** (`MSTeams` / `MicrosoftTeams` Appx) - reported but does **not** fail the check
- Shortcuts named `*Teams*.lnk` - **warn** by default; with `-Detailed` they fail the check

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Clean (no classic fail findings) |
| `2` | Classic remnants still present |
| `1` | Script error |

## Parameters

| Parameter | Meaning |
| --- | --- |
| _(none)_ | Run check |
| `-Remediate` | Remove Classic remnants only, then re-scan |
| `-ForceClassicUserRemoval` | With remediate: wipe classic per-user even if New Teams is missing |
| `-Detailed` | Treat warn items (e.g. shortcuts) as failing; include empty-folder noise |
| `-Json` | Emit JSON summary after logs |
| `-NoExit` / `-Exit` | Host lifecycle for Backstage vs Commands |

## Backstage (SYSTEM) one-liner

Paste the **entire line**:

```powershell
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','TeamsClassicRemnantCheck-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/TeamsClassicRemnantCheck/Test-ClassicTeamsRemnants.ps1?ref=main'); Write-Host ('Downloaded '+$script.Length+' chars'); & ([scriptblock]::Create($script))
```

Expect `TeamsClassicRemnantCheck 1.0.0` and either `PASS: no Classic...` or `FAIL: Classic Teams remnants still present`.

## ScreenConnect Commands

See [`ScreenConnect-Commands.ps1`](ScreenConnect-Commands.ps1).

## Requirements

- Windows PowerShell **5.1+** or PowerShell **7+**
- Prefer **SYSTEM** / admin so all profiles are visible
- Outbound HTTPS to `api.github.com` when bootstrapping from GitHub
