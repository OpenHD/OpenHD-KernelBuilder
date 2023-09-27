#!/usr/bin/env bash

mkdir -p /boot/overlays

# crude hack to avoid making people put fonts somewhere else
cp -af /usr/local/share/openhd/kernel/overlays/* /boot/overlays/
cp -af /usr/local/share/openhd/kernel/kernel7.img /boot/
cp -af /usr/local/share/openhd/kernel/kernel7l.img /boot/ > /dev/null 2>&1 || true
cp -af /usr/local/share/openhd/kernel/dtb/* /boot/

depmod -a

grep "i2c-dev" /etc/modules
if [[ "$?" -ne 0 ]]; then
    echo "i2c-dev" >> /etc/modules
fi
