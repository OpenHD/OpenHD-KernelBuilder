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
}

function package() {
    PACKAGE_NAME=openhd-linux-${PLATFORM}

    VERSION=$(git describe --tags | sed 's/\(.*\)-.*/\1/')

    rm ${PACKAGE_NAME}_${VERSION}_${PACKAGE_ARCH}.deb > /dev/null 2>&1

    fpm -a ${PACKAGE_ARCH} -s dir -t deb -n ${PACKAGE_NAME} -v ${VERSION} -C ${PACKAGE_DIR} \
    --after-install after-install.sh \
    --before-install before-install.sh \
    -p ${PACKAGE_NAME}_VERSION_ARCH.deb || exit 1

    #
    # Only push to cloudsmith for tags. If you don't want something to be pushed to the repo, 
    # don't create a tag. You can build packages and test them locally without tagging.
    #
    git describe --exact-match HEAD > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo "Pushing package to OpenHD repository"
        cloudsmith push deb openhd/openhd-2-0/raspbian/${DISTRO} ${PACKAGE_NAME}_${VERSION}_${PACKAGE_ARCH}.deb
    else
        echo "Pushing package to OpenHD testing repository"
        cloudsmith push deb openhd/openhd-2-0-testing/raspbian/${DISTRO} ${PACKAGE_NAME}_${VERSION}_${PACKAGE_ARCH}.deb
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
