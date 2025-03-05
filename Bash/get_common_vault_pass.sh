#! /bin/bash
if [[ "$(pwd | grep -i 'cdra')" == "" ]]
then
	password=$(git config --file .git/config remote.origin.url | awk -F '/' '{print $NF}' | sed -e "s|^pub-||")
	[[ "${password}" != *".git" ]] && password="${password}.git"
else
	password="cms-build-auto.git"
fi
echo ${password}