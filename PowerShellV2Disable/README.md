# Disable PowerShell 2.0

Turns off the Windows optional features **MicrosoftWindowsPowerShellV2** and **MicrosoftWindowsPowerShellV2Root**. That is the usual CIS / vuln-scanner control for PowerShell 2.0.

Already Disabled, pending-disable, or missing (stripped SKU such as some Windows 11 builds) counts as done.

It does **not** restart the PC. A finding can stay open until the next restart.

## Usage

Run elevated. There is no dry-run.

```powershell
.\Disable-PowerShellV2.ps1
```

Exit `0` means the features are disabled or not present. Exit `1` means the script could not disable them (not elevated, DISM error).

## ScreenConnect

See [`ScreenConnect-Commands.ps1`](ScreenConnect-Commands.ps1). ScToolLauncher: **Hardening → Disable PowerShell 2.0**.
