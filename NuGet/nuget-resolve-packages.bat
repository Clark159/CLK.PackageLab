@echo off
cd /d "%~dp0"
chcp 65001 >nul
setlocal enabledelayedexpansion


REM ===== 設定區 =====

REM 設定 arguments
set NO_PAUSE=0
for %%a in (%*) do (
  if /i "%%~a"=="--no-pause" set NO_PAUSE=1
)


REM ===== 初始區 =====
set EXIT_CODE=0

REM 檢查 .csproj
set CSPROJ_FILE=
set CSPROJ_COUNT=0
for %%f in (*.csproj) do (
  if not defined CSPROJ_FILE (
    set CSPROJ_FILE=%%f
  )
  set /a CSPROJ_COUNT+=1
)
if not defined CSPROJ_FILE (
  echo [ERROR] 找不到 .csproj檔案
  set EXIT_CODE=1
  goto END
)
if %CSPROJ_COUNT% gtr 1 (
  echo [ERROR] 找到 %CSPROJ_COUNT% 個 .csproj 檔案，只允許存在一個
  set EXIT_CODE=1
  goto END
)

REM 初始化 packages.lock.json
if exist "packages.lock.json" (
  del packages.lock.json
)

REM 初始化 obj資料夾
if exist "obj" (
  rmdir /s /q "obj"
)

REM 初始化 packages資料夾
if exist "%PACKAGES_DIR%" (
  rmdir /s /q "%PACKAGES_DIR%"
)


REM ===== 執行區 =====
echo ========================================
echo 套件專案: %CSPROJ_FILE%
echo ========================================
echo.

REM 建立 packages.lock.json
dotnet restore "%CSPROJ_FILE%" ^
  --use-lock-file ^
  --force-evaluate

if not "%ERRORLEVEL%"=="0" (
  echo [ERROR] dotnet restore "%CSPROJ_FILE%" 執行失敗
  set EXIT_CODE=1
  goto END
)

REM 移除 obj資料夾
if exist "obj" (
  rmdir /s /q "obj"
)


REM ===== 結束區 =====
:END
echo.
if "%EXIT_CODE%"=="0" echo [SUCCESS] 解析套件清單成功 packages.lock.json
echo.
echo.
if "%NO_PAUSE%"=="0" pause
endlocal & exit /b %EXIT_CODE%
