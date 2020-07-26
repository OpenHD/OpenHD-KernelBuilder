#!/bin/bash

#######################################
### START TRAVIS TIMEOUT PREVENTION ###
#######################################

# System uptime in seconds
function get_uptime_in_seconds() {
    # https://gist.github.com/OndroNR/0a36f97cd612b75fbf92f22cf72851a3
    local  __resultvar=$1
    
    if [ -e /proc/uptime ] ; then
       local uptime=`cat /proc/uptime | awk '{printf "%0.f", $1}'`
    else
        set +e
        sysctl kern.boottime &> /dev/null
        if [ $? -eq 0 ] ; then
            local kern_boottime=`sysctl kern.boottime 2> /dev/null | sed "s/.* sec\ =\ //" | sed "s/,.*//"`
            local time_now=`date +%s`
            local uptime=$((${time_now} - ${kern_boottime}))
        else
            
            exit 1
        fi
        set -e
    fi    
    eval $__resultvar="'${uptime}'"
}
get_uptime_in_seconds start_time

# Script runtime in seconds
function get_running_time() {
    local  __resultvar=$1
    get_uptime_in_seconds now
    local result=$(echo "${now} - ${start_time}" | bc)   
    eval $__resultvar="'$result'"
}

# This is for Travis, if build takes too long, just exit out and warm up the cache
function check_time() {
    get_running_time uptime

    # If script is running more then 20 minutes, exit out and prevent Travis from timeout
    if [[ -n $TRAVIS && ${uptime} -gt $((20*60)) ]]; then
        echoerr "Uptime: ${uptime}s"
        echoerr "Please restart this Travis build. The cache isn't warm!"
        exit 1
    fi
}
#####################################
### END TRAVIS TIMEOUT PREVENTION ###
#####################################
