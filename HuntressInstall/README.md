# Huntress silent install

Downloads `HuntressInstaller.exe` from `update.huntress.io` and runs a silent
install with the official flags.

## Flags (important)

| Flag | Purpose |
| --- | --- |
| `/ACCT_KEY=` | Account key (**required** — not `/ACCOUNT_KEY=`) |
| `/ORG_KEY=` | Organization key / client short name |
| `/TAGS=` | Optional tags |
| `/S` | Silent (uppercase) |

Using `/ACCOUNT_KEY=` (wrong name) is ignored by the installer and has been
observed to end with a non-zero exit such as **53**. This script uses `/ACCT_KEY=`.

## Parameters

| Parameter | Purpose |
| --- | --- |
| `-AccountKey` | 32-char account key (also used in download URL) |
| `-OrgKey` | Organization key |
| `-Tags` | Optional |
| `-Exit` | ScreenConnect Commands exit code |

## Safety

- **Never commit** real account or org keys. Paste in ScToolLauncher at copy time.
- Prefer elevated ScreenConnect **Backstage** / SYSTEM.
- Troubleshoot with `C:\Windows\Temp\HuntressInstaller.log` if exit ≠ 0.

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Or use ScToolLauncher
(**Agents** → Huntress silent install).
