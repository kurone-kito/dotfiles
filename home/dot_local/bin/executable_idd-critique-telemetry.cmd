@echo off
setlocal
set "ERRORLEVEL="
REM Windows-resolvable launcher for the IDD critiqueLoop.telemetryHook
REM command "idd-critique-telemetry": dispatches to the PS5.1/pwsh-
REM compatible idd-critique-telemetry.ps1 twin in this same directory,
REM preferring pwsh and falling back to powershell (resolved via bare
REM PATHEXT lookup, not a hardcoded .exe suffix) when pwsh is not on
REM PATH. Forwards stdin, stdout, stderr, and the dispatched process's
REM exit code unchanged -- see the executable_idd-critique-telemetry
REM (POSIX) and executable_idd-critique-telemetry.ps1 twins in this same
REM directory, and executable_coderabbit-critique.cmd for the identical
REM pattern this file mirrors verbatim (see its own comment for the
REM ERRORLEVEL-clearing, GOTO-based, and line-ending rationale).
set "SCRIPT_DIR=%~dp0"
set "PS1_PATH=%SCRIPT_DIR%idd-critique-telemetry.ps1"

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
REM Fire-and-forget contract: neither pwsh nor powershell being
REM available must not surface as a failure the C-phase loop could
REM notice -- exit 0, unlike coderabbit-critique.cmd's exit 1.
exit /b 0
