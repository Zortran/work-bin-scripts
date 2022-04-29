@echo off
:start
ping -a -n 10 %*
goto :start