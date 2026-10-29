# Pale Moon Portable

Downloads the official 64-bit Pale Moon portable build onto the PC where PowerShell is running, writes a desktop shortcut, and launches it.

This is for ScreenConnect **Backstage** or a local PowerShell window on the admin PC. It is not a remote Commands tool. There is no `ScreenConnect-Commands.ps1`.

The script reads the current `Palemoon-Portable-*.win64.exe` name and SHA256 from the [Pale Moon download page](https://www.palemoon.org/download.shtml), then downloads that file from the official US mirror (EU if the US download does not match). Files land in `%LOCALAPPDATA%\PaleMoonPortable`. The shortcut is `Pale Moon Portable.lnk` on the current user's desktop and points at `Palemoon-Portable.exe`.

A later run leaves that copy in place when the published version is unchanged. A newer published build replaces the program files and copies the existing `User` folder onto the new copy. Close Pale Moon first if it is still running from that folder.

## Usage

```powershell
.\Install-PaleMoonPortable.ps1
```

ScToolLauncher: **Untested → Pale Moon Portable**. Copy pastes a PowerShell one-liner only.
