# Barracuda Offboarding

PowerShell tool that finds and removes residual Barracuda tenancy from a Microsoft 365 tenant after a client migrates off Barracuda XDR, Email Gateway Defense (EGD), Email Security Gateway (ESG), or Essentials.

**Discover, report, confirm, then act.** Defaults to read-only. Remediation requires `-Mode Remediate` and confirmation (or `-Force`). `-WhatIf` is supported end to end.

## Requirements

- PowerShell 7.4+
- `Microsoft.Graph` (v2.x)
- `ExchangeOnlineManagement` (v3.x)
- Global Admin, or Application Administrator + Exchange Administrator

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
Install-Module ExchangeOnlineManagement -Scope CurrentUser
```

## Quick start

```powershell
cd BarracudaOffboarding

# Read-only discovery (default)
.\Invoke-BarracudaOffboarding.ps1 -ClientName 'Contoso'

# Include uSecure transport rules as Review candidates
.\Invoke-BarracudaOffboarding.ps1 -ClientName 'Contoso' -IncludeUsecure

# Remediate with per-item confirmation
.\Invoke-BarracudaOffboarding.ps1 -ClientName 'Contoso' -Mode Remediate

# Preview remediation with no changes
.\Invoke-BarracudaOffboarding.ps1 -ClientName 'Contoso' -Mode Remediate -WhatIf

# Graph-only or Exchange-only
.\Invoke-BarracudaOffboarding.ps1 -ClientName 'Contoso' -Scope Graph
.\Invoke-BarracudaOffboarding.ps1 -ClientName 'Contoso' -Scope Exchange
```

Reports and backups default to work OneDrive, one folder per client:

```text
%OneDriveCommercial%\BarracudaOffboarding\<Client>\<yyyyMMdd_HHmmss>\
```

`-OutputPath` overrides that root; the per-client subfolder is still created. If work OneDrive is unavailable, falls back to `Desktop\BarracudaOffboarding\<Client>\...`.

## Safety

- No hardcoded Barracuda IP ranges, app IDs, or smart-host FQDNs. Detection is pattern match on discovered objects; ambiguous hits are flagged for review.
- Extend patterns via `config/default.json` or `-ConfigPath` (merged with defaults).
- `knownGoodServicePrincipals` / `knownGoodTransportRules` suppress remediation but still appear as `Info` findings.
- Service principals are disabled and grants revoked. They are **never** deleted by this tool.
- Transport rules are **disabled**, never removed.
- Connectors and connection-filter `IPAllowList` default to Review.
- High severity MX/SPF findings block Remediate unless `-Force`.
- Backup files are written and verified before any mutation.

## Graph scopes

Discover (read-only):

- `Application.Read.All`
- `Directory.Read.All`
- `AuditLog.Read.All`
- `Policy.Read.All`

Remediate adds:

- `AppRoleAssignment.ReadWrite.All`
- `DelegatedPermissionGrant.ReadWrite.All`

## Config

See `config/default.json`:

```json
{
  "vendorPatterns": ["barracuda", "skout", "cudamail", "cudasvc"],
  "knownGoodServicePrincipals": [],
  "knownGoodTransportRules": [],
  "clientNotes": ""
}
```

## Tests

```powershell
Invoke-Pester -Path .\tests
```

Tests mock Graph and Exchange cmdlets. No live tenant is required.

Runtime reports are written outside the repo by default.
