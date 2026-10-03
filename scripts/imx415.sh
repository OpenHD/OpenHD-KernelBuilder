#!/bin/bash

# Called after the builder installs its media Kconfig and camera overlays.
install_imx415_backport() {
    local sensor_dir="${SRC_DIR}/additional/imx415"
    local media_dir="${LINUX_DIR}/drivers/media/i2c"
    local overlay_dir="${LINUX_DIR}/arch/arm/boot/dts/overlays"
    cp "${sensor_dir}/imx415.c" "${media_dir}/imx415.c" || return 1
    cp "${sensor_dir}/imx415-overlay.dts" "${sensor_dir}/imx415.dtsi" "${overlay_dir}/" || return 1
    if ! grep -q '^config VIDEO_IMX415$' "${media_dir}/Kconfig"; then
        cat "${sensor_dir}/Kconfig" >> "${media_dir}/Kconfig" || return 1
    fi
    if ! grep -q 'CONFIG_VIDEO_IMX415.*imx415.o' "${media_dir}/Makefile"; then
        echo 'obj-$(CONFIG_VIDEO_IMX415) += imx415.o' >> "${media_dir}/Makefile" || return 1
    fi
    if ! grep -q 'imx415.dtbo' "${overlay_dir}/Makefile"; then
        echo 'dtbo-$(CONFIG_ARCH_BCM2835) += imx415.dtbo' >> "${overlay_dir}/Makefile" || return 1
    fi
}
