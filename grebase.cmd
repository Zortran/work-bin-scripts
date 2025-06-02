@echo off
git fetch --all -pPf
if "%~1"=="" (
  git branch -a | find /i "origin/master" > nul
  if errorlevel 1 (
    set BASE_BRANCH=main
  ) else (
    set BASE_BRANCH=master
  )
) else (
  set BASE_BRANCH=%1
)
git pull
git rebase origin/%BASE_BRANCH%
call gs.cmd