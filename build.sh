#!/bin/bash

PLATFORM=$1
DISTRO=$2
ONLINE=$3

if  [[ "${PLATFORM}" != "pi" ]] && [[ "${PLATFORM}" != "jetson" ]];  then
    echo "Usage: ./build.sh pi buster"
    echo ""
    echo "Target kernels:"
    echo ""
    ls -1 kernels/
    echo ""
    exit 1
fi


echo "Youre building for $PLATFORM $DISTRO"


##############
### Config ###
##############

# Fixed at v5.2.20 until 5.3.4 works for injection
RTL_8812AU_REPO=https://github.com/OpenHD/rtl8812au.git
RTL_8812AU_BRANCH=20201214.1-new

RTL_8812BU_REPO=https://github.com/OpenHD/rtl88x2bu.git
RTL_8812BU_BRANCH=5.6.1_30362.20181109_COEX20180928-6a6a

RTL_8188EUS_REPO=https://github.com/SmartBoy84/rtl8188eus
RTL_8188EUS_BRANCH=v5.3.9

V4L2LOOPBACK_REPO=https://github.com/OpenHD/v4l2loopback.git
V4L2LOOPBACK_BRANCH=openhd

EXFAT_REPO=https://github.com/OpenHD/exfat-linux.git
EXFAT_BRANCH=openhd2

VEYEV4L2_REPO=https://github.com/OpenHD/veyev4l2.git
VEYEV4L2_BRANCH=2.1-milestones


#####################
### BUILD HELPERS ###
#####################


SRC_DIR=$(pwd)
	if [[ "${PLATFORM}" == "pi" ]]; then
	LINUX_DIR=$(pwd)/workdir/linux-${PLATFORM}
	else
	LINUX_DIR=$(pwd)/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9
	fi
CONFIGS=$(pwd)/configs
J_CORES=$(nproc)
PACKAGE_DIR=$(pwd)/package

