#!/usr/bin/env bash
hostname="node01"
domainname="k8s.la.pingworks.net"
ipv4_address="192.168.22.101"
ipv4_network="255.255.255.0"
ipv4_gateway="192.168.22.2"
dns_servers="192.168.22.2"

ubuntu_version="18.04.4"
# ubuntu_version="20.04"

# file names & paths
tmp="/var/tmp"  # destination folder to store the final iso file
additional_dest_folder="/mnt/ubuntu-iso-creator"

currentuser="$( whoami)"

# define spinner function for slow tasks
# courtesy of http://fitnr.com/showing-a-bash-spinner.html
spinner()
{
    local pid=$1
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# define download function
# courtesy of http://fitnr.com/showing-file-download-progress-using-wget.html
download()
{
    local url=$1
    echo -n "    "
    wget --progress=dot $url 2>&1 | grep --line-buffered "%" | \
        sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
    echo -ne "\b\b\b\b"
    echo " DONE"
}

# define function to check if program is installed
# courtesy of https://gist.github.com/JamieMason/4761049
function program_is_installed {
    # set to 1 initially
    local return_=1
    # set to 0 if not found
    type $1 >/dev/null 2>&1 || { local return_=0; }
    # return value
    echo $return_
}

# print a pretty header
echo
echo " +---------------------------------------------------+"
echo " |            UNATTENDED UBUNTU ISO MAKER            |"
echo " +---------------------------------------------------+"
echo

# ask if script runs without sudo or root priveleges
if [ $currentuser != "root" ]; then
    echo " you need sudo privileges to run this script, or run it as root"
    exit 1
fi

#check that we are in ubuntu 16.04+

case "$(lsb_release -rs)" in
    16*|18*|20*) ub1604="yes" ;;
    *) ub1604="" ;;
esac

download_location="http://cdimages.ubuntu.com/ubuntu/releases/bionic/release/"
download_file="ubuntu-18.04.4-server-amd64.iso"
new_iso_name="ubuntu-18.04.4-server-amd64-unattended.iso"
username="root"
timezone="Europe/Berlin"
pwhash='$6$FHn1fCc0$qCp.HOa/LKayMTydkE6bbzYj5XEz40rQyJqBsJkq8lFYX4JsrUsuYWbEaPG8NcPGMR.KlbeD4iJHrUX6Hu4M30'
bootable="yes"

seed_file="pingworks.seed"
rm -f $tmp/$seed_file
cp $seed_file $tmp/
# download the ubuntu iso. If it already exists, do not delete in the end.
cd $tmp
if [[ ! -f $tmp/$download_file ]]; then
    echo -n " downloading $download_file: "
    download "$download_location$download_file"
fi
if [[ ! -f $tmp/$download_file ]]; then
    echo "Error: Failed to download ISO: $download_location$download_file"
    echo "This file may have moved or may no longer exist."
    echo
    echo "You can download it manually and move it to $tmp/$download_file"
    echo "Then run this script again."
    exit 1
fi

# install required packages
echo " installing required packages"
if [ $(program_is_installed "mkpasswd") -eq 0 ] || [ $(program_is_installed "mkisofs") -eq 0 ]; then
    (apt-get -y update > /dev/null 2>&1) &
    spinner $!
    (apt-get -y install whois genisoimage > /dev/null 2>&1) &
    spinner $!
fi
if [[ $bootable == "yes" ]] || [[ $bootable == "y" ]]; then
    if [ $(program_is_installed "isohybrid") -eq 0 ]; then
      #16.04
      if [[ $ub1604 == "yes" || $(lsb_release -cs) == "artful" ]]; then
        (apt-get -y install syslinux syslinux-utils > /dev/null 2>&1) &
        spinner $!
      else
        (apt-get -y install syslinux > /dev/null 2>&1) &
        spinner $!
      fi
    fi
fi


# create working folders
echo " remastering your iso file"
mkdir -p $tmp
mkdir -p $tmp/iso_org
mkdir -p $tmp/iso_new

# mount the image
if grep -qs $tmp/iso_org /proc/mounts ; then
    echo " image is already mounted, continue"
else
    (mount -o loop $tmp/$download_file $tmp/iso_org > /dev/null 2>&1)
fi

# copy the iso contents to the working directory
(cp -rT $tmp/iso_org $tmp/iso_new > /dev/null 2>&1) &
spinner $!

