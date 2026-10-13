@echo off
setlocal
if not exist "%~dp0Install-ShogoMods.ps1" (
    echo Extract the whole ZIP first, then run this file from the extracted folder.
    pause
    exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-ShogoMods.ps1" -Uninstall %*
set RC=%ERRORLEVEL%
echo.
pause
exit /b %RC%
