#! /bin/bash
if [[ "x$(pwd | grep -i 'cdra')" == "x" ]]
then
	git config remote.origin.url | awk -F '/' '{print $NF}'
else
	echo "cmsp-auto-deploy.git"
fi
