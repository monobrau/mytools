# WinVerifyTrust strict padding check

Enables the opt-in Authenticode check for **CVE-2013-3900**. Windows already has the code. Scanners stay open until `EnableCertPaddingCheck` is set.

On a 64-bit PC the value is written in both registry views:

| View | Key |
| --- | --- |
| 64-bit | `HKLM\Software\Microsoft\Cryptography\Wintrust\Config` |
| 32-bit | `HKLM\Software\Wow6432Node\Microsoft\Cryptography\Wintrust\Config` |

The value is DWORD `1`. An existing string `1` already counts as enabled and is left alone. A restart is required before signature validation changes. The script does not restart the PC.

After that restart, a signed program that carries extra data in the signature is treated as unsigned.

## Usage

Run elevated. Default is a dry run.

```powershell
.\Enable-WinVerifyTrustPaddingCheck.ps1
.\Enable-WinVerifyTrustPaddingCheck.ps1 -Remediate
```

`-CheckOnly` is the same dry run. The launcher sends `-CheckOnly` for Scan and `-Remediate` for Apply.

Exit `0` means the values are set. Exit `2` means a scan still needs the change. Exit `1` means the script could not write.

## ScreenConnect

See [`ScreenConnect-Commands.ps1`](ScreenConnect-Commands.ps1). ScToolLauncher: **Hardening → WinVerifyTrust padding check**.
