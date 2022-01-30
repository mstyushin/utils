#!/bin/bash

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Refreshing local yum cache and installing epel"
yum clean all && yum makecache && yum -y install epel-release && yum makecache

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Installing basic tools for vagrant base box"
yum -y install nano vim kernel-headers kernel-devel python-devel python-pip gcc make automake git man net-tools openssl-devel bzip2 dkms

yum -y update kernel

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Updating OS"
yum check-update && yum -y update

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Rebooting"
reboot

