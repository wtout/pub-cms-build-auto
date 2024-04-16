#! /bin/bash
if [[ "$(pwd | grep -i 'cdra')" == "" ]]
then
	git config --file .git/config remote.origin.url | awk -F '/' '{print $NF}'
else
	echo "cms-build-auto-deploy.git"
fi
