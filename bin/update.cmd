@echo off

cd "%~dp0"

powershell -Command "Unblock-File update.ps1"
powershell -NoProfile -ExecutionPolicy Bypass update.ps1
