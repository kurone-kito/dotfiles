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
REM Uses "if errorlevel 1" (not "if %ERRORLEVEL% ...") for the "where"
REM probes below: %ERRORLEVEL% is a textual expansion that reads a
REM literal environment variable named ERRORLEVEL when one happens to
REM be set (inherited from a parent process, or a prior
REM "set ERRORLEVEL=..."), shadowing the real dynamic error level --
REM "if errorlevel N" reads cmd.exe's actual internal error state
REM directly and is immune to that shadowing.
REM
REM The dispatched pwsh/powershell exit code itself is still forwarded
REM via the explicit "exit /b %ERRORLEVEL%" form, deliberately, not a
REM bare "exit /b": empirically confirmed (real cmd.exe, not
REM documentation alone) that a bare "exit /b" resets the exit code to
REM 0 instead of preserving the immediately-preceding command's real
REM exit code, which would silently break exit-code forwarding --
REM outright worse than the (rare) ERRORLEVEL-shadowing risk the
REM textual expansion carries. Every real Windows batch launcher
REM (npm's own generated .cmd shims included) uses this exact
REM %ERRORLEVEL%-capture idiom for the same reason.
REM
REM Also deliberately GOTO/label-based, never a parenthesized
REM IF (...) ELSE (...) block: inside a "( ... )" block, cmd.exe
REM expands every %VAR% once at the block's own parse time, not fresh
REM per statement -- so an "exit /b %ERRORLEVEL%" placed in the same
REM block as the pwsh/powershell call would read a stale value from
REM before the call ran, not its real exit code. Flat, top-level
REM statements keep every %VAR% expansion fresh instead.
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
exit /b %ERRORLEVEL%

:try_powershell
where powershell >nul 2>nul
if errorlevel 1 goto :no_shell
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%" %*
exit /b %ERRORLEVEL%

:no_shell
echo coderabbit-critique: neither pwsh nor powershell found in PATH 1>&2
exit /b 1
