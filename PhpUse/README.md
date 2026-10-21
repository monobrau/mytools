# PHP use

Read-only check for whether a workstation or Windows Server is using PHP. The same check runs on both. A server is not skipped. The script does not change the computer.

| Line | Meaning |
| --- | --- |
| `USING PHP` | A PHP process is running, a process has a PHP module loaded, or IIS, Apache, nginx, Caddy, a Windows service, or a scheduled task is set up to start it |
| `NOT USING PHP` | None of those were found |
| `INSTALLED` | `php.exe` was found. The files being present does not mean a site is serving PHP |
| `NOT INSTALLED` | The program was not found in the places this check searches. If the line above says PHP is set up, the web server or task may point at a removed copy |
| `Note` | What this check does not search |

Indented lines are the process, loaded DLL, config file, service, scheduled task, path, `PHPRC`, `PHP_INI_SCAN_DIR`, or an IIS configuration redirect.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Not installed and not in use |
| `1` | Installed, but nothing is set up to run it |
| `2` | PHP is in use |

## What counts as in use

- `php.exe`, `php-cgi.exe`, or `php-win.exe` is running.
- Any process has a loaded module named `php.dll`, `php8ts.dll`, `php8apache2_4.dll`, or a similar `php` DLL. Each process is checked on its own, so a process that cannot be read is skipped.
- IIS `applicationHost.config`, parsed as XML, maps a site to `php.exe` or `php-cgi.exe`. Every `virtualDirectory` `physicalPath` is expanded and that folder's `web.config` is checked, including sites outside `inetpub`. If `redirection.config` has `configurationRedirection enabled="true"`, that path is reported and its `applicationHost.config` is checked when it can be reached.
- Apache or nginx is running or installed as a service, including `httpd -f` and `nginx -c`. `Include`, `IncludeOptional`, and nginx `include` are followed from the server root, at most three levels deep, and a file is not read twice.
- Caddy's `Caddyfile`, beside `caddy.exe` or named by `--config`, contains `php_fastcgi`.
- A service starts PHP directly, or through NSSM (`Parameters\Application`), WinSW (the `.xml` beside the service exe), or `srvany`. An `httpd`, `nginx`, or `caddy` target found that way is read the same way as a direct service.
- A scheduled task runs PHP, a `.php` file, or a `.bat`, `.cmd`, or `.ps1` that exists and references PHP.

`fastcgi_pass` and `proxy:fcgi://` count only when the same config block also references `.php` or a PHP executable. A location whose only action is `deny all` or `return 403` / `return 404` does not count. `<!-- ... -->` comments, including comments that span lines, are removed before matching. A `#` comment line is ignored.

## What counts as installed

`php.exe` on the machine PATH or a loaded user's PATH (read from the registry, not only this process), ComposerSetup's recorded PHP path, an installed-program entry, or a usual folder.

Uninstall keys are opened with the 64-bit registry view and the 32-bit view, for this machine and for loaded `HKEY_USERS` profiles. Display names matched are `PHP` plus a version, XAMPP, WampServer, Zend Server, Laragon, Bitnami, and AMPPS.

Usual folders, on each fixed drive: `php`, `xampp\php`, `wamp\bin\php`, `wamp64\bin\php`, `laragon\bin\php`, `UniServerZ`, `EasyPHP`, `tools\php`, `MAMP\bin\php`, and `Bitnami\*\php`. Also `Program Files\PHP`, `Program Files\Ampps\php`, Plesk under `Program Files (x86)\Plesk\Additional`, `Zend\ZendServer\bin`, and Chocolatey. For each user profile: `scoop\apps\php`, `.config\herd\bin`, and `AppData\Local\Microsoft\WinGet\Packages\PHP.PHP*`.

`PHPRC` and `PHP_INI_SCAN_DIR` are printed when the machine or a loaded user has them set. They do not by themselves change the exit code.

## Not checked

PHP inside WSL distributions and Docker containers is not checked. A copy in an unusual folder is listed only when a running web server, a Windows service, a loaded module, or a scheduled task points at it.

## Usage

```powershell
.\Get-PhpUse.ps1
```

Prefer an elevated 64-bit PowerShell window so other sessions' processes and loaded modules are visible. The check runs on Windows PowerShell 2.0 and later. The ScreenConnect bootstrap relaunches through `%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe` when it is started as a 32-bit process on 64-bit Windows. When Windows PowerShell 5.1 is installed, an older session relaunches into it. When this computer only has 2.0, 3.0, or 4.0, the check stays on that version.

## ScreenConnect

See [`ScreenConnect-Commands.ps1`](ScreenConnect-Commands.ps1). ScToolLauncher: **Untested → PHP use**.

The bootstrap downloads `Get-PhpUse.ps1` from a pinned commit and checks the SHA256 of the downloaded bytes. A GitHub API error (rate limit, 403, or 404) is thrown instead of being executed. If the connection to GitHub fails, the paste already carries that same script and the SHA256 check still applies. Reload the launcher after this folder is on that commit.
