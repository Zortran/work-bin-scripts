@echo off
IF "%~1"=="" (
  set /P Comment="Comment: "
) ELSE (
  set Comment=%*
)
git commit -am "%Comment%"