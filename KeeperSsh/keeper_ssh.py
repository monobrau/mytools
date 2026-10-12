"""Run SSH commands on a device with the login stored in Keeper.

A background helper signs in to Keeper once (Commander persistent login) and
keeps the vault in memory. The client asks it to find a record by IP or to run
commands over SSH. The password never leaves the helper process.
"""
import argparse
import base64
import builtins
import ctypes
import getpass
import hashlib
import os
import re
import secrets
import subprocess
import sys
import threading
import time
from multiprocessing.connection import Client, Listener

STATE_DIR = os.path.join(os.environ.get('LOCALAPPDATA') or os.path.expanduser('~'), 'KeeperSsh')
PIPE = r'\\.\pipe\keeper-ssh-' + getpass.getuser()
AUTHKEY_FILE = os.path.join(STATE_DIR, 'authkey')
PID_FILE = os.path.join(STATE_DIR, 'serve.pid')
LOG_FILE = os.path.join(STATE_DIR, 'serve.log')
KNOWN_HOSTS = os.path.join(STATE_DIR, 'known_hosts')

IDLE_EXIT_SECONDS = 4 * 3600
SYNC_EVERY_SECONDS = 60
MAX_OUTPUT_CHARS = 1_000_000
SEARCH_FIELD_TYPES = {'url', 'host', 'text', 'multiline', 'login'}
PAGER = re.compile(r'(?i)(--\s*more\s*--|press any key)')
# Encrypted or hashed secrets in device configs (FortiGate ENC, Cisco type 5/7/8/9).
CONFIG_SECRET = re.compile(r'(?i)(\bENC\s+|\b(?:secret|password)\s+[5789]\s+)\S+')
URL_USERINFO = re.compile(r'//[^/@\s]+@')


# ----- helper (holds the Keeper session) -----

def _no_prompt(*_args, **_kwargs):
    raise RuntimeError('Keeper wants an interactive login. Run "py -m keepercommander shell" once, then try again.')


class Vault:
    def __init__(self):
        from keepercommander import api, utils
        from keepercommander.__main__ import get_params_from_config
        from keepercommander.error import KeeperApiError
        self.api = api
        self.api_error = KeeperApiError
        self.params = get_params_from_config(os.path.join(utils.get_default_path(), 'config.json'))
        self.params.batch_mode = True
        self.synced = 0.0
        self.login()

    def login(self):
        self.api.login(self.params)
        if not self.params.session_token:
            raise RuntimeError('Keeper login did not return a session.')
        self.api.sync_down(self.params)
        self.synced = time.time()

    def refresh(self):
        if time.time() - self.synced < SYNC_EVERY_SECONDS:
            return
        try:
            self.api.sync_down(self.params)
        except self.api_error as e:
            if e.result_code != 'session_token_expired':
                raise
            self.login()
        self.synced = time.time()

    def _records(self):
        from keepercommander import vault
        for uid in list(self.params.record_cache):
            rec = vault.KeeperRecord.load(self.params, uid)
            if isinstance(rec, (vault.PasswordRecord, vault.TypedRecord)):
                yield rec

    @staticmethod
    def _searchable(rec):
        from keepercommander import vault
        yield rec.title
        yield rec.notes
        if isinstance(rec, vault.PasswordRecord):
            yield rec.link
            for cf in rec.custom:
                if cf.type != 'hidden':
                    yield cf.value
            return
        for field in rec.fields + rec.custom:
            if field.type not in SEARCH_FIELD_TYPES:
                continue
            for value in field.value:
                if isinstance(value, dict):
                    yield ' '.join(str(v) for v in value.values())
                else:
                    yield str(value)

    def _folders(self, uid):
        from keepercommander import subfolder
        paths = [subfolder.get_folder_path(self.params, f) for f in subfolder.find_folders(self.params, uid)]
        return paths or ['(My Vault)']

    @staticmethod
    def _login(rec):
        from keepercommander import vault
        if isinstance(rec, vault.PasswordRecord):
            return rec.login, rec.password
        login = rec.get_typed_field('login')
        password = rec.get_typed_field('password')
        return (login.get_default_value(str) or '' if login else '',
                password.get_default_value(str) or '' if password else '')

    @staticmethod
    def _hosts(rec):
        from keepercommander import vault
        if isinstance(rec, vault.PasswordRecord):
            values = [rec.link] if rec.link else []
        else:
            values = []
            for field in rec.fields + rec.custom:
                if field.type not in ('url', 'host'):
                    continue
                for value in field.value:
                    if isinstance(value, dict):
                        value = ':'.join(str(v) for v in (value.get('hostName'), value.get('port')) if v)
                    if value:
                        values.append(str(value))
        return [URL_USERINFO.sub('//', v) for v in values]

    @staticmethod
    def _pattern(target):
        return re.compile(r'(?<![\w.])' + re.escape(target) + r'(?![\w.])', re.IGNORECASE)

    def _mentions(self, rec, pattern):
        return any(text and pattern.search(text) for text in self._searchable(rec))

    def find(self, target):
        pattern = self._pattern(target)
        matches = []
        for rec in self._records():
            if self._mentions(rec, pattern):
                matches.append({
                    'uid': rec.record_uid,
                    'title': rec.title,
                    'folders': self._folders(rec.record_uid),
                    'login': self._login(rec)[0],
                    'hosts': self._hosts(rec),
                })
        return matches

    def credentials(self, uid, target):
        from keepercommander import vault
        rec = vault.KeeperRecord.load(self.params, uid)
        if not isinstance(rec, (vault.PasswordRecord, vault.TypedRecord)):
            raise RuntimeError(f'Keeper record {uid} was not found.')
        # The password only goes to a host the record itself names.
        if not self._mentions(rec, self._pattern(target)):
            raise RuntimeError(f'Keeper record {uid} ({rec.title}) does not mention {target}.')
        login, password = self._login(rec)
        if not login or not password:
            raise RuntimeError(f'Keeper record {uid} ({rec.title}) has no username or password.')
        return login, password


