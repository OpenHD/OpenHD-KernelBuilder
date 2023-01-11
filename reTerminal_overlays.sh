#!/bin/bash

# module version
ver="0.1"

# we create a dir with this version to ensure that 'dkms remove' won't delete
# the sources during kernel updates
marker="0.0.0"

FORCE_KERNEL="1.20210303-1"

uname_r=$(uname -r)
arch_r=$(dpkg --print-architecture)

# Common path
SRC_PATH=/usr/src
MOD_PATH=$(pwd)/modules
RES_PATH=$(pwd)/extras/reTerminal/resources

# RPI
CFG_PATH=/boot/config.txt
CLI_PATH=/boot/cmdline.txt
OVERLAY_DIR=/boot/overlays
BOOT_MOD=/etc/modules
# Ubuntu
[ -f /boot/firmware/config.txt ] && CFG_PATH=/boot/firmware/config.txt
[ -f /boot/firmware/cmdline.txt ] && CLI_PATH=/boot/firmware/cmdline.txt
[ -d /boot/firmware/overlays ] && OVERLAY_DIR=/boot/firmware/overlays

_VER_RUN=""
function get_kernel_version() {
  local ZIMAGE IMG_OFFSET

  [ -z "$_VER_RUN" ] && {
    ZIMAGE=/boot/kernel7l.img
    if [ $arch_r == "arm64" ]; then
      ZIMAGE=/boot/kernel8.img
    fi
    [ -f /boot/firmware/vmlinuz ] && ZIMAGE=/boot/firmware/vmlinuz
    IMG_OFFSET=$(LC_ALL=C grep -abo $'\x1f\x8b\x08\x00' $ZIMAGE | head -n 1 | cut -d ':' -f 1)
    _VER_RUN=$(dd if=$ZIMAGE obs=64K ibs=4 skip=$((IMG_OFFSET / 4)) 2>/dev/null | zcat | grep -a -m1 "Linux version" | strings | awk '{ print $3; }')
  }
  echo "$_VER_RUN"

  return 0
}

