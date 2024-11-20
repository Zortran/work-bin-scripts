@git fetch --all -pPf
@git pull
@git rebase origin/master
@call gs.cmd
@REM @echo off
@REM For /F "Delims=" %%I In ('git branch --show-curren') Do Set BRANCH=%%~I
@REM git checkout master
@REM git pull --rebase origin master
@REM git checkout %BRANCH%
@REM git rebase master
@REM git pull