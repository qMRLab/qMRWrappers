if [ $1 = "latest" ]; then
    echo Checking out $1
    git fetch --tags
    latestTag=$(git describe --tags `git rev-list --tags --max-count=1`)
    git checkout $latestTag
    echo Checked out $latestTag
elif [ $1 = "debug" ]; then
    echo Debug HEAD is on master latest    
else
    git checkout $1 
    echo Checked out $1
fi