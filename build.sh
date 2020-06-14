#!/bin/bash

#
# Copyright (C) 2018-2020 Michele Beccalossi <beccalossi.michele@gmail.com>
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


# # # SET DEVICE AND KERNEL NAME # # #

PRODUCT_DEVICE=oneplus5
PRODUCT_DEVICE_ALIAS=oneplus_msm8998
PRODUCT_NAME=glowing_potato


# # # SET TOOLS PARAMETERS # # #

USE_CCACHE=true
USE_CROSS_COMPILE_REPO=true

CROSS_COMPILE_NAME=aarch64-linux-android-4.9
CROSS_COMPILE_SUFFIX=aarch64-linux-android-
if [ "${USE_CROSS_COMPILE_REPO}" == true ]; then
  CROSS_COMPILE_REPO=https://source.codeaurora.org/quic/la/platform/prebuilts/gcc/linux-x86/aarch64/${CROSS_COMPILE_NAME}
  CROSS_COMPILE_BRANCH=keystone/p-keystone-qcom-release
fi
ZIP_TEMPLATE_REPO=https://github.com/kylothow/AnyKernel3.git
ZIP_TEMPLATE_BRANCH=android-9


# # # SCRIPT INIT # # #

tput reset

cd ../${PRODUCT_DEVICE} 2>/dev/null || \
    cd ../*${PRODUCT_DEVICE_ALIAS} 2>/dev/null || \
    cd ../${PRODUCT_NAME} 2>/dev/null || exit 1


# # # SET LOCAL VARIABLES # # #

BUILD_DIR=$(pwd)
BUILD_DIR_NAME=$(basename ${BUILD_DIR})
BUILD_DIR_ROOT=$(dirname ${BUILD_DIR})

BUILD_HOST_ARCH=$(uname -m)
BUILD_JOB_NUMBER=$(nproc --all)
CROSS_COMPILE_PATH=${BUILD_DIR_ROOT}/gcc/${CROSS_COMPILE_NAME}

BUILD_REVISION=$(git rev-parse HEAD | cut -c -7)
BUILD_TIMESTAMP=$(date '+%Y%m%d')

MAKEFILE=${BUILD_DIR}/Makefile
MAKEFILE_VERSION=$(grep -Po -m 1 '(?<=VERSION = ).*' ${MAKEFILE})
MAKEFILE_PATCHLEVEL=$(grep -Po -m 1 '(?<=PATCHLEVEL = ).*' ${MAKEFILE})
MAKEFILE_SUBLEVEL=$(grep -Po -m 1 '(?<=SUBLEVEL = ).*' ${MAKEFILE})
LINUX_VERSION=${MAKEFILE_VERSION}.${MAKEFILE_PATCHLEVEL}.${MAKEFILE_SUBLEVEL}
if [ -f "${BUILD_DIR}/arch/arm64/configs/${PRODUCT_DEVICE}_defconfig" ]; then
  KERNEL_DEFCONFIG=${PRODUCT_DEVICE}_defconfig
else
  KERNEL_DEFCONFIG=msmcortex-perf_defconfig
fi

BUILD_DIR_OUT=${BUILD_DIR_ROOT}/${BUILD_DIR_NAME}_out
BUILD_DIR_OUT_OBJ=${BUILD_DIR_OUT}/KERNEL_OBJ
BUILD_DIR_ZIP_TEMPLATE=${BUILD_DIR_OUT}/AnyKernel3
KERNEL_IMG=${BUILD_DIR_ZIP_TEMPLATE}/Image.gz-dtb
KERNEL_MOD_SYSTEM=${BUILD_DIR_ZIP_TEMPLATE}/modules/system/lib/modules
KERNEL_MOD_VENDOR=${BUILD_DIR_ZIP_TEMPLATE}/modules/vendor/lib/modules
PACKAGE_NAME=${PRODUCT_NAME}-${PRODUCT_DEVICE}-${BUILD_TIMESTAMP}-${BUILD_REVISION}.zip
PACKAGE_PATH=${BUILD_DIR_OUT}/${PACKAGE_NAME}


# # # SET GLOBAL VARIABLES # # #

export ARCH=arm64
if [ "${BUILD_HOST_ARCH}" == "x86_64" ]; then
  export CROSS_COMPILE=${CROSS_COMPILE_PATH}/bin/${CROSS_COMPILE_SUFFIX}
fi
export LOCALVERSION=~${PRODUCT_NAME}-${BUILD_REVISION}


# # # FUNCTIONS # # #

function verify_toolchain() {
  if [ "${BUILD_HOST_ARCH}" == "x86_64" ] && [ "${USE_CROSS_COMPILE_REPO}" == true ]; then
    if [ ! -d "${CROSS_COMPILE_PATH}" ]; then
      git clone ${CROSS_COMPILE_REPO} ${CROSS_COMPILE_PATH} \
          -b ${CROSS_COMPILE_BRANCH}
    else
      cd ${CROSS_COMPILE_PATH}
      git fetch
      git checkout ${CROSS_COMPILE_BRANCH}
      git pull
      cd ${BUILD_DIR}
    fi
    echo ""
  fi
}

function verify_template() {
  if [ ! -d "${BUILD_DIR_ZIP_TEMPLATE}" ]; then
    git clone ${ZIP_TEMPLATE_REPO} ${BUILD_DIR_ZIP_TEMPLATE} \
        -b ${ZIP_TEMPLATE_BRANCH}
  else
    cd ${BUILD_DIR_ZIP_TEMPLATE}
    git fetch
    git checkout ${ZIP_TEMPLATE_BRANCH}
    git reset --hard @{u}
    cd ${BUILD_DIR}
  fi
  echo ""
}

function clean() {
  rm -rf ${BUILD_DIR_OUT_OBJ}
  rm -f ${KERNEL_IMG}
  rm -f ${KERNEL_MOD_SYSTEM}/*.ko
  rm -f ${KERNEL_MOD_VENDOR}/*.ko
  rm -f ${BUILD_DIR_ZIP_TEMPLATE}/version
  rm -f ${BUILD_DIR_OUT}/*.zip
}

function build() {
  mkdir ${BUILD_DIR_OUT_OBJ}

  make O=${BUILD_DIR_OUT_OBJ} ${KERNEL_DEFCONFIG}
  echo ""

  if [ "$USE_CCACHE" == true ]; then
    make O=${BUILD_DIR_OUT_OBJ} -j${BUILD_JOB_NUMBER} \
        CC="ccache ${CROSS_COMPILE}gcc" CPP="ccache ${CROSS_COMPILE}gcc -E" || exit 1
  else
    make O=${BUILD_DIR_OUT_OBJ} -j${BUILD_JOB_NUMBER} || exit 1
  fi
  echo ""
}

function strip_modules() {
  find ${BUILD_DIR_OUT_OBJ} \
      -name "*.ko" \
      -exec ${CROSS_COMPILE}strip --strip-debug --strip-unneeded {} \;
}

function sign_modules() {
  if [ -f "${BUILD_DIR_OUT_OBJ}/certs/signing_key.pem" ]; then
    find ${BUILD_DIR_OUT_OBJ} \
        -name "*.ko" \
        -exec ${BUILD_DIR_OUT_OBJ}/scripts/sign-file sha512 \
              ${BUILD_DIR_OUT_OBJ}/certs/signing_key.pem \
              ${BUILD_DIR_OUT_OBJ}/certs/signing_key.x509 {} \;
  fi
}

function copy_kernel() {
  cp -v ${BUILD_DIR_OUT_OBJ}/arch/arm64/boot/Image.gz-dtb ${KERNEL_IMG}

  echo "Version: ${LINUX_VERSION}-perf~${PRODUCT_NAME}-${BUILD_REVISION}" > ${BUILD_DIR_ZIP_TEMPLATE}/version

  echo ""
}

function copy_modules() {
  find ${BUILD_DIR_OUT_OBJ} \
      -name "*.ko" \
      -exec cp -v {} ${KERNEL_MOD_SYSTEM} \;
  if [ ! -d "${KERNEL_MOD_VENDOR}" ]; then
    mkdir -p ${KERNEL_MOD_VENDOR}
  fi
  if [ -f "${KERNEL_MOD_SYSTEM}/wlan.ko" ]; then
    mv -v ${KERNEL_MOD_SYSTEM}/wlan.ko ${KERNEL_MOD_SYSTEM}/qca_cld3_wlan.ko
    cp -v ${KERNEL_MOD_SYSTEM}/qca_cld3_wlan.ko ${KERNEL_MOD_VENDOR}/qca_cld3_wlan.ko
  fi
  if [ -f "${KERNEL_MOD_SYSTEM}/msm_11ad_proxy.ko" ] && [ -f "${KERNEL_MOD_SYSTEM}/wil6210.ko" ]; then
    cp -v ${KERNEL_MOD_SYSTEM}/msm_11ad_proxy.ko ${KERNEL_MOD_VENDOR}/msm_11ad_proxy.ko
    cp -v ${KERNEL_MOD_SYSTEM}/wil6210.ko ${KERNEL_MOD_VENDOR}/wil6210.ko
  fi
  echo ""
}

function build_zip() {
  cd ${BUILD_DIR_ZIP_TEMPLATE}
  zip -r9 ${PACKAGE_PATH} * \
      -x .git README.md *placeholder patch/ ramdisk/
  cd ${BUILD_DIR}

  echo ""
  echo "out: ${PACKAGE_NAME}"
  echo ""
}


# # # MAIN FUNCTION # # #

if [ ! -d "${BUILD_DIR_OUT}" ]; then
  mkdir ${BUILD_DIR_OUT}
fi

rm -f ${BUILD_DIR_OUT}/build.log
(
  verify_toolchain
  verify_template
  clean
  build
  copy_kernel
  strip_modules
  sign_modules
  copy_modules
  build_zip
) 2>&1 | tee ${BUILD_DIR_OUT}/build.log
