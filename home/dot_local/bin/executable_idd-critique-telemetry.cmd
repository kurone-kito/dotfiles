@echo off
setlocal
set "ERRORLEVEL="
REM Windows-resolvable launcher for the IDD critiqueLoop.telemetryHook
REM command "idd-critique-telemetry": dispatches to the PS5.1/pwsh-
REM compatible idd-critique-telemetry.ps1 twin in this same directory,
REM preferring pwsh and falling back to powershell (resolved via bare
REM PATHEXT lookup, not a hardcoded .exe suffix) when pwsh is not on
REM PATH -- OR when pwsh IS on PATH but fails to start or run the
REM script (broken runtime, or the .ps1 missing/unreadable/blocked).
REM Forwards stdin unchanged, but -- unlike coderabbit-critique.cmd, a
REM real gate whose failure must propagate -- this is a fire-and-
REM forget telemetry sink: every dispatch attempt's stdout/stderr is
REM suppressed and this script always exits 0 regardless of outcome,
REM mirroring the executable_idd-critique-telemetry (POSIX) and
REM executable_idd-critique-telemetry.ps1 twins' own "never let our
REM own failure surface" contract (regression: an earlier version
REM forwarded a broken-pwsh failure's real nonzero exit code here and
REM skipped the available powershell fallback entirely instead of
REM trying it -- Codex review, PR #426).
REM
REM See executable_coderabbit-critique.cmd's own header for the
REM shared ERRORLEVEL-clearing / GOTO-based flat structure (not a
REM parenthesized IF/ELSE block, whose one-time %VAR% expansion would
REM go stale) / -ExecutionPolicy Bypass rationale, all still in effect
REM here even though the exit code itself is no longer forwarded.
set "SCRIPT_DIR=%~dp0"
set "PS1_PATH=%SCRIPT_DIR%idd-critique-telemetry.ps1"

where pwsh >nul 2>nul
if errorlevel 1 goto :try_powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%" >nul 2>nul
if errorlevel 1 goto :try_powershell
exit /b 0

:try_powershell
where powershell >nul 2>nul
if errorlevel 1 goto :no_shell
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%" >nul 2>nul
exit /b 0

:no_shell
REM Fire-and-forget contract: neither pwsh nor powershell being
REM available, nor either one failing at runtime, may ever surface as
REM a failure the C-phase loop could notice -- always exit 0.
exit /b 0
