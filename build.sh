#!/bin/bash

echoerr() { echo "$@" 1>&2; }

PLATFORM=$1
DISTRO=$2


PI_TOOLS_REPO=https://github.com/raspberrypi/tools.git
PI_TOOLS_BRANCH=master

# Fixed at v5.2.20 until 5.3.4 works for injection
RTL_8812AU_REPO=https://github.com/OpenHD/rtl8812au.git
RTL_8812AU_BRANCH=20200719.1

RTL_8812BU_REPO=https://github.com/OpenHD/rtl88x2bu.git
RTL_8812BU_BRANCH=5.6.1_30362.20181109_COEX20180928-6a6a


V4L2LOOPBACK_REPO=https://github.com/OpenHD/v4l2loopback.git
V4L2LOOPBACK_BRANCH=openhd1


SRC_DIR=$(pwd)

LINUX_DIR=$(pwd)/linux-${PLATFORM}

CONFIGS=$(pwd)/configs

J_CORES=$(nproc)

PACKAGE_DIR=$(pwd)/package

rm -rf ${PACKAGE_DIR}

mkdir -p ${PACKAGE_DIR}/etc/modprobe.d || exit 1
mkdir -p ${PACKAGE_DIR}/boot || exit 1
mkdir -p ${PACKAGE_DIR}/boot/overlays || exit 1
mkdir -p ${PACKAGE_DIR}/lib/modules || exit 1
mkdir -p ${PACKAGE_DIR}/lib/firmware || exit 1
mkdir -p ${PACKAGE_DIR}/usr/local/share/openhd/kernel/overlays || exit 1
mkdir -p ${PACKAGE_DIR}/usr/local/share/openhd/kernel/dtb || exit 1


if [[ "${PLATFORM}" == "pi" ]]; then
    PI_TOOLS_COMPILER_PATH="$(pwd)/tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin"
    if [ ! "$(ls -A ${PWD}/tools)" ]; then
        echo "Downloading Raspberry Pi toolchain"
        git clone --depth=1 -b ${PI_TOOLS_BRANCH} ${PI_TOOLS_REPO} $(pwd)/tools
    fi
    if [[ ${PATH} != *${PI_TOOLS_COMPILER_PATH}* ]]; then
        export PATH=${PI_TOOLS_COMPILER_PATH}:${PATH}
        echo "Path: ${PATH}"
    fi
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
        export PATH=${CCACHE_PATH}:${PATH}
    fi
    if [[ ${PATH} != *${CCACHE_PATH}* ]]; then
        export PATH=${CCACHE_PATH}:${PATH}
    fi

    export ARCH=arm
    PACKAGE_ARCH=armhf
    export CROSS_COMPILE=arm-linux-gnueabihf-
    KERNEL_REPO=https://github.com/OpenHD/linux.git
fi

#######################################
### START TRAVIS TIMEOUT PREVENTION ###
#######################################

# System uptime in seconds
get_uptime_in_seconds() {
    # https://gist.github.com/OndroNR/0a36f97cd612b75fbf92f22cf72851a3
    local  __resultvar=$1
    
    if [ -e /proc/uptime ] ; then
       local uptime=`cat /proc/uptime | awk '{printf "%0.f", $1}'`
    else
        set +e
        sysctl kern.boottime &> /dev/null
        if [ $? -eq 0 ] ; then
            local kern_boottime=`sysctl kern.boottime 2> /dev/null | sed "s/.* sec\ =\ //" | sed "s/,.*//"`
            local time_now=`date +%s`
            local uptime=$((${time_now} - ${kern_boottime}))
        else
            
            exit 1
        fi
        set -e
    fi    
    eval $__resultvar="'${uptime}'"
}
get_uptime_in_seconds start_time

# Script runtime in seconds
get_running_time() {
    local  __resultvar=$1
    get_uptime_in_seconds now
    local result=$(echo "${now} - ${start_time}" | bc)   
    eval $__resultvar="'$result'"
}

# This is for Travis, if build takes too long, just exit out and warm up the cache
check_time() {
    get_running_time uptime

    # If script is running more then 20 minutes, exit out and prevent Travis from timeout
    if [[ -n $TRAVIS && ${uptime} -gt $((20*60)) ]]; then
        echoerr "Uptime: ${uptime}s"
        echoerr "Please restart this Travis build. The cache isn't warm!"
        exit 1
    fi
}
#####################################
### END TRAVIS TIMEOUT PREVENTION ###
#####################################

