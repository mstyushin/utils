#!/bin/bash

SCRIPT_DIR=$( cd $( dirname ${BASH_SOURCE[0]}) && pwd )
LIB_DIR="${SCRIPT_DIR}/../../lib/bash"

if [[ -f ${LIB_DIR}/common.sh ]]; then
  source ${LIB_DIR}/common.sh
else
  echo "Cannot find common lib, exiting"
  exit 1
fi

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
    logme "INFO" "Generating Vagrantfile..."
    if [ -f ${SCRIPT_DIR}/Vagrantfile.tmpl ]; then
        local tmpl=${SCRIPT_DIR}/Vagrantfile.tmpl
    else
        logme "FATAL" "${SCRIPT_DIR}/Vagrantfile.tmpl was not found"
        exit 1
    fi

    local vf=${WORK_DIR}/${BASEBOX_NAME}/Vagrantfile
    cp ${tmpl} ${vf}

    eval $sed_cmd "s/VBOX_BOX_NAME/${VBOX_BOX_NAME}/g" ${vf}
    eval $sed_cmd "s/VBOX_HOSTNAME/${VBOX_HOSTNAME}/g" ${vf}
    eval $sed_cmd "s/VBOX_VM_NAME/${VBOX_VM_NAME}/g" ${vf}
    eval $sed_cmd "s/VBOX_PRIVATE_KEY/${VBOX_PRIVATE_KEY}/g" ${vf}

    logme "INFO" "Vagrantfile has been created"
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
    logme "FATAL" "VM name wasn't specified, exiting"
    exit 1
fi

if [[ -z WORK_DIR ]]; then
    WORK_DIR=${SCRIPT_DIR}
    logme "WARN" "Working directory wasn't specified, use current directory: ${WORK_DIR}"
fi

VBOX_BOX_NAME=${BASEBOX_NAME}
VBOX_HOSTNAME=vagrant
VBOX_VM_NAME=${BASEBOX_NAME}
VBOX_PRIVATE_KEY=id_rsa

mkdir -p ${WORK_DIR}/${BASEBOX_NAME} && cd ${WORK_DIR}/${BASEBOX_NAME}

logme "INFO" "Packaging ${BASEBOX_NAME} base box"
date +%s > ${BASEBOX_NAME}.version
logme "INFO" "Setting version $(cat ${BASEBOX_NAME}.version)"

vagrant package --base ${BASEBOX_NAME} --output ${BASEBOX_NAME}.box --include ${BASEBOX_NAME}.version
if [[ $? -ne 0 ]]; then
  logme "FATAL" "Error while packaging the VM"
  if [[ -d ${WORK_DIR}/${BASEBOX_NAME} ]]; then
    rm -rf ${WORK_DIR}/${BASEBOX_NAME}
  fi
  exit 1
fi

du -hs ${BASEBOX_NAME}.box

logme "INFO" "Basebox is ready, calculating checksum"
shasum -a 256 ${BASEBOX_NAME}.box > ${BASEBOX_NAME}.box.sha256
logme "INFO" "SHA256 is: $(cat ${BASEBOX_NAME}.box.sha256)"

generate_vagrantfile

logme "INFO" "VM has been packaged, find the box file at ${WORK_DIR}/${BASEBOX_NAME}"

exit 0
