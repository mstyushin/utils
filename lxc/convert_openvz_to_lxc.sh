#!/bin/bash

usage() {
cat << EOF
Usage: $0 [options] [args]

Convert OpenVZ container from vzdump to lxc image tarball.

OPTIONS:
   -h | --help             Show this message.
   -s | --source           Path to vzdump archive OR openvz private        (REQUIRED)
   -d | --destination      Path to resulting lxc image.                    (REQUIRED)
   -m | --convert-mode     Whether to cp or mv original image: cp|mv       (OPTIONAL)
   -c | --comment          String to place into LXC container description  (OPTIONAL)
   -r | --remote-host      Hostname or IP of host where to create tarball  (OPTIONAL)

EXAMPLES:
 - Some meaningful examples here

EOF
}

my_exit(){
  echo -n "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Cleaning tmp directory..."
  if [[ -z ${REMOTE_HOST} ]]; then
    rm -rf ${TMPDIR}
    res=$?
  else
    rm -rf ${TMPDIR} && ssh ${REMOTE_HOST} "rm -rf ${TMPDIR}"
    res=$?
  fi

  if [[ $res -ne 0 ]]; then
    echo "Failed"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] Failed to clean tmp directory"
  else
    echo "Done"
  fi

  if [ "$1" == "0" ]; then
    rm -f $LOCKFILE
    exit 0
  else
    rm -f $LOCKFILE
    exit $1
  fi
}

# unzip_dump ${SRC_IMAGE} ${UNZIPPED_PATH} ${CONVERT_MODE}
unzip_dump() {
  local src=$1
  local dst=$2
  local cmd=$3
  if [[ $3 == "cp" ]]; then
    local cmd="${3} -a"
  fi

  echo -n "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Doing ${cmd} to ${dst}..."
  ${cmd} ${src} ${dst}
  if [[ $? -ne 0 ]]; then
    echo "Failed"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Failed to ${cmd} ${src} to ${dst}"
    return 1
  else
    echo "Done"
  fi

  echo -n "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Unpacking OpenVZ dump..."
  cd ${dst} && tar xf $(basename ${src}) && rm -f ${dst}/$(basename ${src})
  if [[ $? -ne 0 ]]; then
    echo "Failed"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Failed to untar ${src}"
    return 1
  else
    echo "Done"
  fi

  return 0
}

# get_fs_type ${UNZIPPED_PATH}
get_fs_type() {
  local unzipped_dump=$1

  if [ -f ${unzipped_dump}/root.hdd/DiskDescriptor.xml ]; then
    echo -n "ploop"
  else
    echo -n "simfs"
  fi
}

