# Entra vendor enterprise app removal

Deletes INKY, usecure, and Barracuda (Skout) enterprise apps from the signed-in Entra tenant.

The app id and the service principal object id are different in each tenant. The script finds apps by display name (INKY / Phish Fence, usecure, Skout or Barracuda Cybersecurity). A few example IDs are kept only so a renamed app in the tenant they came from is still found. Other Barracuda products, such as Email Gateway Defense, are left alone.

Run this after the vendor is offboarded. Deleting Inky Dashboard SSO removes INKY portal sign-in for that tenant.

## Requirements

- PowerShell 5.1 or 7
- `Microsoft.Graph` (Applications + Authentication)
- Application Administrator or Cloud Application Administrator

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

## Usage

```powershell
cd EntraVendorAppRemoval

# Menu of whatever this tenant actually has
.\Remove-VendorEnterpriseApps.ps1

# One vendor, preview only (writes a JSON backup, does not delete)
.\Remove-VendorEnterpriseApps.ps1 -Vendor Inky -WhatIf

# Every match in the tenant
.\Remove-VendorEnterpriseApps.ps1 -All

# This tenant's app id or object id
.\Remove-VendorEnterpriseApps.ps1 -AppId 00000000-0000-0000-0000-000000000000
```

The menu accepts `1,3`, `1-3`, `inky`, `usecure`, `barracuda`, `skout`, `all`, or `q`.

From the SC Tool Launcher, paste the PowerShell one-liner into Backstage on this PC. Scan sends `-CheckOnly` and only lists matches. Apply sends `-Delete` and opens the picker.

Deletion asks you to type `DELETE`. `-Force` skips that prompt. `-WhatIf` still does not delete.

Backups go to `OneDrive\EntraVendorAppRemoval\<tenant>\<timestamp>\` (work OneDrive first) unless you pass `-OutputPath`. Each app is a `<appId>.json` plus `results.csv`. If OneDrive cannot be found, the backup is saved under Documents and the script says so.

Exit codes: `0` done or nothing selected, `2` a delete failed, `1` a hard error (sign-in or backup).

## Restore

Deleted enterprise apps stay under Entra > Enterprise applications > Deleted applications for 30 days.

```powershell
Restore-MgDirectoryDeletedItem -DirectoryObjectId <objectId>
```

That brings the app object back. Consents and role assignments are not restored. The JSON backup is the list of what was there.
