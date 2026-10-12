@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\codex\run-art-library.ps1" -Action install
pause
