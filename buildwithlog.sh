#!/bin/bash
VER2=$(git rev-parse --short HEAD) 
echo ${VER2}
./build.sh $1 $2 $3 |& tee buildlog-$(date '+%m%d%H%M')-${VER2}.log
