# ConnectSecure (CyberCNS) silent install

Downloads the Windows agent from the ConnectSecure agentlink API and runs a
fresh install with `-c` / `-e` / `-j` / `-i`. Leftover **Stopped/Disabled**
agents are removed first using the vendor `uninstall.bat` sequence so install
does not fail with `service CyberCNSAgent already exists`.

For stuck agents (wipe + reinstall), use
[ConnectSecureAgentRepair](../ConnectSecureAgentRepair/).

## Safety

- **Never commit** real `-CompanyId`, `-EnvironmentId`, or `-InstallToken` values.
  Pass them at run time (ScToolLauncher fields or placeholders in
  [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1)).
- Prefer elevated ScreenConnect **Backstage** / SYSTEM.

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Or use ScToolLauncher
(**Agents — SentinelOne + ConnectSecure** → ConnectSecure silent install).
