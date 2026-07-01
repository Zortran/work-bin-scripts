taskkill /f /t /im pageant.exe
del %USERPROFILE%\.ssh\ssh-sock.sock
start /b "pageant.exe" "C:\Program Files\PuTTY\pageant.exe" --unix %USERPROFILE%\.ssh\ssh-sock.sock --openssh-config %USERPROFILE%\.ssh\pageant.conf > nul
