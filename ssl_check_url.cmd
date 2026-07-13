@echo off
echo | openssl s_client -showcerts %*:443 |openssl x509 -noout -dates