#!/bin/sh
# ============================================================================
# QEMU 启动脚本 — qemu_aarch64 模拟平台
#
# 用法：
#   1. 先完成构建：           make BOARD=qemu_aarch64
#   2. 启动模拟器：           ./br-ext-chip-qemu/board/qemu-aarch64/start-qemu.sh
#
# 可通过环境变量覆盖镜像目录（对应顶层 Makefile 的 TARGET 变量）：
#   IMAGES=output-custom/images ./br-ext-chip-qemu/board/qemu-aarch64/start-qemu.sh
#
# 常用操作：
#   - 串口控制台即当前终端，root 登录（密码见 general/overlay/etc/shadow）
#   - SSH 访问：ssh -p 2222 root@127.0.0.1（已通过 hostfwd 映射到 Guest 22 端口）
#   - 退出 QEMU：Ctrl+A 然后按 X
# ============================================================================
set -e

IMAGES=${IMAGES:-output/images}
KERNEL=${KERNEL:-$IMAGES/Image}
ROOTFS=${ROOTFS:-$IMAGES/rootfs.ext2}
SSH_PORT=${SSH_PORT:-2222}

die() { echo "error: $*" >&2; exit 1; }

command -v qemu-system-aarch64 >/dev/null 2>&1 || \
	die "未找到 qemu-system-aarch64，请先安装：sudo apt-get install qemu-system-arm"
[ -f "$KERNEL" ] || die "未找到内核镜像 $KERNEL，请先执行 make BOARD=qemu_aarch64"
[ -f "$ROOTFS" ] || die "未找到根文件系统 $ROOTFS，请先执行 make BOARD=qemu_aarch64"

exec qemu-system-aarch64 \
	-M virt \
	-cpu cortex-a53 \
	-smp 2 \
	-m 512M \
	-nographic \
	-kernel "$KERNEL" \
	-append "console=ttyAMA0 root=/dev/vda rw rootwait" \
	-drive file="$ROOTFS",format=raw,if=none,id=hd0 \
	-device virtio-blk-device,drive=hd0 \
	-netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
	-device virtio-net-device,netdev=net0 \
	-object rng-random,filename=/dev/urandom,id=rng0 \
	-device virtio-rng-device,rng=rng0
