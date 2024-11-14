#!/bin/bash
#########################################################################################################
#
# simple patch wrapper for patching a boot.img during the build process
#
#########################################################################################################
#
# Copyright (C) 2023-2024 steadfasterX <steadfasterX -AT- binbash #DOT# rocks>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#########################################################################################################
#
# usage:
# ./patch.sh <full-path-of-boot.img>
#
#########################################################################################################

# DO NOT set -e !

# parse calling params
export BOOTIMG="$1"
export TOP="$2"
[ -z "$TOP" -o ! -d "$TOP" ] && TOP=$PWD

# colored (optional) output
PRINT(){
    MSG="$2"
    case $1 in
        [1-9]*|E|ERROR)
            echo -e "\e[0;31m$0 - ERROR: ${MSG}\e[0m" ;;
        I|INFO)
            echo -e "\e[1;34m$0 - INFO: ${MSG}\e[0m" ;;
        0|OK|SUCCESS)
            echo -e "\e[0;32m$0 - OK: ${MSG}\e[0m" ;;
        *)
            echo -e "$0 - ${MSG}" ;;
    esac
}

PRINT I "Starting: $0 with: >$BOOTIMG< (TOP=$TOP)"

# LEGACYSAR can't be detected by the magisk patcher so must be set by us where needed (e.g. fajita).
# LEGACYSAR ensures kernel gets patched if required.
# https://github.com/topjohnwu/Magisk/blob/9aa466c7730ef4ef73195b476f9804ebf86932d2/scripts/boot_patch.sh#L220-L243
export LEGACYSAR=${system_root_image}
PRINT I "system_root_image=$LEGACYSAR"

# PREINITDEVICE can't be detected during build so must be set manually
# otherwise  "Requires Additional Setup" on first start will not be able to patch w/o direct flash
# which is a problem on locked devices (obviously)
# https://github.com/AXP-OS/build/wiki/Frequently-Asked-Questions#magisk-requires-additional-setup-on-start
export PREINITDEVICE=userdata

# tell magisk that we are not in booted android
export BOOTMODE=false

# set output file descriptor to pts0 which *should* be the current shell
export OUTFD=0

# do not remove verity nor encryption
export KEEPVERITY=true
export KEEPFORCEENCRYPT=true

# set magisk environment
export OUT_DIR=$TOP/out
export MAG_DIR="$OUT_DIR/.magisk"

# disable due to not allowed binary or useless within the build process
alias dos2unix=
alias mount=echo
alias umount=echo

# enable a fallback to get properties, according to:
# https://github.com/topjohnwu/Magisk/blob/4eaf701cb79cd9255333abad8482e69987f86280/scripts/util_functions.sh#L59
getprop(){
   find $OUT_DIR/target/product -type f -name build.prop -exec grep $1 {} \; | tail -n1
}; export -f getprop

test -e $BOOTIMG
PRINT $? "testing existence of >$BOOTIMG< returned: $?"

# do the magisk magic
/bin/bash $MAG_DIR/boot_patch.sh "$BOOTIMG" \
    && cp -v $MAG_DIR/new-boot.img "$BOOTIMG"
RET=$?

# simple check if magisk can be found in the resulting boot.img
grep -q --text 'magisk' $BOOTIMG
MCHK=$?

# sometimes the above is not valid even though patching was successful
if [ $MCHK -ne 0 ];then
    PRINT I "Simple magisk check failed, unpacking for a detailed test..\n"
    [ -d "$MAG_DIR/test" ] && rm -rf $MAG_DIR/test
    mkdir $MAG_DIR/test
    cd $MAG_DIR/test
    $MAG_DIR/magiskboot unpack $BOOTIMG && $MAG_DIR/magiskboot cpio ramdisk.cpio test
    case $? in
        1|4) MCHK=0;;
        *) ;;
    esac
    cd $TOP
    rm -rf $MAG_DIR/test
fi

# check & print result
if [ "$MCHK" -eq 0 ];then PRINT OK "MAGISK found in $BOOTIMG!";else PRINT E "Magisk not found in $BOOTIMG!";fi
RET=$((RET + $MCHK))

PRINT $RET "ended with: $RET\n\n"
exit $RET
