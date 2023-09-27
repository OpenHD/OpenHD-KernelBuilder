#!/bin/bash

function fetch_reterminal_driver() {

    if [[ "${PLATFORM}" == "pi" ]]; then    
        echo "Download the reTerminal driver"
        git clone https://github.com/Seeed-Studio/seeed-linux-dtoverlays || exit 1
        mkdir -p ${PACKAGE_DIR}/usr/local/share/reterminal || exit 1
        cp -rf seeed-linux-dtoverlays/modules/seeed-voicecard/wm8960_asound.state ${PACKAGE_DIR}/usr/local/share/reterminal/wm8960_asound.state || exit 1
        cp -rf seeed-linux-dtoverlays/modules/seeed-voicecard/asound_2mic.conf ${PACKAGE_DIR}/usr/local/share/reterminal/asound_2mic.conf || exit 1
        cp -rf $(pwd)/../../reTerminal_overlays.sh ${PACKAGE_DIR}/usr/local/bin/reTerminal_overlays.sh || exit 1
    fi
}

function build_reterminal_driver() {

    if [[ "${PLATFORM}" == "pi" ]]; then
        pushd seeed-linux-dtoverlays/modules
        for DRIVER in mipi_dsi ltr30x lis3lv02d bq24179_charger; do
            pushd $DRIVER
            make clean || exit 1
            make -C ${LINUX_DIR} KSRC=${LINUX_DIR} -j $J_CORES M=$(pwd) modules || exit 1
	        mkdir -p ${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/reterminal || exit 1
            install -p -m 644 *.ko "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/reterminal/" || exit 1
            popd
        done
    
       popd
    fi
}
