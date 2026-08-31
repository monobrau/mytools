# ConnectSecure (CyberCNS) agent repair

Scan reports service/folder state. **`-Remediate` always wipes then reinstalls**
(even if a service is already Running): vendor `uninstall.bat`, MMC close,
`sc delete`, `reg delete /f` of service keys, folder remove, then a fresh
download + install.

## Safety

- **Never commit** real `-CompanyId`, `-EnvironmentId`, or `-InstallToken` values.
  Pass them at run time (ScToolLauncher fields or placeholders in
  [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1)).
- Prefer elevated ScreenConnect **Backstage** / SYSTEM.
- Remediate follows vendor `uninstall.bat`: wait, `sc stop/delete CyberCNSAgent` (and monitor if present), `taskkill` osqueryi/nmap/cyberutilities, `cybercnsagent.exe --internalAssetArgument uninstallservice`, then `rmdir` the folder.
- After the folder is gone, leftover SCM keys are deleted (`sc delete` + service registry). That is the usual **Failed to Read Description** ghost service.
- If a service is still registered after that (often "marked for deletion"), **reboot** then re-run `-Remediate`.

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Or use ScToolLauncher
(**Agents / monitoring** → ConnectSecure agent repair).
