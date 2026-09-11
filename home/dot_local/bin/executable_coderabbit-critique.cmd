@echo off
setlocal
REM Windows-resolvable launcher for the IDD C1 critiqueLoop.delegate
REM command "coderabbit-critique": dispatches to the PS5.1/pwsh-compatible
REM coderabbit-critique.ps1 twin in this same directory, preferring pwsh
REM and falling back to powershell (resolved via bare PATHEXT lookup, not a
REM hardcoded .exe suffix) when pwsh is not on PATH. Forwards every
REM argument, stdout, stderr, and the dispatched process's exit code
REM unchanged -- see the executable_coderabbit-critique (POSIX) and
REM executable_coderabbit-critique.ps1 twins in this same directory.
REM
REM Deliberately GOTO/label-based, never a parenthesized IF (...) ELSE (...)
REM block: inside a "( ... )" block, cmd.exe expands %VAR% once at the
REM block's own parse time, not fresh per statement -- so a check placed
REM in the same block as the pwsh/powershell call would read a stale
REM pre-block value instead of the dispatched process's real exit
REM state, silently breaking exit-code forwarding. Flat, top-level
REM statements keep every errorlevel check fresh instead.
REM
REM Uses "if errorlevel 1" and a bare "exit /b" (no explicit code)
REM rather than "if %ERRORLEVEL% ..." / "exit /b %ERRORLEVEL%": %ERRORLEVEL%
REM is a textual expansion that reads a literal environment variable
REM named ERRORLEVEL when one happens to be set (inherited from a
REM parent process, or a prior "set ERRORLEVEL=..."), shadowing the
REM real dynamic error level -- "if errorlevel N" and a bare "exit /b"
REM both read cmd.exe's actual internal error state directly and are
REM immune to that shadowing.
REM
REM -ExecutionPolicy Bypass matches this repo's own
REM run_onchange_after_80-register-zellij-web.ps1.tmpl precedent: a
REM default Windows client install's Restricted execution policy would
REM otherwise block the Windows PowerShell 5.1 fallback branch outright.
REM
REM This file intentionally keeps this repo's default LF line endings:
REM the flat GOTO structure above avoids the multi-line parenthesized
REM blocks where cmd.exe's LF handling is known to be fragile.
set "SCRIPT_DIR=%~dp0"
set "PS1_PATH=%SCRIPT_DIR%coderabbit-critique.ps1"

where pwsh >nul 2>nul
if errorlevel 1 goto :try_powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%" %*
exit /b

:try_powershell
where powershell >nul 2>nul
if errorlevel 1 goto :no_shell
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%" %*
exit /b

:no_shell
echo coderabbit-critique: neither pwsh nor powershell found in PATH 1>&2
exit /b 1
