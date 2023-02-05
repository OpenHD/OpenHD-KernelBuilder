#!/bin/bash

function fetch_v4l2loopback_driver() {
    if [[ ! "$(ls -A v4l2loopback)" ]]; then    
        echo "Download the v4l2loopback driver"
        git clone ${V4L2LOOPBACK_REPO}
    fi

    pushd v4l2loopback
        git fetch
        git reset --hard
        git checkout ${V4L2LOOPBACK_BRANCH}
    popd

if [[ "${PLATFORM}" == "pi" ]]; then
    echo "Merge the v4l2loopback driver into the kernel"
    cp -a v4l2loopback/. ${LINUX_DIR}/drivers/media/v4l2loopback/
fi

}
function build_v4l2loopback_driver() {
    pushd v4l2loopback
    cd v4l2loopback
    make
    mkdir -p $PACKAGE_DIR/test
    make install DESTDIR=$PACKAGE_DIR/test
    popd
}