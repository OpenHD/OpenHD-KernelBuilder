#!/usr/bin/env bash

mkdir -p /boot/overlays

cp -af /usr/local/share/openhd/kernel/* /boot/
mv /boot/kernel.img /boot/Image

   sudo rm -f /boot/dtb/*
   sudo rm -f /boot/*.dtb
   mkdir -p /boot/veyecam/
   cp -arf /usr/local/share/openhd/kernel/veyecam/tegra210-p3448-0003-p3542-0000.dtb /boot/dtb/
   cp -arf /usr/local/share/openhd/kernel/veyecam/tegra210-p3448-0000-p3449-0000-b00.dtb /boot/dtb/
   cp -arf /usr/local/share/openhd/kernel/veyecam/tegra210-p3448-0000-p3449-0000-a02.dtb /boot/dtb/
