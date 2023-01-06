#!/bin/bash

function fetch_reterminal_driver() {

    if [[ ! "$(ls -A seeed-linux-dtoverlays)" ]]; then    
        echo "Download the reTerminal driver"
        git clone https://github.com/Seeed-Studio/seeed-linux-dtoverlays
    fi
}

function build_reterminal_driver() {

    if [[ "${PLATFORM}" == "pi" ]]; then
        pushd seeed-linux-dtoverlays/modules
        for DRIVER in mipi_dsi ltr30x lis3lv02d bq24179_charger; do
            pushd $DRIVER
            make clean
            make -C ${LINUX_DIR} KSRC=${LINUX_DIR} -j $J_CORES M=$(pwd) modules || exit 1
	        mkdir -p ${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/reterminal
            install -p -m 644 *.ko "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/reterminal/" || exit 1
            popd
        done
    
       popd
    fi
    
#overlay reTerminal reTerminal-bridge
}
