@echo off
For /F "Delims=" %%I In ('git branch --show-curren') Do Set BRANCH=%%~I
git checkout main
git pull --rebase origin main
git checkout %BRANCH%
git rebase main
git pull