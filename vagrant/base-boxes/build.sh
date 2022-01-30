#!/bin/bash

SCRIPT_DIR=$( cd $( dirname ${BASH_SOURCE[0]}) && pwd )

if [[ "$OSTYPE" == "linux-gnu" ]]; then
  sha_cmd="sha256sum"
  sed_cmd="sed -i"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  sha_cmd="shasum -a 256"
  # BSD sed hack
  sed_cmd="sed -i ''"
else
  sha_cmd="sha256sum"
fi

usage() {
cat << EOF
Usage: $0 -n VBOX_VM_NAME -d WORK_DIRECTORY

Package vagrant box from specified VirtualBox VM. VBox VM name will also be the name of the resulting vagrant box file.

OPTIONS:
   -h | --help             Show this message.
   -n | --box-name         VirtualBox VM name. It will be set as vagrant box file name as well.
   -d | --work-directory   Where to create directory with vagrant box file and corresponding Vagrantfile.

EOF
}

generate_vagrantfile() {
    echo -n "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Generating Vagrantfile..."
    if [ -f ${SCRIPT_DIR}/Vagrantfile.tmpl ]; then
        local tmpl=${SCRIPT_DIR}/Vagrantfile.tmpl
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [FATAL] ${SCRIPT_DIR}/Vagrantfile.tmpl was not found"
        exit 1
    fi

    local vf=${WORK_DIR}/${BASEBOX_NAME}/Vagrantfile
    cp ${tmpl} ${vf}

    eval $sed_cmd "s/VBOX_BOX_NAME/${VBOX_BOX_NAME}/g" ${vf}
    eval $sed_cmd "s/VBOX_HOSTNAME/${VBOX_HOSTNAME}/g" ${vf}
    eval $sed_cmd "s/VBOX_VM_NAME/${VBOX_VM_NAME}/g" ${vf}

    echo "Done"
    return 0
}

while [[ "$1" != "" ]]; do
    case $1 in
        -n | --box-name )
            shift
            BASEBOX_NAME=${1}
        ;;
        -d | --work-directory )
            shift
            WORK_DIR=${1}
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

if [[ -z BASEBOX_NAME ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [FATAL] VM name wasn't specified, exiting"
    exit 1
fi

if [[ -z WORK_DIR ]]; then
    WORK_DIR=${SCRIPT_DIR}
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] Working directory wasn't specified, use current directory: ${WORK_DIR}"
fi

VBOX_BOX_NAME=${BASEBOX_NAME}
VBOX_HOSTNAME=vagrant
VBOX_VM_NAME=${BASEBOX_NAME}

mkdir -p ${WORK_DIR}/${BASEBOX_NAME} && cd ${WORK_DIR}/${BASEBOX_NAME}

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Packaging ${BASEBOX_NAME} base box"
date +%s > ${BASEBOX_NAME}.version
echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Setting version $(cat ${BASEBOX_NAME}.version)"
vagrant package --base ${BASEBOX_NAME} --output ${BASEBOX_NAME}.box --include ${BASEBOX_NAME}.version
du -hs ${BASEBOX_NAME}.box
shasum -a 256 ${BASEBOX_NAME}.box > ${BASEBOX_NAME}.box.sha256
echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] SHA256 is: $(cat ${BASEBOX_NAME}.box.sha256)"

generate_vagrantfile

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Done"

exit 0
