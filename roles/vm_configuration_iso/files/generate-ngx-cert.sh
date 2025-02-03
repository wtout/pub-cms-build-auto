#!/bin/bash

cp /etc/nginx/silossl.key /etc/nginx/silossl.key.old
cp /etc/nginx/silossl.pem /etc/nginx/silossl.pem.old
openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 -subj "/C=US/ST=Silo/L=Reston/O=Silo/CN=`hostname`" -keyout /etc/nginx/silossl.key -out /etc/nginx/silossl.pem
systemctl restart nginx
