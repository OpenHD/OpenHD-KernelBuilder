#!/bin/bash

function fetch_exfat_driver() {
    if [[ ! "$(ls -A exfat-linux)" ]]; then    
        echo "Download the exfat driver"
        git clone ${EXFAT_REPO}
    fi

    pushd exfat-linux
        git fetch
        git reset --hard
        git checkout ${EXFAT_BRANCH}
    popd

    echo "Merge the exfat driver into the kernel"
    cp -a exfat-linux/. ${LINUX_DIR}/fs/exfat/

}
