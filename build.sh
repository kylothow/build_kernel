#!/bin/bash
#
# Copyright (C) 2018 Michele Beccalossi <beccalossi.michele@gmail.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

# # # INIT # # #
tput reset;
cd ../oneplus5;


# # # SET KERNEL ID # # #

PRODUCT_REVISION=$(git rev-parse HEAD | cut -c -7);
BUILD_TIMESTAMP=$(date '+%Y%m%d');

PRODUCT_NAME=OpenEngine;
PRODUCT_DEVICE=oneplus5;


# # # SET TOOLS PARAMETERS # # #

CROSS_COMPILE_NAME=aarch64-linux-android-4.9;
CROSS_COMPILE_SUFFIX=aarch64-linux-android-;

USE_CCACHE=true;

CROSS_COMPILE_HAS_GIT=true;
CROSS_COMPILE_GIT=https://source.codeaurora.org/quic/la/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9;
CROSS_COMPILE_BRANCH=aosp-new/master;

ZIP_DIR_GIT=https://github.com/kylothow/AnyKernel2.git;
ZIP_DIR_BRANCH=oos;

ZIP_NAME=$PRODUCT_NAME-$BUILD_TIMESTAMP-$PRODUCT_REVISION-oneplus5.zip


# # # SET LOCAL VARIABLES # # #

BUILD_KERNEL_DIR=$(pwd);
BUILD_KERNEL_DIR_NAME=$(basename $BUILD_KERNEL_DIR);
BUILD_ROOT_DIR=$(dirname $BUILD_KERNEL_DIR);
PRODUCT_OUT=$BUILD_ROOT_DIR/${BUILD_KERNEL_DIR_NAME}_out;
BUILD_KERNEL_OUT_DIR=$PRODUCT_OUT/KERNEL_OBJ;
BUILD_ZIP_DIR=$PRODUCT_OUT/AnyKernel2;

BUILD_CROSS_COMPILE=/home/kylothow/android/source/CodeAurora/$CROSS_COMPILE_NAME;
KERNEL_DEFCONFIG=${PRODUCT_DEVICE}_defconfig;

KERNEL_IMG=$BUILD_ZIP_DIR/Image.gz-dtb;
KERNEL_MODULES=$BUILD_ZIP_DIR/modules/system/lib/modules;
VENDOR_MODULES=$BUILD_ZIP_DIR/modules/vendor/lib/modules;

BUILD_JOB_NUMBER=$(nproc --all);
HOST_ARCH=$(uname -m);


# # # SET GLOBAL VARIABLES # # #

export ARCH=arm64;

if [ "$HOST_ARCH" == "x86_64" ]; then
  export CROSS_COMPILE=$BUILD_CROSS_COMPILE/bin/$CROSS_COMPILE_SUFFIX;
fi;

export LOCALVERSION=~$PRODUCT_NAME-$PRODUCT_REVISION;


# # # VERIFY PRODUCT OUTPUT FOLDER EXISTENCE # # #
if [ ! -d "$PRODUCT_OUT" ]; then
  mkdir $PRODUCT_OUT;
fi;

# # # VERIFY TOOLCHAIN PRESENCE # # #

FUNC_VERIFY_TOOLCHAIN()
{
  if [ ! -d "$BUILD_CROSS_COMPILE" ]; then
    git clone $CROSS_COMPILE_GIT $BUILD_CROSS_COMPILE \
        -b $CROSS_COMPILE_BRANCH;
  else
    cd $BUILD_CROSS_COMPILE;
    git fetch;
    git checkout $CROSS_COMPILE_BRANCH;
    git pull;
    cd $BUILD_KERNEL_DIR;
  fi;
  echo "";
}


# # # VERIFY ZIP TEMPLATE PRESENCE # # #

FUNC_VERIFY_TEMPLATE()
{
  if [ ! -d "$BUILD_ZIP_DIR" ]; then
    git clone $ZIP_DIR_GIT $BUILD_ZIP_DIR \
        -b $ZIP_DIR_BRANCH;
  else
    cd $BUILD_ZIP_DIR;
    git fetch;
    git checkout $ZIP_DIR_BRANCH;
    git reset --hard @{u};
    cd $BUILD_KERNEL_DIR;
  fi;
  echo "";
}


# # # CLEAN BUILD OUTPUT # # #

