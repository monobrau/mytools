# ConnectSecure agent repair + reinstall

Scan reports service/folder state.

**`-Remediate`** wipes then reinstalls: vendor `uninstall.bat`, MMC close,
`sc delete`, `reg delete /f` of service keys, folder remove, then a fresh
download + install.

**`-SkipIfRunning`** (fleet / scan-prep): if `CyberCNSAgent` is already **Running**,
report and exit 0 with no wipe. Pair with `-Remediate` when you run this on every
machine before a scan so healthy agents are left alone. Without `-SkipIfRunning`,
`-Remediate` always wipes even if the agent is Running.

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
(**Agents** → ConnectSecure agent repair + reinstall).
