# Stale user profiles

Lists Windows user profiles on a shared lab PC that are older than a cutoff, then removes only that list. The default cutoff is 2 calendar months before today.

The profile folder and the profile-list entry are removed. The user account stays. The next sign-in creates a new profile.

These are kept:

- The signed-in user, and any profile that is loaded
- Special profiles and anything under the Windows directory, including service profiles
- The built-in Administrator account (RID 500)
- Direct members of the local Administrators group

Age is the older of the last logoff time and `NTUSER.DAT`. The Windows profile last-use time is not used; on a lab image it is often today for every profile. Nested domain groups are not expanded. A profile with neither timestamp is listed and kept.

## Usage

Run elevated. Scan first.

```powershell
.\Remove-StaleUserProfile.ps1 -CheckOnly
.\Remove-StaleUserProfile.ps1 -Remediate -Months 2
.\Remove-StaleUserProfile.ps1 -CheckOnly -Weeks 6
.\Remove-StaleUserProfile.ps1 -CheckOnly -Days 45
```

Pass one of `-Months`, `-Weeks`, or `-Days`. The default is `-Months 2`. A month counts back on the calendar. A week is 7 days. `-CheckOnly` wins when both mode switches are passed. An age outside 1–120 months, 1–520 weeks, or 1–3650 days changes nothing.

Exit `0` means nothing to remove, or every targeted profile was removed. Exit `1` means the scan found profiles that would be removed. Exit `2` means a remove failed, the window is not elevated, or the Administrators group could not be read.

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). ScToolLauncher: **Clients → St. Francis Seminary → Stale user profiles**. Scan lists. Clean up removes. The age box defaults to 2 months. Reload the launcher after updating `ScToolLauncher.ahk`.
