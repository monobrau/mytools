# Non-GPO Automate and Huntress deploy

Run elevated as a domain admin. This is the push path when you are not using the Automate startup-script GPO.

## 1. Coverage

`Get-RmmAgentCoverage.ps1` needs the ActiveDirectory module (a DC or RSAT). It lists enabled Windows computers with a logon in the last 30 days, pings them, and queries `LTService` and `Huntress*` remotely.

```powershell
.\Get-RmmAgentCoverage.ps1
```

That writes `C:\Support\coverage.csv`. Columns include `Name`, `Online`, `RemoteAdmin`, `Automate`, `Huntress`. `RemoteAdmin` is `OK` only when the remote service query succeeds. `Automate` and `Huntress` are `MISSING` when that service is absent.

## 2. Deploy

`Deploy-RmmAgents.ps1` reads that CSV. A row is targeted when `Online` is `True`, `RemoteAdmin` is `OK`, and `Automate` or `Huntress` is `MISSING`.

Put `HuntressInstaller.exe` on the machine you run this from. The script copies it only to hosts missing Huntress. You pass the Automate server, location id, installer token, and Huntress keys on the command line. Do not commit those.

Pilot one computer, then drop `-Only`:

```powershell
.\Deploy-RmmAgents.ps1 `
    -Only 'CONTOSO-PC01' `
    -AutomateServer 'automate.example.com' `
    -LocationID 1 `
    -AutomateToken '<token>' `
    -HuntressAcctKey '<acct>' `
    -HuntressOrgKey 'contoso' `
    -Exclude 'DC01','DC02'
```

Each target writes `C:\Windows\Temp\rr-deploy.log` and deletes the staged script, installer, and `RR-AgentDeploy` task when it finishes. Results are written next to the coverage CSV as `deploy-results.csv`.
