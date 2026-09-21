#!/usr/bin/env python3
"""
msi_transform_gui.py -- GUI for CW Automate RMM MST transforms

Bake MST transforms into MSI installers. Two inputs (MSI + MST), selectable output.
Uses subprocess to avoid Windows COM STA deadlocks. tkinter (built-in).
"""

import shutil
import subprocess
import sys
import threading
from pathlib import Path

try:
    import tkinter as tk
    from tkinter import ttk, filedialog, messagebox, scrolledtext
except ImportError:
    print("tkinter not available. Install python3-tk (Linux) or use a Python with tkinter.")
    sys.exit(1)

SCRIPT_DIR = Path(__file__).resolve().parent


def browse_file(parent, entry: ttk.Entry, title: str, filetypes: list[tuple[str, str]]):
    path = filedialog.askopenfilename(parent=parent, title=title, filetypes=filetypes)
    if path:
        entry.delete(0, tk.END)
        entry.insert(0, path)


def browse_save(parent, entry: ttk.Entry, title: str, filetypes: list[tuple[str, str]]):
    path = filedialog.asksaveasfilename(parent=parent, title=title, filetypes=filetypes, defaultextension=".msi")
    if path:
        entry.delete(0, tk.END)
        entry.insert(0, path)


class MsiTransformGui:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("CW Automate RMM — MST Transform")
        self.root.minsize(520, 420)
        self.root.geometry("620x500")

        # Style
        style = ttk.Style()
        style.configure("TFrame", padding=8)
        style.configure("TLabel", padding=(0, 4))
        style.configure("TButton", padding=(12, 6))

        main = ttk.Frame(self.root, padding=12)
        main.pack(fill=tk.BOTH, expand=True)

        # MSI input
        ttk.Label(main, text="MSI installer:").grid(row=0, column=0, sticky=tk.W, pady=(0, 2))
        self.msi_var = tk.StringVar()
        default_msi = SCRIPT_DIR / "Agent_Install.msi"
        if default_msi.exists():
            self.msi_var.set(str(default_msi))
        msi_frame = ttk.Frame(main)
        msi_frame.grid(row=1, column=0, columnspan=2, sticky=tk.EW, pady=(0, 8))
        self.root.columnconfigure(0, weight=1)
        main.columnconfigure(0, weight=1)
        self.msi_entry = ttk.Entry(msi_frame, textvariable=self.msi_var, width=55)
        self.msi_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 6))
        ttk.Button(msi_frame, text="Browse…", command=self._browse_msi).pack(side=tk.RIGHT)

        # MST input
        ttk.Label(main, text="MST transform:").grid(row=2, column=0, sticky=tk.W, pady=(0, 2))
        self.mst_var = tk.StringVar()
        default_mst = SCRIPT_DIR / "Agent_Install.mst"
        if default_mst.exists():
            self.mst_var.set(str(default_mst))
        mst_frame = ttk.Frame(main)
        mst_frame.grid(row=3, column=0, columnspan=2, sticky=tk.EW, pady=(0, 8))
        self.mst_entry = ttk.Entry(mst_frame, textvariable=self.mst_var, width=55)
        self.mst_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 6))
        ttk.Button(mst_frame, text="Browse…", command=self._browse_mst).pack(side=tk.RIGHT)

        # Output
        ttk.Label(main, text="Output MSI:").grid(row=4, column=0, sticky=tk.W, pady=(0, 2))
        self.out_var = tk.StringVar()
        if default_msi.exists():
            self.out_var.set(str(default_msi.parent / (default_msi.stem + "_transformed.msi")))
        out_frame = ttk.Frame(main)
        out_frame.grid(row=5, column=0, columnspan=2, sticky=tk.EW, pady=(0, 12))
        self.out_entry = ttk.Entry(out_frame, textvariable=self.out_var, width=55)
        self.out_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 6))
        ttk.Button(out_frame, text="Save as…", command=self._browse_output).pack(side=tk.RIGHT)

        # Options
        opt_frame = ttk.Frame(main)
        opt_frame.grid(row=6, column=0, columnspan=2, sticky=tk.W, pady=(0, 8))
        self.dry_run_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(opt_frame, text="Dry run (preview only)", variable=self.dry_run_var).pack(side=tk.LEFT, padx=(0, 16))
        self.verbose_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(opt_frame, text="Verbose", variable=self.verbose_var).pack(side=tk.LEFT)

        # Transform button
        btn_frame = ttk.Frame(main)
        btn_frame.grid(row=7, column=0, columnspan=2, sticky=tk.W, pady=(0, 8))
        self.run_btn = ttk.Button(btn_frame, text="Transform", command=self._run_transform)
        self.run_btn.pack(side=tk.LEFT, padx=(0, 8))
        self.status_var = tk.StringVar(value="")
        ttk.Label(btn_frame, textvariable=self.status_var, foreground="gray").pack(side=tk.LEFT)

        # Log area
        ttk.Label(main, text="Log:").grid(row=8, column=0, sticky=tk.W, pady=(8, 2))
        log_frame = ttk.Frame(main)
        log_frame.grid(row=9, column=0, columnspan=2, sticky=tk.NSEW, pady=(0, 0))
        main.rowconfigure(9, weight=1)
        self.log = scrolledtext.ScrolledText(log_frame, height=12, wrap=tk.WORD, font=("Consolas", 9))
        self.log.pack(fill=tk.BOTH, expand=True)

        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

    def _browse_msi(self):
        browse_file(
            self.root,
            self.msi_entry,
            "Select MSI installer",
            [("MSI files", "*.msi"), ("All files", "*.*")],
        )
        self._maybe_set_output()

    def _browse_mst(self):
        browse_file(
            self.root,
            self.mst_entry,
            "Select MST transform",
            [("MST files", "*.mst"), ("All files", "*.*")],
        )

    def _browse_output(self):
        browse_save(
            self.root,
            self.out_entry,
            "Save transformed MSI as",
            [("MSI files", "*.msi"), ("All files", "*.*")],
        )

    def _maybe_set_output(self):
        msi = self.msi_var.get().strip()
        if msi and not self.out_var.get().strip():
            p = Path(msi)
            if p.suffix.lower() == ".msi":
                self.out_var.set(str(p.parent / (p.stem + "_transformed.msi")))

    def _log(self, msg: str):
        self.log.insert(tk.END, msg + "\n")
        self.log.see(tk.END)
        self.root.update_idletasks()

    def _run_transform(self):
        msi = self.msi_var.get().strip()
        mst = self.mst_var.get().strip()
        out = self.out_var.get().strip()

        if not msi:
            messagebox.showerror("Error", "Please select an MSI file.")
            return
        if not mst:
            messagebox.showerror("Error", "Please select an MST file.")
            return
        if not out and not self.dry_run_var.get():
            self._maybe_set_output()
            out = self.out_var.get().strip()
            if not out:
                messagebox.showerror("Error", "Please select an output path.")
                return

        self.run_btn.config(state=tk.DISABLED)
        self.status_var.set("Running…")
        self.log.delete(1.0, tk.END)

        # Run via subprocess to avoid Windows COM STA deadlock (GUI would hang).
        # Use PowerShell script directly - most reliable on Windows for CW Automate.
        transform_script = SCRIPT_DIR / "msi_transform.ps1"
        pwsh = "pwsh" if shutil.which("pwsh") else "powershell.exe"
        cmd = [
            pwsh, "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(transform_script), msi, mst,
        ]
        if out:
            cmd.extend(["-Output", out])
        if self.dry_run_var.get():
            cmd.append("-DryRun")
        if self.verbose_var.get():
            cmd.append("-Verbose")

        def work():
            try:
                proc = subprocess.Popen(
                    cmd,
                    cwd=str(SCRIPT_DIR),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                )
                for line in proc.stdout:
                    msg = line.rstrip("\n\r")
                    if msg:
                        self.root.after(0, lambda m=msg: self._log(m))
                proc.wait()
                self.root.after(0, lambda: self._done(proc.returncode == 0))
            except Exception as e:
                self.root.after(0, lambda: self._done(False, str(e)))

        threading.Thread(target=work, daemon=True).start()

    def _done(self, ok: bool, err: str | None = None):
        self.run_btn.config(state=tk.NORMAL)
        if err:
            self._log(f"[ERROR] {err}")
            self.status_var.set("Failed")
            messagebox.showerror("Error", err)
        elif ok:
            self.status_var.set("Done")
        else:
            self.status_var.set("Failed")

    def _on_close(self):
        self.root.destroy()

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    app = MsiTransformGui()
    app.run()
