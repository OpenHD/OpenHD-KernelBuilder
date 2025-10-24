#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORKDIR="${ROOT_DIR}/workdir/imx662-test"
KERNEL_DIR="${WORKDIR}/linux-pi"
MODULE_BUILD_DIR="${WORKDIR}/imx662-module"
ARTIFACT_DIR="${ROOT_DIR}/artifacts/imx662"
KERNEL_REPO="https://github.com/OpenHD/linux.git"
KERNEL_BRANCH="rpi-6.1-stable"
KERNEL_COMMIT="20cb6d7b533b5e6d7df8a2cb7a83bd4555834bde"
CROSS_COMPILE_TOOLCHAIN="${CROSS_COMPILE:-arm-linux-gnueabihf-}"

rm -rf "${WORKDIR}"
rm -rf "${ARTIFACT_DIR}"
mkdir -p "${WORKDIR}"
mkdir -p "${ARTIFACT_DIR}"

# Fetch the kernel source that matches the main build configuration.
echo "Cloning kernel source..."
git clone --depth 1 --branch "${KERNEL_BRANCH}" "${KERNEL_REPO}" "${KERNEL_DIR}"
pushd "${KERNEL_DIR}" >/dev/null
# Ensure the expected commit is available even when cloning with depth 1.
git fetch --depth 1 origin "${KERNEL_COMMIT}"
git checkout "${KERNEL_COMMIT}"

export ARCH=arm
export CROSS_COMPILE="${CROSS_COMPILE_TOOLCHAIN}"

# Prepare the kernel for external module compilation.
make bcm2711_defconfig
make modules_prepare
popd >/dev/null

mkdir -p "${MODULE_BUILD_DIR}"
cp "${ROOT_DIR}/additional/imx662/imx662.c" "${MODULE_BUILD_DIR}/"
cat <<'MAKEFILE' > "${MODULE_BUILD_DIR}/Makefile"
obj-m += imx662.o
MAKEFILE

# Build the IMX662 kernel module.
make -C "${KERNEL_DIR}" ARCH=arm CROSS_COMPILE="${CROSS_COMPILE_TOOLCHAIN}" M="${MODULE_BUILD_DIR}" modules

# Build the device tree overlay using the kernel build system.
cp "${ROOT_DIR}/additional/imx662/imx662-overlay.dts" "${KERNEL_DIR}/arch/arm/boot/dts/overlays/"
if ! grep -q "imx662-overlay.dtbo" "${KERNEL_DIR}/arch/arm/boot/dts/overlays/Makefile"; then
  KERNEL_MAKEFILE_PATH="${KERNEL_DIR}/arch/arm/boot/dts/overlays/Makefile" \
  python3 - <<'PY'
from pathlib import Path
import os
makefile = Path(os.environ["KERNEL_MAKEFILE_PATH"])
content = makefile.read_text()
needle = "dtbo-$(CONFIG_ARCH_BCM2835) += imx662-overlay.dtbo\n"
if needle not in content:
    replacement = "dtbo-$(CONFIG_ARCH_BCM2835) += imx662-overlay.dtbo\n\ntargets += dtbs dtbs_install"
    content = content.replace("targets += dtbs dtbs_install", replacement, 1)
    makefile.write_text(content)
PY
fi
make -C "${KERNEL_DIR}" ARCH=arm CROSS_COMPILE="${CROSS_COMPILE_TOOLCHAIN}" dtbs

cp "${MODULE_BUILD_DIR}/imx662.ko" "${ARTIFACT_DIR}/"
cp "${ROOT_DIR}/additional/imx662/imx662-overlay.dts" "${ARTIFACT_DIR}/"
cp "${KERNEL_DIR}/arch/arm/boot/dts/overlays/imx662-overlay.dtbo" "${ARTIFACT_DIR}/"

# Provide a quick summary for the CI logs.
echo "Generated artifacts:"
ls -l "${ARTIFACT_DIR}"
