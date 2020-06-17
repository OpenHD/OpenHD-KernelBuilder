#!/bin/bash


PLATFORM=$1
DISTRO=$2


PI_TOOLS_REPO=https://github.com/raspberrypi/tools.git
PI_TOOLS_BRANCH=master

# Fixed at v5.2.20 until 5.3.4 works for injection
RTL_8812AU_REPO=https://github.com/aircrack-ng/rtl8812au.git
RTL_8812AU_BRANCH=v5.2.20

V4L2LOOPBACK_REPO=https://github.com/OpenHD/v4l2loopback.git
V4L2LOOPBACK_BRANCH=openhd1


LINUX_DIR=linux-${PLATFORM}

CONFIGS=$(pwd)/configs

J_CORES=$(nproc)

PACKAGE_DIR=$(pwd)/package

rm -rf ${PACKAGE_DIR}

mkdir -p ${PACKAGE_DIR}/boot/overlays
mkdir -p ${PACKAGE_DIR}/lib/modules


if [[ "${PLATFORM}" == "pi" ]]; then
    if [ ! -d $(pwd)/tools ]; then
        echo "Downloading Raspberry Pi toolchain"
        git clone --depth=1 -b ${PI_TOOLS_BRANCH} ${PI_TOOLS_REPO} $(pwd)/tools
        export PATH=$(pwd)/tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin:${PATH}
        echo "Path: ${PATH}"
    fi

    ARCH=arm
    PACKAGE_ARCH=armhf
    CROSS_COMPILE=arm-linux-gnueabihf-
    KERNEL_REPO=https://github.com/OpenHD/linux.git
fi



fetch_pi_source() {
    if [[ ! -d "${LINUX_DIR}" ]]; then
        echo "Download the pi kernel source"
        git clone ${KERNEL_REPO} ${LINUX_DIR}
    fi

    pushd ${LINUX_DIR}
        git fetch
        git reset --hard
        git checkout ${KERNEL_COMMIT}
    popd
}


fetch_rtl8812_driver() {

    if [[ ! -d rtl8812au ]]; then    
        echo "Download the rtl8812au driver"
        git clone ${RTL_8812AU_REPO}
    fi

    pushd rtl8812au
        git fetch
        git reset --hard
        git checkout ${RTL_8812AU_BRANCH}
    popd

    pushd rtl8812au
        if [[ "${PLATFORM}" == "pi" ]]; then
            sudo sed -i 's/CONFIG_PLATFORM_I386_PC = y/CONFIG_PLATFORM_I386_PC = n/' Makefile
            sudo sed -i 's/CONFIG_PLATFORM_ARM_RPI = n/CONFIG_PLATFORM_ARM_RPI = y/' Makefile
        fi

        # per justins request commented out
        # sudo sed -i 's/CONFIG_USB2_EXTERNAL_POWER = n/CONFIG_USB2_EXTERNAL_POWER = y/' Makefile
        sudo sed -i 's/export TopDIR ?= $(shell pwd)/export TopDIR2 ?= $(shell pwd)/' Makefile
        sudo sed -i '/export TopDIR2 ?= $(shell pwd)/a export TopDIR := $(TopDIR2)/drivers/net/wireless/realtek/rtl8812au/' Makefile

        pushd core
            # Change the STBC value to make all antennas send with awus036ACH
            sudo sed -i 's/u8 fixed_rate = MGN_1M, sgi = 0, bwidth = 0, ldpc = 0, stbc = 0;/u8 fixed_rate = MGN_1M, sgi = 0, bwidth = 0, ldpc = 0, stbc = 1;/' rtw_xmit.c
        popd

    popd

    echo "Merge the RTL8812 driver into the kernel"
    cp -a rtl8812au/. ${LINUX_DIR}/drivers/net/wireless/realtek/rtl8812au/
}


fetch_v4l2loopback_driver() {
    if [[ ! -d v4l2loopback ]]; then    
        echo "Download the v4l2loopback driver"
        git clone ${V4L2LOOPBACK_REPO}
    fi

    pushd rtl8812au
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

        yes "" | KERNEL=${KERNEL} ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} make oldconfig || exit 1

        KERNEL=${KERNEL} ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} make -j $J_CORES zImage modules dtbs || exit 1

        echo "Copy kernel"
        cp arch/arm/boot/zImage "${PACKAGE_DIR}/boot/${KERNEL}.img" || exit 1

        echo "Copy kernel modules"
        make -j $J_CORES ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}  INSTALL_MOD_PATH="${PACKAGE_DIR}" modules_install || exit 1

        echo "Copy DTBs"
        sudo cp arch/arm/boot/dts/*.dtb "${PACKAGE_DIR}/boot/" || exit 1
        sudo cp arch/arm/boot/dts/overlays/*.dtb* "${PACKAGE_DIR}/boot/overlays/" || exit 1
        sudo cp arch/arm/boot/dts/overlays/README "${PACKAGE_DIR}/boot/overlays/" || exit 1

        # prevents the inclusion of firmware that can conflict with normal firmware packages, dpkg will complain. there
        # should be a kernel config to stop installing this into the package dir in the first place
        rm -r "${PACKAGE_DIR}/lib/firmware"
    popd
}


package() {
    PACKAGE_NAME=openhd-linux-${PLATFORM}

    VERSION=$(git describe --tags | sed 's/\(.*\)-.*/\1/')

    fpm -a ${PACKAGE_ARCH} -s dir -t deb -n ${PACKAGE_NAME} -v ${VERSION} -C ${PACKAGE_DIR} -p ${PACKAGE_NAME}_VERSION_ARCH.deb || exit 1

    #
    # Only push to cloudsmith for tags. If you don't want something to be pushed to the repo, 
    # don't create a tag. You can build packages and test them locally without tagging.
    #
    git describe --exact-match HEAD
    if [[ $? -eq 0 ]]; then
        cloudsmith push deb openhd/openhd/raspbian/${DISTRO} ${PACKAGE_NAME}_${VERSION}_${PACKAGE_ARCH}.deb
    fi
}



if [[ "${PLATFORM}" == "pi" ]]; then
    # a simple hack, we want 3 kernels in one package so we source 3 different configs and build them all
    source $(pwd)/kernels/${PLATFORM}-${DISTRO}-v6
    fetch_pi_source
    fetch_rtl8812_driver
    fetch_v4l2loopback_driver
    build_pi_kernel

    source $(pwd)/kernels/${PLATFORM}-${DISTRO}-v7
    fetch_pi_source
    fetch_rtl8812_driver
    fetch_v4l2loopback_driver
    build_pi_kernel

    if [[ -f "$(pwd)/kernels/${PLATFORM}-${DISTRO}-v7l" ]]; then
        source $(pwd)/kernels/${PLATFORM}-${DISTRO}-v7l
        fetch_pi_source
        fetch_rtl8812_driver
        fetch_v4l2loopback_driver
        build_pi_kernel
    fi
fi

package
