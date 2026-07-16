# ============================================================================
# 基础变量定义
# ============================================================================
# Buildroot 版本及下载地址
BR_VER = 2024.02.10
# 调用 Buildroot 的 make，指定外部扩展目录和输出目录
BR_MAKE = $(MAKE) -C $(TARGET)/buildroot-$(BR_VER) BR2_EXTERNAL=$(PWD)/general O=$(TARGET)
BR_LINK = https://github.com/buildroot/buildroot/archive
BR_FILE = /tmp/buildroot-$(BR_VER).tar.gz
# Buildroot 的 defconfig 文件路径
BR_CONF = $(TARGET)/openipc_defconfig
# 构建输出目录（可被外部覆盖）
TARGET ?= $(PWD)/output
# 兼容旧版 CMake 的 policy 设置
export CMAKE_POLICY_VERSION_MINIMUM := 3.5

# BOARD 未定义时触发错误提示
CONFIG = $(error variable BOARD not defined)
# 记录构建开始时间，用于最后显示耗时
TIMER := $(shell date +%s)

# ----------------------------------------------------------------------------
# 板级配置选择（交互式菜单）
# 如果未通过命令行指定 BOARD 变量，则列出所有可用的 defconfig 供用户选择
# ----------------------------------------------------------------------------
ifeq ($(or $(MAKECMDGOALS), $(BOARD)),)
LIST := $(shell find ./br-ext-*/configs/*_defconfig | sort | \
	sed -E "s/br-ext-chip-(.+).configs.(.+)_defconfig/'\2' '\1 \2'/")
BOARD := $(or $(shell whiptail --title "Available boards" --menu "Select a config:" 20 70 12 \
	--notags $(LIST) 3>&1 1>&2 2>&3),$(CONFIG))
endif

# 根据 BOARD 名称查找对应的 defconfig 文件并包含进来
ifneq ($(BOARD),)
CONFIG := $(shell find br-ext-*/configs/*_defconfig | grep -m1 $(BOARD))
include $(CONFIG)
endif

# repack 目标需要引入 BR_CONF 中的配置变量
ifneq ($(filter repack,$(MAKECMDGOALS)),)
-include $(BR_CONF)
endif

# ============================================================================
# 主构建目标
# ============================================================================

# 默认目标：完整构建 + 固件打包，显示构建耗时
all: repack-final timer

# 完整构建：生成 defconfig 后调用 Buildroot 编译
build: defconfig
	@$(BR_MAKE) all -j$(shell nproc)

# 通用 Buildroot target 转发（如 br-linux-menuconfig、br-busybox 等）
br-%: defconfig
	@$(BR_MAKE) $(subst br-,,$@) -j$(shell nproc)

# ----------------------------------------------------------------------------
# 生成 Buildroot 的 defconfig
#   - 将板级 defconfig 与通用 openipc.fragment 合并
#   - 补丁目录和 rootfs overlay 配置也会一并追加
# ----------------------------------------------------------------------------
defconfig: prepare
	@echo --- $(or $(CONFIG),$(error variable BOARD not found))
	@cat $(CONFIG) $(PWD)/general/openipc.fragment > $(BR_CONF)
	@grep -s '^BR2_GLOBAL_PATCH_DIR=' $(CONFIG) >> $(BR_CONF) || true
	@grep -s '^BR2_ROOTFS_OVERLAY=' $(CONFIG) >> $(BR_CONF) || true
	@$(BR_MAKE) BR2_DEFCONFIG=$(BR_CONF) defconfig

# ----------------------------------------------------------------------------
# 准备阶段：下载并解压 Buildroot
#   - 如果 output 目录下没有 buildroot，则下载指定版本的源码包并解压
#   - 同时将 openipc 的 linux 扩展配置注入到 Buildroot 的 linux Config.in 中
# ----------------------------------------------------------------------------
prepare:
	@if test ! -e $(TARGET)/buildroot-$(BR_VER); then \
		wget -c -q $(BR_LINK)/$(BR_VER).tar.gz -O $(BR_FILE); \
		mkdir -p $(TARGET); tar -xf $(BR_FILE) -C $(TARGET); fi
	@if test -f $(TARGET)/buildroot-$(BR_VER)/linux/Config.in; then \
		sed -i '/source "$$(BR2_EXTERNAL_GENERAL_PATH)\/linux\/Config.ext.in"/d' \
			$(TARGET)/buildroot-$(BR_VER)/linux/Config.in; \
		grep -qF 'source "$$BR2_EXTERNAL_GENERAL_PATH/linux/Config.ext.in"' \
			$(TARGET)/buildroot-$(BR_VER)/linux/Config.in || \
		sed -i '/source "linux\/Config.ext.in"/a source "$$BR2_EXTERNAL_GENERAL_PATH/linux/Config.ext.in"' \
			$(TARGET)/buildroot-$(BR_VER)/linux/Config.in; \
	fi

# ============================================================================
# 辅助工具目标
# ============================================================================

# 显示使用帮助
help:
	@printf "BR-OpenIPC usage:\n \
	- make list - show available device configurations\n \
	- make deps - install build dependencies\n \
	- make clean - remove defconfig and target folder\n \
	- make package - list available packages\n \
	- make distclean - remove buildroot and output folder\n \
	- make br-linux - build linux kernel only\n\n"

# 列出所有可用的板级 defconfig
list:
	@ls -1 br-ext-chip-*/configs

# 列出 general/package 下的所有可用包名（以 br- 为前缀）
package:
	@find $(PWD)/general/package/* -maxdepth 0 -type d -printf "br-%f\n" | grep -v patch

# 显示外部工具链名称
toolname:
	@echo toolchain.$(BR2_OPENIPC_SOC_VENDOR)-$(BR2_OPENIPC_SOC_FAMILY)

# 清理构建产物（保留 buildroot 和下载的源码包）
clean:
	@rm -rf $(TARGET)/build $(TARGET)/images $(TARGET)/per-package $(TARGET)/target

# 深度清理：删除 buildroot 源码和整个 output 目录
distclean:
	@rm -rf $(BR_FILE) $(TARGET)

# ABI 审计脚本
audit-abi:
	@python3 $(PWD)/general/scripts/audit-vendor-abi.py

# 安装构建所需的系统依赖
deps:
	sudo apt-get install -y automake autotools-dev bc build-essential cpio \
		curl file fzf git libncurses-dev libtool lzop make rsync unzip wget libssl-dev \
		python3 python3-pip
	# kconfiglib is the only non-stdlib dep added by general/scripts/kconfig_graph.py;
	# install with --break-system-packages on PEP 668 distros (Ubuntu 24.04+, Debian 12+).
	python3 -m pip install --user --break-system-packages kconfiglib

# 显示本次构建的总耗时
timer:
	@echo - Build time: $(shell date -d @$(shell expr $(shell date +%s) - $(TIMER)) -u +%M:%S)

# ============================================================================
# 工具链构建
# ============================================================================

# 构建标准工具链 + SDK
#   1. 如果使用外部工具链，复制 gcc 包定义并生成工具链 defconfig
#   2. 编译 SDK
#   3. 调用 BUNDLE_SDK 整合 OSDRV 驱动、兼容库等资源
toolchain: defconfig
ifeq ($(BR2_TOOLCHAIN_EXTERNAL),y)
	@cp -rf $(PWD)/general/package/gcc $(TARGET)/buildroot-$(BR_VER)/package
	@$(MAKE) -f $(PWD)/general/toolchain.mk BR_CONF=$(BR_CONF) CONFIG=$(PWD)/$(CONFIG)
	@$(BR_MAKE) BR2_DEFCONFIG=$(BR_CONF) defconfig
endif
	@$(BR_MAKE) sdk -j$(shell nproc)
	@$(call BUNDLE_SDK)

# 构建支持 AddressSanitizer (ASan) 的工具链 + SDK
#   相比标准工具链，额外启用了 GCC 的 --enable-libsanitizer 选项
toolchain-asan: defconfig
ifeq ($(BR2_TOOLCHAIN_EXTERNAL),y)
	@cp -rf $(PWD)/general/package/gcc $(TARGET)/buildroot-$(BR_VER)/package
	@$(MAKE) -f $(PWD)/general/toolchain.mk BR_CONF=$(BR_CONF) CONFIG=$(PWD)/$(CONFIG)
	@$(BR_MAKE) BR2_DEFCONFIG=$(BR_CONF) defconfig
endif
	@echo 'BR2_EXTRA_GCC_CONFIG_OPTIONS="--enable-libsanitizer"' >> $(BR_CONF)
	@$(BR_MAKE) BR2_DEFCONFIG=$(BR_CONF) defconfig
	@$(BR_MAKE) sdk -j$(shell nproc)
	@$(call BUNDLE_SDK)

# ============================================================================
# 固件打包
# ============================================================================

# 固件打包入口：先完成构建，再执行打包
repack-final: build
	@$(MAKE) --no-print-directory BOARD=$(BOARD) TARGET=$(TARGET) repack

# 固件打包主流程：根据不同的 ROOTFS / SOC 类型，校验镜像大小并打包
#   PREPARE_REPACK 参数：(kernel镜像, kernel大小上限, rootfs镜像, rootfs大小上限, 固件类型)
#   固件类型包括：nfs-root / nor / nand / initramfs
repack:
# --- NFS Root 模式 ---
ifeq ($(BR2_PACKAGE_OPENIPC_NFS_ROOT),y)
ifeq ($(BR2_OPENIPC_SOC_VENDOR),"rockchip")
	@$(call PREPARE_REPACK,zboot.img,16384,,,nfs-root)
else
	@$(call PREPARE_REPACK,uImage,16384,,,nfs-root)
endif
else
# --- Hisilicon 特殊 SOC（全量 firmware.bin）---
ifeq ($(BR2_OPENIPC_SOC_FAMILY),"hi3516cv6xx")
	@$(call PREPARE_REPACK,firmware.bin,$(shell expr $(subst ",,$(BR2_OPENIPC_FLASH_SIZE)) \* 1024),,,nor)
else ifeq ($(BR2_OPENIPC_SOC_FAMILY),"hi3519dv500")
	@$(call PREPARE_REPACK,firmware.bin,$(shell expr $(subst ",,$(BR2_OPENIPC_FLASH_SIZE)) \* 1024),,,nor)
else ifneq ($(wildcard $(TARGET)/images/firmware.bin),)
	@$(call PREPARE_REPACK,firmware.bin,8192,,,nor)
else
# --- NOR Flash 模式 (SquashFS) ---
ifeq ($(BR2_TARGET_ROOTFS_SQUASHFS),y)
ifeq ($(BR2_OPENIPC_SOC_VENDOR),"rockchip")
	@$(call PREPARE_REPACK,zboot.img,4096,rootfs.squashfs,8192,nor)
else ifeq ($(BR2_OPENIPC_FLASH_SIZE),"8")
	@$(call PREPARE_REPACK,uImage,2048,rootfs.squashfs,5120,nor)
else
	@$(call PREPARE_REPACK,uImage,2048,rootfs.squashfs,8192,nor)
endif
endif
# --- NAND Flash 模式 (UBI) ---
ifeq ($(BR2_TARGET_ROOTFS_UBI),y)
ifneq ($(filter $(BR2_OPENIPC_SOC_VENDOR),"rockchip" "sigmastar"),)
	@$(call PREPARE_REPACK,,,rootfs.ubi,16384,nand)
else
	@$(call PREPARE_REPACK,uImage,4096,rootfs.ubi,16384,nand)
endif
endif
# --- Initramfs 模式 ---
ifeq ($(BR2_TARGET_ROOTFS_INITRAMFS),y)
	@$(call PREPARE_REPACK,uImage,16384,,,initramfs)
endif
endif
endif

# ============================================================================
# 分析报告
# ============================================================================

# 生成固件大小分析报告
size-report:
	@TARGET_DIR=$(TARGET)/target \
	BR2_OUTPUT_DIR=$(TARGET) \
	IMAGES_DIR=$(TARGET)/images \
	OPENIPC_SOC_MODEL=$(BR2_OPENIPC_SOC_MODEL) \
	OPENIPC_VARIANT=$(BR2_OPENIPC_VARIANT) \
	BR2_OPENIPC_FLASH_SIZE=$(BR2_OPENIPC_FLASH_SIZE) \
	BR2_OPENIPC_SOC_VENDOR=$(BR2_OPENIPC_SOC_VENDOR) \
	BR2_TARGET_ROOTFS_SQUASHFS=$(BR2_TARGET_ROOTFS_SQUASHFS) \
	BR2_TARGET_ROOTFS_UBI=$(BR2_TARGET_ROOTFS_UBI) \
	python3 $(PWD)/general/scripts/size_report.py

# 生成 Kconfig 依赖关系图
kconfig-graph:
	@TARGET_DIR=$(TARGET)/target \
	BR2_OUTPUT_DIR=$(TARGET) \
	IMAGES_DIR=$(TARGET)/images \
	OPENIPC_SOC_MODEL=$(BR2_OPENIPC_SOC_MODEL) \
	OPENIPC_VARIANT=$(BR2_OPENIPC_VARIANT) \
	BR_VER=$(BR_VER) \
	PWD=$(PWD) \
	python3 $(PWD)/general/scripts/kconfig_graph.py

# ============================================================================
# 函数定义
# ============================================================================

# ----------------------------------------------------------------------------
# BUNDLE_SDK — 将 OSDRV 驱动、MPP 头文件、兼容库整合到 SDK tar.gz 中
#   1. 找到生成的 SDK tar.gz 包
#   2. 复制 OSDRV 文件到 SDK 目录
#   3. 如果是 hisilicon 平台，补充 MPP 头文件
#   4. 交叉编译 uclibc-compat / glibc-compat 兼容库（动态库 .so + 静态库 .a）
#   5. 将 overlay 追加到 SDK tar.gz 中
# ----------------------------------------------------------------------------
define BUNDLE_SDK
	OSDRV_DIR=$(PWD)/general/package/$(BR2_OPENIPC_SOC_VENDOR)-osdrv-$(BR2_OPENIPC_SOC_FAMILY)/files; \
	MPP_HEADERS=$(PWD)/general/package/hisilicon-osdrv-hi3516cv100/files/include; \
	SDK_TGZ=$$(find $(TARGET)/images -name '*_sdk-buildroot.tar.gz' | head -1); \
	UCLIBC_COMPAT_SRC=$(PWD)/general/package/uclibc-compat/src/uclibc-compat.c; \
	UCLIBC_COMPAT_STATIC=$(PWD)/general/package/uclibc-compat/src/uclibc-compat-static.c; \
	GLIBC_COMPAT_SRC=$(PWD)/general/package/glibc-compat/src/glibc-compat.c; \
	GLIBC_COMPAT_STATIC=$(PWD)/general/package/glibc-compat/src/glibc-compat-static.c; \
	SDK_CC=$$(ls $(TARGET)/host/bin/*-gcc 2>/dev/null | head -1); \
	if [ -d "$$OSDRV_DIR" ] && [ -n "$$SDK_TGZ" ]; then \
		SDK_TOP=$$(tar tzf $$SDK_TGZ | head -1 | cut -d/ -f1); \
		rm -rf /tmp/sdk-overlay && mkdir -p /tmp/sdk-overlay/$$SDK_TOP/sdk; \
		cp -a $$OSDRV_DIR/* /tmp/sdk-overlay/$$SDK_TOP/sdk/; \
		if [ "$(BR2_OPENIPC_SOC_VENDOR)" = "hisilicon" ] && [ ! -d "$$OSDRV_DIR/include" ] && [ -d "$$MPP_HEADERS" ]; then \
			mkdir -p /tmp/sdk-overlay/$$SDK_TOP/sdk/include; \
			cp -a $$MPP_HEADERS/. /tmp/sdk-overlay/$$SDK_TOP/sdk/include/; \
		fi; \
		if [ -n "$$SDK_CC" ]; then \
			SDK_AR=$$(echo $$SDK_CC | sed 's/-gcc$$/-ar/'); \
			if [ -f "$$UCLIBC_COMPAT_SRC" ]; then \
				$$SDK_CC -shared -Wall -O2 -fPIC \
					-o /tmp/sdk-overlay/$$SDK_TOP/sdk/lib/libuclibc-compat.so \
					$$UCLIBC_COMPAT_SRC; \
			fi; \
			if [ -f "$$UCLIBC_COMPAT_STATIC" ]; then \
				$$SDK_CC -Wall -O2 -fPIC -c \
					-o /tmp/sdk-overlay/$$SDK_TOP/sdk/lib/uclibc-compat-static.o \
					$$UCLIBC_COMPAT_STATIC; \
				$$SDK_AR rcs /tmp/sdk-overlay/$$SDK_TOP/sdk/lib/libuclibc-compat-static.a \
					/tmp/sdk-overlay/$$SDK_TOP/sdk/lib/uclibc-compat-static.o; \
				rm -f /tmp/sdk-overlay/$$SDK_TOP/sdk/lib/uclibc-compat-static.o; \
			fi; \
			if [ -f "$$GLIBC_COMPAT_SRC" ]; then \
				$$SDK_CC -shared -Wall -O2 -fPIC \
					-o /tmp/sdk-overlay/$$SDK_TOP/sdk/lib/libglibc-compat.so \
					$$GLIBC_COMPAT_SRC; \
			fi; \
			if [ -f "$$GLIBC_COMPAT_STATIC" ]; then \
				$$SDK_CC -Wall -O2 -fPIC -c \
					-o /tmp/sdk-overlay/$$SDK_TOP/sdk/lib/glibc-compat-static.o \
					$$GLIBC_COMPAT_STATIC; \
				$$SDK_AR rcs /tmp/sdk-overlay/$$SDK_TOP/sdk/lib/libglibc-compat-static.a \
					/tmp/sdk-overlay/$$SDK_TOP/sdk/lib/glibc-compat-static.o; \
				rm -f /tmp/sdk-overlay/$$SDK_TOP/sdk/lib/glibc-compat-static.o; \
			fi; \
		fi; \
		gunzip $$SDK_TGZ && \
		tar rf $${SDK_TGZ%.tar.gz}.tar -C /tmp/sdk-overlay $$SDK_TOP && \
		gzip $${SDK_TGZ%.tar.gz}.tar; \
		rm -rf /tmp/sdk-overlay; \
	fi
endef

# ----------------------------------------------------------------------------
# PREPARE_REPACK — 固件打包流程（校验 + 重打包）
#   参数：(1) kernel 镜像名  (2) kernel 大小上限(KB)
#         (3) rootfs 镜像名  (4) rootfs 大小上限(KB)
#         (5) 固件类型标签（nor / nand / nfs-root / initramfs）
# ----------------------------------------------------------------------------
define PREPARE_REPACK
	$(if $(1),$(call CHECK_SIZE,$(1),$(2)))
	$(if $(3),$(call CHECK_SIZE,$(3),$(4)))
	$(call REPACK_FIRMWARE,$(1),$(3),$(5))
endef

# ----------------------------------------------------------------------------
# CHECK_SIZE — 校验镜像文件大小是否超出分区上限
#   如果文件大小为 0 或超出限制，则报错退出
# ----------------------------------------------------------------------------
define CHECK_SIZE
	$(eval FILE_SIZE = $(shell expr $(shell stat -c %s $(TARGET)/images/$(1) || echo 0) / 1024))
	if test $(FILE_SIZE) -eq 0; then exit 1; fi
	echo - $(1): [$(FILE_SIZE)KB/$(2)KB]
	if test $(FILE_SIZE) -gt $(2); then \
		echo -- size exceeded by: $(shell expr $(FILE_SIZE) - $(2))KB; exit 1; fi
endef

# ----------------------------------------------------------------------------
# REPACK_FIRMWARE — 将 kernel 和 rootfs 镜像重命名、生成 MD5 校验、打包为 tgz
#   1. 将 rootfs.tar 重命名为带 SOC 型号后缀的文件
#   2. 将 kernel / rootfs 镜像文件重命名为带 SOC 型号后缀
#   3. 生成对应的 md5sum 文件
#   4. 将所有文件打包为 openipc.<型号>-<类型>-<变体>.tgz
#   5. 清理临时 md5sum 文件
# ----------------------------------------------------------------------------
define REPACK_FIRMWARE
	cd $(TARGET)/images && if test -e rootfs.tar; then mv -f rootfs.tar rootfs.$(BR2_OPENIPC_SOC_MODEL).tar; fi
	$(if $(1),cd $(TARGET)/images && if test -e $(1); then mv -f $(1) $(1).$(BR2_OPENIPC_SOC_MODEL); fi)
	$(if $(2),cd $(TARGET)/images && if test -e $(2); then mv -f $(2) $(2).$(BR2_OPENIPC_SOC_MODEL); fi)
	$(if $(1),cd $(TARGET)/images && md5sum $(1).$(BR2_OPENIPC_SOC_MODEL) > $(1).$(BR2_OPENIPC_SOC_MODEL).md5sum)
	$(if $(2),cd $(TARGET)/images && md5sum $(2).$(BR2_OPENIPC_SOC_MODEL) > $(2).$(BR2_OPENIPC_SOC_MODEL).md5sum)
	$(if $(1),$(eval KERNEL = $(1).$(BR2_OPENIPC_SOC_MODEL) $(1).$(BR2_OPENIPC_SOC_MODEL).md5sum),$(eval KERNEL =))
	$(if $(2),$(eval ROOTFS = $(2).$(BR2_OPENIPC_SOC_MODEL) $(2).$(BR2_OPENIPC_SOC_MODEL).md5sum),$(eval ROOTFS =))
	$(eval ARCHIVE = openipc.$(BR2_OPENIPC_SOC_MODEL)-$(3)-$(BR2_OPENIPC_VARIANT).tgz)
	cd $(TARGET)/images && tar -czf $(ARCHIVE) $(KERNEL) $(ROOTFS)
	rm -f $(TARGET)/images/*.md5sum
endef
