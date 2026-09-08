# Acrobat XI removal (EOL)

Client-specific campaign: detect **Adobe Acrobat XI** (Standard/Pro, 11.x) and
optionally uninstall it. Reports **Foxit PDF Reader** / **Foxit PDF Editor**.

Does not remove Acrobat DC, current Acrobat, or Adobe Reader. Does not install
Foxit. Cannot decide a business dependency — scan first and skip uninstall on
hosts that must keep XI.

## Campaign workflow

1. **Scan** (`-CheckOnly`). Keep the output as evidence.
2. Review exceptions: no Foxit, or a known XI dependency.
3. **Uninstall** (`-Uninstall` / `-Remediate`) where XI should go. Default:
   skip if Foxit is missing. `-Force` uninstalls XI anyway.

Uninstall is `msiexec /x {ProductCode} /qn /norestart` with
`REBOOT=ReallySuppress` and `MSIRESTARTMANAGERCONTROL=Disable`. It waits for
the Windows Installer mutex and retries MSI 1618. XI removal often takes
10+ minutes; do not rerun or Force while `msiexec` is still running. Verbose
log: `%SystemRoot%\Temp\AcrobatXi-uninstall.log`.

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Or use ScToolLauncher
(**Client-specific** → client → Acrobat XI removal). Prefer elevated / Backstage.
Commands uninstall timeout is 20 minutes. Reload the launcher after pull so
snippets pick up `1.0.1`.
