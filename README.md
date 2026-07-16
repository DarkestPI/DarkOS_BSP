# DarkOS BSP

DarkOS 的板级支持包（BSP），基于 [Buildroot](https://buildroot.org/) 构建的嵌入式 Linux 系统，专为 IP 摄像头 SoC 平台优化。

## 支持的平台

### 全志（Allwinner）
| SoC   | 配置                              |
|-------|-----------------------------------|
| v83x  | `v83x_lite`, `v83x_ultimate`      |
| v851s | `v851s_lite`                      |

### 瑞芯微（Rockchip）
| SoC      | 配置                                                                 |
|----------|----------------------------------------------------------------------|
| rv1103   | `rv1103_lite`                                                        |
| rv1106   | `rv1106_lite`                                                        |
| rv1109   | `rv1109_lite`                                                        |
| rv1126   | `rv1126_lite`, `rv1126_mini`                                         |
| rv1126b  | `rv1126b_mini`                                                       |

## 快速开始

### 环境要求

- Linux 构建主机（推荐 Ubuntu 22.04+）
- 基本构建工具链：`wget`, `make`, `gcc`, `g++`, `perl`, `bison`, `flex` 等

### 安装依赖

```bash
make deps
```

### 编译

选择目标板卡并构建完整系统：

```bash
make BOARD=<board_config>
```

例如编译 `rv1126_mini`：

```bash
make BOARD=rv1126_mini
```

如果未指定 `BOARD`，Makefile 会通过交互式菜单提示选择可用的板卡配置。

### 其他构建命令

```bash
make list          # 列出所有可用的板卡配置
make br-linux      # 仅编译 Linux 内核
make package       # 列出可用软件包
make clean         # 清理构建产物（保留 Buildroot 源码）
make distclean     # 完全清理（包括 Buildroot 源码）
make help          # 查看帮助信息
```

## 目录结构

```
DarkOS_BSP/
├── br-ext-chip-allwinner/   # 全志平台板卡配置
│   ├── board/               #   板级配置文件
│   └── configs/             #   Buildroot defconfig
├── br-ext-chip-rockchip/    # 瑞芯微平台板卡配置
│   ├── board/               #   板级配置文件
│   └── configs/             #   Buildroot defconfig
├── general/                 # 通用 Buildroot external tree
│   ├── overlay/             #   根文件系统覆盖层（init 脚本、网络配置等）
│   ├── package/             #   自定义软件包
│   ├── linux/               #   Linux 内核扩展配置
│   └── openipc.fragment     #   通用 Buildroot 配置片段
├── rockchip-tools/          # 瑞芯微打包工具
├── contrib/                 # 辅助脚本和工具
├── .github/                 # CI/CD 工作流
└── Makefile                 # 顶层构建入口
```

## 特性

- **Buildroot 2024.02.10** 构建系统
- 基于 OpenIPC 的固件框架
- 支持以太网、Wi-Fi、4G 等多种网络接口
- 内置 Dropbear SSH、WireGuard、ntpd、crond 等服务
- 自动挂载外接存储设备
- OTA 固件升级支持
- 模块化构建，支持按板卡定制

## CI/CD

通过 GitHub Actions 支持自动化构建和固件打包（`demo.yml`），可手动触发编译并生成 `update.img` 产物。

## 许可证

基于 OpenIPC 项目，遵循相关开源协议。

## 贡献者
