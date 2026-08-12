@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT=%~dp0gclone_repos.ps1"
if not exist "%SCRIPT%" (
  echo [error] Missing companion script: "%SCRIPT%"
  exit /b 1
)

set "ARGS="
:parse
if "%~1"=="" goto run
if /i "%~1"=="--dry" goto dry
if /i "%~1"=="-dry" goto dry
if /i "%~1"=="/dry" goto dry
if /i "%~1"=="--dry-run" goto dry
if /i "%~1"=="-DryRun" goto dry
if /i "%~1"=="--verbose" goto verbose
if /i "%~1"=="-verbose" goto verbose
if /i "%~1"=="/verbose" goto verbose
if /i "%~1"=="-v" goto verbose
if /i "%~1"=="--archive" goto archive
if /i "%~1"=="-archive" goto archive
if /i "%~1"=="/archive" goto archive
set ARGS=!ARGS! "%~1"
shift
goto parse

:dry
set "ARGS=!ARGS! -DryRun"
shift
goto parse

:verbose
set "ARGS=!ARGS! -Verbose"
shift
goto parse

:archive
set "ARGS=!ARGS! -Archive"
shift
goto parse

:run
pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"%ARGS%
exit /b %ERRORLEVEL%
