# Huntress silent install

Downloads `HuntressInstaller.exe` from `update.huntress.io` and runs a silent
install with the official flags. If `HuntressAgent` (service or
`HuntressAgent.exe`) is already present, the script reports it and skips.

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

Already-installed agents are detected via the `HuntressAgent` service or
`%ProgramFiles%\Huntress\HuntressAgent.exe` (also x86). No download in that case.

## Safety

- **Never commit** real account or org keys. Paste in ScToolLauncher at copy time.
- Prefer elevated ScreenConnect **Backstage** / SYSTEM.
- Troubleshoot with `C:\Windows\Temp\HuntressInstaller.log` if exit ≠ 0.

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Or use ScToolLauncher
(**Agents** → Huntress silent install).

ScreenConnect `#!ps` is often the **32-bit PowerShell 2.0** engine (`<<<<`
errors, `Ssl3, Tls` only). The Commands snippet does **not** pull this 5.1
script from GitHub — it downloads `HuntressInstaller.exe` from
`update.huntress.io` with `WebClient` and runs `/ACCT_KEY= /ORG_KEY= /S`.
That works on 2.0 if the OS can speak TLS 1.2 (numeric `3072`).

Other launcher tools still need Windows PowerShell 5.1 (WMF 5.1, or a
64-bit session via `SysNative`).
