# Stale user profiles

Lists Windows user profiles on a shared lab PC that have not signed in for 90 days, then removes only that list.

The profile folder and the profile-list entry are removed. The user account stays. The next sign-in creates a new profile.

These are kept:

- The signed-in user, and any profile that is loaded
- Special profiles and anything under the Windows directory, including service profiles
- The built-in Administrator account (RID 500)
- Direct members of the local Administrators group

Nested domain groups are not expanded. A profile with no last-use time is listed and kept.

## Usage

Run elevated. Scan first.

```powershell
.\Remove-StaleUserProfile.ps1 -CheckOnly -Days 90
.\Remove-StaleUserProfile.ps1 -Remediate -Days 90
```

`-CheckOnly` wins when both switches are passed. `-Days` below 1 changes nothing.

Exit `0` means nothing to remove, or every targeted profile was removed. Exit `1` means the scan found profiles that would be removed. Exit `2` means a remove failed, the window is not elevated, or the Administrators group could not be read.

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). ScToolLauncher: **Untested → Stale user profiles**. Scan lists. Clean up removes. Reload the launcher after updating `ScToolLauncher.ahk`.
