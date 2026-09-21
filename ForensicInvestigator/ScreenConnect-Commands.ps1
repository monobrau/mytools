# Forensic Investigator for ScreenConnect (Sysinternals + Harkins artifacts + all-user Downloads).
# BACKSTAGE: one-liners only. Writes under C:\SecurityReports. Prefer elevated / Backstage.
# VirusTotal is off here — do not embed API keys.

# =============================================================================
# BACKSTAGE — FULL SCAN
# =============================================================================
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $ProgressPreference='SilentlyContinue'; $out=Join-Path $env:TEMP 'Invoke-ForensicAnalysis.ps1'; Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/monobrau/mytools/main/ForensicInvestigator/Invoke-ForensicAnalysis.ps1?v=3.1.1' -OutFile $out; & $out -OutputPath "C:\SecurityReports"

# =============================================================================
# COMMANDS tab — FULL SCAN (#!ps)
# =============================================================================
#!ps
#timeout=900000
#maxlength=100000
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $ProgressPreference='SilentlyContinue'; $out=Join-Path $env:TEMP 'Invoke-ForensicAnalysis.ps1'; Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/monobrau/mytools/main/ForensicInvestigator/Invoke-ForensicAnalysis.ps1?v=3.1.1' -OutFile $out; & $out -OutputPath "C:\SecurityReports"
# NOTE: Reports under C:\SecurityReports (CSV + EventLogs + zip). All-user Downloads/Desktop included. Prefer elevated. No VirusTotal in this snippet.

# =============================================================================
# COMMANDS tab — SKIP EVTX (faster)
# =============================================================================
#!ps
#timeout=600000
#maxlength=100000
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $ProgressPreference='SilentlyContinue'; $out=Join-Path $env:TEMP 'Invoke-ForensicAnalysis.ps1'; Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/monobrau/mytools/main/ForensicInvestigator/Invoke-ForensicAnalysis.ps1?v=3.1.1' -OutFile $out; & $out -OutputPath "C:\SecurityReports" -SkipEventLogs
