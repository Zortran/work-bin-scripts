@echo off

echo "Clean exited docker containers"
docker ps -f status=exited -q | xargs -r docker rm

echo "Clean untaged docker images"
docker images -f "dangling=true" -q | xargs -r docker rmi

::docker system prune --volumes -f