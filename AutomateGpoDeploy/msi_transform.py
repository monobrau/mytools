#!/usr/bin/env python3
"""
msi_transform.py -- Apply an MST transform to an MSI installer (standalone output)

Produces a single MSI with the transform baked in -- no /TRANSFORMS flag at deploy time.

Platform support:
  - Windows native:  uses Windows Installer COM, no extra deps
  - WSL:             shells out to powershell.exe, no extra deps
  - Linux (non-WSL): needs msitools + olefile (see below)

Usage:
    python3 msi_transform.py Agent_Install.msi Agent_Install.mst
    python3 msi_transform.py Agent_Install.msi Agent_Install.mst -o CustomAgent.msi
    python3 msi_transform.py Agent_Install.msi Agent_Install.mst --dry-run
    python3 msi_transform.py Agent_Install.msi Agent_Install.mst --verbose

Linux-only (non-WSL) requirements:
    sudo apt install msitools
    pip install olefile
"""

import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


# ===========================================================================
# Platform detection
# ===========================================================================

def _is_wsl() -> bool:
    """True if running inside Windows Subsystem for Linux."""
    try:
        with open("/proc/version") as f:
            return "microsoft" in f.read().lower()
    except OSError:
        return False


def _find_powershell() -> str | None:
    """Return the path to powershell.exe or pwsh, preferring the Windows one from WSL."""
    for candidate in ("powershell.exe", "pwsh.exe", "pwsh"):
        if shutil.which(candidate):
            return candidate
    return None


ON_WINDOWS = platform.system() == "Windows"
ON_WSL     = (not ON_WINDOWS) and _is_wsl()
ON_LINUX   = (not ON_WINDOWS) and (not ON_WSL)


# ===========================================================================
# PowerShell backend  (Windows native + WSL)
# ===========================================================================

# Inline PS script that does all the heavy lifting.
# Called with JSON args; prints JSON results to stdout.
_PS_SCRIPT = r"""
param(
    [string]$Action,       # read_props | extract_changes | patch_msi
    [string]$MsiPath,
    [string]$MstPath,
    [string]$OutputPath
)

$msiOpenReadOnly  = 0
$msiOpenTransact  = 1
$installer = New-Object -ComObject WindowsInstaller.Installer

function Get-MsiProps([string]$path, [int]$mode) {
    $db   = $installer.OpenDatabase($path, $mode)
    $view = $db.OpenView("SELECT Property, Value FROM Property")
    $view.Execute()
    $props = @{}
    while ($true) {
        $rec = $view.Fetch()
        if ($null -eq $rec) { break }
        $props[$rec.StringData(1)] = $rec.StringData(2)
    }
    $view.Close()
    return $db, $props
}

if ($Action -eq "read_props") {
    $db, $props = Get-MsiProps $MsiPath $msiOpenReadOnly
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($db) | Out-Null
    $props | ConvertTo-Json -Compress
}

elseif ($Action -eq "extract_changes") {
    # Read original props
    $db0, $orig = Get-MsiProps $MsiPath $msiOpenReadOnly
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($db0) | Out-Null

    # Apply transform to a temp copy
    $tmp = [System.IO.Path]::GetTempFileName() + ".msi"
    Copy-Item $MsiPath $tmp
    try {
        $db1 = $installer.OpenDatabase($tmp, $msiOpenTransact)
        $db1.ApplyTransform($MstPath, 0)
        $view = $db1.OpenView("SELECT Property, Value FROM Property")
        $view.Execute()
        $patched = @{}
        while ($true) {
            $rec = $view.Fetch()
            if ($null -eq $rec) { break }
            $patched[$rec.StringData(1)] = $rec.StringData(2)
        }
        $view.Close()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($db1) | Out-Null
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }

    $changes = @{}
    foreach ($k in $patched.Keys) {
        if ($orig[$k] -ne $patched[$k]) { $changes[$k] = $patched[$k] }
    }
    $changes | ConvertTo-Json -Compress
}

elseif ($Action -eq "patch_msi") {
    $changesJson = $env:MSI_CHANGES
    $changes = $changesJson | ConvertFrom-Json -AsHashtable

    Copy-Item $MsiPath $OutputPath -Force
    $db = $installer.OpenDatabase($OutputPath, $msiOpenTransact)

    $results = @()
    foreach ($key in $changes.Keys) {
        $val = $changes[$key]
        $chk = $db.OpenView("SELECT Value FROM Property WHERE Property = '$key'")
        $chk.Execute()
        $exists = $chk.Fetch()
        $chk.Close()

        if ($null -ne $exists) {
            $upd = $db.OpenView("UPDATE Property SET Value = ? WHERE Property = '$key'")
            $rec = $installer.CreateRecord(1)
            $rec.StringData(1) = $val
            $upd.Execute($rec)
            $upd.Close()
            $results += "$key (updated)"
        } else {
            $ins = $db.OpenView("INSERT INTO Property (Property, Value) VALUES (?, ?)")
            $rec = $installer.CreateRecord(2)
            $rec.StringData(1) = $key
            $rec.StringData(2) = $val
            $ins.Execute($rec)
            $ins.Close()
            $results += "$key (added)"
        }
    }
    $db.Commit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($db) | Out-Null
    $results | ConvertTo-Json -Compress
}
"""


