# PUP remnant cleanup

Definition-driven leftover sweep for toolbars and search hijackers. **Ask Toolbar / Ask.com** is the first family. Add the next PUP as another catalog entry in `Invoke-PupRemnantCleanup.ps1` (`Get-PupCatalog`).

Default is a **dry-run of every catalog family** (Ask Toolbar, MediaArena PDF converters, AppSuite/TamperedChef PDF Editor, Wave Browser, OneLaunch, fake converter installers) and reports whatever is actually on the host. Pass **`-Name AskToolbar`** (or several ids) to limit to some families. Pass **`-Remove`** (or **`-Remediate`**) to delete every removable finding for those families. Chromium / Firefox preference files are **reported only** — never rewritten (live JSON / `prefs.js`).

Huntress (or similar) often already removed `Scheduled Update for Ask Toolbar` and `updatetask.exe`. This finishes what is typically left behind.

Matches stay specific (`Ask Toolbar`, `Ask.com`, `AskToolbar`, `APN`). A bare `Ask` is not used, so Copilot and other help UI are not flagged.

## Catalog

| Id | What it targets |
| --- | --- |
| `AskToolbar` | Ask.com / Ask Toolbar / APN folders, ARP, registry, leftover tasks/services, IE search scopes, Run keys, `ask.com` prefs |
| `MediaArena` | PdfPower / PdfMagic / zip-gif converters, `searchpoweronline.com` hijack, Desktop/Downloads leftovers |
| `AppSuitePdf` | AppSuite-PDF.msi / TamperedChef `PDF Editor` / ManualFinderApp (not Foxit or Adobe) |
| `WaveBrowser` | Wavesor Wave Browser (`WaveBrowser-StartAtLogin`) |
| `OneLaunch` | OneLaunch / OneStart launcher adware |
| `FakePdfConverter` | ConvertMate, Easy2Convert, UpdateRetriever, and related malvertising converter installers |

```powershell
.\Invoke-PupRemnantCleanup.ps1 -List
.\Invoke-PupRemnantCleanup.ps1                  # all catalog families; what's on the host
.\Invoke-PupRemnantCleanup.ps1 -Name AskToolbar # one family
.\Invoke-PupRemnantCleanup.ps1 -Remove          # delete every present family
```

To add a family: copy a hashtable in `Get-PupCatalog`, change `Id` / paths / regexes. Keep patterns specific — do not use a vendor-generic word (`PDF`, `Update`, `Search`) that hits unrelated software. Domain matches need a lookbehind (`(?<![A-Za-z0-9])ask\.com`) so a site like `hydroflask.com` is not flagged. `FolderNameMatch` / `LooseFileMatch` catch per-user AppData folders and leftover Downloads/Desktop/Startup installers.

## What it flags

| Type | Action on `-Remove` |
| --- | --- |
| Folders (Program Files, ProgramData, per-user AppData) | Delete |
| Scheduled tasks + leftover `System32\Tasks` files | Unregister / delete |
| Services | Stop + delete |
| Uninstall (ARP) keys | Delete |
| PUP registry roots + hijacked IE / policy values | Delete key or value |
| IE search scopes | Delete |
| Run / RunOnce values | Delete value |
| Matching processes (`updatetask`, etc.) | Stop |
| Chrome / Edge / Brave `Preferences`, Firefox `prefs.js` | Report only |
| Named AppData / Program Files folders (`FolderNameMatch`) | Delete |
| Leftover Downloads / Desktop / Startup installers (`LooseFileMatch`) | Delete file |

Prefer **elevated / Backstage** so every profile folder and loaded hive is visible.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Clean (or removal left nothing behind) |
| `2` | Remnants still present |
| `1` | Script error |

## Parameters

| Parameter | Meaning |
| --- | --- |
| _(none)_ | Dry-run every catalog family; report what is present |
| `-Name AskToolbar` | One family (`-Id` / `-Product` aliases; comma-separated for several) |
| `-All` | Every catalog family (same as omitting `-Name`) |
| `-List` | Print ids |
| `-Remove` / `-Remediate` | Delete removable findings for the selected families, then re-scan |
| `-CheckOnly` | Force dry-run |
| `-Json` | JSON summary after the log |
| `-NoExit` / `-Exit` | Host lifecycle for Backstage vs Commands |

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Prefer elevated / Backstage. Or use ScToolLauncher (**IR / forensics** → PUP remnant cleanup).

## Requirements

- Windows PowerShell **5.1+** or PowerShell **7+**
- Outbound HTTPS to `api.github.com` when bootstrapping from GitHub
