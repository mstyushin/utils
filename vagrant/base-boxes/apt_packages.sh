#!/bin/bash
# Must be run as root!
# Dont forget to insert guest additions iso

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Refreshing local apt cache and upgrading system"
apt-get update && apt-get upgrade

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Installing basic tools for vagrant base box"
apt-get install -qq -y sudo nano vim git build-essential make automake libssl-dev dkms linux-headers-$(uname -r) python-dev python-pip gcc net-tools

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Building guest additions"
mount -o loop /dev/cdrom /mnt
/mnt/VBoxLinuxAdditions.run

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Rebooting"
reboot

