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

    VERSION="2.3.1-evo-$(date '+%m%d%H%M')-$(git rev-parse --short HEAD)"

    rm ${PACKAGE_NAME}_${VERSION}_${PACKAGE_ARCH}.deb >/dev/null 2>&1
    if [[ "${PLATFORM}" == "pi" ]]; then
        cd ${SRC_DIR}
        fpm -a ${PACKAGE_ARCH} -s dir -t deb -n ${PACKAGE_NAME} -v ${VERSION} -C ${PACKAGE_DIR} \
            --after-install after-install.sh \
            --before-install before-install.sh \
            -p ${PACKAGE_NAME}_VERSION_ARCH.deb || exit 1
    fi
    if [[ "${PLATFORM}" == "jetson" ]]; then

        fpm -a ${PACKAGE_ARCH} -s dir -t deb -n ${PACKAGE_NAME} -v ${VERSION} -C ${PACKAGE_DIR} \
            --after-install after-install-jetson.sh \
            --before-install before-install.sh \
            -p ${PACKAGE_NAME}_VERSION_ARCH.deb || exit 1
    fi

    if [[ "${PLATFORM}" == "rock5" ]]; then

        fpm -a ${PACKAGE_ARCH} -s dir -t deb -n ${PACKAGE_NAME} -v ${VERSION} -C ${PACKAGE_DIR} \
            --after-install after-install-jetson.sh \
            --before-install before-install.sh \
            -p ${PACKAGE_NAME}_VERSION_ARCH.deb || exit 1
    fi

    #
    # You can build packages and test them locally without tagging or uploading to the repo, which is only done for
    # releases. Note that we push the same kernel to multiple versions of the repo because there isn't much reason
    # to separate them, and it would create a bit of overhead to manage it that way.
    #

    if [[ "${ONLINE}" == "ONLINE" ]]; then
       
	if [[ "${PLATFORM}" == "jetson" ]]; then
	    git describe --exact-match HEAD >/dev/null 2>&1
            echo "Pushing package to OpenHD repository"
            cloudsmith push deb openhd/openhd-2-3-evo/ubuntu/${DISTRO} ${PACKAGE_NAME}_${VERSION}_${PACKAGE_ARCH}.deb
        fi


        if [[ $? -eq 0 ]]; then
	    git describe --exact-match HEAD >/dev/null 2>&1
            echo "Pushing package to OpenHD 2.3 repository"
            cloudsmith push deb openhd/openhd-2-3-evo/raspbian/${DISTRO} ${PACKAGE_NAME}_${VERSION}_${PACKAGE_ARCH}.deb
        else
	    git describe --exact-match HEAD >/dev/null 2>&1
            echo "Pushing package to OpenHD 2.3 repository"
            cloudsmith push deb openhd/openhd-2-3-evo/raspbian/${DISTRO} ${PACKAGE_NAME}_${VERSION}_${PACKAGE_ARCH}.deb
        fi
    fi
}
function package_headers() {
    PACKAGE_NAME=openhd-linux-${PLATFORM}-headers

    VERSION="2.2.3-evo-$(date '+%m%d%H%M')-$(git rev-parse --short HEAD)"
    rm ${PACKAGE_NAME}_${VERSION}_${PACKAGE_ARCH}.deb >/dev/null 2>&1
    if [[ "${PLATFORM}" == "pi" ]]; then
        cd ${SRC_DIR}
        fpm -a ${PACKAGE_ARCH} -s dir -t deb -n ${PACKAGE_NAME} -v ${VERSION} -C ${PACKAGE_DIR} \
            -p ${PACKAGE_NAME}_VERSION_ARCH.deb || exit 1
    fi
    if [[ "${PLATFORM}" == "jetson" ]]; then

        fpm -a ${PACKAGE_ARCH} -s dir -t deb -n ${PACKAGE_NAME} -v ${VERSION} -C ${PACKAGE_DIR} \
            --after-install after-install-jetson.sh \
            --before-install before-install.sh \
            -p ${PACKAGE_NAME}_VERSION_ARCH.deb || exit 1
    fi
#
    # You can build packages and test them locally without tagging or uploading to the repo, which is only done for
    # releases. Note that we push the same kernel to multiple versions of the repo because there isn't much reason
    # to separate them, and it would create a bit of overhead to manage it that way.
    #

    if [[ "${ONLINE}" == "ONLINE" ]]; then
       
	if [[ "${PLATFORM}" == "jetson" ]]; then
	    git describe --exact-match HEAD >/dev/null 2>&1
            echo "Pushing package to OpenHD repository"
            cloudsmith push deb openhd/openhd-2-3-evo/ubuntu/${DISTRO} ${PACKAGE_NAME}_${VERSION}_${PACKAGE_ARCH}.deb
        fi
    if [[ "${PLATFORM}" == "rock5" ]]; then
	    git describe --exact-match HEAD >/dev/null 2>&1
            echo "Pushing package to OpenHD repository"
            cloudsmith push deb openhd/openhd-2-3-evo/debian/bullseye ${PACKAGE_NAME}_${VERSION}_${PACKAGE_ARCH}.deb
        fi


        if [[ $? -eq 0 ]]; then
	    git describe --exact-match HEAD >/dev/null 2>&1
            echo "Pushing package to OpenHD 2.3 repository"
            cloudsmith push deb openhd/openhd-2-3-evo/raspbian/${DISTRO} ${PACKAGE_NAME}_${VERSION}_${PACKAGE_ARCH}.deb
        else
	    git describe --exact-match HEAD >/dev/null 2>&1
            echo "Pushing package to OpenHD 2.3 repository"
            cloudsmith push deb openhd/openhd-2-3-evo/raspbian/${DISTRO} ${PACKAGE_NAME}_${VERSION}_${PACKAGE_ARCH}.deb
        fi
    fi
}


function copy_overlay() {
    cp -r ${SRC_DIR}/overlay/etc/modprobe.d/* "${PACKAGE_DIR}/etc/modprobe.d/" || exit 1
    cp -r ${SRC_DIR}/overlay/lib/firmware/* "${PACKAGE_DIR}/lib/firmware/" || exit 1
}

function post_processing() {
    unset ARCH CROSS_COMPILE

    echo "Clean kernel build for cache optimization"

    pushd ${LINUX_DIR}
    make clean
    popd
}
