# AArch64 与 AArch32 的区别

本文记录 QEMU 模拟平台相关的 ARM 架构术语与差异。项目目前仅提供
`qemu_aarch64` 一个模拟平台；本文同时保留了曾经尝试的 32 位
（AArch32）平台的调研结论与放弃原因，供后续参考。

## 术语对应关系

ARM 只有两种执行状态（Execution State），下列各组名称指的是同一样东西：

| ARM 官方术语 | 业界习惯叫法 | 含义                          |
|--------------|--------------|-------------------------------|
| AArch64      | arm64        | 64 位执行状态（A64 指令集）   |
| AArch32      | arm32        | 32 位执行状态（A32/T32 指令集）|

- **aarch64 = arm64**：`aarch64` 是 ARM 官方、Linux 内核（`arch/arm64/`）、
  GNU 工具链（`aarch64-linux-gnu`）使用的名字；`arm64` 是 Debian/Ubuntu
  的包架构名。不存在第三种 "arm64" 状态。
- **aarch32 ≈ arm32**：严格说 `AArch32` 是 ARMv8 引入的术语，特指 v8 核上
  的 32 位执行状态（兼容 ARMv7-A）；`arm32` 是泛称，还包括 ARMv5/v6/v7
  这些没有 64 位能力的老架构。两者用户态 ABI 一致。

## 本质区别

| 项目       | AArch64                          | AArch32                              |
|------------|----------------------------------|--------------------------------------|
| 寄存器     | 31 个 64 位通用寄存器（x0–x30）  | 15 个 32 位寄存器（r0–r14）          |
| 指令集     | A64（全新定长指令）              | A32/T32（ARM/Thumb-2，延续自 v7）    |
| 寻址空间   | 64 位虚拟地址                    | 单进程最多约 3GB 可用                |
| 工具链前缀 | `aarch64-buildroot-linux-gnu`    | `arm-buildroot-linux-gnueabihf`      |
| 兼容性     | 64 位内核可跑 64 位和 32 位（compat）用户空间 | 32 位内核只能跑 32 位用户空间 |

取舍：AArch64 寄存器多、性能更好；AArch32 指针占 4 字节、更省内存，
因此小内存摄像头 SoC（如 rv1126 的 Cortex-A7）至今仍使用 32 位系统。

## 内核镜像格式：zImage 与 Image

两种架构的内核产物文件名不同（arm32 为 `zImage`，aarch64 为 `Image`），
这是两种架构**内核启动协议（boot protocol）设计不同**导致的：

- **arm32 的 zImage 是自解压内核**：32 位 ARM 诞生于 bootloader 功能极简
  的时代，bootloader 只负责把内核二进制拷到固定物理地址（通常是 RAM 起始
  +0x8000）然后跳转。因此内核必须"自助"：`zImage` = 一小段解压 stub
  （`arch/arm/boot/compressed/`）+ 压缩过的 vmlinux，启动后先自解压到
  正确位置，再进入真正的内核入口。压缩还顺带解决了早期 Flash 小、
  加载慢的问题。
- **aarch64 的 Image 是"加载器负责制"**：ARM64 制定新启动协议
  （`Documentation/arch/arm64/booting.rst`）时，U-Boot/UEFI/GRUB 等
  加载器已经普及，于是协议把内核做成不带解压 stub 的裸二进制：`Image`
  就是 vmlinux 加一个 64 字节头部（含 `ARM\x64` 魔数），由加载器负责
  放置到对齐地址、关 MMU、直接跳入。想要压缩也可以（`Image.gz`），
  但解压是加载器的工作，内核自身不参与。

对应到本项目：

- QEMU 的 `-kernel` 直接启动对两种协议都有实现：arm32 时加载 zImage
  后直接跳转；aarch64 时按 arm64 协议加载 Image（传入 `Image.gz` 等
  压缩格式时由 QEMU 先行解压）。
- Buildroot 默认值随架构走：arm → `BR2_LINUX_KERNEL_ZIMAGE=y`，
  arm64 → `Image`。`qemu_aarch64` 的启动脚本引用 `Image`，匹配 QEMU
  对 arm64 的加载预期。
- 补充：arm32 也能构建裸 `Image` 和带 U-Boot 头的 `uImage`，zImage
  只是无 bootloader 场景下最省事的通用选择；aarch64 则没有 zImage
  这个产物。

## 附：32 位（AArch32）模拟平台的尝试与放弃原因

曾提供过 `qemu_arm32` 配置（`virt` 机器 + Cortex-A53 AArch32），
构建产物完全正常，但在宿主机 QEMU 6.2（Ubuntu 22.04）上无法运行，
实测结论：

| 组合                                             | 结果                     |
|--------------------------------------------------|--------------------------|
| `qemu-system-arm` + cortex-a53                   | 二进制不含该 CPU 型号    |
| `qemu-system-aarch64` 6.2 + cortex-a53 + 32 位 zImage | 静默不启动（无 guest error） |
| `qemu-system-arm` + cortex-a15 + 32 位 zImage    | 内核正常启动             |

不能改用 cortex-a15/a7 凑合的原因：用户空间按 cortex-a53（ARMv8-A
AArch32）编译，GCC 会生成 v8 特有的原子指令（`ldaex`/`stlex` 等），
在 ARMv7 核上运行会随机 `SIGILL`。

可行但未被采用的方案：

- 启用 `BR2_PACKAGE_HOST_QEMU=y`，由 BSP 自构建 QEMU 8.1 作为模拟器
  （Buildroot 官方 qemu 板级配置的 CI 做法）；
- 或将 32 位平台 CPU 改为 cortex-a7（ARMv7-A，与 rv1126 真实硬件同核），
  内核与用户空间全部按 ARMv7-A 编译后可直接用 `qemu-system-arm` 运行。

若未来需要 32 位模拟平台，可按上述任一路径重建。
