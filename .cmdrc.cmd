@echo off

cd %USERPROFILE%
if not exist .cmdrc.d mkdir .cmdrc.d

for %%f in (.cmdrc.d\*.cmd) do call %%f
