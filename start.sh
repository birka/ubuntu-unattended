#!/bin/bash
set -e

# set defaults
default_hostname="$(hostname)"
default_domain="$(hostname -d)"
tmp="/root/"

clear

# check for root privilege
if [ "$(id -u)" != "0" ]; then
   echo " this script must be run as root" 1>&2
   echo
   exit 1
fi

# check for interactive shell
if ! grep -q "noninteractive" /proc/cmdline ; then
    stty sane

    # ask questions
    read -ep " please enter your preferred hostname: " -i "$default_hostname" hostname
    read -ep " please enter your preferred domain: " -i "$default_domain" domain
fi

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

# set fqdn
fqdn="$hostname.$domain"

# update hostname
echo "$hostname" > /etc/hostname
sed -i "s@ubuntu.ubuntu@$fqdn@g" /etc/hosts
sed -i "s@ubuntu@$hostname@g" /etc/hosts
hostname "$hostname"

# update repos
apt-get -y update
apt-get -y upgrade
apt-get -y autoremove
apt-get -y purge

# install docker.io
apt-get -y install docker.io

# remove myself to prevent any unintended changes at a later stage
rm $0

# finish
echo " DONE; rebooting ... "

# reboot
reboot
