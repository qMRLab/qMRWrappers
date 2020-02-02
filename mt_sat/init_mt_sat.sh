
git clone https://github.com/qMRLab/qMRWrappers.git \
cd qMRWrappers

if [ $1 == "latest" ]; then
    git fetch --tags
    latestTag=$(git describe --tags `git rev-list --tags --max-count=1`)
    git checkout $latestTag
else
    git checkout $1
fi    

cd mt_sat