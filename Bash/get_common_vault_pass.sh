#! /bin/bash
if [[ "$(pwd | grep -i 'cdra')" == "" ]]
then
	git config remote.origin.url | awk -F '/' '{print $NF}'
else
	echo "cms-auto-deploy.git"
fi
