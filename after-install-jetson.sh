#!/usr/bin/env bash

mkdir -p /boot/overlays

cp -a /usr/local/share/openhd/kernel/* /boot/
mv /boot/kernel.img /boot/Image

if test -f "/usr/local/share/openhd/Jetson-2GB"; then 
   echo "you have a jetson 2GB model"
   cp -a /usr/local/share/openhd/kernel/kernel_tegra210-p3448-0003-p3542-0000.dtb /boot/dtb/
fi

if test -f "/usr/local/share/openhd/Jetson-4GB"; then 
   echo "you have a jetson 4GB model"
   cp -a /usr/local/share/openhd/kernel/kernel_tegra210-p3448-0000-p3449-0000-b00.dtb /boot/dtb/
fi

depmod -a

mount -oremount,ro /boot || true

grep "i2c-dev" /etc/modules
if [[ "$?" -ne 0 ]]; then
    echo "i2c-dev" >> /etc/modules
fi
