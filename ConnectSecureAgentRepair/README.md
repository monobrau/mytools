# ConnectSecure (CyberCNS) agent repair

Checks whether `CyberCNSAgent` and `CyberCNSAgentMonitor` are both running. With
`-Remediate`, stops/deletes stuck services, kills processes, removes
`C:\Program Files (x86)\CyberCNSAgent`, downloads a fresh Windows agent, and
reinstalls.

## Safety

- **Never commit** real `-CompanyId`, `-EnvironmentId`, or `-InstallToken` values.
  Pass them at run time (ScToolLauncher fields or placeholders in
  [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1)).
- Prefer elevated ScreenConnect **Backstage** / SYSTEM.
- Remediate follows vendor `uninstall.bat`: wait, `sc stop/delete CyberCNSAgent` (and monitor if present), `taskkill` osqueryi/nmap/cyberutilities, `cybercnsagent.exe --internalAssetArgument uninstallservice`, then `rmdir` the folder.
- If a service is still registered after that (often "marked for deletion"), **reboot** then re-run `-Remediate`.

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Or use ScToolLauncher
(**Agents / monitoring** → ConnectSecure agent repair).
