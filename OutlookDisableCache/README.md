# Outlook: disable local cache

Shared lab computers fill the disk with one Outlook mailbox copy (`.ost`) per person. This turns **Cached Exchange Mode** off for every local profile, including the Default profile so the next sign-in does not start a new cache.

Classic Outlook only (2013 and 2016 / 2019 / 2021 / Microsoft 365). New Outlook is a different app and is not changed. Personal `.pst` archives are not deleted.

A domain GPO that turns Cached Exchange Mode back on writes the same registry value and will undo this at the next Group Policy refresh.

## What it sets

For Office **15.0** and **16.0**, in each user hive:

| Value | Effect |
| --- | --- |
| `Software\Policies\Microsoft\Office\<ver>\Outlook\Cached Mode` `Enable` = `0` | Policy "Use Cached Exchange Mode for new and existing Outlook profiles" is Disabled. The checkbox is off and the user cannot turn it back on. |
| `Software\Microsoft\Office\<ver>\Outlook\OST` `NoOST` = `3` | Outlook does not create an OST and does not use one that is already there. |

## What it deletes

Only with **`-Apply -RemoveCache`**:

- `AppData\Local\Microsoft\Outlook\*.ost` and `*.nst`
- Files in a custom `ForceOSTPath`, when one is set

Classic Outlook is closed first so the files are not locked. Offline Address Book folders are left alone.

## Usage

Run elevated. Default is a dry run.

```powershell
.\Disable-OutlookLocalCache.ps1
.\Disable-OutlookLocalCache.ps1 -Apply
.\Disable-OutlookLocalCache.ps1 -Apply -RemoveCache
```

`-CheckOnly` is the same dry run. `-Remediate` is the same as `-Apply -RemoveCache`. The launcher sends those two.

ScToolLauncher: **Lab PC → Outlook disable local cache**. Scan copies a dry run. Clean up copies the policy write and cache delete. Both paste a `#!ps` or PowerShell one-liner that downloads this script from GitHub and runs it. Reload the launcher after pulling.

Exit `0` means the PC is already compliant, or `-Apply` finished. Exit `2` means a scan found policy gaps or cache files. Exit `1` means a hive could not be loaded or a cache file stayed locked.

## ScreenConnect

See [`ScreenConnect-Commands.ps1`](ScreenConnect-Commands.ps1).
