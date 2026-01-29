@echo off
echo ======TOP======
kubectl top pod --sum --containers %*
echo ======LIMITS======
kubectl get pods -o custom-columns="POD:metadata.name,CONTAINER:spec.containers[*].name,CPU_REQ:spec.containers[*].resources.requests.cpu,CPU_LIM:spec.containers[*].resources.limits.cpu,MEM_REQ:spec.containers[*].resources.requests.memory,MEM_LIM:spec.containers[*].resources.limits.memory" %*
echo ======QUOTA======
kubectl describe quota