# set the language for the installation menu
cd $tmp/iso_new
#doesn't work for 16.04
echo en > $tmp/iso_new/isolinux/lang

#16.04
#taken from https://github.com/fries/prepare-ubuntu-unattended-install-iso/blob/master/make.sh
sed -i -r 's/timeout\s+[0-9]+/timeout 1/g' $tmp/iso_new/isolinux/isolinux.cfg


# set late command
home_username="/home/$username"
if [[ "$username" = "root" ]] ; then
    home_username="/root"
fi
late_command="chroot /target mkdir $home_username/.ssh ; \
    chroot /target chmod 0700 $home_username/.ssh ; \
    chroot /target touch $home_username/.ssh/authorized_keys ; \
    chroot /target curl -L -o $home_username/.ssh/authorized_keys https://raw.githubusercontent.com/birka/ubuntu-unattended/master/authorized_keys ; \
    chroot /target chmod 0600 $home_username/.ssh/authorized_keys ; \
    chroot /target curl -L -o $home_username/start.sh https://raw.githubusercontent.com/birka/ubuntu-unattended/master/start.sh ; \
    chroot /target chmod +x $home_username/start.sh ;"

# copy the netson seed file to the iso
cp -rT $tmp/$seed_file $tmp/iso_new/preseed/$seed_file

# include firstrun script
echo "
d-i preseed/late_command                                    string      $late_command" >> $tmp/iso_new/preseed/$seed_file


# update the seed file to reflect the users' choices
# the normal separator for sed is /, but both the password and the timezone may contain it
# so instead, I am using @
sed -i "s@{{username}}@$username@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{pwhash}}@$pwhash@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{hostname}}@$hostname@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{domainname}}@$domainname@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{ipv4_address}}@$ipv4_address@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{ipv4_network}}@$ipv4_network@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{ipv4_gateway}}@$ipv4_gateway@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{dns_servers}}@$dns_servers@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{dns_search}}@$dns_search@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{timezone}}@$timezone@g" $tmp/iso_new/preseed/$seed_file

# remove unwanted efi boot loader and copy the good one over...
rm -f $tmp/iso_new/EFI/BOOT/mmx64.efi
rm -f $tmp/iso_new/EFI/BOOT/BOOTx64.EFI
cp $tmp/iso_new/EFI/BOOT/grubx64.efi $tmp/iso_new/EFI/BOOT/BOOTx64.EFI

# calculate checksum for seed file
seed_checksum=$(md5sum $tmp/iso_new/preseed/$seed_file)

# add the autoinstall option to the menu
sed -i "/label install/ilabel autoinstall\n\
  menu label ^Autoinstall Ubuntu Server\n\
  kernel /install/vmlinuz\n\
  append file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/pingworks.seed preseed/file/checksum=$seed_checksum --" $tmp/iso_new/isolinux/txt.cfg

# add the autoinstall option to the menu for USB Boot
sed -i '/set timeout=30/amenuentry "Autoinstall Ubuntu Server" {\n\	set gfxpayload=keep\n\	linux /install/vmlinuz append file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/pingworks.seed quiet ---\n\	initrd	/install/initrd.gz\n\}' $tmp/iso_new/boot/grub/grub.cfg
sed -i -r 's/timeout=[0-9]+/timeout=1/g' $tmp/iso_new/boot/grub/grub.cfg

echo " creating the remastered iso"
cd $tmp/iso_new
(mkisofs -D -r -V "UBUNTU" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $tmp/$new_iso_name . > /dev/null 2>&1) &
spinner $!

# make iso bootable (for dd'ing to  USB stick)
if [[ $bootable == "yes" ]] || [[ $bootable == "y" ]]; then
    isohybrid $tmp/$new_iso_name
fi

# cleanup
umount $tmp/iso_org
rm -rf $tmp/iso_new
rm -rf $tmp/iso_org
rm -rf $tmphtml


# print info to user
echo " -----"
echo " finished remastering your ubuntu iso file"
echo " the new file is located at: $tmp/$new_iso_name"
echo " your username is: $username"
echo " your hostname is: $hostname"
echo " your timezone is: $timezone"
echo

if [ -d $additional_dest_folder ] ; then
    cp $tmp/$new_iso_name $additional_dest_folder/$new_iso_name
fi

# unset vars
unset username
unset hostname
unset timezone
unset pwhash
unset download_file
unset download_location
unset new_iso_name
unset tmp
unset seed_file
