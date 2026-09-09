# Windows Defender repair

**Scan** (`-CheckOnly`): report `WinDefend` / `WdNisSvc` / `Sense` running
state, real-time protection, and tamper protection. No changes.

**Apply**: full RTP repair — re-enable services that were Disabled, set
`Disable*` policy/preference DWORDs to 0, set `ForceDefenderPassiveMode=0`,
start `WinDefend` / `WdNisSvc` / `Sense` / `MdCoreSvc` / Security Center
services, then `Set-MpPreference` after WinDefend is Running. Waits for
`Get-MpComputerStatus` to refresh (CIM often lags). Does not restart
WinDefend (protected). Does not uninstall a third-party AV or turn off
Tamper Protection.

**Backstage / SYSTEM only.** Defender cmdlets often fail or return empty in
ScreenConnect Commands. The launcher forces the Backstage one-liner.

**`-ResetPlatform`** (nuclear): runs
`MpCmdRun.exe -ResetPlatform` from the newest
`%ProgramData%\Microsoft\Windows Defender\Platform\<version>` folder, then
applies the same real-time protection repair.

## ScreenConnect

Use ScToolLauncher (**AV** → Windows Defender repair). Paste format is locked
to Backstage. Reload the launcher after pull so the catalog picks up `1.0.6`.
Scan = health only. Apply covers disabled services, policy/preference
`Disable*` keys, Passive mode, and a status settle wait. If Apply says RTP
is off, run Scan — CIM can lag. If Scan is still off, read the Exception.
