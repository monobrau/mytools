#!/bin/bash
# msi_transform.sh -- WSL wrapper for msi_transform.ps1
#
# Usage (from WSL):
#   ./msi_transform.sh Agent_Install.msi Agent_Install.mst
#   ./msi_transform.sh Agent_Install.msi Agent_Install.mst -o CustomAgent.msi
#   ./msi_transform.sh Agent_Install.msi Agent_Install.mst -DryRun
#   ./msi_transform.sh Agent_Install.msi Agent_Install.mst -Verbose
#
# Requires: powershell.exe on PATH (standard in WSL), msi_transform.ps1 in same folder

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PS1_SCRIPT="$SCRIPT_DIR/msi_transform.ps1"

if [[ ! -f "$PS1_SCRIPT" ]]; then
    echo "[ERROR] msi_transform.ps1 not found next to this script at: $PS1_SCRIPT"
    exit 1
fi

if ! command -v powershell.exe &>/dev/null; then
    echo "[ERROR] powershell.exe not found. Is this running in WSL?"
    exit 1
fi

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <file.msi> <file.mst> [-o output.msi] [-DryRun] [-Verbose]"
    exit 1
fi

# Convert Linux paths to Windows paths for PowerShell
to_win() { wslpath -w "$1"; }

MSI_ARG="$1"; shift
MST_ARG="$1"; shift

# Resolve to absolute paths before converting
MSI_ABS="$(realpath "$MSI_ARG")"
MST_ABS="$(realpath "$MST_ARG")"
WIN_MSI="$(to_win "$MSI_ABS")"
WIN_MST="$(to_win "$MST_ABS")"
WIN_PS1="$(to_win "$PS1_SCRIPT")"

# Pass remaining args (-o, -DryRun, -Verbose) straight through,
# converting any .msi path argument after -o
PS_EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output|-Output)
            shift
            WIN_OUT="$(to_win "$(realpath -m "$1")")"
            PS_EXTRA_ARGS+=("-Output" "$WIN_OUT")
            ;;
        *)
            PS_EXTRA_ARGS+=("$1")
            ;;
    esac
    shift
done

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_PS1" \
    "$WIN_MSI" "$WIN_MST" "${PS_EXTRA_ARGS[@]}"
