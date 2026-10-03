# IMX415 backport for OpenHD's Raspberry Pi kernel

Target: OpenHD/linux commit `20cb6d7b533b5e6d7df8a2cb7a83bd4555834bde`,
Linux 6.1.29, ARM `v7` and `v7l` builds. This does not update the kernel version.

Sources:

- Driver: raspberrypi/linux `e89ccf9caeaa7e7e88e75d03fe39a0ec9deb52b1`
  (`rpi-6.3.y`), `drivers/media/i2c/imx415.c`, GPL-2.0-only.
- Overlay and include: raspberrypi/linux `a553c4648f68caaa9fe246adb40269af771a0ee7`
  (`rpi-6.12.y`), `arch/arm/boot/dts/overlays/imx415-overlay.dts`
  and `imx415.dtsi`. The CAM0 bus is adapted to the 6.1 `i2c_vc` symbol.
- The 1782 Mbps and 37.125 MHz clock settings are taken from that 6.12 driver.
- Binning register reference: [OpenIPC IMX415](https://github.com/OpenIPC/sensors/blob/master/sigmastar/infinity6e/sensor_imx415_mipi.c),
  `Sensor_init_table_2m90fps` (four lanes). Two-lane timing is derived from
  Sony IMX415-AAQR-C E19504 pages 49 and 57-61, rather than using that table's
  four-lane 90 fps timing.

The original driver already uses APIs available in 6.1. The backport additionally
provides writable VBLANK with coordinated shutter updates, updates the exposure
range while suspended, fixes fixed-size format negotiation, supplies NATIVE_SIZE,
reports Bayer order after flips, locks flips during streaming, and checks subdev
state initialization errors. These changes are needed for libcamera configuration
and frame-duration controls. Gain remains limited to codes 0..100 (0.3 dB steps).

The builder copies the driver, adds its Kconfig/Makefile entries, enables
`CONFIG_VIDEO_IMX415=m` after both Pi defconfigs, and builds `imx415.dtbo`.
The normal module/overlay packaging includes both. Source selection uses the
kernel commit declared in `kernels/*` before driver injection and refuses to
switch a modified checkout.

## Modes and configuration

The default uses sensor H/V 2/2 binning with 10-bit conversion and RAW12 output.
The transmitted image is 1944x1097 including margins/dummy pixels; the recording
area is 1920x1080. HMAX=550 and VMAX=2250 give exactly 60 fps at a 74.25 MHz
internal timing clock. Each binned output line occupies two XHS periods, which
is accounted for in pixel rate, blanking and exposure controls. Bayer order
remains RGGB when reversing binned readout, as specified by Sony.

| Wiring | Clock | Link frequency | Maximum sensor rate |
| --- | --- | --- | --- |
| 2 lanes, default, binning | 27 or 37.125 MHz | 891 MHz (1782 Mbps/lane) | 60 fps |
| 2 lanes, all-pixel | 24 MHz | 360 MHz (720 Mbps/lane) | about 15.74 fps |
| 2 lanes, high link rate | 24 MHz | 720 MHz (1440 Mbps/lane) | about 30.01 fps |
| 4 lanes | 27 or 37.125 MHz | 445.5 MHz (891 Mbps/lane) | 30 fps |

Use the module's actual oscillator and wiring. The default node uses I2C address
0x37 and the CAM1 connector. Parameters include `addr`, `cam0`, `rotation`,
`orientation`, `clock-frequency`, `link-frequency`, `4lane`, and `clk-37125`.

Examples:

```ini
# Default 27 MHz, two-lane binning:
camera_auto_detect=0
dtoverlay=imx415

# Two-lane binning with a 37.125 MHz module:
# dtoverlay=imx415,clk-37125

# Legacy 24 MHz all-pixel module (about 30 fps):
# dtoverlay=imx415,clock-frequency=24000000,link-frequency=720000000

# Four-lane 37.125 MHz module on a suitably wired CM4 CAM0 connector:
# dtoverlay=imx415,cam0,4lane,clk-37125
```

`4lane` changes both endpoints, chooses the 891 Mbps mode and defaults the clock
to 27 MHz; add `clk-37125` for a 37.125 MHz module. The ordinary Pi 4 connector
has only two data lanes. The high-rate two-lane option is not validated on Pi 4.

OpenHD camera profile 48 defaults to 1920x1080 at 60 fps. The added two-lane
sensor mode is a source-level implementation and has not been capture-tested.
The module must have a supported input clock and the receiver/cabling must
support 1782 Mbps per lane. ISP output scaling supplies 720p60 as well.

## Libcamera and OpenHD

The separate OpenHD/libcamera checkout adds the registered IMX415 Pi helper,
1.45 um pixel properties and `src/ipa/rpi/vc4/data/imx415.json`. Meson installs the
tuning in `/usr/share/libcamera/ipa/rpi/vc4/` in the existing libcamera-openhd
package. The tuning and helper originate from Raspberry Pi libcamera tag
`v0.7.1+rpt20260609`, commit `06c385619acb10bbfb33f52f3abeb8f8c095f42b`.
The helper's gain-code clamp matches this driver's analogue gain limit.
The colour/lens calibration is for Arducam B0569 and needs checking for other
modules/lenses. This integration targets VC4 on Pi <=4; Pi 5/PISP is not covered.

OpenHD profile 48 uses the existing libcamera backend. SysUtils selects
`dtoverlay=imx415` and CMA=400M. The generated OpenHD/QOpenHD registry exposes it
under SONY for Pi <=4/CM4. Selecting the standard profile reapplies default overlay
parameters; custom module parameters must be added after that setup step.

## Validation performed

- Built and modposted the final driver with GCC 13 against existing
  `6.1.29-v7l+` headers and Module.symvers; vermagic matches that target.
- Compiled the overlay and merged it using Raspberry Pi `dtmerge` against Pi 4
  and CM4 device trees fetched from the pinned OpenHD kernel commit. Checked the
  default and CAM0/four-lane/37.125 MHz configurations.
- Built the fork's libcamera core on amd64 and compiled its actual Pi controller
  and IMX415 helper into a validation executable. Registered helper, gain
  conversion and loading/initialization of all VC4 tuning algorithms passed.
  The unrelated binary Pivariety SDK has no amd64 package, so this is not a full
  armhf libcamera-openhd package build.
- Built SysUtils and regenerated both OpenHD and QOpenHD camera registries.

No camera capture, full kernel package build, Pi deployment, or end-to-end OpenHD
stream has been performed. After installing matching kernel/libcamera/SysUtils
and OpenHD packages, reboot and check `dmesg`, `media-ctl -p`, and
`libcamera-vid --list-cameras`. First verify capture, exposure and flips using
`libcamera-vid --nopreview -t 10000 --width 1920 --height 1080 --framerate 60
-o /tmp/imx415.h264`, then verify the OpenHD stream. Retain the previous kernel,
overlay and boot configuration for rollback.

For a standalone module compile:

```sh
bash additional/imx415/validate.sh /path/to/matching/kernel/headers /tmp/imx415-build
```
