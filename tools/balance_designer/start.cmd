@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\codex\run-balance-designer.ps1" -Action start
if errorlevel 1 (
    pause
    exit /b 1
)
start "" "http://127.0.0.1:8811"
