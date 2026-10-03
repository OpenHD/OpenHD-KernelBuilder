#!/usr/bin/env python3
"""Replace the executable in a snapshot of an installed OpenHD runtime package.

The base tar must contain only dpkg-owned runtime files and maintainer scripts.
This preserves the tested Pi service, SDK helpers and gst-perf plugin.
"""
import argparse
import pathlib
import re
import shutil
import subprocess
import tarfile
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--base', required=True)
parser.add_argument('--control', required=True)
parser.add_argument('--binary', required=True)
parser.add_argument('--version', required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()
out = pathlib.Path(args.output).resolve()
out.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='openhd-gx-runtime-') as temporary:
    root = pathlib.Path(temporary)
    with tarfile.open(args.base) as archive:
        archive.extractall(root, filter='data')
    binary = root / 'usr/local/bin/openhd'
    shutil.copyfile(args.binary, binary)
    binary.chmod(0o755)
    control = pathlib.Path(args.control).read_text()
    control = re.sub(r'^Status:.*\n', '', control, flags=re.MULTILINE)
    control = re.sub(r'^Installed-Size:.*\n', '', control, flags=re.MULTILINE)
    control = re.sub(r'^Version:.*$', 'Version: ' + args.version, control, flags=re.MULTILINE)
    if not re.search(r'^Package: openhd$', control, re.MULTILINE):
        parser.error('Base package must be openhd')
    if not re.search(r'^Architecture: armhf$', control, re.MULTILINE):
        parser.error('Base package must be armhf')
    (root / 'DEBIAN/control').write_text(control)
    for kind in ['preinst', 'postinst', 'prerm', 'postrm']:
        script = root / 'DEBIAN' / kind
        if script.exists():
            script.write_text(script.read_text())
            script.chmod(0o755)
    subprocess.run(['dpkg-deb', '-Zxz', '--root-owner-group', '--build', str(root),
                    str(out / f'openhd_{args.version}_armhf.deb')], check=True)
