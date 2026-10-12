# Keeper SSH

Run read-only commands on switches, firewalls, and Linux hosts over SSH with the login stored in Keeper. Cursor (or you) never sees the password.

A background helper signs in to Keeper once with Commander persistent login and keeps the vault in memory. Each call finds the record that mentions the device IP, opens SSH with that username and password, and prints only what the device returned. The helper exits after 4 hours idle, or on `stop`.

## One-time setup

```powershell
py -m pip install --user keepercommander paramiko
py -m keepercommander shell
```

In the Commander shell, sign in, then run `this-device persistent-login on` and `quit`.

## Use

```powershell
$ks = 'C:\Git\mytools\KeeperSsh\keeper_ssh.py'
py $ks find 192.0.2.10
py $ks run 192.0.2.10 "show version" "show interfaces status"
py $ks run 192.0.2.10 --shell "show running-config"
py $ks run 192.0.2.10 --record <UID> "uptime"
py $ks status
py $ks stop
```

The first call after the helper stops takes about a minute while the vault loads.

| Option | Meaning |
| --- | --- |
| `--record UID` | Use this Keeper record when the IP matches more than one (the list shows each folder, which is usually the client) |
| `--shell` | Type the commands into an interactive shell. Use for devices that refuse SSH exec (many switches). Paging prompts are answered with a space |
| `--trust-new-host` | Save the host key of a device seen for the first time. Without it, an unknown key is refused and its fingerprint is printed |
| `--port N` | SSH port, default 22 |
| `--timeout S` | Per-command limit, default 120 |
| `--idle S` | Shell mode: seconds of silence that end a command, default 3 |

## Matching

The IP or hostname must appear as a whole value in the record title, notes, URL (`https://192.0.2.10:4443` counts), host, login, or a non-hidden custom field. Password and secret fields are never searched or printed.

The password is only sent to the host that was looked up. With `--record`, that record must still mention the IP you are connecting to.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Commands ran (exec mode: every command exited 0) |
| `1` | No record, login failed, SSH failed, or the helper could not start |
| `2` | The IP matches more than one record. Rerun with `--record` |
| other | Exit status of the last failing command |

## Local files

`%LOCALAPPDATA%\KeeperSsh` holds the helper log, PID, a per-start pipe key, and `known_hosts`. A new host key is saved only with `--trust-new-host`. A changed key is always refused.

## Limits

Anything running as your Windows user can read the pipe key and use the helper, the same as it could use Commander directly. The helper keeps a program that runs as you from printing passwords. It does not protect you from malware already running as you.
