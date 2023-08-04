@git fetch --all -pPf
@git rebase origin/master
@REM @echo off
@REM For /F "Delims=" %%I In ('git branch --show-curren') Do Set BRANCH=%%~I
@REM git checkout master
@REM git pull --rebase origin master
@REM git checkout %BRANCH%
@REM git rebase master
@REM git pull