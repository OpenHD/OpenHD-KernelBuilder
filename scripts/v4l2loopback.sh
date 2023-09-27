#!/bin/bash

function fetch_v4l2loopback_driver() {
    if [[ ! "$(ls -A v4l2loopback)" ]]; then    
        echo "Download the v4l2loopback driver"
        git clone ${V4L2LOOPBACK_REPO} || exit 1
    fi

    pushd v4l2loopback
        git fetch || exit 1
        git reset --hard || exit 1
        git checkout ${V4L2LOOPBACK_BRANCH} || exit 1
    popd

if [[ "${PLATFORM}" == "pi" ]]; then
    echo "Merge the v4l2loopback driver into the kernel"
    cp -af v4l2loopback/. ${LINUX_DIR}/drivers/media/v4l2loopback/ || exit 1
fi

}
function build_v4l2loopback_driver() {
    pushd v4l2loopback
    cd v4l2loopback
    make || exit 1
    mkdir -p $PACKAGE_DIR/test || exit 1
    make install DESTDIR=$PACKAGE_DIR/test || exit 1
    popd
}
