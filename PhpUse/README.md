# PHP use

Read-only check for whether a Windows PC is using PHP.

| Line | Meaning |
| --- | --- |
| `USING PHP` | A PHP process is running, or IIS, Apache, nginx, a Windows service, or a scheduled task is set up to start it |
| `NOT USING PHP` | None of those were found |
| `INSTALLED` | `php.exe` is on PATH, in the installed-programs list, or in a usual install folder. The files being present does not mean a site is serving PHP |
| `NOT INSTALLED` | The program was not found in those places. If the line above says PHP is set up, the server or task may point at a removed copy |
| `Note` | What this check does not search |

Indented lines are the process, config file, service, scheduled task, or path.

Commented sample blocks, such as the PHP example in a default nginx config, are ignored. XAMPP, WampServer, and Laragon often load PHP inside `httpd.exe`, so a running `php.exe` is not required.

Usual folders, on each fixed drive: `php`, `xampp\php`, `wamp\bin\php`, `wamp64\bin\php`, `laragon\bin\php`, `UniServerZ`, `EasyPHP`, and `tools\php`. Also `Program Files\PHP`, Plesk under `Program Files (x86)\Plesk\Additional`, and Chocolatey. A copy in some other folder is listed only when a running web server, a Windows service, or a scheduled task points at it.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Not installed and not in use |
| `1` | Installed, but nothing is set up to run it |
| `2` | PHP is in use |

## Usage

```powershell
.\Get-PhpUse.ps1
```

Prefer an elevated PowerShell window so PHP processes in other sessions are visible. The script does not change the PC.

## ScreenConnect

See [`ScreenConnect-Commands.ps1`](ScreenConnect-Commands.ps1). ScToolLauncher: **Untested → PHP use**. Reload the launcher after this folder is on `main`.