def _ps(action: str, msi: Path, mst: Path = None, output: Path = None,
        changes: dict = None) -> object:
    """Run the embedded PS script and return parsed JSON output."""
    ps = _find_powershell()
    if not ps:
        print("[ERROR] PowerShell not found. Install pwsh or ensure powershell.exe is in PATH.")
        sys.exit(1)

    # In WSL, paths must be Windows-style for PowerShell
    def to_ps_path(p: Path) -> str:
        if ON_WSL:
            r = subprocess.run(["wslpath", "-w", str(p)], capture_output=True, text=True)
            return r.stdout.strip()
        return str(p)

    args = [ps, "-NoProfile", "-NonInteractive", "-Command", _PS_SCRIPT,
            "-Action", action,
            "-MsiPath", to_ps_path(msi)]
    if mst:
        args += ["-MstPath", to_ps_path(mst)]
    if output:
        args += ["-OutputPath", to_ps_path(output)]

    env = os.environ.copy()
    if changes is not None:
        env["MSI_CHANGES"] = json.dumps(changes)

    r = subprocess.run(args, capture_output=True, text=True, env=env)
    if r.returncode != 0:
        print(f"[ERROR] PowerShell failed:\n{r.stderr.strip()}")
        sys.exit(1)

    out = r.stdout.strip()
    if not out:
        return {}
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        print(f"[ERROR] Unexpected PS output:\n{out}")
        sys.exit(1)


def ps_read_properties(msi: Path) -> dict[str, str]:
    return _ps("read_props", msi)


def ps_extract_changes(msi: Path, mst: Path, current: dict) -> dict[str, str]:
    return _ps("extract_changes", msi, mst=mst)


def ps_patch_msi(msi: Path, output: Path, changes: dict) -> list[str]:
    result = _ps("patch_msi", msi, output=output, changes=changes)
    if isinstance(result, list):
        return result
    if isinstance(result, str):
        return [result]
    return []


# ===========================================================================
# Linux backend (msitools + olefile)
# ===========================================================================

REQUIRED_LINUX_TOOLS = ["msidump", "msibuild"]


def linux_check_deps():
    missing = [t for t in REQUIRED_LINUX_TOOLS if not shutil.which(t)]
    if missing:
        print(f"[ERROR] Missing tools: {', '.join(missing)}")
        print("        sudo apt install msitools")
        sys.exit(1)
    try:
        import olefile  # noqa: F401
    except ImportError:
        print("[ERROR] olefile not installed.  pip install olefile")
        sys.exit(1)


