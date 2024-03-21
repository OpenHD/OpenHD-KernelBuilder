#!/bin/bash

function setup_platform_env() {
	if [[ "${PLATFORM}" == "pi" ]]; then
		# CCACHE workaround
		CCACHE_PATH=${PI_TOOLS_COMPILER_PATH}/../bin-ccache

		if [[ ! "$(ls -A ${CCACHE_PATH})" ]]; then
			mkdir -p ${CCACHE_PATH}
			pushd ${CCACHE_PATH}
			ln -fs $(which ccache) arm-linux-gnueabihf-gcc
			ln -fs $(which ccache) arm-linux-gnueabihf-g++
			ln -fs $(which ccache) arm-linux-gnueabihf-cpp
			ln -fs $(which ccache) arm-linux-gnueabihf-c++
			popd
		fi
		if [[ ${PATH} != *${CCACHE_PATH}* ]]; then
			export PATH=${CCACHE_PATH}:${PATH}
		fi

		export ARCH=arm
		PACKAGE_ARCH=armhf
		export CROSS_COMPILE=arm-linux-gnueabihf-
		KERNEL_REPO=https://github.com/OpenHD/linux-rpi
		KERNEL_BRANCH=openhd-rpi-6.1-stable
	fi

	if [[ "${PLATFORM}" == "jetson" ]]; then
		
		mkdir workdir
		mkdir workdir/tools

		WorkDir=$(pwd)/workdir
		Tools=$(pwd)/workdir/tools

		if test -f "$WorkDir/jetsonkernel"; then
			echo "Kernel is already downloaded."
		else
			echo "Download the kernel tools"
			cd $Tools
			rm -Rf *
			wget -q --show-progress --progress=bar:force:noscroll http://releases.linaro.org/components/toolchain/binaries/7.3-2018.05/aarch64-linux-gnu/gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu.tar.xz || exit 1
			tar xf gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu.tar.xz || exit 1
			export CROSS_COMPILE=$Tools/gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
			export ARCH=arm64
			PACKAGE_ARCH=arm64
			export CROSS_COMPILE=arm-linux-aarch64-
			cd $WorkDir
    		echo "Download the original kernel source"
			wget -q --show-progress --progress=bar:force:noscroll https://developer.nvidia.com/embedded/l4t/r32_release_v6.1/sources/t210/public_sources.tbz2 || exit 1
			tar -xf public_sources.tbz2 || exit 1
			cd Linux_for_Tegra/source/public
			JETSON_NANO_KERNEL_SOURCE=$(pwd)
			tar -xf kernel_src.tbz2 || exit 1
			cd $JETSON_NANO_KERNEL_SOURCE
			TOOLCHAIN_PREFIX=$Tools/gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
			touch $WorkDir/jetsonkernel
			cd $SRC_DIR
			echo "replacing original kernel-config with OpenHD-config"
			echo "removing Nvidia Wifi-Drivers"
		fi
	fi
}

function fetch_SBC_source() {
	if [[ "${PLATFORM}" == "pi" ]]; then

		if [[ ! "$(ls -A ${LINUX_DIR})" ]]; then
			mkdir -p $SRC_DIR/workdir
			echo "Download the kernel source"
			echo "------------------------------"
			# Use --depth 1 to save some space on unneccessary huge git log
			git clone ${KERNEL_REPO} ${LINUX_DIR} -b ${KERNEL_BRANCH} --depth=1 || exit 1
			echo "_________________GIT_____________________________"
			git status
			echo "__________________GIT_END____________________"
			popd
		fi

	fi

	if [[ "${PLATFORM}" == "jetson" ]]; then
		if test -f "$WorkDir/jetsonkernelpatch"; then
    		echo "Kernelpatch is already downloaded."
		JETSON_NANO_KERNEL_SOURCE=$WorkDir/Linux_for_Tegra/source/public
		else
		rm -Rf $WorkDir/Linux_for_Tegra/source/public/kernel/kernel-4.9
		echo "clone kernel source jetson"
		git clone --branch jetson-nano-4.9.253-openhd https://github.com/OpenHD/linux.git $WorkDir/Linux_for_Tegra/source/public/kernel/kernel-4.9 || exit 1
		touch $WorkDir/jetsonkernelpatch
		fi
	fi

}
