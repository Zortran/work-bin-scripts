@pwsh -command "(git branch -v | sls \[gone\]) | foreach {git branch -D ($_ -split '\s+')[1]}"
::@git branch | findstr /v "* master" | xargs -r git branch -D
