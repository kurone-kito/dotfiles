@echo off

powershell -Command "Unblock-File %~dp0\setup_.ps1"
powershell -NoProfile -ExecutionPolicy Bypass %~dp0\setup_.ps1
