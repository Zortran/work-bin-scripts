@ (git checkout main||git checkout master) && git fetch -pPf --all && git branch -av | awk  '/\[gone\]/{print $1}'|xargs -r git branch -D
