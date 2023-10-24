@echo off
set programs_list= "C:\Program Files\PuTTY\pageant.exe" "C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE" "C:\Program Files\Rocket.Chat\Rocket.Chat.exe" "C:\Program Files\Telegram Desktop\Telegram.exe" "C:\Program Files\KeePass Password Safe 2\KeePass.exe" "c:\Program Files\Microsoft Office\Office15\lync.exe" "C:\Program Files (x86)\Yandex\Punto Switcher\punto.exe"
for %%i in (%programs_list%); do (
  echo %%i
  if exist %%i (
    tasklist /fi "IMAGENAME eq %%~nxi" | find /i "%%~nxi" || start /b "%%~nxi" %%i > nul
  ) else (
    echo NOT FOUND
  )
)