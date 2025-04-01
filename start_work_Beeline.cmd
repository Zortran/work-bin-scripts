@echo off
set programs_list= "C:\Program Files\PuTTY\pageant.exe" "C:\Program Files\VMware\VMware Horizon View Client\vmware-view.exe" "C:\Users\zortr\AppData\Local\Programs\time-desktop\TiMe.exe" "C:\Program Files\Telegram Desktop\Telegram.exe" "C:\Program Files\KeePass Password Safe 2\KeePass.exe" "C:\Users\zortr\AppData\Local\Yandex\Punto Switcher\punto.exe" "C:\Users\zortr\AppData\Local\Programs\ktalk\ktalk.exe" "C:\Program Files\Docker\Docker\Docker Desktop.exe" "C:\Program Files (x86)\Cisco\Cisco AnyConnect Secure Mobility Client\vpnui.exe"
:: "C:\Program Files\TrueConf\Client\TrueConf.exe"
for %%i in (%programs_list%); do (
  echo %%i
  if exist %%i (
    tasklist /fi "IMAGENAME eq %%~nxi" | find /i "%%~nxi" || start /b "%%~nxi" %%i > nul
  ) else (
    echo NOT FOUND
  )
)