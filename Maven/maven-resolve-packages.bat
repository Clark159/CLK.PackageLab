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

REM 檢查 pom.xml
if not exist "pom.xml" (
  echo [ERROR] 找不到 pom.xml
  set EXIT_CODE=1
  goto END
)

REM 初始化 dependency.list.temp
if exist "dependency.list.temp" (
  del dependency.list.temp
)

REM 初始化 dependency.list.txt
if exist "dependency.list.txt" (
  del dependency.list.txt
)

REM 初始化 packages-lock.xml
if exist "packages-lock.xml" (
  del packages-lock.xml
)

REM 初始化 packages-lock-start/end
copy /y pom.xml pom.xml.temp >nul
> pom.xml (
	for /f "usebackq delims=" %%A in ("pom.xml.temp") do (
		set "line=%%A"    
		set "line=!line:<!-- packages-lock-start -->=<!-- packages-lock-start!"
		set "line=!line:<!-- packages-lock-end -->=packages-lock-end -->!"
		echo(!line!
	)
)


REM ===== 執行區 =====
echo ========================================
echo 套件專案: pom.xml
echo ========================================

REM 解析套件清單
call mvn dependency:list ^
  -DoutputFile="dependency.list.tmp" ^
  -DincludeScope=compile ^
  -Dstyle.color=never

if not "%ERRORLEVEL%"=="0" (
  echo [ERROR] mvn dependency:list 執行失敗
  set EXIT_CODE=1
  goto END
)

REM 過濾套件清單
> "dependency.list.txt" (
  for /f "usebackq delims=" %%A in ("dependency.list.tmp") do (
    set "line=%%A"
    if not "!line: -- module =!"=="!line!" (
      for /f "tokens=1 delims=|" %%B in ("!line: -- module =|!") do (
        for /f "tokens=* delims= " %%C in ("%%B") do echo %%C
      )
    )
  )
)

REM 讀取專案參數
for /f "delims=" %%a in ('mvn help:evaluate -Dexpression^=project.modelVersion -q -DforceStdout 2^>nul') do set "PROJECT_MODELVERSION=%%a"
for /f "delims=" %%a in ('mvn help:evaluate -Dexpression^=project.groupId -q -DforceStdout 2^>nul') do set "PROJECT_GROUPID=%%a"
for /f "delims=" %%a in ('mvn help:evaluate -Dexpression^=project.artifactId -q -DforceStdout 2^>nul') do set "PROJECT_ARTIFACTID=%%a"
for /f "delims=" %%a in ('mvn help:evaluate -Dexpression^=project.version -q -DforceStdout 2^>nul') do set "PROJECT_VERSION=%%a"
echo [INFO] groupId: %PROJECT_GROUPID%
echo [INFO] artifactId: %PROJECT_ARTIFACTID%
echo [INFO] version: %PROJECT_VERSION%
echo [INFO] ------------------------------------------------------------------------

REM 產生 packages-lock.xml

(
  echo ^<project xmlns="http://maven.apache.org/POM/4.0.0"
  echo          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  echo          xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd"^>
  echo.
  echo     ^<groupId^>%PROJECT_GROUPID%^</groupId^>
  echo     ^<artifactId^>%PROJECT_ARTIFACTID%-lock^</artifactId^>
  echo     ^<version^>%PROJECT_VERSION%^</version^>
  echo     ^<modelVersion^>%PROJECT_MODELVERSION%^</modelVersion^>
  echo     ^<packaging^>pom^</packaging^>
  echo.
  echo     ^<dependencyManagement^>
  echo         ^<dependencies^>
) > packages-lock.xml

for /f "usebackq tokens=1-5 delims=:" %%A in ("dependency.list.txt") do (
  (
    echo             ^<dependency^>
    echo                 ^<groupId^>%%A^</groupId^>
    echo                 ^<artifactId^>%%B^</artifactId^>
    echo                 ^<version^>%%D^</version^>
    echo             ^</dependency^>
    echo.
  ) >> packages-lock.xml
)

(
  echo         ^</dependencies^>
  echo     ^</dependencyManagement^>
  echo.
  echo ^</project^>
) >> packages-lock.xml


REM 移除 dependency.list.tmp
del dependency.list.tmp

REM 移除 dependency.list.txt
del dependency.list.txt


REM ===== 結束區 =====
:END
echo.
if "%EXIT_CODE%"=="0" echo [SUCCESS] 解析套件清單成功 packages-lock.xml
echo.
echo.
if "%NO_PAUSE%"=="0" pause
endlocal & exit /b %EXIT_CODE%
