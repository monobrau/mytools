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
| `-Force` | Rip and replace: wipe leftovers, then install |
| `-Exit` | ScreenConnect Commands exit code |

Skip only if the `HuntressAgent` service exists, unless `-Force` / launcher
**Rip and replace** (wipe leftovers, then install in-session; no reboot).

Launcher **Schedule SYSTEM install + cleanup + reboot at chosen time** is a
separate option (`$schedule=$true` in `ScreenConnect-Commands.ps1`). It creates
`HuntressSC-Install` + `HuntressSC-Cleanup` and arms `shutdown /r /t` for the
date/time in the launcher picker (`$rebootAt`, endpoint local). Abort that
reboot with `shutdown /a`.

## Safety

- Account key is baked into `ScreenConnect-Commands.ps1` and ScToolLauncher
  (this tenant key does not rotate). Org key is still pasted per client.
- Do not paste live org keys into tickets.
- Prefer elevated ScreenConnect **Backstage** / SYSTEM.
- Troubleshoot with `C:\Windows\Temp\HuntressInstaller.log` if exit ≠ 0.
- Commands install prints a heartbeat every 10s and stops waiting after 240s
  without killing the installer (a silent `/S` run can take minutes).
- Tamper Protection can block wipe. If `Uninstall.exe` or file delete fails,
  create a Huntress TP exclusion and retry Force.

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Or use ScToolLauncher
(**Agents** → Huntress silent install).

`#!ps` and `#timeout=900000` must be the **first lines** in Commands. Anything
above them makes ScreenConnect ignore the timeout and default to **60 seconds**,
which kills a slow `HuntressInstaller.exe` mid-install.

ScreenConnect `#!ps` is often the **32-bit PowerShell 2.0** engine (`<<<<`
errors, `Ssl3, Tls` only). The Commands snippet does **not** pull this 5.1
script from GitHub — it downloads `HuntressInstaller.exe` from
`update.huntress.io` with `WebClient` and runs `/ACCT_KEY= /ORG_KEY= /S`.
That works on 2.0 if the OS can speak TLS 1.2 (numeric `3072`).

Other launcher tools still need Windows PowerShell 5.1 (WMF 5.1, or a
64-bit session via `SysNative`).