def _run(cmd, cwd=None):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"[ERROR] {cmd[0]} failed:\n{r.stderr}")
        sys.exit(1)
    return r


def _parse_idt(prop_file: Path) -> dict[str, str]:
    props = {}
    for line in prop_file.read_text(encoding="latin-1").splitlines():
        parts = line.rstrip("\r").split("\t")
        if len(parts) != 2:
            continue
        k, v = parts
        if not k or k == "Property" or re.match(r'^[sl]\d+$', k):
            continue
        props[k] = v
    return props


def linux_read_properties(msi: Path) -> dict[str, str]:
    with tempfile.TemporaryDirectory() as tmpdir:
        _run(["msidump", "-t", str(msi)], cwd=tmpdir)
        return _parse_idt(Path(tmpdir) / "Property.idt")


def linux_extract_mst_changes(mst: Path, known_keys: set[str]) -> dict[str, str]:
    # Try msidump on the MST first
    with tempfile.TemporaryDirectory() as tmpdir:
        _run(["msidump", "-t", str(mst)], cwd=tmpdir)
        prop_file = Path(tmpdir) / "Property.idt"
        if prop_file.exists():
            props = _parse_idt(prop_file)
            if props:
                return props

    # OLE stream fallback -- split on known key names (longest first)
    import olefile
    sorted_keys = sorted(known_keys, key=len, reverse=True)
    pattern = re.compile("(" + "|".join(re.escape(k) for k in sorted_keys) + ")")
    properties = {}
    ole = olefile.OleFileIO(str(mst))
    for entry in ole.listdir():
        data = ole.openstream("/".join(entry)).read()
        if len(data) < 50:
            continue
        try:
            text = data.decode("latin-1")
        except Exception:
            continue
        printable = "".join(c if c.isprintable() else "" for c in text)
        if not any(k in printable for k in known_keys):
            continue
        parts = pattern.split(printable)
        i = 1
        while i < len(parts) - 1:
            key = parts[i]
            val = pattern.split(parts[i + 1])[0] if pattern.search(parts[i + 1]) else parts[i + 1]
            if val:
                properties[key] = val
            i += 2
    ole.close()
    return properties


def linux_patch_msi(msi: Path, output: Path, changes: dict[str, str]) -> list[str]:
    shutil.copy2(msi, output)
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        _run(["msidump", "-t", str(output)], cwd=tmp)
        prop_file = tmp / "Property.idt"
        content = prop_file.read_text(encoding="latin-1")
        changed = []
        for key, val in changes.items():
            pat = rf"^({re.escape(key)}\t)(.+)$"
            new_content, count = re.subn(pat, rf"\g<1>{val}", content, flags=re.MULTILINE)
            if count:
                content = new_content
                changed.append(f"{key} (updated)")
            else:
                lines = content.rstrip("\r\n").split("\n")
                lines.append(f"{key}\t{val}\r")
                content = "\n".join(lines) + "\n"
                changed.append(f"{key} (added)")
        prop_file.write_text(content, encoding="latin-1")
        _run(["msibuild", str(output), "-i", "Property.idt"], cwd=tmp)
    return changed


# ===========================================================================
# Shared helpers
# ===========================================================================

def _disp(s: str, n: int = 55) -> str:
    return (s[:n] + "...") if len(s) > n + 3 else s


def print_changes(changes: dict, current: dict):
    for k in sorted(changes):
        old_v = current.get(k, "<not present>")
        new_v = changes[k]
        action = "UPDATE" if k in current else "ADD"
        print(f"  [{action}] {k}")
        print(f"          was: {_disp(old_v)}")
        print(f"          now: {_disp(new_v)}")


# ===========================================================================
# Programmatic API (for GUI / scripting)
# ===========================================================================

