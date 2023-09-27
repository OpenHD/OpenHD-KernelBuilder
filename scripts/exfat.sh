#!/bin/bash

function fetch_exfat_driver() {
    if [[ ! "$(ls -A exfat-linux)" ]]; then    
        echo "Download the exfat driver"
        git clone ${EXFAT_REPO}
    fi

    pushd exfat-linux
        git fetch || exit 1
        git reset --hard || exit 1
        git checkout ${EXFAT_BRANCH} || exit 1
    popd

    echo "Merge the exfat driver into the kernel"
    cp -af exfat-linux/. ${LINUX_DIR}/fs/exfat/ || exit 1

}
