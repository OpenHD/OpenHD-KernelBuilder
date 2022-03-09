#!/bin/bash
bash /home/openhd/kernelbuilder/build.sh "$@"
mv /home/openhd/kernelbuilder/*.deb /out/. > /dev/null 2>&1