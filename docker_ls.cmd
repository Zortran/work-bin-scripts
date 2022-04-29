@echo off
echo ==== Network =======
docker network ls
echo ==== Volumes =======
docker volume ls
echo ==== Images =======
docker images
echo ==== Contaners ====
docker ps -a