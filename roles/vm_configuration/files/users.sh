
#M- maximum number of days for expiry (default 180), W- Number of days of warning before password expires(default-14), m- Minimum number of days between password change (default 1)
#I- Number of days before user account to be locked after I number of inactivity days (default 30)

chage -M $1 ciscosupporttier1
chage -W $2 ciscosupporttier1
chage -m $3 ciscosupporttier1
chage -I $4 ciscosupporttier1

chage -M $1 ciscosupporttier2
chage -W $2 ciscosupporttier2
chage -m $3 ciscosupporttier2
chage -I $4 ciscosupporttier2

chage -M $1 ciscosupporttier3
chage -W $2 ciscosupporttier3
chage -m $3 ciscosupporttier3
chage -I $4 ciscosupporttier3

chage -M $1 em7dcot
chage -W $2 em7dcot
chage -m $3 em7dcot
chage -I $4 em7dcot

chage -M $1 em7release
chage -W $2 em7release
chage -m $3 em7release
chage -I $4 em7release

chage -M $1 silosupport
chage -W $2 silosupport
chage -m $3 silosupport
chage -I $4 silosupport
