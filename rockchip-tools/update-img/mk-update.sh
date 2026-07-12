#!/bin/bash
set -e

SCRIPT_DIR=$(dirname $(realpath $0))
PROJECT_TOP=$(realpath $SCRIPT_DIR/../..)
PACK_TOOL=$PROJECT_TOP/rockchip-tools/Linux_Pack_Firmware
BUILDROOT_IMAGES=$PROJECT_TOP/output/images
WORK_DIR=$SCRIPT_DIR/work

# 1. 准备临时工作目录
rm -rf $WORK_DIR
mkdir -p $WORK_DIR

# 2. 复制预编译的 bootloader / 内核 / 分区表
cp $SCRIPT_DIR/download.bin $WORK_DIR/
cp $SCRIPT_DIR/env.img      $WORK_DIR/
cp $SCRIPT_DIR/uboot.img    $WORK_DIR/
cp $SCRIPT_DIR/boot.img     $WORK_DIR/

# 3. 从 Buildroot 拿最新的 rootfs
cp $BUILDROOT_IMAGES/rootfs.ubi.rv1126 $WORK_DIR/rootfs.img

# 4. 使用 SDK 打包脚本生成 update.img
echo "=== Packaging update.img ==="
$PACK_TOOL/mk-update_pack.sh -id rv1126b -i $WORK_DIR

# 5. 输出到 update-img 目录
cp $WORK_DIR/update.img $SCRIPT_DIR/
rm -rf $WORK_DIR

echo "=== Done: $SCRIPT_DIR/update.img ==="
ls -lh $SCRIPT_DIR/update.img
