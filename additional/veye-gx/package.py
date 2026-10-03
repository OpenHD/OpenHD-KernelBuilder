#!/usr/bin/env python3
"""Package an already built GX driver for its exact Raspberry Pi kernel."""
import argparse
import pathlib
import shutil
import subprocess
import tempfile
import tarfile

parser = argparse.ArgumentParser()
parser.add_argument('--module', required=True)
parser.add_argument('--overlay', required=True)
parser.add_argument('--kernel', default='6.1.29-v7l+')
parser.add_argument('--kernel-package-version', required=True)
parser.add_argument('--version', required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()
vermagic = subprocess.check_output(['modinfo', '-F', 'vermagic', args.module], text=True)
if vermagic.split()[0] != args.kernel:
    parser.error('Module vermagic does not match the requested kernel')
out = pathlib.Path(args.output).resolve()
out.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='openhd-gx-package-') as temporary:
    root = pathlib.Path(temporary)
    def write(name, content, mode=0o644):
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        target.chmod(mode)
    for source, destination in [(args.module, f'lib/modules/{args.kernel}/extra/veye_gxcam.ko'),
                                (args.overlay, 'usr/share/openhd/overlays/veye_gxcam.dtbo')]:
        target = root / destination
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        target.chmod(0o644)
    write('DEBIAN/control', f'''Package: openhd-veye-gx
Version: {args.version}
Architecture: armhf
Maintainer: OpenHD Team
Section: kernel
Priority: optional
Depends: openhd-linux-pi (= {args.kernel_package_version}), kmod, v4l-utils
Description: VEYE GX/GXC ISP camera driver for OpenHD Raspberry Pi
 Built exclusively for kernel {args.kernel}. Provides the GX IMX662
 driver and device-tree overlay; camera selection is managed by SysUtils.
''')
    write('DEBIAN/postinst', f'''#!/bin/sh
set -e
if [ "$1" = configure ]; then
    boot=/boot
    if [ -f /boot/firmware/config.txt ]; then boot=/boot/firmware; fi
    mkdir -p "$boot/overlays"
    install -m 644 /usr/share/openhd/overlays/veye_gxcam.dtbo "$boot/overlays/veye_gxcam.dtbo"
    if [ -d /lib/modules/{args.kernel} ]; then depmod -a {args.kernel}; fi
fi
exit 0
''', 0o755)
    # The old header package lacks Module.symvers; recovered CRCs do not encode
    # module ownership. Load the media framework before this standalone module.
    write('etc/modprobe.d/openhd-veye-gx.conf',
          'softdep veye_gxcam pre: videodev v4l2_fwnode v4l2_async\n')
    # Installing support must not select a camera or reset existing settings.
    write('usr/share/doc/openhd-veye-gx/README',
          f'Kernel: {args.kernel}\nSelect GX/GXC IMX662 (camera type 64) in ImageWriter/OpenHD.\n'
          'External camera power is required. Reboot after changing camera type.\n')
    shutil.copyfile(pathlib.Path(__file__).with_name('README.md'),
                    root / 'usr/share/doc/openhd-veye-gx/SOURCE.md')
    source_dir = pathlib.Path(__file__).parent
    with tarfile.open(root / 'usr/share/doc/openhd-veye-gx/source.tar.gz', 'w:gz') as archive:
        for name in ['veye_gxcam.c', 'veye_gxcam.h', 'veye_gxcam-overlay.dts', 'README.md', 'package.py']:
            archive.add(source_dir / name, arcname=name)
    write('usr/share/doc/openhd-veye-gx/copyright',
          'Copyright (C) 2025 www.veye.cc\nLicense: GPL-2.0-only\n'
          'Source and local kernel API port are included in source.tar.gz.\n')
    shutil.copyfile('/usr/share/common-licenses/GPL-2',
                    root / 'usr/share/doc/openhd-veye-gx/COPYING')
    subprocess.run(['dpkg-deb', '-Zxz', '--root-owner-group', '--build', str(root),
                    str(out / f'openhd-veye-gx_{args.version}_armhf.deb')], check=True)
