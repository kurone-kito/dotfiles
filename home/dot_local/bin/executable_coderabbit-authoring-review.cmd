@echo off
setlocal
set "ERRORLEVEL="
REM Windows-resolvable launcher for the IDD issue-authoring delegate
REM "coderabbit-authoring-review": dispatches to the PS5.1/pwsh-compatible
REM coderabbit-authoring-review.ps1 twin in this same directory, preferring
REM pwsh and falling back to powershell when pwsh is not on PATH. Forwards
REM every argument, stdin, stdout, stderr, and the dispatched process's exit
REM code unchanged. Same structure as the executable_coderabbit-critique.cmd
REM twin: the ERRORLEVEL clear, the flat GOTO layout, and the explicit
REM "exit /b %ERRORLEVEL%" keep the exit code real under cmd.exe.
REM -ExecutionPolicy Bypass matches the repository's other launchers.
set "SCRIPT_DIR=%~dp0"
set "PS1_PATH=%SCRIPT_DIR%coderabbit-authoring-review.ps1"

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
echo coderabbit-authoring-review: neither pwsh nor powershell found in PATH 1>&2
exit /b 1
