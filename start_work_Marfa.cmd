@echo off
set programs_list= "C:\Program Files\Mozilla Thunderbird\thunderbird.exe" "C:\Program Files\Telegram Desktop\Telegram.exe" "C:\Program Files\KeePass Password Safe 2\KeePass.exe" "C:\Program Files (x86)\Yandex\Punto Switcher\punto.exe" "C:\Users\zortr\AppData\Local\slack\slack.exe" "C:\Program Files\Fortinet\FortiClient\FortiClient.exe" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
for %%i in (%programs_list%); do (
  echo %%i
  if exist %%i (
    tasklist /fi "IMAGENAME eq %%~nxi" | find /i "%%~nxi" || start /b "%%~nxi" %%i > nul
  ) else (
    echo NOT FOUND
  )
)
tasklist /fi "IMAGENAME eq pageant.exe" | find /i "pageant.exe" || "C:\Program Files\PuTTY\pageant.exe" --unix %TEMP%\ssh-sock.sock --openssh-config %USERPROFILE%\.ssh\pageant.conf > nul
exit