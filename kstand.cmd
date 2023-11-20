@echo off
kubectl -n "%*" get pods  --output="jsonpath={range .items[*]}[{.metadata.name},{.spec.containers..image}]{'\n'}{end}"