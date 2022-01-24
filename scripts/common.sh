#!/bin/bash

# Echo to stderr
echoerr() { echo "$@" 1>&2; }

function init() {
    rm -rf ${PACKAGE_DIR}

    mkdir -p ${PACKAGE_DIR}/etc/modprobe.d || exit 1
    mkdir -p ${PACKAGE_DIR}/boot || exit 1
    mkdir -p ${PACKAGE_DIR}/boot/overlays || exit 1
    mkdir -p ${PACKAGE_DIR}/lib/modules || exit 1
    mkdir -p ${PACKAGE_DIR}/lib/firmware || exit 1
    mkdir -p ${PACKAGE_DIR}/usr/local/share/openhd/kernel/overlays || exit 1
    mkdir -p ${PACKAGE_DIR}/usr/local/share/openhd/kernel/dtb || exit 1
    mkdir -p ${PACKAGE_DIR}/usr/local/bin || exit 1
}

function package() {
    PACKAGE_NAME=openhd-linux-${PLATFORM}

    VERSION=20201124.1

    rm ${PACKAGE_NAME}_${VERSION}_${PACKAGE_ARCH}.deb > /dev/null 2>&1

    fpm -a ${PACKAGE_ARCH} --name ${PACKAGE_NAME}\
    --after-install after-install.sh\
    --before-install before-install.sh\
    -p ${PACKAGE_NAME}_VERSION_ARCH.deb -s dir -t deb\
    -C ${PACKAGE_DIR} --version ${VERSION}  || exit 1

    #
    # You can build packages and test them locally without tagging or uploading to the repo, which is only done for
    # releases. Note that we push the same kernel to multiple versions of the repo because there isn't much reason
    # to separate them, and it would create a bit of overhead to manage it that way.
    #
    git describe --exact-match HEAD > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo "Pushing package to OpenHD repository"
        cloudsmith push deb openhd/openhd-2-1/raspbian/${DISTRO} ${PACKAGE_NAME}_${VERSION}_${PACKAGE_ARCH}.deb
    else
        echo "Pushing package to OpenHD testing repository"
        cloudsmith push deb openhd/openhd-2-1-testing/raspbian/${DISTRO} ${PACKAGE_NAME}_${VERSION}_${PACKAGE_ARCH}.deb
    fi
}


function copy_overlay() {
    cp ${SRC_DIR}/overlay/etc/modprobe.d/* "${PACKAGE_DIR}/etc/modprobe.d/" || exit 1
    cp ${SRC_DIR}/overlay/lib/firmware/* "${PACKAGE_DIR}/lib/firmware/" || exit 1
}

function post_processing() {
    unset ARCH CROSS_COMPILE

    echo "Clean kernel build for cache optimization"

    pushd ${LINUX_DIR}
        make clean
    popd
}
