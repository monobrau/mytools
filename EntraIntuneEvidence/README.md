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

Files land in `OneDrive\EntraIntuneEvidence\<tenant>\<timestamp>\`:

| File | Contents |
| --- | --- |
| `AuthorizedUsers.csv` | Enabled Entra members. This is the authorized-user list. |
| `ServiceAccounts.csv` | Accounts whose name, title, department, or on-premises OU looks like a service account. |
| `BitLocker-Workstations.csv` | One Windows workstation per row, with `BitLockerDeployed` and the Intune policy name. |
| `Evidence-Notes.txt` | When it was collected, what each file means, and the counts. |

`-OutputPath` overrides the folder. If OneDrive cannot be found, the script warns and uses Documents.

## Service accounts

Entra has no service-account object class. A row is included when any of these match:

- the name, UPN, or mail nickname looks like `svc`, `srv`, or `sa-`
- the job title or department says "service account"
- the on-premises distinguished name has an OU containing "service"
- `-ServiceAccountPattern` matches (your extra regular expression)

`PasswordNeverExpires` is a column on the row. It is not enough, by itself, to call someone a service account.

```powershell
.\Get-EntraIntuneEvidence.ps1 -ServiceAccountPattern 'backup|sqlagent'
```

Review `ServiceAccounts.csv` before you send it. A person who sits in an OU named Service will be on that list.

## BitLocker

`BitLockerDeployed` is `Yes` when the Intune report says the device is encrypted and the OS volume is not reported unprotected. `IntunePolicyNames` is the encryption policy Intune attached to that workstation. Mac, iPhone, iPad, and Android devices are left out of the workstation file.