def _read_until_idle(chan, idle, deadline):
    out = []
    last = time.time()
    while time.time() - last < idle and time.time() < deadline:
        if chan.recv_ready():
            data = chan.recv(65536).decode('utf-8', errors='replace')
            out.append(data)
            last = time.time()
            if PAGER.search(data[-200:]):
                chan.send(' ')
        elif chan.exit_status_ready():
            break
        else:
            time.sleep(0.1)
    return ''.join(out)


def _refuse_unknown_host(client, hostname, key):
    digest = base64.b64encode(hashlib.sha256(key.asbytes()).digest()).decode().rstrip('=')
    raise RuntimeError(f'{hostname} has no saved SSH host key ({key.get_name()} SHA256:{digest}). '
                       'If that fingerprint is the device, rerun with --trust-new-host.')


def ssh_run(host, port, login, password, commands, shell, timeout, idle, trust_new_host, via=None):
    import paramiko
    import socket
    if not os.path.exists(KNOWN_HOSTS):
        open(KNOWN_HOSTS, 'a').close()
    client = paramiko.SSHClient()
    client.load_host_keys(KNOWN_HOSTS)
    if trust_new_host:
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    else:
        policy = paramiko.MissingHostKeyPolicy()
        policy.missing_host_key = _refuse_unknown_host
        client.set_missing_host_key_policy(policy)
    # Through a port forward the host key is still saved and checked under the device itself.
    sock = socket.create_connection(via, timeout=15) if via else None
    client.connect(host, port=port, username=login, password=password, look_for_keys=False,
                   allow_agent=False, timeout=15, banner_timeout=15, auth_timeout=20, sock=sock)
    results = []
    try:
        if shell:
            deadline = time.time() + timeout
            chan = client.invoke_shell(width=250, height=1000)
            transcript = _read_until_idle(chan, idle, deadline)
            for cmd in commands:
                chan.send(cmd + '\n')
                transcript += _read_until_idle(chan, idle, deadline)
            chan.close()
            results.append({'command': '(shell)', 'stdout': transcript, 'stderr': '', 'exit': None})
        else:
            for cmd in commands:
                _, stdout, stderr = client.exec_command(cmd, timeout=timeout)
                out = stdout.read().decode('utf-8', errors='replace')
                err = stderr.read().decode('utf-8', errors='replace')
                results.append({'command': cmd, 'stdout': out, 'stderr': err,
                                'exit': stdout.channel.recv_exit_status()})
    finally:
        client.close()
    for r in results:
        for key in ('stdout', 'stderr'):
            text = CONFIG_SECRET.sub(r'\1********', r[key].replace(password, '********'))
            r[key] = text[:MAX_OUTPUT_CHARS]
    return results