# load helper scripts
for File in scripts/*.sh; do
    source ${File}
    echo "LOAD ${File}"
done

# Remove previous build dir and recreate
init

###################   Env's like $ARCH
### BUILD ENV's ###   and $CROSS_COMPILE
###################   are set here

setup_platform_env



build_pi_kernel() {

    echo "Building pi kernel"

    pushd ${LINUX_DIR}

        echo "Set kernel config"
        cp "${CONFIGS}/.config-${KERNEL_BRANCH}-${ISA}" ./.config || exit 1

        make clean

        yes "" | make oldconfig || exit 1

        KERNEL=${KERNEL} KBUILD_BUILD_TIMESTAMP='' make -j $J_CORES zImage modules dtbs || exit 1

        echo "Copy kernel modules"
        make -j $J_CORES INSTALL_MOD_PATH="${PACKAGE_DIR}" modules_install || exit 1

        echo "Copy DTBs"
        cp arch/arm/boot/dts/*.dtb "${PACKAGE_DIR}/usr/local/share/openhd/kernel/dtb/" || exit 1
        cp arch/arm/boot/dts/overlays/*.dtb* "${PACKAGE_DIR}/usr/local/share/openhd/kernel/overlays/" || exit 1
        cp arch/arm/boot/dts/overlays/README "${PACKAGE_DIR}/usr/local/share/openhd/kernel/overlays/" || exit 1

        # prevents the inclusion of firmware that can conflict with normal firmware packages, dpkg will complain. there
        # should be a kernel config to stop installing this into the package dir in the first place
        rm -r "${PACKAGE_DIR}/lib/firmware/*"

        pushd tools/perf
            #ARCH=${ARCH} KERNEL=${KERNEL} make perf || exit 1
            #cp perf ${PACKAGE_DIR}/usr/local/bin/perf-${KERNEL_VERSION} || exit 1
        popd
    popd

    # Build Realtek drivers
    build_rtl8812au_driver
    build_rtl8812bu_driver
    build_rtl8188eus_driver

    depmod -b ${PACKAGE_DIR} ${KERNEL_VERSION}

}

build_jetson_kernel() {

    
	echo "Building jetson kernel"
	
	TEGRA_KERNEL_OUT=$LINUX_DIR/build
	KERNEL_MODULES_OUT=$LINUX_DIR/modules		
	export CROSS_COMPILE=$Tools/gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
	

	cd $JETSON_NANO_KERNEL_SOURCE
 
    cp $SRC_DIR/additional/imx519/*.dtsi $SRC_DIR/workdir/Linux_for_Tegra/source/public/hardware/nvidia/platform/t210/porg/kernel-dts/porg-platforms
    cp $SRC_DIR/additional/imx519/*.dts $SRC_DIR/workdir/Linux_for_Tegra/source/public/hardware/nvidia/platform/t210/porg/kernel-dts
    cp $SRC_DIR/additional/imx519/imx519_mode_tbls.h $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/drivers/media/i2c
    cp $SRC_DIR/additional/imx519/imx519.c $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/drivers/media/i2c

    sed -i '27 i #include "porg-platforms/tegra210-porg-camera-arducam-dual-imx519.dtsi"' $SRC_DIR/workdir/Linux_for_Tegra/source/public/hardware/nvidia/platform/t210/porg/kernel-dts/tegra210-p3448-0002-p3449-0000-b00.dts
    sed -i '27 i #include "porg-platforms/tegra210-porg-camera-arducam-dual-imx519.dtsi"' $SRC_DIR/workdir/Linux_for_Tegra/source/public/hardware/nvidia/platform/t210/porg/kernel-dts/tegra210-p3448-0000-p3449-0000-b00.dts
    sed -i '27 i #include "porg-platforms/tegra210-porg-camera-arducam-imx519.dtsi"' $SRC_DIR/workdir/Linux_for_Tegra/source/public/hardware/nvidia/platform/t210/porg/kernel-dts/tegra210-p3448-0000-p3449-0000-a02.dts
    sed -i '27 i #include "../../porg/kernel-dts/porg-platforms/tegra210-porg-camera-arducam-imx519.dtsi"' $SRC_DIR/workdir/Linux_for_Tegra/source/public/hardware/nvidia/platform/t210/batuu/kernel-dts/tegra210-p3448-0003-p3542-0000.dts
    sed -i '24 i obj-$(CONFIG_VIDEO_IMX519) += imx519.o' $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/drivers/media/i2c/Makefile
    sed -i '1210 i CONFIG_VIDEO_IMX519=y' $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/arch/arm64/configs/tegra_defconfig
    
    echo "added IMX519 Drivers"
    
    
	make -C kernel/kernel-4.9/ ARCH=arm64 O=$TEGRA_KERNEL_OUT LOCALVERSION=-tegra CROSS_COMPILE=${TOOLCHAIN_PREFIX} tegra_defconfig
	rm $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/build/.config
	cp $SRC_DIR/configs/.config-jetson-4.9.253-openhd $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/build/.config
   	echo "using OpenHD-config"


	make -C kernel/kernel-4.9/ ARCH=arm64 O=$TEGRA_KERNEL_OUT LOCALVERSION=-tegra CROSS_COMPILE=${TOOLCHAIN_PREFIX} -j $J_CORES --output-sync=target zImage
	make -C kernel/kernel-4.9/ ARCH=arm64 O=$TEGRA_KERNEL_OUT LOCALVERSION=-tegra CROSS_COMPILE=${TOOLCHAIN_PREFIX} -j $J_CORES --output-sync=target modules
	make -C kernel/kernel-4.9/ ARCH=arm64 O=$TEGRA_KERNEL_OUT LOCALVERSION=-tegra CROSS_COMPILE=${TOOLCHAIN_PREFIX} -j $J_CORES --output-sync=target dtbs
	echo "Entering packaging Stage"
	
	echo "Copy kernel"
        cp $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/build/arch/arm64/boot/Image "${PACKAGE_DIR}/usr/local/share/openhd/kernel/kernel.img" || exit 1
	
 	echo "Copy kernel modules"
	make -C kernel/kernel-4.9/ ARCH=arm64 O=$TEGRA_KERNEL_OUT LOCALVERSION=-tegra INSTALL_MOD_PATH=${PACKAGE_DIR} modules_install

	echo "Copy DTBs"
        cp $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/build/arch/arm64/boot/dts/*.dtb "${PACKAGE_DIR}/usr/local/share/openhd/kernel/dtb/" || exit 1
	cp $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/arch/arm64/boot/dts/nvidia/* "${PACKAGE_DIR}/usr/local/share/openhd/kernel/overlays/" || exit 1

	# prevents the inclusion of firmware that can conflict with normal firmware packages, dpkg will complain. there
        # should be a kernel config to stop installing this into the package dir in the first place
        #rm -r "${PACKAGE_DIR}/lib/firmware/*"

	

	 # Build Realtek drivers
 	mkdir $SRC_DIR/workdir/mods/
	cd $SRC_DIR/workdir/mods/

	fetch_rtl8812au_driver    
   	build_rtl8812au_driver
	fetch_rtl8812bu_driver
	build_rtl8812bu_driver
	fetch_rtl8188eus_driver
    	build_rtl8188eus_driver
	
        depmod -b ${PACKAGE_DIR} ${KERNEL_VERSION}

	cd $SRC_DIR
    
    

	
}


prepare_build() {
    
    # on the pi our kernel is new enough that we don't need to add the exfat driver anymore
    if [[ "${PLATFORM}" == "pi" ]]; then
    check_time
    fetch_SBC_source
    mkdir $SRC_DIR/workdir/mods/
    cd $SRC_DIR/workdir/mods/
    fetch_rtl8812au_driver
    fetch_rtl8812bu_driver
    fetch_rtl8188eus_driver
    fetch_v4l2loopback_driver
    fi 

    if [[ "${PLATFORM}" == "jetson" ]]; then
      check_time
      fetch_SBC_source
      echo "Downloading additional modules and fixes"
      	mkdir $SRC_DIR/workdir/mods/
	cd $SRC_DIR/workdir/mods/
     echo "Download the exfat driver"
      git clone ${EXFAT_REPO}
        cp -a exfat-linux/. $JETSON_NANO_KERNEL_SOURCE/kernel/kernel-4.9/fs/exfat/
     echo "Download the v4l2loopback_driver"
	fetch_v4l2loopback_driver
        cp -a v4l2loopback/. $JETSON_NANO_KERNEL_SOURCE/kernel/kernel-4.9/drivers/media/v4l2loopback/
    fi 
}

if [[ "${PLATFORM}" == "pi" ]]; then
    # a simple hack, we want 2 kernels in one package so we source 2 different configs and build them all.
    # note that pi zero kernels are not being generated here because they are prepackaged with a specific 
    # kernel build. this is a temporary thing due to the unique issues with USB on the pi zero.
    source $SRC_DIR/kernels/${PLATFORM}-${DISTRO}-v7
    prepare_build
    build_pi_kernel
	echo "Copy kernel7"
	pushd ${LINUX_DIR}
	ls -a
	cp arch/arm/boot/zImage "${PACKAGE_DIR}/usr/local/share/openhd/kernel/kernel7.img" || exit 1


    source $SRC_DIR/kernels/${PLATFORM}-${DISTRO}-v7l
    prepare_build
    build_pi_kernel
	echo "Copy kernel7l"
	pushd ${LINUX_DIR}
	ls -a
        cp arch/arm/boot/zImage "${PACKAGE_DIR}/usr/local/share/openhd/kernel/kernel7l.img" || exit 1


    source $SRC_DIR/kernels/${PLATFORM}-${DISTRO}-v6
    prepare_build
    build_pi_kernel
	echo "Copy kernel6"
	pushd ${LINUX_DIR}
	ls -a
        cp arch/arm/boot/zImage "${PACKAGE_DIR}/usr/local/share/openhd/kernel/kernel.img" || exit 1


fi

if [[ "${PLATFORM}" == "jetson" ]]; then
    prepare_build
    build_jetson_kernel
    ls -a
    
fi
copy_overlay
package

post_processing

# Show cache stats
ccache -s
