export PACKAGE_DIR=/opt/openhd-linux-x86/package
export KERNEL_VERSION=$(uname -r)

git clone --recursive https://github.com/svpcom/rtl8812au.git
git clone --recursive https://github.com/cilynx/rtl88x2bu.git
git clone --recursive https://github.com/aircrack-ng/rtl8188eus.git
ln -sf /usr/lib/modules/$(uname -r)/vmlinux.xz /boot/

cd rtl8812au
git checkout v5.6.4.2
make
mkdir -p ${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/rtl8812au
#install -p -m 644 88XXau_wfb.ko "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/rtl8812au/"
make install
cd ..
cd rtl88x2bu
make
#mkdir -p ${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/rtl88x2bu
#install -p -m 644 88x2bu.ko "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/rtl88x2bu/"
make install
cd ..
cd rtl8188eus
make
#mkdir -p ${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/rtl8188eus
#install -p -m 644 8188eu.ko "${PACKAGE_DIR}/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/wireless/realtek/rtl8188eus/"
make install
#echo "packaging stage"
#cd ..
#fpm -a x86_64 -s dir -t deb -n openhd-linux-x86 -v 2.2.2-evo-$(date '+%m%d%H%M') -C package -p openhd-linux-x86_VERSION_ARCH.deb
