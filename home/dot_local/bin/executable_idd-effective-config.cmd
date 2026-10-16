@echo off
setlocal
set "ERRORLEVEL="
REM Windows-resolvable launcher for the upstream idd-effective-config helper
REM (dotfiles issue #646). PATHEXT has no .PS1, so a bare idd-effective-config
REM resolves only through this file. It dispatches to the PowerShell twin
REM idd-effective-config.ps1 in this same directory, preferring pwsh and
REM falling back to powershell when pwsh is not on PATH. It forwards the
REM arguments and the exit code, so the twin's fail-loud guard reaches the
REM caller.
set "SCRIPT_DIR=%~dp0"
set "PS1_PATH=%SCRIPT_DIR%idd-effective-config.ps1"

where pwsh >nul 2>nul
if errorlevel 1 goto :try_powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%" %*
exit /b %ERRORLEVEL%

:try_powershell
where powershell >nul 2>nul
if errorlevel 1 goto :no_shell
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%" %*
exit /b %ERRORLEVEL%

:no_shell
echo idd-effective-config: neither pwsh nor powershell found in PATH 1>&2
exit /b 1
