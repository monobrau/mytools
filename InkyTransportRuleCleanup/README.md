# Inky / IPW transport rule cleanup

Lists or removes Exchange Online transport rules whose names match `IPW`,
`Inky`, or `IOC Strip`.

**Requires** an already-connected Exchange Online session (`Connect-ExchangeOnline`).
This is an admin-workstation helper, not an endpoint ScreenConnect remediation.

Default is dry-run. Pass `-Delete` to remove (no `Read-Host` prompt).

## Usage

```powershell
Connect-ExchangeOnline
# then paste from ScreenConnect-Commands.ps1 or ScToolLauncher
```

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1).
