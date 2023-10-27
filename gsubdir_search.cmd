@powershell -command "Get-ChildItem -Directory -Force -Recurse *.git | ForEach-Object { $OLDDIR=$PWD; write $_.Parent.FullName; cd $_; git fetch --all -pPf; git branch -av |foreach {write ($_ -split '\s+')[1] | sls %*}}"
::@git branch | findstr /v "* master" | xargs -r git branch -D