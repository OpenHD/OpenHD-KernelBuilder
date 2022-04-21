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
        mkdir -p ${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/media/i2c/
        install -p -m 644 ./pi/${KERNEL_VERSION}/veyecam2m.ko  "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/media/i2c/"
        install -p -m 644 ./pi/${KERNEL_VERSION}/veyecam2m.dtbo "${PACKAGE_DIR}/boot/overlays/"
        install -p -m 644 ./pi/${KERNEL_VERSION}/csimx307.ko  "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/media/i2c/"
        install -p -m 644 ./pi/${KERNEL_VERSION}/csimx307.dtbo "${PACKAGE_DIR}/boot/overlays/"
        /sbin/depmod -a ${KERNEL_VERSION}
    popd
}