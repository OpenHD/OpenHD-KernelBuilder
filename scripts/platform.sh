#!/bin/bash

function setup_ccache_prefix() {
        local prefix=$1
        local wrapper_dir=${CCACHE_WRAPPER_DIR:-${HOME}/.cache/ccache/bin}

        mkdir -p "${wrapper_dir}"

        pushd "${wrapper_dir}" >/dev/null
                for tool in gcc g++ cpp cc; do
                        ln -fs "$(which ccache)" "${prefix}${tool}"
                done
        popd >/dev/null

        if [[ ${PATH} != *${wrapper_dir}* ]]; then
                export PATH=${wrapper_dir}:${PATH}
        fi
}

function setup_platform_env() {
        if [[ "${PLATFORM}" == "pi" ]]; then
                export ARCH=arm
                PACKAGE_ARCH=armhf
                export CROSS_COMPILE=arm-linux-gnueabihf-
                KERNEL_REPO=https://github.com/OpenHD/linux.git

                setup_ccache_prefix "${CROSS_COMPILE}"
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
			git clone ${KERNEL_REPO} ${LINUX_DIR} || exit 1
			pushd ${LINUX_DIR}
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
