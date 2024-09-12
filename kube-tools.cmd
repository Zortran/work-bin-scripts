@echo off
set "config=%1"
if "%config%"=="" set "config=%USERPROFILE%\temp\MTS-kuber\epc-autotest-bmra636.conf"
echo %config%
for /F "delims=" %%i in ("%config%") do set stand="%%~ni"
::echo %stand%
docker run -it --rm -v %USERPROFILE%\.bash_history:/root/.bash_history -v %USERPROFILE%\.kube\cache:/root/.kube/cache -v %USERPROFILE%\git\MTS\ecat:/wrk -v %config%:/root/.kube/config -e PS1="$? %stand% > " sregistry.mts.ru/ep-pub/docker/release/kube-tools:1.0.43 bash -c "chmod 0600 /root/.kube/config;. /wrk/infra/helms/.vault-mts.sh~; bash"