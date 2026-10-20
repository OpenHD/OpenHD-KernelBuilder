#!/bin/bash

# The media Kconfig installed by build.sh already contains VIDEO_IMX662.
install_imx662_driver() {
    local media_dir="${LINUX_DIR}/drivers/media/i2c"
    cp "${SRC_DIR}/additional/imx662/imx662.c" "${media_dir}/imx662.c" || return 1
    # Older builder runs forced obj-m as well as the CONFIG entry.
    sed -i '/^obj-m[[:space:]]*+=[[:space:]]*imx662\.o[[:space:]]*$/d' "${media_dir}/Makefile" || return 1
    if ! grep -q 'CONFIG_VIDEO_IMX662.*imx662.o' "${media_dir}/Makefile"; then
        echo 'obj-$(CONFIG_VIDEO_IMX662) += imx662.o' >> "${media_dir}/Makefile" || return 1
    fi
}
