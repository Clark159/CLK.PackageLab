@echo off
cd /d "%~dp0"
chcp 65001 >nul
setlocal enabledelayedexpansion

mvn dependency:copy-dependencies -DoutputDirectory=./packages -Dmaven.repo.local=./packages-repo