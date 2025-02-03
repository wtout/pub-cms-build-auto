#! /bin/bash
if [[ "$(pwd | grep -i 'cdra')" == "" ]]
then
	git config --file .git/config remote.origin.url | awk -F '/' '{print $NF}' | sed -e "s|^pub-||"
else
	echo "cms-build-auto.git"
fi
