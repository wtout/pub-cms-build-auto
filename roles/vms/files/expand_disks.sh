#! /bin/bash
# Disk1 expansion
partprobe
pvresize /dev/sdb
lvresize -l +100%FREE -r /dev/mapper/vgroup2-opt

## disk 2 and 3 creation
# partition the new disk 2
if [[ "x$(ls /dev/sdc 2>/dev/null)" != "x" ]]
then
        parted --script /dev/sdc mklabel gpt mkpart vgroup3 0% 100% set 1 lvm on
        pvcreate /dev/sdc1
        vgcreate vgroup3 /dev/sdc1
        lvcreate -l100%FREE -n data01 /dev/vgroup3
        mkfs.ext4 /dev/vgroup3/data01
        /bin/mkdir /data01
        echo '/dev/mapper/vgroup3-data01 /data01                    ext4    defaults        1 2' >> /etc/fstab
        /bin/mount -a
        /bin/chown -R root:root /data01
fi

# partition the new disk 3
if [[ "x$(ls /dev/sdd 2>/dev/null)" != "x" ]]
then
        parted --script /dev/sdd mklabel gpt mkpart vgroup4 0% 100% set 1 lvm on
        pvcreate /dev/sdd1
        vgcreate vgroup4 /dev/sdd1
        lvcreate -l100%FREE -n data02 /dev/vgroup4
        mkfs.ext4 /dev/vgroup4/data02
        /bin/mkdir /data02
        echo '/dev/mapper/vgroup4-data02 /data02                    ext4    defaults        1 2' >> /etc/fstab
        /bin/mount -a
        /bin/chown -R root:root /data02
fi
