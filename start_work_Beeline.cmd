@echo off
set programs_list= "C:\Program Files\Omnissa\Omnissa Horizon Client\horizon-client.exe" "C:\Program Files\Telegram Desktop\Telegram.exe" "C:\Program Files\KeePass Password Safe 2\KeePass.exe" "C:\Users\zortr\AppData\Local\Programs\ktalk\ktalk.exe" "C:\Program Files\Docker\Docker\Docker Desktop.exe" "C:\Program Files (x86)\Cisco\Cisco AnyConnect Secure Mobility Client\vpnui.exe" "C:\Program Files\Buzz\Buzz.exe" "C:\Program Files (x86)\Caramba\Switcher\CarambaSwitcher.exe" 
:: "C:\Program Files\TrueConf\Client\TrueConf.exe" "C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE" "C:\Program Files\TiMe\TiMe.exe" "C:\Users\zortr\AppData\Local\Yandex\Punto Switcher\punto.exe"
for %%i in (%programs_list%); do (
  echo %%i
  if exist %%i (
    tasklist /fi "IMAGENAME eq %%~nxi" | find /i "%%~nxi" || start /b "%%~nxi" %%i > nul
  ) else (
    echo NOT FOUND
  )
)
taskkill /f /t /im pageant.exe
del %USERPROFILE%\.ssh\ssh-sock.sock
start /b "pageant.exe" "C:\Program Files\PuTTY\pageant.exe" --unix %USERPROFILE%\.ssh\ssh-sock.sock --openssh-config %USERPROFILE%\.ssh\pageant.conf > nul

:: explorer.exe shell:AppsFolder\BlueMail.BlueMailEmail_t08282y3j4hc4!BlueMail.BlueMailEmail