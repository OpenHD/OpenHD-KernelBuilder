#!/bin/bash
VER2=$(git rev-parse --short HEAD) 
echo ${VER2}
./build.sh "$@" |& tee buildlog-$(date '+%m%d%H%M')-${VER2}.log