FUNC_CLEAN()
{
  rm -rf $BUILD_KERNEL_OUT_DIR;
  rm -f $KERNEL_IMG;
  rm -f $KERNEL_MODULES/*.ko;
  rm -f $VENDOR_MODULES/*.ko;
  rm -f $BUILD_ZIP_DIR/version;
  rm -f $PRODUCT_OUT/*.zip;
}


# # # BUILD CONFIG AND KERNEL # # #

FUNC_BUILD()
{
  mkdir $BUILD_KERNEL_OUT_DIR;

  make O=$BUILD_KERNEL_OUT_DIR $KERNEL_DEFCONFIG;
  echo "";

  if [ "$USE_CCACHE" == true ]; then
    make O=$BUILD_KERNEL_OUT_DIR -j$BUILD_JOB_NUMBER \
        CC="ccache ${CROSS_COMPILE}gcc" CPP="ccache ${CROSS_COMPILE}gcc -E" || exit 1;
  else
    make O=$BUILD_KERNEL_OUT_DIR -j$BUILD_JOB_NUMBER || exit 1;
  fi;
  echo "";
}


# # # STRIP MODULES # # #

FUNC_STRIP_MODULES()
{
  find $BUILD_KERNEL_OUT_DIR \
      -name "*.ko" \
      -exec ${CROSS_COMPILE}strip --strip-debug {} \;
}


# # # COPY BUILD OUTPUT # # #

FUNC_COPY_KERNEL()
{
  cp -v $BUILD_KERNEL_OUT_DIR/arch/arm64/boot/Image.gz-dtb $KERNEL_IMG;
  echo "";

  MAKEFILE=$BUILD_KERNEL_DIR/Makefile;
  VERSION=$(grep -Po -m 1 '(?<=VERSION = ).*' $MAKEFILE)
  PATCHLEVEL=$(grep -Po -m 1 '(?<=PATCHLEVEL = ).*' $MAKEFILE)
  SUBLEVEL=$(grep -Po -m 1 '(?<=SUBLEVEL = ).*' $MAKEFILE)
  LINUX_VERSION=$VERSION.$PATCHLEVEL.$SUBLEVEL;

  echo "Version: $LINUX_VERSION-perf~$PRODUCT_NAME-$BUILD_TIMESTAMP-$PRODUCT_REVISION" > $BUILD_ZIP_DIR/version;
}

FUNC_COPY_MODULES()
{
  find $BUILD_KERNEL_OUT_DIR \
      -name "*.ko" \
      -exec cp -v {} $KERNEL_MODULES \;

  if [ ! -d "$VENDOR_MODULES" ]; then
    mkdir -p $VENDOR_MODULES;
  fi;

  mv -v $KERNEL_MODULES/wlan.ko $KERNEL_MODULES/qca_cld3_wlan.ko;
  cp -v $KERNEL_MODULES/qca_cld3_wlan.ko $VENDOR_MODULES/qca_cld3_wlan.ko;
  cp -v $KERNEL_MODULES/msm_11ad_proxy.ko $VENDOR_MODULES/msm_11ad_proxy.ko;
  cp -v $KERNEL_MODULES/wil6210.ko $VENDOR_MODULES/wil6210.ko;

  echo "";
}


# # # BUILD ZIP # # #

FUNC_BUILD_ZIP()
{
  ZIP_PATH=$PRODUCT_OUT/$ZIP_NAME;

  cd $BUILD_ZIP_DIR;
  zip -r9 $ZIP_PATH * \
      -x .git* README.md patch/\* ramdisk/\* *.placeholder;
  cd $BUILD_KERNEL_DIR;
}


# # # MAIN FUNCTION # # #
rm -f $PRODUCT_OUT/build.log;
(
  if [ "$HOST_ARCH" == "x86_64" ] && [ "$CROSS_COMPILE_HAS_GIT" == true ]; then
    FUNC_VERIFY_TOOLCHAIN;
  fi;
  FUNC_VERIFY_TEMPLATE;
  FUNC_CLEAN;
  FUNC_BUILD;
  FUNC_COPY_KERNEL;
  FUNC_STRIP_MODULES;
  FUNC_COPY_MODULES;
  FUNC_BUILD_ZIP;
) 2>&1 | tee $PRODUCT_OUT/build.log;
