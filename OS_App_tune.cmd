@echo off
set "OptApp=cygwin nmap python3 putty.install"
set "AppList=git.install winmerge fsviewer 7zip.install Far-3 keepass.install keepass-plugin-keeagent keepass-plugin-keepassotp gpg4win thunderbird notepadplusplus.install putty.install qbittorrent telegram.install go docker-desktop"
set "VSCode=vscode.install vscode-ansible vscode-docker vscode-python vscode-go vscode-prettier vscode-yaml vscode-intellicode vscode-mssql vscode-markdownlint vscode-powershell vscode-xmltools vscode-gitlens"
net session >nul 2>&1
if %errorLevel% == 0 (
    for %%i in (%OptApp%) do (
      choco install -y %%i --params "/InstallDir:c:\opt\%%i"
    )
  choco install -y %AppList%
  choco install -y %VSCode%

) else (
    echo Failure: Administrative rights require.
)
set "Choco_clean=thunderbird telegram vscode"
for %%i in (%Choco_clean%) do (
  @echo on
  pushd C:\ProgramData\chocolatey\lib\
  for /f "usebackq tokens=*" %%a in (`dir /b %%i*`) do (rmdir /s /q %%a)
  popd
)
pause
