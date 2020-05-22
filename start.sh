#!/bin/bash
set -e

clear

# check for root privilege
if [ "$(id -u)" != "0" ]; then
   echo " this script must be run as root" 1>&2
   echo
   exit 1
fi
# Disabling swap
swapoff -a
sed -i '/swapfile / s/^/#/' /etc/fstab

# print status message
echo " preparing your server; this may take a few minutes ..."

# create mountpoint for docker
[ -d /var/lib/docker ] || mkdir -p /var/lib/docker

# detect free partition
FREE_UNMOUNTED_PART=""
for P in $(fdisk -l /dev/sda | grep 'Linux filesystem' | awk '{print $1;}');do
    if mount | grep $P;then
        echo 'Partition $P already mounted - skipping...'
    else
        echo 'Partition $P is free and unmounted - using it.'
        FREE_UNMOUNTED_PART=$P
    fi
done
mount $FREE_UNMOUNTED_PART /var/lib/docker
echo "$FREE_UNMOUNTED_PART	/var/lib/docker	ext4	defaults	0	0" >> /etc/fstab

# update repos
apt-get -y update
apt-get -y upgrade
apt-get -y autoremove
apt-get -y purge

apt-get install -y unattended-upgrades
cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

# remove myself to prevent any unintended changes at a later stage
# rm $0

# finish
echo " DONE; rebooting ... "

# reboot
#reboot
