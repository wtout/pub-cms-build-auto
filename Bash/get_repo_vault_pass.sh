#! /bin/bash
echo ${MYHOME} | awk -F '/' '{print $NF}'