fetch_pi_source() {
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


fetch_rtl8812au_driver() {

    if [[ ! "$(ls -A rtl8812au)" ]]; then    
        echo "Download the rtl8812au driver"
        git clone ${RTL_8812AU_REPO}
    fi

    pushd rtl8812au
        git fetch
        git reset --hard
        git checkout ${RTL_8812AU_BRANCH}
        git pull
    popd

    pushd rtl8812au
        if [[ "${PLATFORM}" == "pi" ]]; then
            sed -i 's/CONFIG_PLATFORM_I386_PC = y/CONFIG_PLATFORM_I386_PC = n/' Makefile
            sed -i 's/CONFIG_PLATFORM_ARM_RPI = n/CONFIG_PLATFORM_ARM_RPI = y/' Makefile
        fi

        pushd core
            # Change the STBC value to make all antennas send with awus036ACH
            sed -i 's/u8 fixed_rate = MGN_1M, sgi = 0, bwidth = 0, ldpc = 0, stbc = 0;/u8 fixed_rate = MGN_1M, sgi = 0, bwidth = 0, ldpc = 0, stbc = 1;/' rtw_xmit.c
        popd

    popd
}

fetch_rtl8812bu_driver() {

    if [[ ! "$(ls -A rtl88x2bu)" ]]; then    
        echo "Download the rtl8812bu driver"
        git clone ${RTL_8812BU_REPO}
    fi

    pushd rtl88x2bu
        git fetch
        git reset --hard
        git checkout ${RTL_8812BU_BRANCH}
        git pull
    popd

    pushd rtl88x2bu
        if [[ "${PLATFORM}" == "pi" ]]; then
            sed -i 's/CONFIG_PLATFORM_I386_PC = y/CONFIG_PLATFORM_I386_PC = n/' Makefile
            sed -i 's/CONFIG_PLATFORM_ARM_RPI = n/CONFIG_PLATFORM_ARM_RPI = y/' Makefile
        fi

        sed -i 's/CONFIG_WIFI_MONITOR = n/CONFIG_WIFI_MONITOR = y\nCONFIG_AP_MODE = y/' Makefile

        sed -i 's/export TopDIR ?= $(shell pwd)/export TopDIR2 ?= $(shell pwd)/' Makefile
        sed -i '/export TopDIR2 ?= $(shell pwd)/a export TopDIR := $(TopDIR2)/drivers/net/wireless/realtek/rtl88x2bu/' Makefile
    popd
}


fetch_v4l2loopback_driver() {
    if [[ ! "$(ls -A v4l2loopback)" ]]; then    
        echo "Download the v4l2loopback driver"
        git clone ${V4L2LOOPBACK_REPO}
    fi

    pushd v4l2loopback
        git fetch
        git reset --hard
        git checkout ${V4L2LOOPBACK_BRANCH}
    popd

    echo "Merge the v4l2loopback driver into the kernel"
    cp -a v4l2loopback/. ${LINUX_DIR}/drivers/media/v4l2loopback/

}


build_pi_kernel() {
    echo "Building pi kernel"

    pushd ${LINUX_DIR}

        echo "Set kernel config"
        cp "${CONFIGS}/.config-${KERNEL_BRANCH}-${ISA}" ./.config || exit 1

        make clean

        yes "" | make oldconfig || exit 1

        KBUILD_BUILD_TIMESTAMP='' make -j $J_CORES zImage modules dtbs || exit 1

        echo "Copy kernel"
        cp arch/arm/boot/zImage "${PACKAGE_DIR}/usr/local/share/openhd/kernel/${KERNEL}.img" || exit 1

        echo "Copy kernel modules"
        make -j $J_CORES INSTALL_MOD_PATH="${PACKAGE_DIR}" modules_install || exit 1

        echo "Copy DTBs"
        cp arch/arm/boot/dts/*.dtb "${PACKAGE_DIR}/usr/local/share/openhd/kernel/dtb/" || exit 1
        cp arch/arm/boot/dts/overlays/*.dtb* "${PACKAGE_DIR}/usr/local/share/openhd/kernel/overlays/" || exit 1
        cp arch/arm/boot/dts/overlays/README "${PACKAGE_DIR}/usr/local/share/openhd/kernel/overlays/" || exit 1

        # prevents the inclusion of firmware that can conflict with normal firmware packages, dpkg will complain. there
        # should be a kernel config to stop installing this into the package dir in the first place
        rm -r "${PACKAGE_DIR}/lib/firmware/*"
    popd

    pushd rtl8812au
        make clean
        make KSRC=${LINUX_DIR} -j $J_CORES M=$(pwd) modules || exit 1
        mkdir -p ${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/rtl8812au
        install -p -m 644 88XXau.ko "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/rtl8812au/" || exit 1
    popd

    pushd rtl88x2bu
        make clean
        make KSRC=${LINUX_DIR} -j $J_CORES M=$(pwd) modules || exit 1
        mkdir -p ${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/rtl88x2bu
        install -p -m 644 88x2bu.ko "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/rtl88x2bu/" || exit 1
    popd

    cp ${SRC_DIR}/overlay/boot/* "${PACKAGE_DIR}/usr/local/share/openhd/kernel/" || exit 1
}


package() {
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
        echo "Not a tagged release, skipping push to OpenHD repository"
    fi
}


copy_overlay() {
    cp ${SRC_DIR}/overlay/etc/modprobe.d/* "${PACKAGE_DIR}/etc/modprobe.d/" || exit 1
    cp ${SRC_DIR}/overlay/lib/firmware/* "${PACKAGE_DIR}/lib/firmware/" || exit 1
}

prepare_build() {
    check_time
    fetch_pi_source
    fetch_rtl8812au_driver
    fetch_rtl8812bu_driver
    fetch_v4l2loopback_driver
    build_pi_kernel
}

if [[ "${PLATFORM}" == "pi" ]]; then
    # a simple hack, we want 3 kernels in one package so we source 3 different configs and build them all
    source $(pwd)/kernels/${PLATFORM}-${DISTRO}-v6
    prepare_build

    source $(pwd)/kernels/${PLATFORM}-${DISTRO}-v7
    prepare_build

    if [[ -f "$(pwd)/kernels/${PLATFORM}-${DISTRO}-v7l" ]]; then
        source $(pwd)/kernels/${PLATFORM}-${DISTRO}-v7l
        prepare_build
    fi
fi

copy_overlay
package

unset ARCH CROSS_COMPILE

echo "Clean kernel build for cache optimization"

pushd ${LINUX_DIR}
    make clean
popd

# Show cache stats
ccache -s
