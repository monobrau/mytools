# Windows Defender repair

**Scan** (`-CheckOnly`): report `WinDefend` / `WdNisSvc` / `Sense` running
state, real-time protection, and tamper protection. No changes.

**Apply**: full RTP repair — re-enable services that were Disabled, set
`Disable*` policy/preference DWORDs to 0, set `ForceDefenderPassiveMode=0`,
start `WinDefend` / `WdNisSvc` / `Sense` / `MdCoreSvc` / Security Center
services, then `Set-MpPreference` after WinDefend is Running (retry once).
Does not uninstall a third-party AV and does not turn off Tamper Protection.

**Backstage / SYSTEM only.** Defender cmdlets often fail or return empty in
ScreenConnect Commands. The launcher forces the Backstage one-liner.

**`-ResetPlatform`** (nuclear): runs
`MpCmdRun.exe -ResetPlatform` from the newest
`%ProgramData%\Microsoft\Windows Defender\Platform\<version>` folder, then
applies the same real-time protection repair.

## ScreenConnect

Use ScToolLauncher (**AV** → Windows Defender repair). Paste format is locked
to Backstage. Reload the launcher after pull so the catalog picks up `1.0.5`.
Scan = health only. Apply covers disabled services, policy/preference
`Disable*` keys, Passive mode, and a WinDefend restart retry. If RTP stays
off, read the Exception line (other WSC AV, Tamper, or GPO).
