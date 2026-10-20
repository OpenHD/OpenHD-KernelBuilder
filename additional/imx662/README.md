# Native IMX662 on OpenHD Raspberry Pi

This is the existing raw Sony IMX662 driver for OpenHD's pinned Raspberry Pi
Linux 6.1.29 (`20cb6d7b533b5e6d7df8a2cb7a83bd4555834bde`). It is distinct from
VEYE GX/GXC IMX662 modules, which have an onboard ISP and use `veye_gxcam`.

## Integration

The kernel builder installs the driver with `CONFIG_VIDEO_IMX662=m` for the Pi
v7/v7l builds and packages `imx662.ko` and `imx662.dtbo`. The installation helper
is repeatable and removes the old unconditional `obj-m` entry so the sensor is
built only once. VBLANK changes now update exposure limits while suspended,
VMAX writes propagate exposure-write failures, and the I2C remove callback
releases the registered subdevice, controls, media entity and runtime PM state.

OpenHD/libcamera installs the existing `bcm2835` IMX662 tuning in the VC4 tuning
directory, registers 2.9 um pixel properties, and matches the helper's analogue
gain clamp (0..100) and integration margin (4 lines) to this driver. The tuning
is the existing Soho/IMX290-derived calibration in this fork; it is not a fresh
calibration for every IMX662 module/lens. Image quality needs real-module testing.

OpenHD camera type **47** (`ARDUCAM_IMX662`) and the SysUtils/QOpenHD camera
selection already exist. Type **64** is the separate VEYE GX ISP path.

## Wiring and boot configuration

The existing overlay defaults to CAM1, I2C address `0x1a`, two CSI lanes,
74.25 MHz sensor clock and 594 MHz link frequency (1188 Mbps per lane).
A Pi 4 connector has two lanes. Use the module's real clock and wiring; declaring
a clock in the device tree does not make an incompatible module work.

```ini
camera_auto_detect=0
dtoverlay=imx662
# For a suitably wired four-lane CM4 CAM0 module:
# dtoverlay=imx662,cam0,4lane
# For a module using another clock already supported by the driver:
# dtoverlay=imx662,clock-frequency=37125000
```

Other accepted clocks are 24, 27 and 72 MHz. These alternatives and four-lane
operation require validation on the matching module. Register tables, lane rates,
black-level tuning and the existing fixed Bayer-order behavior are preserved;
this change does not add HDR or promise arbitrary crop/high-frame-rate modes.

## Verification

Build the module against matching target headers and compiler:

```sh
bash additional/imx662/validate.sh /path/to/linux-headers-6.1.29-v7l+ /tmp/imx662-module
```

`additional/imx662/test-integration.sh` checks repeatable driver installation and
compiles the device-tree overlay with `cpp` and `dtc`.
The companion libcamera change provides `test/run-imx662-openhd.sh`, which builds
the actual helper/controller and checks gain, exposure margins, sensor properties
and VC4 tuning initialization against a matching built libcamera core.

Validation on 2026-10-20: the module built and modposted with GCC 13 against
matching 6.1.29-v7l+ headers; repeatable installation and overlay compilation
passed. The actual libcamera helper/controller test passed gain/blanking limits,
sensor metadata and initialization of the VC4 tuning algorithms.

After installing matching kernel and libcamera packages, select camera type 47,
reboot, inspect `dmesg`, and run `libcamera-vid --list-cameras`. Test capture first:

```sh
libcamera-vid --nopreview -t 10000 --width 1920 --height 1080 --framerate 30 -o /tmp/imx662.h264
```

Then test the advertised 60 fps modes, exposure, gain, Bayer colors/orientation,
OpenHD encoding and RF streaming. Keep the previous boot configuration and
packages for rollback. Module compilation and userspace tests are not proof of
physical sensor capture, complete package production or live deployment.
