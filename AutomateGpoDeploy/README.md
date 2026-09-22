# Automate GPO Deploy

Download a ConnectWise Automate location installer, bake the **MST** into the
**MSI**, stage that single installer on NETLOGON, and create an AD GPO that
deploys it.

The location installer from `Deployment.aspx?InstallerToken=` is a zip
(`Agent_Install.msi` + `Agent_Install.mst`). After Automate patch 2024.7 the MSI
no longer has server/location embedded — the MST is required. This tool commits
the transform so Group Policy does not need `TRANSFORMS=`.

Native **Software Installation** packages cannot be created from PowerShell
(there is no public API for `.aas` files). The GPO is a computer **startup
script** that runs `msiexec` on the baked MSI when `LTService` is missing.

## ScreenConnect (client DC)

Prefer **ScToolLauncher → Agents → Automate GPO deploy**. Paste the location
token, Location ID, and client name. Dry-run bakes the MSI in `%TEMP%` only;
Apply stages NETLOGON and creates the GPO.

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1) for a hand-built
snippet. Run elevated as Domain Admin on a DC or RSAT box. Set `$token`,
`$locationId`, `$clientName`, and `$domain` from the location deployment ticket.
Do not commit tokens.

`#!ps` and `#timeout=900000` must be the first lines in Commands.

## What it does

1. Downloads `MSI_Install_Package.zip` from the Automate token URL
2. Bakes the MST with `msi_transform.ps1` (local copy, or fetched from this folder)
3. Copies the MSI to `\\<domain>\NETLOGON\Automate\<client>-<location>-<id>\`
4. Creates `Deploy Automate - <client> <location> (<id>)`
5. Publishes a computer **Immediate Task** that runs at the next Group Policy refresh
6. `Install-Automate.cmd` skips if `LTService` exists
7. Optional `-LinkToDomain` plus a workstation-only WMI filter (`ProductType = 1`). Computers are granted read on that filter. If the filter cannot be attached, the script does not link at the domain root.
8. Grants and checks read access for **Domain Computers** and **Authenticated Users** on the MSI folder, the GPO files in SYSVOL, and the NETLOGON share. The GPO itself gets **Authenticated Users: Apply** and **Domain Computers: Apply**.

The task runs as SYSTEM during background policy refresh, about every 90 minutes, while the PC is on. A reboot is not required. The log is `C:\Windows\Temp\Automate-GPO-Install.log`. On a domain controller, `gpresult /r /scope computer` should show this GPO denied by the WMI filter.

Do **not** put uninstall-then-reinstall (`-Force` from the ticket) in this GPO.

## Parameters

| Parameter | Purpose |
| --- | --- |
| `-Server` | Automate hostname (required) |
| `-LocationID` | Location ID (required) |
| `-Token` | Windows MSI installer token (required) |
| `-Domain` | AD DNS name (default: current domain) |
| `-ClientName` / `-LocationName` | GPO and folder naming |
| `-TargetOU` | Link to this OU DN |
| `-LinkToDomain` | Link at domain root + workstation WMI filter |
| `-SkipGpo` | Stage the MSI only |
| `-DryRun` | Transform in `%TEMP%` only |

## Local transform

```powershell
.\msi_transform.ps1 Agent_Install.msi Agent_Install.mst
.\msi_transform.ps1 Agent_Install.msi Agent_Install.mst -Output CustomAgent.msi
.\msi_transform.ps1 Agent_Install.msi Agent_Install.mst -DryRun
```

The DC needs outbound HTTPS to the Automate server and `api.github.com` (or
`raw.githubusercontent.com`). Clients need to read NETLOGON and reach Automate
after install. Pilot by security-filtering the GPO to a test computer group;
leave **Authenticated Users** with **Read** (MS16-072).
