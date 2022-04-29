@echo off
For /F "Delims=" %%I In ('git branch --show-curren') Do Set BRANCH=%%~I
git checkout master
git pull --rebase origin master
git checkout %BRANCH%
git rebase master
git pull