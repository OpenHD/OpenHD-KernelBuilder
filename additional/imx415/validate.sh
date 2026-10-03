#!/bin/bash
set -euo pipefail
source_dir=$(cd "$(dirname "$0")" && pwd)
headers=${1:?Usage: validate.sh KERNEL_HEADERS OUTPUT_DIR}
validation_dir=${2:?Usage: validate.sh KERNEL_HEADERS OUTPUT_DIR}
mkdir -p "$validation_dir"
validation_dir=$(cd "$validation_dir" && pwd)
cp "$source_dir/imx415.c" "$source_dir/Makefile" "$validation_dir/"
make -C "$headers" M="$validation_dir" ARCH=arm \
    CROSS_COMPILE="${CROSS_COMPILE:-arm-linux-gnueabihf-}" modules
