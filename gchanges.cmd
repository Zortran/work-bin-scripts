@echo off
git branch -a | find /i "origin/master" > null
if errorlevel 1 (
  set BASE_BRANCH=main
) else (
  set BASE_BRANCH=master
)
@REM echo %BASE_BRANCH%
for /F "delims=" %%I in ('git branch --show-current') do set CURRENT_BRANCH=%%I
@REM echo %CURRENT_BRANCH%
for /F "delims=" %%I in ('git merge-base --fork-point %BASE_BRANCH% %CURRENT_BRANCH%') do set FORK_COMMIT=%%I
@REM echo %FORK_COMMIT%
git diff %FORK_COMMIT% %*