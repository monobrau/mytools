@echo off
setlocal
rem The launcher lives in the work_ahk repo. This starts that copy when it sits next to mytools.
set "SCRIPT=%~dp0..\work_ahk\ScToolLauncher\ScToolLauncher.ahk"
if not exist "%SCRIPT%" (
  echo ScToolLauncher.ahk has moved to the work_ahk repo.
  echo Clone https://github.com/monobrau/work_ahk next to this folder, or run ScToolLauncher.cmd there.
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
