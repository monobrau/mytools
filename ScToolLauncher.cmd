@echo off
setlocal
rem Starts SC Tool Launcher (ScToolLauncher\ScToolLauncher.ahk) with AutoHotkey v2.
set "SCRIPT=%~dp0ScToolLauncher\ScToolLauncher.ahk"
if not exist "%SCRIPT%" (
  echo ScToolLauncher.ahk was not found next to this file.
  pause
  exit /b 1
)
set "AHK="
for %%P in (
  "%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
  "%ProgramFiles%\AutoHotkey\v2\AutoHotkey32.exe"
  "%ProgramFiles(x86)%\AutoHotkey\v2\AutoHotkey32.exe"
  "%LocalAppData%\Programs\AutoHotkey\v2\AutoHotkey64.exe"
) do if not defined AHK if exist %%~P set "AHK=%%~P"
if not defined AHK (
  echo AutoHotkey v2 was not found.
  echo Install it from https://www.autohotkey.com/ and run this again.
  pause
  exit /b 1
)
start "" "%AHK%" "%SCRIPT%"
exit /b 0
