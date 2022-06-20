@echo off
rem Source: https://umi-uyura.hatenablog.com/entry/2021/09/30/083419

if "%FNM_SETUP%"=="true" exit /b

where fnm > NUL 2>&1
if errorlevel 1 exit /b

set FNM_SETUP=true
for /f "tokens=*" %%z in ('fnm env --use-on-cd') do call %%z
