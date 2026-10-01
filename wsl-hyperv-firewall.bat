@echo off
REM If arguments are passed, run directly (terminal usage)
if not "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0wsl-hyperv-firewall.ps1" %*
    exit /b %ERRORLEVEL%
)

REM Interactive mode for double-click / shortcut without arguments
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0wsl-hyperv-firewall.ps1"
echo.

:loop
set /p "cmd=Command (add <port> [TCP|UDP], list, remove <port>) > "
if "%cmd%"=="" goto end
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0wsl-hyperv-firewall.ps1" %cmd%
echo.
goto loop

:end
pause
