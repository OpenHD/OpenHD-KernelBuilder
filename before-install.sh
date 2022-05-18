#!/usr/bin/env bash
sudo apt remove linux-firmware
mount -oremount,rw /boot || true
