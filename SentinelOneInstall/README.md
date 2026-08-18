# SentinelOne silent install

Downloads (optional) and silently installs the SentinelOne Windows agent using a
site or group token.

## Parameters

| Parameter | Purpose |
| --- | --- |
| `-SiteToken` | Site/group token (required; never commit real values) |
| `-InstallerPath` | EXE or MSI path on the endpoint (default `C:\Windows\Temp\SentinelOneInstaller.exe`) |
| `-InstallerUrl` | Optional HTTPS URL to download into `-InstallerPath` first |
| `-Quiet` | EXE: pass `-q` (older agent lines) |
| `-Exit` | ScreenConnect Commands exit code |

EXE: `SentinelOneInstaller.exe -t <token> [-q]`  
MSI: `msiexec /i … /qn /norestart SITE_TOKEN=<token>`

## Safety

- **Never commit** real site tokens. Use ScToolLauncher fields or placeholders.
- Prefer elevated ScreenConnect **Backstage** / SYSTEM.

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Or use ScToolLauncher
(**Agents — SentinelOne + ConnectSecure** → SentinelOne silent install).
