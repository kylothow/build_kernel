#!/bin/bash
#
# Copyright (C) 2018-2019 Michele Beccalossi <beccalossi.michele@gmail.com>
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


# # # SET KERNEL ID # # #

PRODUCT_NAME=DarkDescent;
PRODUCT_DEVICE=oneplus5;
PRODUCT_DEVICE_ALIAS=oneplus_msm8998;


# # # SCRIPT INIT # # #

tput reset;
cd ../$PRODUCT_DEVICE || cd ../*$PRODUCT_DEVICE_ALIAS || exit 1;


# # # SET TOOLS PARAMETERS # # #

USE_CCACHE=true;
USE_CROSS_COMPILE_REPO=true;

CROSS_COMPILE_REPO=https://source.codeaurora.org/quic/la/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9;
CROSS_COMPILE_BRANCH=keystone/p-keystone-qcom-release;
CROSS_COMPILE_NAME=aarch64-linux-android-4.9;
CROSS_COMPILE_SUFFIX=aarch64-linux-android-;

ZIP_TEMPLATE_REPO=https://github.com/kylothow/AnyKernel2.git;
ZIP_TEMPLATE_BRANCH=oos;

BUILD_TIMESTAMP=$( date '+%Y%m%d' );
BUILD_REVISION=$( git rev-parse HEAD | cut -c -7 );
PACKAGE_NAME=$PRODUCT_NAME-$PRODUCT_DEVICE-$BUILD_TIMESTAMP-$BUILD_REVISION.zip


# # # SET LOCAL VARIABLES # # #

BUILD_DIR=$( pwd );
BUILD_DIR_NAME=$( basename $BUILD_DIR );
BUILD_DIR_ROOT=$( dirname $BUILD_DIR );
BUILD_DIR_OUT=$BUILD_DIR_ROOT/${BUILD_DIR_NAME}_out;
BUILD_DIR_OUT_OBJ=$BUILD_DIR_OUT/KERNEL_OBJ;
BUILD_DIR_ZIP_TEMPLATE=$BUILD_DIR_OUT/template;

if [ -f "$BUILD_DIR/arch/arm64/configs/${PRODUCT_DEVICE}_defconfig" ]; then
  KERNEL_DEFCONFIG=${PRODUCT_DEVICE}_defconfig;
else
  KERNEL_DEFCONFIG=msmcortex-perf_defconfig;
fi;

KERNEL_IMG=$BUILD_DIR_ZIP_TEMPLATE/Image.gz-dtb;
SYSTEM_MODULES=$BUILD_DIR_ZIP_TEMPLATE/modules/system/lib/modules;
VENDOR_MODULES=$BUILD_DIR_ZIP_TEMPLATE/modules/vendor/lib/modules;

BUILD_JOB_NUMBER=$( nproc --all );
BUILD_HOST_ARCH=$( uname -m );
BUILD_USERNAME=$( whoami );

CROSS_COMPILE_PATH=/home/$BUILD_USERNAME/source/CodeAurora/$CROSS_COMPILE_NAME;


# # # SET GLOBAL VARIABLES # # #

export ARCH=arm64;

if [ "$BUILD_HOST_ARCH" == "x86_64" ]; then
  export CROSS_COMPILE=$CROSS_COMPILE_PATH/bin/$CROSS_COMPILE_SUFFIX;
fi;

export LOCALVERSION=~$PRODUCT_NAME-$BUILD_REVISION;


# # # VERIFY PRODUCT OUTPUT FOLDER EXISTENCE # # #

if [ ! -d "$BUILD_DIR_OUT" ]; then
  mkdir $BUILD_DIR_OUT;
fi;

# # # VERIFY TOOLCHAIN PRESENCE # # #

FUNC_VERIFY_TOOLCHAIN()
{
  if [ ! -d "$CROSS_COMPILE_PATH" ]; then
    git clone $CROSS_COMPILE_REPO $CROSS_COMPILE_PATH \
        -b $CROSS_COMPILE_BRANCH;
  else
    cd $CROSS_COMPILE_PATH;
    git fetch;
    git checkout $CROSS_COMPILE_BRANCH;
    git pull;
    cd $BUILD_DIR;
  fi;
  echo "";
}


# # # VERIFY ZIP TEMPLATE PRESENCE # # #

FUNC_VERIFY_TEMPLATE()
{
  if [ ! -d "$BUILD_DIR_ZIP_TEMPLATE" ]; then
    git clone $ZIP_TEMPLATE_REPO $BUILD_DIR_ZIP_TEMPLATE \
        -b $ZIP_TEMPLATE_BRANCH;
  else
    cd $BUILD_DIR_ZIP_TEMPLATE;
    git fetch;
    git checkout $ZIP_TEMPLATE_BRANCH;
    git reset --hard @{u};
    cd $BUILD_DIR;
  fi;
  echo "";
}


# # # CLEAN BUILD OUTPUT # # #

FUNC_CLEAN()
{
  rm -rf $BUILD_DIR_OUT_OBJ;
  rm -f $KERNEL_IMG;
  rm -f $SYSTEM_MODULES/*.ko;
  rm -f $VENDOR_MODULES/*.ko;
  rm -f $BUILD_DIR_ZIP_TEMPLATE/version;
  rm -f $BUILD_DIR_OUT/*.zip;
}


# # # BUILD CONFIG AND KERNEL # # #

FUNC_BUILD()
{
  mkdir $BUILD_DIR_OUT_OBJ;

  make O=$BUILD_DIR_OUT_OBJ $KERNEL_DEFCONFIG;
  echo "";

  if [ "$USE_CCACHE" == true ]; then
    make O=$BUILD_DIR_OUT_OBJ -j$BUILD_JOB_NUMBER \
        CC="ccache ${CROSS_COMPILE}gcc" CPP="ccache ${CROSS_COMPILE}gcc -E" || exit 1;
  else
    make O=$BUILD_DIR_OUT_OBJ -j$BUILD_JOB_NUMBER || exit 1;
  fi;
  echo "";
}


# # # STRIP MODULES # # #

FUNC_STRIP_MODULES()
{
  find $BUILD_DIR_OUT_OBJ \
      -name "*.ko" \
      -exec ${CROSS_COMPILE}strip --strip-debug --strip-unneeded {} \;
}


# # # SIGN MODULES # # #

FUNC_SIGN_MODULES()
{
  find $BUILD_DIR_OUT_OBJ \
      -name "*.ko" \
      -exec $BUILD_DIR_OUT_OBJ/scripts/sign-file sha512 \
            $BUILD_DIR_OUT_OBJ/certs/signing_key.pem \
            $BUILD_DIR_OUT_OBJ/certs/signing_key.x509 {} \;
}


# # # COPY BUILD OUTPUT # # #

FUNC_COPY_KERNEL()
{
  cp -v $BUILD_DIR_OUT_OBJ/arch/arm64/boot/Image.gz-dtb $KERNEL_IMG;
  echo "";

  MAKEFILE=$BUILD_DIR/Makefile;
  MAKEFILE_VERSION=$( grep -Po -m 1 '(?<=VERSION = ).*' $MAKEFILE )
  MAKEFILE_PATCHLEVEL=$( grep -Po -m 1 '(?<=PATCHLEVEL = ).*' $MAKEFILE )
  MAKEFILE_SUBLEVEL=$( grep -Po -m 1 '(?<=SUBLEVEL = ).*' $MAKEFILE )

  LINUX_VERSION=$MAKEFILE_VERSION.$MAKEFILE_PATCHLEVEL.$MAKEFILE_SUBLEVEL;

  echo "Version: $LINUX_VERSION-perf~$PRODUCT_NAME-$BUILD_REVISION" > $BUILD_DIR_ZIP_TEMPLATE/version;
}

FUNC_COPY_MODULES()
{
  find $BUILD_DIR_OUT_OBJ \
      -name "*.ko" \
      -exec cp -v {} $SYSTEM_MODULES \;

  if [ ! -d "$VENDOR_MODULES" ]; then
    mkdir -p $VENDOR_MODULES;
  fi;

  if [ -f "$SYSTEM_MODULES/wlan.ko" ]; then
    mv -v $SYSTEM_MODULES/wlan.ko $SYSTEM_MODULES/qca_cld3_wlan.ko;
    cp -v $SYSTEM_MODULES/qca_cld3_wlan.ko $VENDOR_MODULES/qca_cld3_wlan.ko;
  fi;
  if [ -f "$SYSTEM_MODULES/msm_11ad_proxy.ko" ] && [ -f "$SYSTEM_MODULES/wil6210.ko" ]; then
    cp -v $SYSTEM_MODULES/msm_11ad_proxy.ko $VENDOR_MODULES/msm_11ad_proxy.ko;
    cp -v $SYSTEM_MODULES/wil6210.ko $VENDOR_MODULES/wil6210.ko;
  fi;

  echo "";
}


# # # BUILD ZIP # # #

FUNC_BUILD_ZIP()
{
  PACKAGE_PATH=$BUILD_DIR_OUT/$PACKAGE_NAME;

  cd $BUILD_DIR_ZIP_TEMPLATE;
  zip -r9 $PACKAGE_PATH * \
      -x patch/ prebuilt/ ramdisk/ README.md *.placeholder;
  cd $BUILD_DIR;

  echo "";
  echo "out: $PACKAGE_NAME";
  echo "";
}


# # # MAIN FUNCTION # # #

rm -f $BUILD_DIR_OUT/build.log;
(
  if [ "$BUILD_HOST_ARCH" == "x86_64" ] && [ "$USE_CROSS_COMPILE_REPO" == true ]; then
    FUNC_VERIFY_TOOLCHAIN;
  fi;
  FUNC_VERIFY_TEMPLATE;
  FUNC_CLEAN;
  FUNC_BUILD;
  FUNC_COPY_KERNEL;
  FUNC_STRIP_MODULES;
  FUNC_SIGN_MODULES;
  FUNC_COPY_MODULES;
  FUNC_BUILD_ZIP;
) 2>&1 | tee $BUILD_DIR_OUT/build.log;
