#!/bin/bash
set -euo pipefail
SRC_DIR=$(cd "$(dirname "$0")/../.." && pwd)
validation_dir=$(mktemp -d)
trap 'rm -rf "$validation_dir"' EXIT
LINUX_DIR="$validation_dir/kernel"
mkdir -p "$LINUX_DIR/drivers/media/i2c"
printf 'obj-m += imx662.o\n' > "$LINUX_DIR/drivers/media/i2c/Makefile"
source "$SRC_DIR/scripts/imx662.sh"
install_imx662_driver
install_imx662_driver
cmp "$SRC_DIR/additional/imx662/imx662.c" "$LINUX_DIR/drivers/media/i2c/imx662.c"
test "$(grep -c 'CONFIG_VIDEO_IMX662.*imx662.o' "$LINUX_DIR/drivers/media/i2c/Makefile")" = 1
! grep -q '^obj-m.*imx662.o' "$LINUX_DIR/drivers/media/i2c/Makefile"
cpp -nostdinc -undef -x assembler-with-cpp -P \
    "$SRC_DIR/additional/imx662/imx662.dts" > "$validation_dir/imx662.dts"
dtc -q -@ -I dts -O dtb -o "$validation_dir/imx662.dtbo" "$validation_dir/imx662.dts"
test "$(fdtget -t x "$validation_dir/imx662.dtbo" /fragment@0/__overlay__ data-lanes)" = '1 2'
test "$(fdtget -t x "$validation_dir/imx662.dtbo" /fragment@1/__dormant__ data-lanes)" = '1 2 3 4'
test "$(fdtget -t u "$validation_dir/imx662.dtbo" /fragment@13/__overlay__ clock-frequency)" = 74250000
echo 'IMX662 repeatable installation and overlay compilation passed'
