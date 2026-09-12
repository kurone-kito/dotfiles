@echo off
setlocal
set "ERRORLEVEL="
REM Windows-resolvable launcher for idd-critique-telemetry-report:
REM dispatches to the PS5.1/pwsh-compatible
REM idd-critique-telemetry-report.ps1 twin in this same directory,
REM preferring pwsh and falling back to powershell (resolved via bare
REM PATHEXT lookup, not a hardcoded .exe suffix) when pwsh is not on
REM PATH. Forwards stdout, stderr, and the dispatched process's exit
REM code unchanged -- see executable_coderabbit-critique.cmd for the
REM identical pattern this file mirrors verbatim (see its own comment
REM for the ERRORLEVEL-clearing, GOTO-based, and line-ending rationale).
set "SCRIPT_DIR=%~dp0"
set "PS1_PATH=%SCRIPT_DIR%idd-critique-telemetry-report.ps1"

where pwsh >nul 2>nul
if errorlevel 1 goto :try_powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%"
exit /b %ERRORLEVEL%

:try_powershell
where powershell >nul 2>nul
if errorlevel 1 goto :no_shell
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%"
exit /b %ERRORLEVEL%

:no_shell
echo idd-critique-telemetry-report: neither pwsh nor powershell found in PATH 1>&2
exit /b 1
