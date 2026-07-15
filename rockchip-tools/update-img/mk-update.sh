#!/bin/bash
set -e

SCRIPT_DIR=$(dirname $(realpath $0))
PROJECT_TOP=$(realpath $SCRIPT_DIR/../..)
PACK_TOOL=$PROJECT_TOP/rockchip-tools/Linux_Pack_Firmware
BUILDROOT_IMAGES=$PROJECT_TOP/output/images
HOST_BIN=$PROJECT_TOP/output/host/sbin
WORK_DIR=$SCRIPT_DIR/Image

# UBI 参数 (与 NAND 颗粒匹配)
PEB_SIZE=0x20000      # 128 KiB 物理擦除块
MIN_IO=0x800          # 2 KiB 最小 I/O
SUB_SIZE=2048         # 子页大小
LEB_SIZE=0x1f000      # 124 KiB 逻辑擦除块
BOARD_PREBUILT="$PROJECT_TOP/br-ext-chip-rockchip/board/rv1126b_zs_im06a/prebuilt"

# 1. 准备 Image 目录
rm -rf $WORK_DIR
mkdir -p $WORK_DIR

# 2. 复制 bootloader / 内核 / 分区表
cp $SCRIPT_DIR/download.bin        $WORK_DIR/MiniLoaderAll.bin
cp $SCRIPT_DIR/parameter.txt       $WORK_DIR/
cp $SCRIPT_DIR/uboot.img           $WORK_DIR/
cp $SCRIPT_DIR/boot.img            $WORK_DIR/

# 3. 从 DarkOS Buildroot 拿最新的 rootfs
cp $BUILDROOT_IMAGES/rootfs.ubi.rv1126b $WORK_DIR/rootfs.img

# 4. 生成预格式化的空 UBI 镜像 (zs_sys_file_a, zs_sys_file_b, oem)
echo "=== Creating UBI images ==="
TMP_EMPTY=$(mktemp -d)

# zs_sys_file_a (48 MiB, 384 PEBs)
ZSA_SRC=$TMP_EMPTY
[ -d $BOARD_PREBUILT/zs_sys_file_a ] && [ "$(ls -A $BOARD_PREBUILT/zs_sys_file_a)" ] && ZSA_SRC=$BOARD_PREBUILT/zs_sys_file_a
$HOST_BIN/mkfs.ubifs -d $ZSA_SRC -e $LEB_SIZE -c 376 -m $MIN_IO -x lzo -F -o /tmp/zs_sys_file_a.ubifs
cat > $TMP_EMPTY/ubinize_sys.cfg << EOFCFG
[zs_sys_file_a]
mode=ubi
vol_id=0
vol_type=dynamic
vol_name=zs_sys_file_a
vol_alignment=1
vol_flags=autoresize
image=/tmp/zs_sys_file_a.ubifs
EOFCFG
$HOST_BIN/ubinize -o $WORK_DIR/zs_sys_file_a.img -p $PEB_SIZE -m $MIN_IO -s $SUB_SIZE $TMP_EMPTY/ubinize_sys.cfg
echo "  zs_sys_file_a.img done"

# zs_sys_file_b (48 MiB, 384 PEBs)
ZSB_SRC=$TMP_EMPTY
[ -d $BOARD_PREBUILT/zs_sys_file_b ] && [ "$(ls -A $BOARD_PREBUILT/zs_sys_file_b)" ] && ZSB_SRC=$BOARD_PREBUILT/zs_sys_file_b
$HOST_BIN/mkfs.ubifs -d $ZSB_SRC -e $LEB_SIZE -c 376 -m $MIN_IO -x lzo -F -o /tmp/zs_sys_file_b.ubifs
cat > $TMP_EMPTY/ubinize_sys.cfg << EOFCFG
[zs_sys_file_b]
mode=ubi
vol_id=0
vol_type=dynamic
vol_name=zs_sys_file_b
vol_alignment=1
vol_flags=autoresize
image=/tmp/zs_sys_file_b.ubifs
EOFCFG
$HOST_BIN/ubinize -o $WORK_DIR/zs_sys_file_b.img -p $PEB_SIZE -m $MIN_IO -s $SUB_SIZE $TMP_EMPTY/ubinize_sys.cfg
echo "  zs_sys_file_b.img done"

# oem (默认空，优先用 board prebuilt，其次 update-img/oem_overlay/)
OEM_SRC=$TMP_EMPTY
if [ -d $BOARD_PREBUILT/oem ] && [ "$(ls -A $BOARD_PREBUILT/oem)" ]; then
    OEM_SRC=$BOARD_PREBUILT/oem
elif [ -d $SCRIPT_DIR/oem_overlay ]; then
    OEM_SRC=$SCRIPT_DIR/oem_overlay
fi
$HOST_BIN/mkfs.ubifs -d $OEM_SRC -e $LEB_SIZE -c 2400 -m $MIN_IO -x lzo -F -o /tmp/oem.ubifs
cat > $TMP_EMPTY/ubinize_oem.cfg << EOFCFG
[oem]
mode=ubi
vol_id=0
vol_type=dynamic
vol_name=oem
vol_alignment=1
vol_flags=autoresize
image=/tmp/oem.ubifs
EOFCFG
$HOST_BIN/ubinize -o $WORK_DIR/oem.img -p $PEB_SIZE -m $MIN_IO -s $SUB_SIZE $TMP_EMPTY/ubinize_oem.cfg
echo "  oem.img done"

rm -rf $TMP_EMPTY

# 5. 创建 package-file
cat > $SCRIPT_DIR/package-file << 'EOF'
# NAME            PATH
package-file       package-file
parameter          Image/parameter.txt
bootloader         Image/MiniLoaderAll.bin
uboot              Image/uboot.img
boot               Image/boot.img
rootfs             Image/rootfs.img
zs_sys_file_a      Image/zs_sys_file_a.img
zs_sys_file_b      Image/zs_sys_file_b.img
oem                Image/oem.img
EOF

# 6. 打包
echo "=== Packaging update.img ==="
cd $SCRIPT_DIR
$PACK_TOOL/afptool -pack ./ $WORK_DIR/update_tmp.img || {
    echo "afptool failed!"
    exit 1
}
$PACK_TOOL/rkImageMaker -RV110F $WORK_DIR/MiniLoaderAll.bin $WORK_DIR/update_tmp.img update.img -os_type:androidos || {
    echo "rkImageMaker failed!"
    exit 1
}

# 7. 清理
rm -f $WORK_DIR/update_tmp.img

echo "=== Done: $SCRIPT_DIR/update.img ==="
ls -lh $SCRIPT_DIR/update.img
