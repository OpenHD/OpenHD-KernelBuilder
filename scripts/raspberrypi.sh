#!/bin/bash

function setup_pi_env() {
    if [[ "${PLATFORM}" == "pi" ]]; then
        # CCACHE workaround
        CCACHE_PATH=${PI_TOOLS_COMPILER_PATH}/../bin-ccache
    
        if [[ ! "$(ls -A ${CCACHE_PATH})" ]]; then
            mkdir -p ${CCACHE_PATH}
            pushd ${CCACHE_PATH}
                ln -s $(which ccache) arm-linux-gnueabihf-gcc
                ln -s $(which ccache) arm-linux-gnueabihf-g++
                ln -s $(which ccache) arm-linux-gnueabihf-cpp
                ln -s $(which ccache) arm-linux-gnueabihf-c++
            popd
        fi
        if [[ ${PATH} != *${CCACHE_PATH}* ]]; then
            export PATH=${CCACHE_PATH}:${PATH}
        fi

        export ARCH=arm
        PACKAGE_ARCH=armhf
        export CROSS_COMPILE=arm-linux-gnueabihf-
        KERNEL_REPO=https://github.com/OpenHD/linux.git
    fi
}

function fetch_pi_source() {
    if [[ ! "$(ls -A ${LINUX_DIR})" ]]; then
        echo "Download the pi kernel source"
        git clone ${KERNEL_REPO} ${LINUX_DIR}
    fi

    pushd ${LINUX_DIR}
        git fetch
        git reset --hard
        git checkout ${KERNEL_COMMIT}
    popd
}
