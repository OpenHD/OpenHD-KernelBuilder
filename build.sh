#!/bin/bash
PLATFORM=$1
DISTRO=$2
ONLINE=$3

if  [[ "${PLATFORM}" != "pi" ]] && [[ "${PLATFORM}" != "jetson" ]];  then
    echo "Usage: ./build.sh pi bullseye"
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
RTL_8812AU_REPO=https://github.com/OpenHD/rtl8812au
RTL_8812AU_BRANCH=v5.2.20

RTL_8812BU_REPO=https://github.com/OpenHD/rtl88x2bu
RTL_8812BU_BRANCH=master

# RTL_8812CU_REPO=https://github.com/OpenHD/rtl88x2cu
# RTL_8812CU_BRANCH=master

RTL_8812EU_REPO=https://github.com/OpenHD/rtl88x2eu
RTL_8812EU_BRANCH=v5.15.0.1

RTL_8188EUS_REPO=https://github.com/gglluukk/rtl8188eus
RTL_8188EUS_BRANCH=v5.3.9
# Testing Driver not stable, yet


V4L2LOOPBACK_REPO=https://github.com/OpenHD/v4l2loopback.git
V4L2LOOPBACK_BRANCH=openhd
# needed for thermal cameras

EXFAT_REPO=https://github.com/OpenHD/exfat-linux.git
EXFAT_BRANCH=openhd2
#needed for writing to exfat-usb-sticks, not needed on most (all ?) platforms [but doesn't hurt]

