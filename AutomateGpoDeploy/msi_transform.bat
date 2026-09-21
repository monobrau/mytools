@echo off
:: msi_transform.bat -- Launch CW Automate RMM MST Transform GUI
::
:: Usage: double-click or run msi_transform.bat

setlocal

set "SCRIPT_DIR=%~dp0"
set "GUI=%SCRIPT_DIR%msi_transform_gui.py"

if not exist "%GUI%" (
    echo [ERROR] msi_transform_gui.py not found at: %GUI%
    pause
    exit /b 1
)

cd /d "%SCRIPT_DIR%"
python "%GUI%"
exit /b %ERRORLEVEL%
