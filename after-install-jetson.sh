#!/usr/bin/env bash

mkdir -p /boot/overlays

cp -a /usr/local/share/openhd/kernel/* /boot/
mv /boot/kernel.img /boot/Image

depmod -a

mount -oremount,ro /boot || true

grep "i2c-dev" /etc/modules
if [[ "$?" -ne 0 ]]; then
    echo "i2c-dev" >> /etc/modules
fi
