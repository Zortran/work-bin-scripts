@(git checkout main||git cheeckout master) && git fetch --all -pPf && git branch -av | awk  '/\[gone\]/{print $1}'|xargs -r git branch -D
