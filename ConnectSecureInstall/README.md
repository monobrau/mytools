# ConnectSecure (CyberCNS) silent install

Downloads the Windows agent from the ConnectSecure agentlink API and runs a
fresh install with `-c` / `-e` / `-j` / `-i`. Leftover **Stopped/Disabled**
agents are removed first using the vendor `uninstall.bat` sequence so install
does not fail with `service CyberCNSAgent already exists`.

Windows is the default. ScToolLauncher can also copy the portal shell commands
for Mac (`darwinpkg`), Linux, ARM, and ARM-32. Those do not use this script.

**`-SkipIfRunning`** (fleet / scan-prep): if `CyberCNSAgent` is already **Running**,
report and exit 0 with no install. Use when you run this on every machine before
a scan so healthy agents are left alone. Stopped leftovers still get cleaned up
and reinstalled.

For stuck agents (wipe + reinstall), use
[ConnectSecureAgentRepair](../ConnectSecureAgentRepair/).

## Safety

- **Never commit** real `-CompanyId`, `-EnvironmentId`, or `-InstallToken` values.
  In ScToolLauncher, paste the official portal install script. Company (`-c`),
  environment (`-e`), and token (`-j`) are read from it and are not saved.
  Placeholders in [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1) are
  the other way to pass them.
- Prefer elevated ScreenConnect **Backstage** / SYSTEM.

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Or use ScToolLauncher
(**Agents — SentinelOne + ConnectSecure** → ConnectSecure silent install).
