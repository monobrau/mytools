# Windows Defender repair

Re-enables real-time protection (MpPreference + policy DWORD values set to 0)
and starts `WinDefend` and `WdNisSvc`.

**`-ResetPlatform`** (nuclear): runs
`MpCmdRun.exe -ResetPlatform` from the newest
`%ProgramData%\Microsoft\Windows Defender\Platform\<version>` folder, then
applies the same real-time protection repair.

Needs elevation (ScreenConnect **Backstage** / SYSTEM).

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Or use ScToolLauncher
(**AV** → Windows Defender repair).