def run_transform(
    msi_path: Path,
    mst_path: Path,
    output_path: Path | None = None,
    dry_run: bool = False,
    verbose: bool = False,
    log_func=None,
) -> bool:
    """
    Run the MST transform. Returns True on success, False on failure or dry-run.
    log_func: optional callable(str) to receive progress messages (default: print).
    """
    log = log_func or print
    use_ps = ON_WINDOWS or ON_WSL
    use_linux = ON_LINUX

    if use_linux:
        linux_check_deps()
    elif use_ps and not _find_powershell():
        log("[ERROR] PowerShell not found.")
        return False

    msi_path = Path(msi_path).resolve()
    mst_path = Path(mst_path).resolve()

    for p, label in [(msi_path, "MSI"), (mst_path, "MST")]:
        if not p.exists():
            log(f"[ERROR] {label} not found: {p}")
            return False

    if output_path is None:
        output_path = msi_path.parent / (msi_path.stem + "_transformed" + msi_path.suffix)
    else:
        output_path = Path(output_path).resolve()

    backend_label = "Windows COM" if ON_WINDOWS else ("WSL -> PowerShell" if ON_WSL else "msitools")
    msi_mb = f"{msi_path.stat().st_size / 1024 / 1024:.1f} MB"
    mst_kb = f"{mst_path.stat().st_size / 1024:.0f} KB"
    log(f"  MSI:     {msi_path.name}  ({msi_mb})")
    log(f"  MST:     {mst_path.name}  ({mst_kb})")
    log(f"  Backend: {backend_label}")
    if not dry_run:
        log(f"  Output:  {output_path}")
    log("")

    log("[1/4] Reading MSI property table...")
    if use_ps:
        current = ps_read_properties(msi_path)
    else:
        current = linux_read_properties(msi_path)
    log(f"       {len(current)} properties in source MSI")

    log("[2/4] Parsing MST transform...")
    if use_ps:
        changes = ps_extract_changes(msi_path, mst_path, current)
    else:
        changes = linux_extract_mst_changes(mst_path, set(current.keys()))

    if not changes:
        log("[WARN] No property changes detected in MST.")
        return True

    if verbose:
        log(f"       {len(changes)} properties to apply:")
        for k in sorted(changes):
            log(f"         {k} = {_disp(changes[k], 72)}")
    else:
        log(f"       {len(changes)} properties: {', '.join(sorted(changes))}")

    if dry_run:
        log("")
        log("Changes that would be applied:")
        for k in sorted(changes):
            old_v = current.get(k, "<not present>")
            new_v = changes[k]
            action = "UPDATE" if k in current else "ADD"
            log(f"  [{action}] {k}")
            log(f"          was: {_disp(old_v)}")
            log(f"          now: {_disp(new_v)}")
        log("")
        log("[DRY RUN] No files written.")
        return True

    log("[3/4] Copying MSI and patching Property table...")
    if use_ps:
        changed = ps_patch_msi(msi_path, output_path, changes)
    else:
        changed = linux_patch_msi(msi_path, output_path, changes)
    log(f"       {', '.join(changed)}")

    log("[4/4] Done.")
    size_mb = f"{output_path.stat().st_size / 1024 / 1024:.1f} MB"
    log("")
    log(f"[OK]  {output_path.name}  ({size_mb})")
    log(f'      Deploy: msiexec /i "{output_path.name}" /qn')
    return True


# ===========================================================================
# Entry point
# ===========================================================================

def main():
    parser = argparse.ArgumentParser(
        description=(
            "Bake an MST transform into an MSI for standalone deployment.\n"
            "Windows/WSL: no extra deps required.\n"
            "Linux (bare): needs msitools + olefile."
        )
    )
    parser.add_argument("msi", help="Source MSI file")
    parser.add_argument("mst", help="MST transform file")
    parser.add_argument("-o", "--output",
                        help="Output path (default: <source>_transformed.msi)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would change without writing files")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Print all property values from the MST")
    args = parser.parse_args()

    output_path = Path(args.output).resolve() if args.output else None
    ok = run_transform(
        args.msi, args.mst,
        output_path=output_path,
        dry_run=args.dry_run,
        verbose=args.verbose,
    )
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
