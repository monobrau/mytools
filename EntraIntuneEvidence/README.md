# Entra / Intune evidence export

Read-only export for the evidence request that asks for:

- an Active Directory authorized-user list (also Microsoft 365 and Entra)
- a list of service accounts from Active Directory (also Microsoft 365 and Entra)
- evidence that BitLocker is deployed, one row per workstation

The directory source is Entra ID. That is the Microsoft 365 directory. Users synced from on-premises Active Directory are included (`OnPremisesSyncEnabled`). Accounts that exist only on a domain controller and are not synced are not in the export.

BitLocker rows come from the Intune encryption report. Recovery keys are not exported.

## Requirements

- PowerShell 5.1 or 7
- `Microsoft.Graph` (Authentication is enough; the script calls Graph directly)
- A signed-in account that can read users and Intune device encryption. Consent prompts for `User.Read.All`, `Directory.Read.All`, `AuditLog.Read.All`, `DeviceManagementManagedDevices.Read.All`, and `DeviceManagementConfiguration.Read.All`.

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

`AuditLog.Read.All` fills `LastSignInDateTime`. If that consent is missing, the script still writes the lists and leaves last sign-in blank.

## Usage

```powershell
cd EntraIntuneEvidence
.\Get-EntraIntuneEvidence.ps1
```

Files are written to the local OneDrive folder on this PC, `OneDrive\EntraIntuneEvidence\<tenant>\<timestamp>\`. The script does not sign in to OneDrive.

| File | Contents |
| --- | --- |
| `AuthorizedUsers.csv` | Enabled Entra members. This is the authorized-user list. |
| `ServiceAccounts.csv` | Accounts whose name, title, department, or on-premises OU looks like a service account. |
| `BitLocker-Workstations.csv` | One Windows workstation per row, with `BitLockerDeployed` and the Intune policy name. |
| `Evidence-Notes.txt` | When it was collected, what each file means, and the counts. |

`-OutputPath` overrides the folder. If no local OneDrive path is set, the script warns and uses Documents.

## Service accounts

Entra has no service-account object class. `ServiceAccounts.csv` is what remains after three exclusions:

- obvious person names (two or more name words, or a hyphenated first-last sign-in)
- admin accounts (the name contains `admin` or `break-glass`)
- test accounts (the name contains `test`)

A matching `svc`, `srv`, or `sa-` name, a "service account" title, a service OU, or `-ServiceAccountPattern` is recorded in `ServiceAccountReason` when it applies. Everything else that survived the exclusions is included with reason `NeedsReview`.

```powershell
.\Get-EntraIntuneEvidence.ps1 -ServiceAccountPattern 'backup|sqlagent'
```

Prune `ServiceAccounts.csv` before you send it. One-word application names and Microsoft-generated ids can still be on the list.

## BitLocker

`BitLockerDeployed` is `Yes` when the Intune report says the device is encrypted and the OS volume is not reported unprotected. `IntunePolicyNames` is the encryption policy Intune attached to that workstation. Mac, iPhone, iPad, and Android devices are left out of the workstation file.