prepare_rootfs() {
  echo -n "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Extracting container hostname: "
  CT_HOSTNAME=$(cat ${ROOTFS_PATH}/etc/sysconfig/network | grep HOSTNAME | cut -d '=' -f2 | tr -d '"')
  echo ${CT_HOSTNAME}
  echo -n "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Extracting container IP address: "
  CT_IPADDR=$(cat ${ROOTFS_PATH}/etc/sysconfig/network-scripts/ifcfg-venet0:0 | grep IPADDR | cut -d '=' -f2 | tr -d '"')
  echo ${CT_IPADDR}

  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Generating metadata.yaml..."
  cat <<EOF > ${TMPDIR}/metadata.yaml
{
    "architecture": "x86_64",
    "creation_date": ${TIMESTAMP},
    "properties": {
        "architecture": "x86_64",
        "description": "${COMMENT}",
        "name": "${CT_HOSTNAME}",
        "os": "centos",
        "release": "6",
        "variant": "default"
    },
    "templates": {
        "/etc/hostname": {
            "template": "hostname.tpl",
            "when": [
                "create"
            ]
        }
        # "/etc/hosts": {
        #     "template": "hosts.tpl",
        #     "when": [
        #         "create"
        #     ]
        # }
    }
}

EOF

  mkdir -p ${TMPDIR}/templates

  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Generating hostname.tpl..."
  cat <<EOF > ${TMPDIR}/templates/hostname.tpl
{{ container.name }}
EOF
  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Generating hosts.tpl..."
  cat <<EOF > ${TMPDIR}/templates/hosts.tpl
127.0.0.1   localhost
127.0.1.1   {{ container.name }}
EOF

  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Cleaning up virtual interfaces..."
  rm -f ${ROOTFS_PATH}/etc/sysconfig/network-scripts/ifcfg-venet0
  rm -f ${ROOTFS_PATH}/etc/sysconfig/network-scripts/ifcfg-venet0:0

  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Generating eth0 config..."
  cat <<EOF > ${ROOTFS_PATH}/etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
BOOTPROTO=static
IPADDR=${CT_IPADDR}
NETMASK=255.255.248.0
ONBOOT=yes
HOSTNAME=${CT_HOSTNAME}
NM_CONTROLLED=no
TYPE=Ethernet
GATEWAY=10.10.40.4
MTU=
IPV6INIT=no
EOF
  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Setting up hostname..."
  cat <<EOF > ${ROOTFS_PATH}/etc/sysconfig/network
NETWORKING="yes"
HOSTNAME="${CT_HOSTNAME}"
EOF

  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Configure limits..."
  cat <<EOF > ${ROOTFS_PATH}/etc/security/limits.d/90-nproc.conf
*          soft    nproc     8196
root       soft    nproc     8196
EOF

  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Setup session auditing..."
  sed -i '/^session.*pam_loginuid.so/s/^session/# session/' ${ROOTFS_PATH}/etc/pam.d/login
  sed -i '/^session.*pam_loginuid.so/s/^session/# session/' ${ROOTFS_PATH}/etc/pam.d/sshd

  if [ -f ${ROOTFS_PATH}/etc/pam.d/crond ]; then
    sed -i '/^session.*pam_loginuid.so/s/^session/# session/' ${ROOTFS_PATH}/etc/pam.d/crond
  fi

  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Disabling pam_loginuid..."
  if [ -f ${ROOTFS_PATH}/lib/security/pam_loginuid.so ]; then
    ( cd ${ROOTFS_PATH}/lib/security/
    mv pam_loginuid.so pam_loginuid.so.disabled
    ln -s pam_permit.so pam_loginuid.so
    )
  fi

  if [ -f ${ROOTFS_PATH}/lib64/security/pam_loginuid.so ]; then
    ( cd ${ROOTFS_PATH}/lib64/security/
    mv pam_loginuid.so pam_loginuid.so.disabled
    ln -s pam_permit.so pam_loginuid.so
    )
  fi

  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Setting default localtime to the host localtime..."
  if [ -e /etc/localtime -a ! -e ${ROOTFS_PATH}/etc/localtime ]; then
    # if /etc/localtime is a symlink, this should preserve it.
    cp -a /etc/localtime ${ROOTFS_PATH}/etc/localtime
  fi

  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Patching halt script..."
  if [ -f ${ROOTFS_PATH}/etc/init.d/halt ]; then
    sed -e '/hwclock/,$d' \
        < ${ROOTFS_PATH}/etc/init.d/halt \
        > ${ROOTFS_PATH}/etc/init.d/lxc-halt

    echo '$command -f' >> ${ROOTFS_PATH}/etc/init.d/lxc-halt
    chmod 755 ${ROOTFS_PATH}/etc/init.d/lxc-halt

    # Link them into the rc directories...
    (
         cd ${ROOTFS_PATH}/etc/rc.d/rc0.d
         ln -s ../init.d/lxc-halt S00lxc-halt
         cd ${ROOTFS_PATH}/etc/rc.d/rc6.d
         ln -s ../init.d/lxc-halt S00lxc-reboot
    )
  fi

  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Generating lxc compatibility init script..."
  cat <<EOF > ${ROOTFS_PATH}/etc/init/lxc-sysinit.conf
start on startup
env container
pre-start script
        if [ "x\$container" != "xlxc" -a "x\$container" != "xlibvirt" ]; then
                stop;
        fi
        rm -f /var/lock/subsys/*
        rm -f /var/run/*.pid
        [ -e /etc/mtab ] || ln -s /proc/mounts /etc/mtab
        mkdir -p /dev/shm
        mount -t tmpfs -o nosuid,nodev tmpfs /dev/shm
        initctl start tty TTY=console
        telinit 3
        exit 0
end script
EOF

  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Initializing /dev..."
  rm -rf ${ROOTFS_PATH}/dev
  mkdir -p ${ROOTFS_PATH}/dev
  mknod -m 666 ${ROOTFS_PATH}/dev/null c 1 3
  mknod -m 666 ${ROOTFS_PATH}/dev/zero c 1 5
  mknod -m 666 ${ROOTFS_PATH}/dev/random c 1 8
  mknod -m 666 ${ROOTFS_PATH}/dev/urandom c 1 9
  mkdir -m 755 ${ROOTFS_PATH}/dev/pts
  mkdir -m 1777 ${ROOTFS_PATH}/dev/shm
  mknod -m 666 ${ROOTFS_PATH}/dev/tty c 5 0
  mknod -m 666 ${ROOTFS_PATH}/dev/tty0 c 4 0
  mknod -m 666 ${ROOTFS_PATH}/dev/tty1 c 4 1
  mknod -m 666 ${ROOTFS_PATH}/dev/tty2 c 4 2
  mknod -m 666 ${ROOTFS_PATH}/dev/tty3 c 4 3
  mknod -m 666 ${ROOTFS_PATH}/dev/tty4 c 4 4
  mknod -m 600 ${ROOTFS_PATH}/dev/console c 5 1
  mknod -m 666 ${ROOTFS_PATH}/dev/full c 1 7
  mknod -m 600 ${ROOTFS_PATH}/dev/initctl p
  mknod -m 666 ${ROOTFS_PATH}/dev/ptmx c 5 2
  rm -f ${ROOTFS_PATH}/etc/init/console.conf
  rm -f ${ROOTFS_PATH}/etc/init/tty2.conf

#   echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Prevent mingetty from calling vhangup(2)..."
#   cat <<EOF > ${ROOTFS_PATH}/etc/init/tty.conf
# stop on runlevel [S016]
# respawn
# instance $TTY
# exec /sbin/mingetty --nohangup $TTY
# usage 'tty TTY=/dev/ttyX  - where X is console id'
# EOF
  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Disable serial consoles..."
  rm -f ${ROOTFS_PATH}/etc/init/tty.conf
  rm -f ${ROOTFS_PATH}/etc/init/serial.conf
  rm -f ${ROOTFS_PATH}/etc/init/start-ttys.conf

  # echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] PTY setup..."
  # ln -s ${ROOTFS_PATH}/dev/pts/ptmx ${ROOTFS_PATH}/dev/ptmx

  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Configuring centos init..."
  sed -i 's|.sbin.start_udev||' ${ROOTFS_PATH}/etc/rc.sysinit
  sed -i 's|.sbin.start_udev||' ${ROOTFS_PATH}/etc/rc.d/rc.sysinit
  chroot ${ROOTFS_PATH} chkconfig udev-post off
  if [ -d ${ROOTFS_PATH}/etc/init ]; then
    # This is to make upstart honor SIGPWR
    cat <<EOF >${ROOTFS_PATH}/etc/init/power-status-changed.conf
#  power-status-changed - shutdown on SIGPWR
#
start on power-status-changed
exec /sbin/shutdown -h now "SIGPWR received"
EOF
  fi

  return 0
}

create_tarball_local() {
  echo -n "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Assembling lxc tarball..."
  cd ${TMPDIR} && tar cpf ./${CT_HOSTNAME}_${TIMESTAMP}.tar metadata.yaml rootfs templates 2>/dev/null
  if [[ $? -ne 0 ]]; then
    echo "Failed"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Failed to create lxc tarball"
    return 1
  else
    echo "Done"
  fi

  echo -n "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Copy final tarball to ${DST_IMAGE}..."
  mv ${TMPDIR}/${CT_HOSTNAME}_${TIMESTAMP}.tar ${DST_IMAGE}
  if [[ $? -ne 0 ]]; then
    echo "Failed"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Failed to copy lxc tarball"
    return 1
  else
    echo "Done"
  fi

  return 0
}

create_tarball_remote() {
  echo -n "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Copy image contents to ${TMPDIR} on host ${REMOTE_HOST}..."
  ssh ${REMOTE_HOST} "mkdir ${TMPDIR}" && rsync -az --del ${ROOTFS_PATH} ${REMOTE_HOST}:${TMPDIR}/ && rsync -az --del ${TMPDIR}/templates ${REMOTE_HOST}:${TMPDIR}/ && rsync -az --del ${TMPDIR}/metadata.yaml ${REMOTE_HOST}:${TMPDIR}/
  if [[ $? -ne 0 ]]; then
    echo "Failed"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Failed to copy image contents"
    return 1
  else
    echo "Done"
  fi

  echo -n "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Assembling lxc tarball on host ${REMOTE_HOST}..."
  ssh ${REMOTE_HOST} "cd ${TMPDIR} && tar cpf ./${CT_HOSTNAME}_${TIMESTAMP}.tar metadata.yaml rootfs templates 2>/dev/null" && ssh ${REMOTE_HOST} "mv ${TMPDIR}/${CT_HOSTNAME}_${TIMESTAMP}.tar ${DST_IMAGE}"
  if [[ $? -ne 0 ]]; then
    echo "Failed"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Failed to create lxc tarball on host ${REMOTE_HOST}"
    return 1
  else
    echo "Done"
  fi

  return 0
}

# convert_simfs
convert_simfs() {
  if [ "$IS_ALIVE" = true ]; then
    cp -a ${UNZIPPED_PATH} ${ROOTFS_PATH}
  else
    mv ${UNZIPPED_PATH} ${ROOTFS_PATH}
  fi

  if ! prepare_rootfs ; then
    return 1
  fi

  if [[ -z REMOTE_HOST ]]; then
    if ! create_tarball_local; then
      return 1
    fi
  else
    if ! create_tarball_remote; then
      return 1
    fi
  fi

  return 0
}

convert_ploop() {
  mkdir -p ${ROOTFS_PATH}
  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Mounting ploop partition..."
  ploop mount -m ${ROOTFS_PATH} ${UNZIPPED_PATH}/root.hdd/DiskDescriptor.xml 2>&1 | while IFS= read -r line; do printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S') [INFO]" "$line"; done
  if [[ $? -ne 0 ]]; then
    echo "Failed"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Failed to mount ploop partition"
    return 1
  fi

  if ! prepare_rootfs ; then
    return 1
  fi

  # echo -n "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Copy from "
  # cp -a ${TMPDIR}/mnt/* ${ROOTFS_PATH}/

  if [[ -z REMOTE_HOST ]]; then
    if ! create_tarball_local; then
      return 1
    fi
  else
    if ! create_tarball_remote; then
      return 1
    fi
  fi

  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Unmounting ploop partition..."
  ploop umount ${UNZIPPED_PATH}/root.hdd/DiskDescriptor.xml 2>&1 | while IFS= read -r line; do printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S') [INFO]" "$line"; done
  if [[ $? -ne 0 ]]; then
    echo "Failed"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Failed to mount ploop partition"
  fi

  return 0
}

# Load parameters
while [[ "$1" != "" ]]; do
  case $1 in
    -c | --comment )
      shift
      COMMENT=$1
      ;;
    -m | --convert-mode )
      shift
      CONVERT_MODE=$1
      ;;
    -d | --destination )
      shift
      DST_IMAGE=$1
      ;;
    -s | --source )
      shift
      SRC_IMAGE=$1
      ;;
    -r | --remote-host )
      shift
      REMOTE_HOST=$1
      ;;
    -h | --help )
      usage
      exit 0
      ;;
    * )
      usage
      exit 1
    esac
  shift
done

if [[ -z $COMMENT ]]; then
  COMMENT="$(basename ${SRC_IMAGE})"
fi

if [[ -z $CONVERT_MODE ]]; then
  CONVERT_MODE="mv"
fi

if [[ -z $SRC_IMAGE ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') [FATAL] Mandatory argument is missing: -s|--source"
  usage
  exit 1
fi

if [[ -z $DST_IMAGE ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') [FATAL] Mandatory argument is missing: -d|--destination"
  usage
  exit 1
fi

TIMESTAMP=$(date +%s)
TMPDIR=$(mktemp -d)
LOCKFILE=/tmp/$(basename ${SRC_IMAGE}|cut -d '.' -f1).lck

# Main execution flow
if [ ! -e $LOCKFILE ]; then
  touch $LOCKFILE

  echo -n "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Preparing tmp directory: "
  ROOTFS_PATH=${TMPDIR}/rootfs
  echo ${TMPDIR}

  if [ -f ${SRC_IMAGE} ]; then
    UNZIPPED_PATH=${TMPDIR}/unzipped
    mkdir -p ${UNZIPPED_PATH}

    if ! unzip_dump ${SRC_IMAGE} ${UNZIPPED_PATH} ${CONVERT_MODE} ; then
      my_exit 1
    fi
  elif [ -d ${SRC_IMAGE} ]; then
    UNZIPPED_PATH=${SRC_IMAGE}
    IS_ALIVE=true
  fi

  FS_TYPE=$(get_fs_type ${UNZIPPED_PATH})
  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Got filesystem layout: ${FS_TYPE}"

  if convert_${FS_TYPE} ; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Conversion process successfully finished"
    my_exit 0
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Conversion of ${SRC_IMAGE} failed"
    my_exit 1
  fi
else
  echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Another conversion process is running. Lockfile: ${LOCKFILE}"
  exit 1
fi

