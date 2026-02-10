@pwsh -command "Get-ChildItem -Directory -Force -Recurse *.git | ForEach-Object -Parallel { cd $($_.Parent); $LOG=&{ echo ""$($_.Parent)""; git pull --rebase --all --prune --tags }; write $LOG }"
