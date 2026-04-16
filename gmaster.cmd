@echo off
  git branch -a | find /i "origin/master" > nul
  if errorlevel 1 (
    set BASE_BRANCH=main
  ) else (
    set BASE_BRANCH=master
  )

git checkout %BASE_BRANCH% %*