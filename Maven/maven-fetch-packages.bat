@echo off
cd /d "%~dp0"
chcp 65001 >nul
setlocal enabledelayedexpansion

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dpn0.ps1" -Pause %*

exit /b %ERRORLEVEL%



REM ===== 設定區 =====
REM set MAVEN_SOURCE=https://repo.maven.apache.org/maven2
REM set PACKAGES_DIR=packages

REM mvn dependency:list -Dmaven.repo.local=./packages-repo -DincludeScope=runtime

REM mvn dependency:copy-dependencies -DoutputDirectory=./packages -Dmaven.repo.local=./packages-repo -DincludeScope=runtime
