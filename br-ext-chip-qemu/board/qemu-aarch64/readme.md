# QEMU aarch64 模拟平台

基于 QEMU `virt` 机器的 DarkOS 模拟平台，用于在无真实硬件的情况下构建、
运行和调试 DarkOS 用户空间。

## 平台规格

| 项目     | 说明                                       |
|----------|--------------------------------------------|
| 架构     | aarch64 (Cortex-A53)                       |
| 机器类型 | QEMU `virt`                                |
| 内核     | 主线 Linux 6.1.44                          |
| 工具链   | Buildroot 内置工具链（glibc，内核头 6.1）  |
| 根文件系统 | ext4（`rootfs.ext2`，128M，可读写）      |
| 控制台   | PL011 串口（`ttyAMA0`）                    |
| 网络     | virtio-net，用户模式网络（DHCP 自动获取）  |

## 构建

```bash
make BOARD=qemu_aarch64
```

构建产物位于 `output/images/`：

- `Image` — Linux 内核镜像
- `rootfs.ext2` — ext4 根文件系统镜像

## 运行

```bash
./br-ext-chip-qemu/board/qemu-aarch64/start-qemu.sh
```

前提：宿主机已安装 QEMU（`sudo apt-get install qemu-system-arm`）。

- 启动后进入串口控制台，root 登录（密码与 DarkOS 标准 overlay 一致）
- SSH 访问：`ssh -p 2222 root@127.0.0.1`（hostfwd 已映射 2222 → 22）
- 退出模拟器：先按 `Ctrl+A`，再按 `X`

## 说明

- 全局补丁目录使用 `all-patches-neo`：`all-patches` 中的 linux 补丁针对
  厂商旧内核（4.19 时代），无法应用于主线 6.x 内核。
- 该平台不产生固件打包产物（无 NOR/NAND 分区概念），`make` 的 repack
  阶段自动跳过，镜像直接由 QEMU 加载。
