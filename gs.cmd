@echo off
git status -sbu %*
git submodule status --recursive