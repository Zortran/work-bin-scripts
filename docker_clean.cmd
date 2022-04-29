@echo off

echo "Clean ALL docker containers"
docker ps -a -q | xargs -r docker rm -f 

echo "Clean ALL docker images"
docker images -q | xargs -r docker rmi -f 

echo "Prune system objects"
docker system prune -f