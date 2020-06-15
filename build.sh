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

DEVICE_NAME=oneplus5
DEVICE_SOC=oneplus_msm8998
PROJECT_NAME=glowing_potato


# # # SET TOOLS PARAMETERS # # #

USE_CCACHE=true
USE_GCC_REMOTE=true

GCC_NAME=aarch64-linux-android-4.9
GCC_BINARY=aarch64-linux-android-
if [ "${USE_GCC_REMOTE}" == true ]; then
  GCC_REMOTE=https://source.codeaurora.org/quic/la/platform/prebuilts/gcc/linux-x86/aarch64/${GCC_NAME}
  GCC_BRANCH=keystone/p-keystone-qcom-release
fi
TEMPLATE_REMOTE=https://github.com/kylothow/AnyKernel3.git
TEMPLATE_BRANCH=android-10


# # # SCRIPT INIT # # #

tput reset

cd ../${DEVICE_NAME} 2>/dev/null || \
    cd ../*${DEVICE_SOC} 2>/dev/null || \
    cd ../${PROJECT_NAME} 2>/dev/null || exit 1


# # # SET LOCAL VARIABLES # # #

KERNEL_SRC_DIR=$(pwd)
KERNEL_SRC_DIR_NAME=$(basename ${KERNEL_SRC_DIR})
KERNEL_SRC_DIR_PARENT=$(dirname ${KERNEL_SRC_DIR})

HOST_ARCH=$(uname -m)
HOST_PROC_NUMBER=$(nproc --all)
GCC_DIR=${KERNEL_SRC_DIR_PARENT}/gcc/${GCC_NAME}

BUILD_REVISION=$(git rev-parse HEAD | cut -c -7)
BUILD_TIMESTAMP=$(date '+%Y%m%d')

MAKEFILE=${KERNEL_SRC_DIR}/Makefile
MAKEFILE_VERSION=$(grep -Po -m 1 '(?<=VERSION = ).*' ${MAKEFILE})
MAKEFILE_PATCHLEVEL=$(grep -Po -m 1 '(?<=PATCHLEVEL = ).*' ${MAKEFILE})
MAKEFILE_SUBLEVEL=$(grep -Po -m 1 '(?<=SUBLEVEL = ).*' ${MAKEFILE})
LINUX_VERSION=${MAKEFILE_VERSION}.${MAKEFILE_PATCHLEVEL}.${MAKEFILE_SUBLEVEL}
if [ -f "${KERNEL_SRC_DIR}/arch/arm64/configs/${DEVICE_NAME}_defconfig" ]; then
  KERNEL_DEFCONFIG=${DEVICE_NAME}_defconfig
else
  KERNEL_DEFCONFIG=msmcortex-perf_defconfig
fi

OUT_DIR=${KERNEL_SRC_DIR_PARENT}/${KERNEL_SRC_DIR_NAME}_out
KERNEL_OUT_DIR=${OUT_DIR}/KERNEL_OBJ
TEMPLATE_SRC_DIR=${OUT_DIR}/AnyKernel3
KERNEL_IMG=${TEMPLATE_SRC_DIR}/Image.gz-dtb
SYSTEM_MOD_DIR=${TEMPLATE_SRC_DIR}/modules/system/lib/modules
VENDOR_MOD_DIR=${TEMPLATE_SRC_DIR}/modules/vendor/lib/modules
PACKAGE_NAME=${PROJECT_NAME}-${DEVICE_NAME}-${BUILD_TIMESTAMP}-${BUILD_REVISION}.zip
PACKAGE_ZIP=${OUT_DIR}/${PACKAGE_NAME}


# # # SET GLOBAL VARIABLES # # #

export ARCH=arm64
if [ "${HOST_ARCH}" == "x86_64" ]; then
  export CROSS_COMPILE=${GCC_DIR}/bin/${GCC_BINARY}
fi
export LOCALVERSION=~${PROJECT_NAME}-${BUILD_REVISION}


# # # FUNCTIONS # # #

function verify_gcc() {
  if [ "${HOST_ARCH}" == "x86_64" ] && [ "${USE_GCC_REMOTE}" == true ]; then
    if [ ! -d "${GCC_DIR}" ]; then
      git clone ${GCC_REMOTE} ${GCC_DIR} \
          -b ${GCC_BRANCH}
    else
      cd ${GCC_DIR}
      git fetch
      git checkout ${GCC_BRANCH}
      git pull --ff-only
      cd ${KERNEL_SRC_DIR}
    fi
    echo ""
  fi
}

function verify_template() {
  if [ ! -d "${TEMPLATE_SRC_DIR}" ]; then
    git clone ${TEMPLATE_REMOTE} ${TEMPLATE_SRC_DIR} \
        -b ${TEMPLATE_BRANCH}
  else
    cd ${TEMPLATE_SRC_DIR}
    git fetch
    git checkout ${TEMPLATE_BRANCH}
    git reset --hard @{u}
    cd ${KERNEL_SRC_DIR}
  fi
  echo ""
}

function clean_output() {
  rm -rf ${KERNEL_OUT_DIR}
  rm -f ${KERNEL_IMG}
  rm -f ${SYSTEM_MOD_DIR}/*.ko
  rm -f ${VENDOR_MOD_DIR}/*.ko
  rm -f ${TEMPLATE_SRC_DIR}/version
  rm -f ${OUT_DIR}/*.zip
}

function build_kernel() {
  mkdir ${KERNEL_OUT_DIR}

  make O=${KERNEL_OUT_DIR} ${KERNEL_DEFCONFIG}
  echo ""

  if [ "$USE_CCACHE" == true ]; then
    make O=${KERNEL_OUT_DIR} -j${HOST_PROC_NUMBER} \
        CC="ccache ${CROSS_COMPILE}gcc" CPP="ccache ${CROSS_COMPILE}gcc -E" || exit 1
  else
    make O=${KERNEL_OUT_DIR} -j${HOST_PROC_NUMBER} || exit 1
  fi
  echo ""
}

function strip_modules() {
  find ${KERNEL_OUT_DIR} \
      -name "*.ko" \
      -exec ${CROSS_COMPILE}strip --strip-debug --strip-unneeded {} \;
}

function sign_modules() {
  if [ -f "${KERNEL_OUT_DIR}/certs/signing_key.pem" ]; then
    find ${KERNEL_OUT_DIR} \
        -name "*.ko" \
        -exec ${KERNEL_OUT_DIR}/scripts/sign-file sha512 \
              ${KERNEL_OUT_DIR}/certs/signing_key.pem \
              ${KERNEL_OUT_DIR}/certs/signing_key.x509 {} \;
  fi
}

function copy_image() {
  cp -v ${KERNEL_OUT_DIR}/arch/arm64/boot/Image.gz-dtb ${KERNEL_IMG}

  echo "Version: ${LINUX_VERSION}-perf~${PROJECT_NAME}-${BUILD_REVISION}" > ${TEMPLATE_SRC_DIR}/version

  echo ""
}

function copy_modules() {
  find ${KERNEL_OUT_DIR} \
      -name "*.ko" \
      -exec cp -v {} ${SYSTEM_MOD_DIR} \;
  if [ ! -d "${VENDOR_MOD_DIR}" ]; then
    mkdir -p ${VENDOR_MOD_DIR}
  fi
  if [ -f "${SYSTEM_MOD_DIR}/wlan.ko" ]; then
    mv -v ${SYSTEM_MOD_DIR}/wlan.ko ${SYSTEM_MOD_DIR}/qca_cld3_wlan.ko
    cp -v ${SYSTEM_MOD_DIR}/qca_cld3_wlan.ko ${VENDOR_MOD_DIR}/qca_cld3_wlan.ko
  fi
  if [ -f "${SYSTEM_MOD_DIR}/msm_11ad_proxy.ko" ] && [ -f "${SYSTEM_MOD_DIR}/wil6210.ko" ]; then
    cp -v ${SYSTEM_MOD_DIR}/msm_11ad_proxy.ko ${VENDOR_MOD_DIR}/msm_11ad_proxy.ko
    cp -v ${SYSTEM_MOD_DIR}/wil6210.ko ${VENDOR_MOD_DIR}/wil6210.ko
  fi
  echo ""
}

function build_zip() {
  cd ${TEMPLATE_SRC_DIR}
  zip -r9 ${PACKAGE_ZIP} * \
      -x .git README.md *placeholder patch/ ramdisk/
  cd ${KERNEL_SRC_DIR}

  echo ""
  echo "out: ${PACKAGE_ZIP}"
  echo ""
}


# # # MAIN FUNCTION # # #

if [ ! -d "${OUT_DIR}" ]; then
  mkdir ${OUT_DIR}
fi

(
  verify_gcc
  verify_template
  clean_output
  build_kernel
  copy_image
  strip_modules
  sign_modules
  copy_modules
  build_zip
) 2>&1 | tee ${OUT_DIR}/build.log