def handle(vault, req):
    op = req.get('op')
    if op == 'ping':
        return {'ok': True}
    vault.refresh()
    if op == 'find':
        return {'ok': True, 'matches': vault.find(req['target'])}
    if op == 'run':
        uid = req.get('record')
        if not uid:
            matches = vault.find(req['target'])
            if len(matches) != 1:
                return {'ok': False, 'matches': matches}
            uid = matches[0]['uid']
        login, password = vault.credentials(uid, req['target'])
        via = tuple(req['via']) if req.get('via') else None
        results = ssh_run(req['target'], req['port'], login, password, req['commands'],
                          req['shell'], req['timeout'], req['idle'], req.get('trust_new_host', False), via)
        # Exec mode cannot answer a pager, so the output stops at the first page.
        if not req['shell'] and any(PAGER.search(r['stdout']) for r in results):
            results = ssh_run(req['target'], req['port'], login, password, req['commands'],
                              True, req['timeout'], req['idle'], False, via)
        return {'ok': True, 'record': uid, 'results': results}
    return {'ok': False, 'error': f'Unknown request {op!r}.'}


def serve():
    import logging
    builtins.input = _no_prompt
    getpass.getpass = _no_prompt
    logging.basicConfig(filename=LOG_FILE, level=logging.WARNING,
                        format='%(asctime)s %(message)s', force=True)
    with open(PID_FILE, 'w') as f:
        f.write(str(os.getpid()))
    try:
        logging.warning('Signing in to Keeper and loading the vault.')
        vault = Vault()
        key = secrets.token_bytes(32)
        with open(AUTHKEY_FILE, 'wb') as f:
            f.write(key)
        listener = Listener(PIPE, family='AF_PIPE', authkey=key)
        logging.warning('Ready.')
        last = [time.time()]

        def idle_watch():
            while time.time() - last[0] < IDLE_EXIT_SECONDS:
                time.sleep(60)
            logging.warning('Idle, exiting.')
            os._exit(0)

        threading.Thread(target=idle_watch, daemon=True).start()
        while True:
            try:
                conn = listener.accept()
            except Exception as e:
                logging.warning('Rejected a connection: %s', e)
                continue
            with conn:
                last[0] = time.time()
                try:
                    req = conn.recv()
                    if req.get('op') == 'stop':
                        conn.send({'ok': True})
                        break
                    try:
                        reply = handle(vault, req)
                    except Exception as e:
                        reply = {'ok': False, 'error': f'{type(e).__name__}: {e}'}
                    conn.send(reply)
                except (OSError, EOFError) as e:
                    logging.warning('Client went away: %s', e)
                last[0] = time.time()
    except Exception as e:
        logging.warning('Helper stopped: %s: %s', type(e).__name__, e)
        raise SystemExit(1)
    finally:
        try:
            os.remove(PID_FILE)
        except OSError:
            pass


# ----- client -----

def _pid_alive(pid):
    handle = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)
    if not handle:
        return False
    code = ctypes.c_ulong()
    ctypes.windll.kernel32.GetExitCodeProcess(handle, ctypes.byref(code))
    ctypes.windll.kernel32.CloseHandle(handle)
    return code.value == 259


def _helper_pid():
    try:
        with open(PID_FILE) as f:
            pid = int(f.read().strip())
    except (OSError, ValueError):
        return None
    return pid if _pid_alive(pid) else None


def _connect():
    with open(AUTHKEY_FILE, 'rb') as f:
        key = f.read()
    return Client(PIPE, family='AF_PIPE', authkey=key)


def _start_helper():
    exe = os.path.join(os.path.dirname(sys.executable), 'pythonw.exe')
    if not os.path.exists(exe):
        exe = sys.executable
    log = open(LOG_FILE, 'a')
    base = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
    for flags in (base | subprocess.CREATE_BREAKAWAY_FROM_JOB, base):
        try:
            subprocess.Popen([exe, os.path.abspath(__file__), 'serve'], creationflags=flags,
                             stdin=subprocess.DEVNULL, stdout=log, stderr=log, close_fds=True)
            return
        except OSError:
            continue
    raise RuntimeError('Could not start the Keeper helper.')


def _log_tail(lines=5):
    try:
        with open(LOG_FILE, errors='replace') as f:
            return ''.join(f.readlines()[-lines:])
    except OSError:
        return ''


