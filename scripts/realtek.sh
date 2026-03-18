#!/bin/bash

function resolve_latest_ref() {
    local requested="$1"
    if [[ -z "${requested}" || "${requested}" == "latest" ]]; then
        local head
        head=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
        if [[ -z "${head}" ]]; then
            head=$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p')
        fi
        if [[ -z "${head}" ]]; then
            head="master"
        fi
        echo "${head}"
        return
    fi
    echo "${requested}"
}

function checkout_latest_ref() {
    local requested="$1"
    local ref
    ref=$(resolve_latest_ref "${requested}")

    if git show-ref --verify --quiet "refs/tags/${ref}"; then
        git checkout -f "tags/${ref}" || exit 1
        return
    fi

    if git show-ref --verify --quiet "refs/remotes/origin/${ref}"; then
        git checkout -f -B "${ref}" "origin/${ref}" || exit 1
        git reset --hard "origin/${ref}" || exit 1
        return
    fi

    git checkout -f "${ref}" || exit 1
}

function fetch_rtl8812au_driver() {

    if [[ ! "$(ls -A rtl8812au)" ]]; then
        echo "Download the rtl8812au driver"
        git clone ${RTL_8812AU_REPO}
    fi

    pushd rtl8812au
        git fetch --all --tags --prune || exit 1
        checkout_latest_ref "${RTL_8812AU_BRANCH}"

        if [[ "${PLATFORM}" == "pi" ]]; then
            sed -i 's/CONFIG_PLATFORM_I386_PC = y/CONFIG_PLATFORM_I386_PC = n/' Makefile || exit 1
            sed -i 's/CONFIG_PLATFORM_ARM_RPI = n/CONFIG_PLATFORM_ARM_RPI = y/' Makefile || exit 1
        fi

        if [[ "${PLATFORM}" == "jetson" ]]; then
            sed -i 's/CONFIG_PLATFORM_I386_PC = y/CONFIG_PLATFORM_I386_PC = n/g' Makefile || exit 1
            sed -i 's/CONFIG_PLATFORM_ARM64_RPI = n/CONFIG_PLATFORM_ARM64_RPI = y/g' Makefile || exit 1
            echo "jetsonSBC"
        fi


        pushd core
            # Change the STBC value to make all antennas send with awus036ACH
            sed -i 's/u8 fixed_rate = MGN_1M, sgi = 0, bwidth = 0, ldpc = 0, stbc = 0;/u8 fixed_rate = MGN_1M, sgi = 0, bwidth = 0, ldpc = 0, stbc = 1;/' rtw_xmit.c || exit 1
        popd

    popd
}

