/bin/sudo -S <<<'em7release' /bin/bash -c '/bin/echo ciscosupporttier1:'$2' | /usr/sbin/chpasswd'
/bin/sudo -S <<<'em7release' /bin/bash -c '/bin/echo ciscosupporttier2:'$3' | /usr/sbin/chpasswd'
/bin/sudo -S <<<'em7release' /bin/bash -c '/bin/echo ciscosupporttier3:'$4' | /usr/sbin/chpasswd'
/bin/sudo -S <<<'em7release' /bin/bash -c '/bin/echo silosupport:'$5' | /usr/sbin/chpasswd'
/bin/sudo -S <<<'em7release' /bin/bash -c '/bin/echo ciscosupporttier4:'$6' | /usr/sbin/chpasswd'
/bin/sudo -S <<<'em7release' /bin/bash -c '/bin/echo em7release:'$1' | /usr/sbin/chpasswd'