# VEYEV4L2_REPO=https://github.com/OpenHD/veyev4l2.git
# VEYEV4L2_BRANCH=2.1-milestones
# No need for now, veye-raspberrypi (broadcom is already build)



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
        # needs to be customised again in the future
        # cp "${CONFIGS}/.config-${KERNEL_BRANCH}-${ISA}" ./.config || exit 1
        make clean || exit 1

        #add v4l2-loopback
        echo "CONFIG_VIDEO_V4L2LOOPBACK=y" >> ${LINUX_DIR}/arch/arm/configs/bcm2711_defconfig
        echo "CONFIG_VIDEO_V4L2LOOPBACK=y" >> ${LINUX_DIR}/arch/arm/configs/bcm2709_defconfig
        echo "CONFIG_VIDEO_V4L2LOOPBACK=y" >> ${LINUX_DIR}/arch/arm/configs/bcmrpi_defconfig


        # yes "" | make oldconfig || exit 1
            if [[ "${ISA}" == "v7l" ]]; then
                make clean || exit 1
                make bcm2711_defconfig || exit 1
            elif [[ "${ISA}" == "v7" ]]; then
                make clean || exit 1
                make bcm2709_defconfig || exit 1
            # currently only doing default config, modified config can follow later, but standart eases the possibility to upgrade to a newer kernel 
            fi
        KERNEL=${KERNEL} KBUILD_BUILD_TIMESTAMP='' make -j $J_CORES zImage modules dtbs || exit 1

        echo "Copy kernel modules"
        make -j $J_CORES INSTALL_MOD_PATH="${PACKAGE_DIR}" modules_install || exit 1
	
	    echo "Copy DTBs"
        cp -f arch/arm/boot/dts/*.dtb "${PACKAGE_DIR}/usr/local/share/openhd/kernel/dtb/" || exit 1
        cp -f arch/arm/boot/dts/overlays/*.dtb* "${PACKAGE_DIR}/usr/local/share/openhd/kernel/overlays/" || exit 1
        cp -f arch/arm/boot/dts/overlays/README "${PACKAGE_DIR}/usr/local/share/openhd/kernel/overlays/" || exit 1
        
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
    # build_rtl8812cu_driver
    build_rtl8812eu_driver
    #build_rtl8188eus_driver
    #build_reterminal_driver


    depmod -b ${PACKAGE_DIR} ${KERNEL_VERSION}

}

build_jetson_kernel() {

    
	echo "Building jetson kernel"
	
	TEGRA_KERNEL_OUT=$LINUX_DIR/build
	KERNEL_MODULES_OUT=$LINUX_DIR/modules	
    export NVIDIA_PATH=$SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/nvidia/ 
    export NANO_DTS_PATH=$SRC_DIR/workdir/Linux_for_Tegra/source/public/hardware/nvidia/platform/t210/ 	
	export CROSS_COMPILE=$Tools/gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
	
    echo "Prepare additional drivers"

    #downloading and including veye-driver-source
    #not working,yet

    cd $SRC_DIR/workdir/Linux_for_Tegra/source/public/
    #needs to be adapted to our own fork, to enable more then one additional kernel patch
    git clone https://github.com/OpenHD/nvidia_jetson_veye_bsp || exit 1
    export RELEASE_PACK_DIR=$SRC_DIR/workdir/Linux_for_Tegra/source/public/nvidia_jetson_veye_bsp 

    echo "Patching Veye Drivers into kernel source"
    echo "remove buggy kernel configs from veye"
    rm $RELEASE_PACK_DIR/drivers_source/cam_drv_src/Makefile*
    rm $RELEASE_PACK_DIR/drivers_source/cam_drv_src/Kconfig*
    echo "copying drivers"
    cp $RELEASE_PACK_DIR/drivers_source/cam_drv_src/* $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/drivers/media/i2c/ || exit 1
    cp $RELEASE_PACK_DIR/drivers_source/kernel_veyecam_config_r32.6.1  $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/arch/arm64/configs/tegra_veyecam_defconfig  || exit 1
    echo "Injecting our own driver Makefile and Kconfig"
    cp $RELEASE_PACK_DIR/openhd/Kconfig $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/drivers/media/i2c/ || exit 1
    cp $RELEASE_PACK_DIR/openhd/Makefile $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/drivers/media/i2c/ || exit 1

    #echo "copying arducam drivers"
    #cp $SRC_DIR/additional/imx519/*.dtsi $SRC_DIR/workdir/Linux_for_Tegra/source/public/hardware/nvidia/platform/t210/porg/kernel-dts/porg-platforms
    #cp $SRC_DIR/additional/imx519/*.dts $SRC_DIR/workdir/Linux_for_Tegra/source/public/hardware/nvidia/platform/t210/porg/kernel-dts
    #cp $SRC_DIR/additional/imx519/imx519_mode_tbls.h $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/drivers/media/i2c
    #cp $SRC_DIR/additional/imx519/imx519.c $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/nvidia/kernel-4.9/media/i2c

    #sed -i '27 i #include "porg-platforms/tegra210-porg-camera-arducam-dual-imx519.dtsi"' $SRC_DIR/workdir/Linux_for_Tegra/source/public/hardware/nvidia/platform/t210/porg/kernel-dts/tegra210-p3448-0002-p3449-0000-b00.dts
    #sed -i '27 i #include "porg-platforms/tegra210-porg-camera-arducam-dual-imx519.dtsi"' $SRC_DIR/workdir/Linux_for_Tegra/source/public/hardware/nvidia/platform/t210/porg/kernel-dts/tegra210-p3448-0000-p3449-0000-b00.dts
	#sed -i '27 i #include "porg-platforms/tegra210-porg-camera-arducam-imx519.dtsi"' $SRC_DIR/workdir/Linux_for_Tegra/source/public/hardware/nvidia/platform/t210/porg/kernel-dts/tegra210-p3448-0000-p3449-0000-a02.dts
   	#sed -i '27 i #include "../../porg/kernel-dts/porg-platforms/tegra210-porg-camera-arducam-imx519.dtsi"' $SRC_DIR/workdir/Linux_for_Tegra/source/public/hardware/nvidia/platform/t210/batuu/kernel-dts/tegra210-p3448-0003-p3542-0000.dts
    # Makefile is missing
    # Kconfig is missing from Arducam
    #sed -i '1210 i CONFIG_VIDEO_IMX519=y' $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/arch/arm64/configs/tegra_veyecam_defconfig

   	cd $JETSON_NANO_KERNEL_SOURCE
    echo "added additional Drivers"
    
    
	make -C kernel/kernel-4.9/ ARCH=arm64 O=$TEGRA_KERNEL_OUT LOCALVERSION=-tegra CROSS_COMPILE=${TOOLCHAIN_PREFIX} tegra_veyecam_defconfig || exit 1
	#rm $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/build/.config
	#cp $SRC_DIR/configs/.config-jetson-4.9.253-openhd $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/build/.config
   	echo "using OpenHD-config"


	make -C kernel/kernel-4.9/ ARCH=arm64 O=$TEGRA_KERNEL_OUT LOCALVERSION=-tegra CROSS_COMPILE=${TOOLCHAIN_PREFIX} -j $J_CORES Image || exit 1
    echo "zimage done"
	make -C kernel/kernel-4.9/ ARCH=arm64 O=$TEGRA_KERNEL_OUT LOCALVERSION=-tegra CROSS_COMPILE=${TOOLCHAIN_PREFIX} -j $J_CORES --output-sync=target modules || exit 1
    echo "modules done"
	
	echo "Copy kernel"
    cp $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/build/arch/arm64/boot/Image "${PACKAGE_DIR}/usr/local/share/openhd/kernel/kernel.img" || exit 1
	
 	echo "Copy kernel modules"
	make -C kernel/kernel-4.9/ ARCH=arm64 O=$TEGRA_KERNEL_OUT LOCALVERSION=-tegra INSTALL_MOD_PATH=${PACKAGE_DIR} modules_install || exit 1

    echo "Build DTB's Veye"
    cp $RELEASE_PACK_DIR/dtbs/Nano/JetPack_4.6_Linux_JETSON_NANO_TARGETS/dts\ dtb/common/t210/* -r $NANO_DTS_PATH/ || exit 1
    cp $RELEASE_PACK_DIR/dtbs/Nano/JetPack_4.6_Linux_JETSON_NANO_TARGETS/dts\ dtb/VEYE-MIPI-327/tegra210-porg-plugin-manager.dtsi -r $NANO_DTS_PATH/porg/kernel-dts/porg-plugin-manager  || exit 1
    export COMMON_DTS_PATH=$TEGRA_KERNEL_OUT/arch/arm64/boot/dts 
    make -C kernel/kernel-4.9/ ARCH=arm64 O=$TEGRA_KERNEL_OUT LOCALVERSION=-tegra CROSS_COMPILE=${TOOLCHAIN_PREFIX} -j $J_CORES --output-sync=target dtbs || exit 1
    #Commenting those 3 lines since SRC File = DST File
    #cp $COMMON_DTS_PATH/tegra210-p3448-0000-p3449-0000-a02.dtb $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/build/arch/arm64/boot/dts/ || exit 1
    #cp $COMMON_DTS_PATH/tegra210-p3448-0000-p3449-0000-b00.dtb $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/build/arch/arm64/boot/dts/ || exit 1
    #cp $COMMON_DTS_PATH/tegra210-p3448-0003-p3542-0000.dtb  $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/build/arch/arm64/boot/dts/ || exit 1
	echo "Copy DTBs"
    mkdir -p ${PACKAGE_DIR}/usr/local/share/openhd/kernel/veyecam/ || exit 1
    cp $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/build/arch/arm64/boot/dts/*.dtb "${PACKAGE_DIR}/usr/local/share/openhd/kernel/veyecam/" || exit 1
	cp $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/kernel-4.9/arch/arm64/boot/dts/nvidia/* "${PACKAGE_DIR}/usr/local/share/openhd/kernel/overlays/" || exit 1
    cd $JETSON_NANO_KERNEL_SOURCE
	echo "Entering packaging Stage"
    rm -r "${PACKAGE_DIR}/lib/firmware/*"

	

	 # Build Realtek drivers
 	mkdir -p $SRC_DIR/workdir/mods/ || exit 1
	cd $SRC_DIR/workdir/mods/

	fetch_rtl8812au_driver    
   	build_rtl8812au_driver
	fetch_rtl8812bu_driver    
 	build_rtl8812bu_driver
    # fetch_rtl8812cu_driver    
    # build_rtl8812cu_driver
    fetch_rtl8812eu_driver    
    build_rtl8812eu_driver

        depmod -b ${PACKAGE_DIR} ${KERNEL_VERSION}

	cd $SRC_DIR
	
}


prepare_build() {
    
    # on the pi our kernel is new enough that we don't need to add the exfat driver anymore
    if [[ "${PLATFORM}" == "pi" ]]; then
    check_time
    mkdir -p $SRC_DIR/workdir/mods/ || exit 1
    cd $SRC_DIR/workdir/mods/
    fetch_rtl8812au_driver
    fetch_rtl8812bu_driver
    # fetch_rtl8812cu_driver
    fetch_rtl8812eu_driver
    #fetch_rtl8188eus_driver
    fetch_v4l2loopback_driver
    #fetch_reterminal_driver
    fi 

    if [[ "${PLATFORM}" == "jetson" ]]; then
      echo "depricated"
      check_time
      fetch_SBC_source
      echo "Downloading additional modules and fixes"
      	mkdir -p $SRC_DIR/workdir/mods/ || exit 1
	cd $SRC_DIR/workdir/mods/
     echo "Download the exfat driver"
      git clone ${EXFAT_REPO} || exit 1
        cp -af exfat-linux/. $JETSON_NANO_KERNEL_SOURCE/kernel/kernel-4.9/fs/exfat/ || exit 1
     echo "Download the v4l2loopback_driver"
	fetch_v4l2loopback_driver
        cp -af v4l2loopback/. $JETSON_NANO_KERNEL_SOURCE/kernel/kernel-4.9/drivers/media/v4l2loopback/ || exit 1
    fi 
}

if [[ "${PLATFORM}" == "pi" ]]; then
    # a simple hack, we want 2 kernels in one package so we source 2 different configs and build them all.
    # note that pi zero kernels are not being generated here because they are prepackaged with a specific 
    # kernel build. this is a temporary thing due to the unique issues with USB on the pi zero.
    fetch_SBC_source
    ls -a
set -x 
    echo $(pwd)
         ##veye v4l2
         git clone https://github.com/veyeimaging/raspberrypi_v4l2 workdir/mods/raspberrypi_v4l2 || exit 1
         export RELEASE_PACK_DIR=workdir/mods/raspberrypi_v4l2
         ls -a
         ls -a workdir/mods/raspberrypi_v4l2
         #copy drivers, not copying the makefile (the makefile will make the kernel not build)
         cp -r $RELEASE_PACK_DIR/driver_source/cam_drv_src/rpi-6.1.y/*.c workdir/linux-pi/drivers/media/i2c/ || exit 1
         cp -r $RELEASE_PACK_DIR/driver_source/cam_drv_src/rpi-6.1.y/*.h workdir/linux-pi/drivers/media/i2c/ || exit 1
         echo 'obj-m += veye_mvcam.o csimx307.o veyecam2m.o cssc132.o' >> workdir/linux-pi/drivers/media/i2c/Makefile
         cp -r additional/Kconfig workdir/linux-pi/drivers/media/i2c/ || exit 1
         #copying the dts-files
         cp -r $RELEASE_PACK_DIR/driver_source/dts/rpi-6.1.y/* workdir/linux-pi/arch/arm/boot/dts/overlays/ || exit 1
         rm -f workdir/linux-pi/arch/arm/boot/dts/overlays/csimx307-dual-cm4-overlay*
         sed -i '280 i csimx307-overlay.dtbo \\' workdir/linux-pi/arch/arm/boot/dts/overlays/Makefile || exit 1
         sed -i '281 i cssc132-overlay.dtbo \\' workdir/linux-pi/arch/arm/boot/dts/overlays/Makefile || exit 1
         sed -i '282 i veyecam2m-overlay.dtbo \\' workdir/linux-pi/arch/arm/boot/dts/overlays/Makefile || exit 1
         sed -i '283 i veye_mvcam-overlay.dtbo \\' workdir/linux-pi/arch/arm/boot/dts/overlays/Makefile || exit 1
         sed -i '280,283s/^/        /' workdir/linux-pi/arch/arm/boot/dts/overlays/Makefile || exit 1
        #git clone https://github.com/Seeed-Studio/seeed-linux-dtoverlays workdir/mods/seeed-linux-dtoverlays
        #export RETERMINAL_DIR=workdir/mods/seeed-linux-dtoverlays
        #cp -r $RETERMINAL_DIR/overlays/rpi/reTerminal* workdir/linux-pi/arch/arm/boot/dts/overlays/
        #sed -i '285 i reTerminal-bridge-overlay.dtbo \\' workdir/linux-pi/arch/arm/boot/dts/overlays/Makefile
        #sed -i '286 i reTerminal-overlay.dtbo \\' workdir/linux-pi/arch/arm/boot/dts/overlays/Makefile

        #echo "Set Overlays"

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