function build_rtl8812au_driver() {
    pushd rtl8812au
        make clean

        if [[ "${PLATFORM}" == "pi" ]]; then
         make KSRC=${LINUX_DIR} -j $J_CORES M=$(pwd) modules || exit 1
         mkdir -p ${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/rtl8812au || exit 1
         install -p -m 644 88XXau_ohd.ko "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/rtl8812au/88XXau_wfb.ko" || exit 1

        fi

        if [[ "${PLATFORM}" == "jetson" ]]; then
                export KERNEL_VERSION="4.9.253OpenHD-2.1-tegra"
                export CROSS_COMPILE=$Tools/gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
                make KSRC=${LINUX_DIR}/build -j $J_CORES M=$(pwd) modules || exit 1
                mkdir -p ${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/rtl8812au || exit 1
                rm $SRC_DIR/workdir/Linux_for_Tegra/source/public/kernel/nvidia/drivers/net/wireless/realtek/rtl8812au/rtl8812au.ko
                install -p -m 644 88XXau_ohd.ko "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/rtl8812au/rtl8812au.ko" || exit 1
        fi


       popd
}

function prepare_rtl88x2_repo() {

    local repo_dir=$1
    local repo=$2
    local branch=$3
    local driver_folder=$4

    if [[ ! -d ${repo_dir} || -z "$(ls -A ${repo_dir} 2>/dev/null)" ]]; then
        echo "Download the ${repo_dir} driver"
        git clone ${repo} ${repo_dir} || exit 1
    fi

    pushd ${repo_dir}
        git fetch --all --tags --prune || exit 1
        checkout_latest_ref "${branch}"

        if [[ "${PLATFORM}" == "pi" ]]; then
            sed -i 's/CONFIG_PLATFORM_I386_PC = y/CONFIG_PLATFORM_I386_PC = n/' Makefile || exit 1
            sed -i 's/CONFIG_PLATFORM_ARM_RPI = n/CONFIG_PLATFORM_ARM_RPI = y/' Makefile || exit 1
        fi

        sed -i 's/CONFIG_WIFI_MONITOR = n/CONFIG_WIFI_MONITOR = y\nCONFIG_AP_MODE = y/' Makefile || exit 1

        sed -i 's/export TopDIR ?= $(shell pwd)/export TopDIR2 ?= $(shell pwd)/' Makefile || exit 1
        sed -i "/export TopDIR2 ?= \$(shell pwd)/a export TopDIR := \$(TopDIR2)/drivers/net/wireless/realtek/${driver_folder}/" Makefile || exit 1
    popd
}

function build_rtl88x2_driver() {
    local repo_dir=$1
    local module=$2
    local driver_folder=$3

    pushd ${repo_dir}
        make clean || exit 1

        if [[ "${PLATFORM}" == "jetson" ]]; then
                export KERNEL_VERSION="4.9.253OpenHD-2.1-tegra"
                export CROSS_COMPILE=$Tools/gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
                make KSRC=${LINUX_DIR}/build -j $J_CORES M=$(pwd) modules || exit 1
        else
                make KSRC=${LINUX_DIR} -j $J_CORES M=$(pwd) modules || exit 1
        fi

        mkdir -p ${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/${driver_folder} || exit 1
        install -p -m 644 ${module} "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/${driver_folder}/" || exit 1
    popd
}

function fetch_rtl8812bu_driver() {
    prepare_rtl88x2_repo rtl88x2bu ${RTL_8812BU_REPO} ${RTL_8812BU_BRANCH} rtl88x2bu
}

function build_rtl8812bu_driver() {
    build_rtl88x2_driver rtl88x2bu 88x2bu_ohd.ko rtl88x2bu
    rm -Rf ${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/rtl8xxxu
    echo "removed original realtek driver out of the rpi source"
}

function fetch_rtl8812cu_driver() {
    prepare_rtl88x2_repo rtl88x2cu ${RTL_8812CU_REPO} ${RTL_8812CU_BRANCH} rtl88x2cu
}

function build_rtl8812cu_driver() {
    build_rtl88x2_driver rtl88x2cu 88x2cu_ohd.ko rtl88x2cu
}

function fetch_rtl8812eu_driver() {
    prepare_rtl88x2_repo rtl88x2eu ${RTL_8812EU_REPO} ${RTL_8812EU_BRANCH} rtl88x2eu
}

function build_rtl8812eu_driver() {
    build_rtl88x2_driver rtl88x2eu 88x2eu_ohd.ko rtl88x2eu
}
# ========================================================== #

function fetch_rtl8188eus_driver() {

    if [[ ! "$(ls -A rtl8188eus)" ]]; then
        echo "Download the rtl8188eus driver"
        git clone ${RTL_8188EUS_REPO} || exit 1
    fi

    pushd rtl8188eus
        git fetch --all --tags --prune || exit 1
        checkout_latest_ref "${RTL_8188EUS_BRANCH}"

        if [[ "${PLATFORM}" == "pi" ]]; then
            sed -i 's/CONFIG_PLATFORM_I386_PC = y/CONFIG_PLATFORM_I386_PC = n/' Makefile || exit 1
            sed -i 's/CONFIG_PLATFORM_ARM_RPI = n/CONFIG_PLATFORM_ARM_RPI = y/' Makefile || exit 1
        fi
    popd
}

function build_rtl8188eus_driver() {
    pushd rtl8188eus
        make clean || exit 1
        if [[ "${PLATFORM}" == "jetson" ]]; then
                export KERNEL_VERSION="4.9.253OpenHD-2.1-tegra"
                export CROSS_COMPILE=$Tools/gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
                make KSRC=${LINUX_DIR}/build -j $J_CORES M=$(pwd) modules || exit 1
                else
                make KSRC=${LINUX_DIR} -j $J_CORES M=$(pwd) modules || exit 1
                fi
        mkdir -p ${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/rtl8188eus || exit 1
        install -p -m 644 8188eu.ko "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/rtl8188eus/" || exit 1
    popd
}
