# Unquoted service paths

Read-only check for a Windows service whose binary path contains a space and is not in quotes. The script does not change the service.

| Result | Meaning |
| --- | --- |
| `Safe` / `No service needs a quote` | Every spaced path is already quoted, or no service binary has a space |
| `Safe` plus service lines | Unquoted, but Users, Everyone, and Authenticated Users cannot write the split folders. Leave them |
| `leave it - Windows platform` | Defender or Sense. Do not quote these. Windows ships them unquoted |
| `Action needed` | A user can write one of the folders Windows would search, or the ACL could not be read |

Each `Action needed` line is followed by `Next:` and an elevated `sc.exe config` command that quotes the binary and keeps the existing arguments. Review it before running it. The space after `binPath=` is required. Restart the service afterward if it was running. A vendor reinstall can remove the quotes.

Exit `0` when nothing needs a change. Exit `1` when a service needs a quote or an ACL could not be read.

## ScreenConnect

See [ScreenConnect-Commands.ps1](ScreenConnect-Commands.ps1). Or use ScToolLauncher (**Untested** → Unquoted service paths). The launcher downloads the script from GitHub `main`.
