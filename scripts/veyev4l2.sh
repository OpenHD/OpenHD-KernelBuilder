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
	install -p -m 644 ./pi/5.10.92-v7+/veyecam2m.ko  "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/media/i2c/"	
        install -p -m 644 ./pi/5.10.92-v7+/veyecam2m.dtbo "${PACKAGE_DIR}/boot/overlays/"
        install -p -m 644 ./pi/5.10.92-v7+/csimx307.ko  "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/media/i2c/"
        install -p -m 644 ./pi/5.10.92-v7+/csimx307.dtbo "${PACKAGE_DIR}/boot/overlays/"
        install -p -m 644 ./pi/5.10.92-v7l+/veyecam2m.ko  "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/media/i2c/"
        install -p -m 644 ./pi/5.10.92-v7l+/veyecam2m.dtbo "${PACKAGE_DIR}/boot/overlays/"
        install -p -m 644 ./pi/5.10.92-v7l+/csimx307.ko  "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/media/i2c/"
        install -p -m 644 ./pi/5.10.92-v7l+/csimx307.dtbo "${PACKAGE_DIR}/boot/overlays/"
        install -p -m 644 ./pi/5.10.92-v8+/veyecam2m.ko  "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/media/i2c/"
        install -p -m 644 ./pi/5.10.92-v8+/veyecam2m.dtbo "${PACKAGE_DIR}/boot/overlays/"
        install -p -m 644 ./pi/5.10.92-v8+/csimx307.ko  "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/media/i2c/"
        install -p -m 644 ./pi/5.10.92-v8+/csimx307.dtbo "${PACKAGE_DIR}/boot/overlays/"
        /sbin/depmod -a 5.10.92-v7+
        /sbin/depmod -a 5.10.92-v7l+
        /sbin/depmod -a 5.10.92-v8+
    popd
}