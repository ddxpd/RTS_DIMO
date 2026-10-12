@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\codex\run-balance-designer.ps1" -Action stop
if errorlevel 1 pause
