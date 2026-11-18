# MMIO stale data mitigation

Sets the Windows registry mitigation for Intel **MMIO stale data** (CVE-2022-21123, CVE-2022-21125, CVE-2022-21127, CVE-2022-21166). Nothing is installed.

| CPU and Hyper-Threading | `FeatureSettingsOverride` | `FeatureSettingsOverrideMask` |
| --- | --- | --- |
| Intel, Hyper-Threading on | `72` | `3` |
| Intel, Hyper-Threading off | `8264` | `3` |
| Same, plus BHI (`-IncludeBhi`) | `8388680` or `8396872` | `3` |

`8264` and `8396872` are Microsoft's values for these mitigations **with Hyper-Threading disabled**. The script uses them only when logical processors are not greater than cores. It does not turn Hyper-Threading off on a CPU that still has it.

AMD is a false positive. No write.

If `FeatureSettingsOverride` is already `1`, `2`, or `3`, a disable bit is set. The script leaves it alone.

Any other existing override is also left alone. `72`, `8264`, `8388680`, and `8396872` with mask `3` count as already applied.

The script does not reboot. The keys take effect on the next restart. The OS mitigation still needs current CPU microcode from the PC maker. On a virtual machine, the hypervisor host needs that firmware too.

`-IncludeBhi` is off unless you pass it. The launcher does not pass it.

## Usage

Run elevated. Default is a dry run.

```powershell
.\Enable-MmioStaleDataMitigation.ps1
.\Enable-MmioStaleDataMitigation.ps1 -Remediate
.\Enable-MmioStaleDataMitigation.ps1 -Remediate -IncludeBhi
```

`-CheckOnly` is the same dry run. The launcher sends `-CheckOnly` for Scan and `-Remediate` for Apply.

Exit `0` means already applied, or not an Intel CPU. Exit `2` means a scan would write the keys. Exit `1` means the script refused to change an existing value, or the write failed.

## ScreenConnect

See [`ScreenConnect-Commands.ps1`](ScreenConnect-Commands.ps1). ScToolLauncher: **Hardening → MMIO stale data**.