def request(req, wait, start=True):
    deadline = time.time() + wait
    started = None
    while True:
        try:
            with _connect() as conn:
                conn.send(req)
                return conn.recv()
        except (OSError, EOFError):
            pass
        if not start:
            return None
        if _helper_pid() is None:
            if started is None:
                print('Signing in to Keeper and loading the vault. The first run takes a couple of minutes.',
                      file=sys.stderr)
                _start_helper()
                started = time.time()
            elif time.time() - started > 15:
                sys.exit('The Keeper helper stopped:\n' + _log_tail())
        if time.time() > deadline:
            sys.exit('The Keeper helper is still loading. Run the same command again shortly.')
        time.sleep(2)


def _print_matches(matches):
    for m in matches:
        print(f"{m['uid']}  {m['title']}  [{'; '.join(m['folders'])}]  login={m['login']}"
              f"  hosts={', '.join(m.get('hosts') or []) or '-'}")


def main():
    os.makedirs(STATE_DIR, exist_ok=True)
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest='cmd', required=True)
    sub.add_parser('serve', help=argparse.SUPPRESS)
    sub.add_parser('status', help='Show whether the Keeper helper is running')
    sub.add_parser('stop', help='Stop the Keeper helper and drop the vault from memory')
    f = sub.add_parser('find', help='List Keeper records that mention an IP or hostname')
    f.add_argument('target')
    f.add_argument('--wait', type=int, default=300)
    r = sub.add_parser('run', help='Run commands over SSH with the matching Keeper login')
    r.add_argument('target', help='IP or hostname to connect to and to look up in Keeper')
    r.add_argument('commands', nargs='+')
    r.add_argument('--record', help='Keeper record UID, when the IP matches more than one record')
    r.add_argument('--port', type=int, default=22)
    r.add_argument('--via', help='HOST:PORT to open the TCP connection to instead, such as a port forward to the target')
    r.add_argument('--trust-new-host', action='store_true',
                   help='Save the host key of a device seen for the first time')
    r.add_argument('--shell', action='store_true',
                   help='Send commands to an interactive shell (for devices that refuse SSH exec)')
    r.add_argument('--timeout', type=int, default=120)
    r.add_argument('--idle', type=float, default=3.0, help='Shell mode: seconds of silence that end a command')
    r.add_argument('--wait', type=int, default=300)
    a = p.parse_args()

    if a.cmd == 'serve':
        serve()
        return
    if a.cmd == 'status':
        pid = _helper_pid()
        ready = request({'op': 'ping'}, 0, start=False) if pid else None
        print('ready' if ready else f'loading (pid {pid})' if pid else 'not running')
        return
    if a.cmd == 'stop':
        print('stopped' if request({'op': 'stop'}, 0, start=False) else 'not running')
        return
    if a.cmd == 'find':
        reply = request({'op': 'find', 'target': a.target}, a.wait)
        if not reply['ok']:
            sys.exit(reply['error'])
        if not reply['matches']:
            sys.exit(f'No Keeper record mentions {a.target}.')
        _print_matches(reply['matches'])
        return

    via = None
    if a.via:
        via_host, _, via_port = a.via.rpartition(':')
        if not via_host or not via_port.isdigit():
            sys.exit('--via must be HOST:PORT.')
        via = [via_host, int(via_port)]
    reply = request({'op': 'run', 'target': a.target, 'record': a.record, 'port': a.port,
                     'commands': a.commands, 'shell': a.shell, 'timeout': a.timeout, 'idle': a.idle,
                     'trust_new_host': a.trust_new_host, 'via': via}, a.wait)
    if not reply['ok']:
        if 'matches' in reply:
            if not reply['matches']:
                sys.exit(f'No Keeper record mentions {a.target}. Pass --record UID.')
            print(f'{a.target} matches {len(reply["matches"])} Keeper records. Pick one with --record:',
                  file=sys.stderr)
            _print_matches(reply['matches'])
            sys.exit(2)
        sys.exit(reply['error'])
    code = 0
    for res in reply['results']:
        if len(reply['results']) > 1:
            print(f"### {res['command']}")
        sys.stdout.write(res['stdout'])
        if res['stderr']:
            sys.stderr.write(res['stderr'])
        if res['exit']:
            code = res['exit']
    sys.exit(code)


if __name__ == '__main__':
    main()
