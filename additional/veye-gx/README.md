# VEYE GX driver for the OpenHD Raspberry Pi 6.1 kernel

Source: https://github.com/veyeimaging/raspberrypi_v4l2
Upstream revision: d1cedd65e5f8006219261e789649c97004d982cc
Original files: driver_source/cam_drv_src/rpi-6.12.y/veye_gxcam.{c,h}
and driver_source/dts/rpi-6.12.y/veye_gxcam-overlay.dts.

The port uses asm/unaligned.h, the 6.1 V4L2 try-format/crop accessors,
and i2c_driver.probe_new. The source retains its upstream GPL license.
The overlay is installed as veye_gxcam.dtbo. GX/GXC cameras need their
specified external supply and output processed UYVY video.

The module was compiled against the target 6.1.29-v7l+ headers. Those
packaged headers omitted Module.symvers; matching import CRCs were recovered
from modules shipped with that same kernel. No version checks were disabled.
Loading the module passed. The overlay uses the 6.1 i2c_vc symbol for cam0.
On the powered GX-MIPI-IMX662 attached to the Raspberry Pi 4 at 192.168.1.42,
the driver identifies the sensor on I2C bus 10 at 0x3b and creates /dev/video0.
Raw UYVY capture and GStreamer H.264 encoding at 1920x1080, 30 fps passed.
OpenHD defaults this profile to 30 fps and sets the GX frame_rate control before
starting capture. Camera power remains external.

Build the kernel-addon package with package.py, passing the compiled module,
overlay, exact openhd-linux-pi package version, package version and output path.
The dependency pins the matching kernel package: a different build with the same
uname release can have different symbol CRCs. The addon installs support only;
it does not change boot camera selection, provisioning or saved user settings.
Upload the addon plus updated openhd-sys-utils and openhd armhf packages to the
same Bullseye repository used by ImageBuilder. ImageBuilder installs the addon
when the existing 6.1.29 Pi 4 kernel lacks the module; newer kernel packages
build it directly. ImageWriter selection GX/GXC IMX662 (ISP) writes type 64.