# Check headers
function check_kernel_headers() {
  VER_RUN=$(get_kernel_version)

  if [[ -e "/lib/modules/${VER_RUN}/build" ]]; then
    echo KBUILD: "/lib/modules/${VER_RUN}/build"
    return 0
  fi

  echo " !!! Your kernel version is $VER_RUN"
  echo "     Couldn't find *** corresponding *** kernel headers with apt-get."
  echo "     This may happen if you ran 'rpi-update'."
  echo " Choose  *** y *** to install kernel-headers to version $(uname -r) and continue."
  echo " Choose  *** N *** to exit without this driver support, by default."
  read -p "Would you like to proceed? (y/N)" -n 1 -r -s
  echo
  if ! [[ $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi

  apt-get -y install raspberrypi-kernel-headers
}

function download_install_debpkg() {
  local prefix name r pkg status _name
  prefix=$1
  name=$2
  pkg=${name%%_*}

  status=$(dpkg -l $pkg | tail -1)
  _name=$(echo "$status" | awk '{ printf "%s_%s_%s", $2, $3, $4; }')
  status=$(echo "$status" | awk '{ printf "%s", $1; }')

  if [ "X$status" == "Xii" -a "X${name%.deb}" == "X$_name" ]; then
    echo "debian package $name already installed."
    return 0
  fi

  for ((i = 0; i < 3; i++)); do
    wget $prefix$name -O /tmp/$name && break
  done

  dpkg -i /tmp/$name
  r=$?
  rm -f /tmp/$name

  return $r
}

function install_kernel() {
  local _url _prefix

  # Instead of retrieving the lastest kernel & headers
  [ "X$FORCE_KERNEL" == "X" ] && {
    # Raspbian kernel packages
    apt-get -y --force-yes install raspberrypi-kernel-headers raspberrypi-kernel || {
      # Ubuntu kernel packages
      apt-get -y install linux-raspi linux-headers-raspi linux-image-raspi
    }
  } || {
    # We would like to a fixed version
    KERN_NAME=raspberrypi-kernel_${FORCE_KERNEL}_${arch_r}.deb
    HDR_NAME=raspberrypi-kernel-headers_${FORCE_KERNEL}_${arch_r}.deb
    _url=$(apt-get download --print-uris raspberrypi-kernel | sed -nre "s/'([^']+)'.*$/\1/g;p")
    _prefix=$(echo $_url | sed -nre 's/^(.*)raspberrypi-kernel_.*$/\1/g;p')

    download_install_debpkg "$_prefix" "$KERN_NAME" && {
      download_install_debpkg "$_prefix" "$HDR_NAME"
    } || {
      echo "Error: Install kernel or header failed"
      exit 2
    }
  }
}

# Install module
function install_modules {
  if [ $# -eq 0 ]; then
    echo "No module to install!"
    exit 1
  fi

  # locate currently installed kernels (may be different to running kernel if
  # it's just been updated)
  kernel=$(get_kernel_version)

  for mod; do
    target=$SRC_PATH/$mod-$ver
    mkdir -p $target
    cp -a $MOD_PATH/$mod/* $target/

    dkms build -k ${kernel} -m $mod -v $ver && {
      dkms install --force -k ${kernel} -m $mod -v $ver
    } || {
      echo "Can't compile with this kernel, aborting"
      echo "Please try to compile with the option --compat-kernel"
      exit 1
    }

    mkdir -p /var/lib/dkms/$mod/$ver/$marker
  done
}


# Overlay
function install_overlay {
  if [ $# -eq 0 ]; then
    echo "No dtbo to install!"
    exit 1
  fi

  # cmdline.txt
  CMDLINE=$(cat $CLI_PATH)
  CMDLINE=$(echo $CMDLINE | sed 's/ *\bconsole=tty0\b//g')
  grep -q "\blogo.nologo\b" $CLI_PATH ||
    CMDLINE="$CMDLINE logo.nologo"
  grep -q "\bvt.global_cursor_default=0\b" $CLI_PATH ||
    CMDLINE="$CMDLINE vt.global_cursor_default=0"
  grep -q "\bconsole=tty3\b" $CLI_PATH ||
    CMDLINE="$CMDLINE console=tty3"
  grep -q "\bloglevel=0\b" $CLI_PATH ||
    CMDLINE="$CMDLINE loglevel=0"
  echo $CMDLINE >$CLI_PATH

  # config.txt
  sed -i "s/.*dtparam=i2c_arm=.*$/dtparam=i2c_arm=on/g" ${CFG_PATH}

  grep -q "^enable_uart=1$" $CFG_PATH ||
    echo "enable_uart=1" >>$CFG_PATH
  grep -q "^dtoverlay=dwc2,dr_mode=host$" $CFG_PATH ||
    echo "dtoverlay=dwc2,dr_mode=host" >>$CFG_PATH
  grep -q "^dtparam=ant2$" $CFG_PATH ||
    echo "dtparam=ant2" >>$CFG_PATH
  grep -q "^disable_splash=1$" $CFG_PATH ||
    echo "disable_splash=1" >>$CFG_PATH

  grep -q "^ignore_lcd=1$" $CFG_PATH ||
    echo "ignore_lcd=1" >>$CFG_PATH
  grep -q "^dtoverlay=vc4-kms-v3d-pi4$" $CFG_PATH ||
    echo "dtoverlay=vc4-kms-v3d-pi4" >>$CFG_PATH
  grep -q "^dtoverlay=i2c3,pins_4_5$" $CFG_PATH ||
    echo "dtoverlay=i2c3,pins_4_5" >>$CFG_PATH
  grep -q "^gpio=13=pu$" $CFG_PATH ||
    echo "gpio=13=pu" >>$CFG_PATH

  for i; do
    grep -q "^dtoverlay=$i$" $CFG_PATH ||
      echo "dtoverlay=$i" >>$CFG_PATH
  done
}

function uninstall_overlay {
  if [ $# -eq 0 ]; then
    echo "No dtbo to remove!"
    exit 1
  fi

  # cmdline.txt
  CMDLINE=$(cat $CLI_PATH)
  CMDLINE=$(echo $CMDLINE | sed 's/ *\blogo.nologo\b//g')
  CMDLINE=$(echo $CMDLINE | sed 's/ *\bvt.global_cursor_default=0\b//g')
  CMDLINE=$(echo $CMDLINE | sed 's/ *\bconsole=tty3\b//g')
  CMDLINE=$(echo $CMDLINE | sed 's/ *\bloglevel=0\b//g')
  echo $CMDLINE >$CLI_PATH

  # config.txt
  sed -i "/^disable_splash=1$/d" ${CFG_PATH}
  sed -i "/^ignore_lcd=1$/d" ${CFG_PATH}
  sed -i "/^dtoverlay=vc4-kms-v3d-pi4$/d" ${CFG_PATH}
  sed -i "/^dtoverlay=i2c3,pins_4_5$/d" ${CFG_PATH}
  sed -i "/^gpio=13=pu$/d" ${CFG_PATH}

  for i; do
    #rm -fv $OVERLAY_DIR/$i.dtbo || exit 1
    sed -i "/^dtoverlay="$i"$/d" ${CFG_PATH}
  done
}

function setup_overlay {
  sed -i "/^dtoverlay=$1$/s//dtoverlay=$1,$2/" ${CFG_PATH}
}

#NOTICE: this function must be used
# before the uninstall_overlay
function unsetup_overlay {
  sed -i "/^dtoverlay=$1,$2$/s//dtoverlay=$1/" ${CFG_PATH}
}

function usage() {
  cat <<-__EOF__
    usage: sudo ./scripts/reTerminal.sh [ --autoremove | --install ] [ -h | --help ]
             default action is update kernel & headers to latest version.
             --compat-kernel uses an older kernel but ensures that the driver can work.
             --keep-kernel   don't change/update the system kernel, maybe install
                             coressponding kernel headers.
             --autoremove    used for automatic cleaning
             --help          show this help message
__EOF__
  exit 1
}

function install {
  install_overlay reTerminal-overlay reTerminal-bridge-overlay
  setup_overlay reTerminal-overlay tp_rotate=1

  #audio
  if [ -f "/var/lib/alsa/asound.state" ]; then
    cp /var/lib/alsa/asound.state /var/lib/alsa/asound.state.bak
  fi
  if [ -f "/etc/asound.conf" ]; then
    cp /etc/asound.conf /etc/asound.conf.bak
  fi

  cp /usr/local/share/reterminal/wm8960_asound.state /var/lib/alsa/asound.state
  cp /usr/local/share/reterminal/asound_2mic.conf /etc/asound.conf
  alsactl -L restore

  echo "------------------------------------------------------"
  echo "Please reboot your device to apply all settings"
  echo "Enjoy!"
  echo "------------------------------------------------------"
}

function uninstall {
  unsetup_overlay reTerminal-overlay tp_rotate=1
  uninstall_overlay reTerminal-overlay reTerminal-bridge-overlay
}

function install_mod_boot {
  grep -q "^als_ltr30x$" $BOOT_MOD ||
    echo als_ltr30x >>$BOOT_MOD
  grep -q "^bq24179_charger$" $BOOT_MOD ||
    echo bq24179_charger >>$BOOT_MOD
  grep -q "^lis331dlh-i2c$" $BOOT_MOD ||
    echo lis331dlh-i2c >>$BOOT_MOD
  grep -q "^mipi_dsi$" $BOOT_MOD ||
    echo mipi_dsi >>$BOOT_MOD
}

function uninstall_mod_boot {
  sed -i "/^als_ltr30x$/d" $BOOT_MOD
  sed -i "/^bq24179_charger$/d" $BOOT_MOD
  sed -i "/^lis331dlh-i2c$/d" $BOOT_MOD
  sed -i "/^mipi_dsi$/d" $BOOT_MOD
}
# Check root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root (use sudo)" 1>&2
  exit 1
fi

install
