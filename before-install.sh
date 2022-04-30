#!/usr/bin/env bash

mount -oremount,rw /boot || true
rm /lib/modules/4.9.253-tegra/kernel/drivers/net/wireless/realtek/rtl8812au/rtl8812au.ko
rm /lib/firmware/htc_9271.fw