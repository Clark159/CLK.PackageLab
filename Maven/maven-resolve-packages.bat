@echo off
cd /d "%~dp0"
chcp 65001 >nul
setlocal enabledelayedexpansion

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dpn0.ps1" -Pause %*

exit /b %ERRORLEVEL%