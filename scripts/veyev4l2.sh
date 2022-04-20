#!/bin/bash

function fetch_veyev4l2_driver() {
    if [[ ! "$(ls -A veyev4l2)" ]]; then    
        echo "Download the veyev4l2 driver"
        git clone ${VEYEV4L2_REPO}
    fi

    pushd veyev4l2
        git fetch
        git reset --hard
        git checkout ${VEYEV4L2_BRANCH}
    popd

}

function build_veyev4l2_driver() {
    pushd veyev4l2
        install -p -m 644 ./pi/$(uname -r)/veyecam2m.ko  /lib/modules/$(uname -r)/kernel/drivers/media/i2c/
        install -p -m 644 ./pi/$(uname -r)/veyecam2m.dtbo /boot/overlays/
        install -p -m 644 ./pi/$(uname -r)/csimx307.ko  /lib/modules/$(uname -r)/kernel/drivers/media/i2c/
        install -p -m 644 ./pi/$(uname -r)/csimx307.dtbo /boot/overlays/
        /sbin/depmod -a $(uname -r)
    popd
}
