# Speculative Store Bypass mitigation

Turns on the Windows mitigation for **CVE-2018-3639** (Speculative Store Bypass / SSBD).

Microsoft's client setting is bit `8` of `FeatureSettingsOverride`, with `FeatureSettingsOverrideMask` covering the low two bits (`3`). This script ORs those bits in. It does not replace the value, so other mitigations already stored there stay.

It does **not**:

- install Windows quality updates
- apply OEM CPU microcode or BIOS firmware
- restart the PC

A finding titled "Updates Required" can stay open until those updates are installed. Use the Windows Update quality tool for the OS updates. Firmware comes from the PC maker. The registry mitigation itself is not active until the next restart.

## Usage

Run elevated. Default is a dry run.

```powershell
.\Enable-SpeculativeStoreBypass.ps1
.\Enable-SpeculativeStoreBypass.ps1 -Remediate
```

`-CheckOnly` is the same dry run. The launcher sends `-CheckOnly` for Scan and `-Remediate` for Apply.

Exit `0` means the SSBD bits are set. Exit `2` means a scan still needs the change. Exit `1` means the script could not write.

## ScreenConnect

See [`ScreenConnect-Commands.ps1`](ScreenConnect-Commands.ps1). ScToolLauncher: **Untested → Speculative Store Bypass**.
