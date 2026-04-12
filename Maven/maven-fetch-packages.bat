@echo off
cd /d "%~dp0"
chcp 65001 >nul
setlocal enabledelayedexpansion

REM ===== 設定區 =====
set MAVEN_SOURCE=https://repo.maven.apache.org/maven2
set PACKAGES_DIR=packages

REM 設定 arguments
set NO_PAUSE=0
for %%a in (%*) do (
  if /i "%%~a"=="--no-pause" set NO_PAUSE=1
)

REM ===== 初始區 =====
set EXIT_CODE=0

REM 檢查 pom.xml
if not exist "pom.xml" (
  echo [ERROR] 找不到 pom.xml
  set EXIT_CODE=1
  goto END
)

REM 檢查 packages-lock.xml
if not exist "packages-lock.xml" (
  echo [ERROR] 找不到 packages-lock.xml
  set EXIT_CODE=1
  goto END
)

REM 初始化 packages-repo資料夾
if exist "packages-repo" (
  rmdir /s /q "packages-repo"
)

REM 初始化 packages資料夾
if exist "%PACKAGES_DIR%" (
  rmdir /s /q "%PACKAGES_DIR%"
)


REM ===== 執行區 =====
echo ========================================
echo 套件專案: pom.xml
echo 套件來源: %MAVEN_SOURCE%
echo 套件目錄: %CD%\%PACKAGES_DIR%
echo ========================================
echo.




mvn dependency:copy-dependencies -DoutputDirectory=./packages -Dmaven.repo.local=./packages-repo