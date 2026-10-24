# RK3568B2 板级支持 —— 构建入口
#
# 常见用法：
#   make deps                 检查编译依赖
#   make install              把板级文件装进 SDK
#   make check                只编 dtb（秒级，验证设备树）
#   make kernel               编内核
#   make image                全量编译并打包 update.img
#   make clean                清理 buildroot 输出（下次全量重编）
#
# 覆盖 SDK 路径：
#   make image SDK=/path/to/sdk

SDK ?= $(HOME)/rk3568-sdk
SERIAL_PORT ?= /dev/ttyUSB0
SERIAL_BAUD ?= 1500000
LOG  ?= serial.log

REPO_DIR  := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
NAME      := rk3568-myboard-v10
DEPS_BIN  := $(HOME)/.local/opt/sdk-deps/bin
IMAGE     := $(SDK)/output/update/Image/update.img
LOADER    := $(SDK)/u-boot/rk356x_spl_loader_v1.25.114.bin
UT        := $(SDK)/tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool

# 依赖工具解压在用户目录时自动挂到 PATH 前面
ifneq ($(wildcard $(DEPS_BIN)),)
export PATH := $(DEPS_BIN):$(PATH)
endif

.DEFAULT_GOAL := help
.PHONY: help deps install check kernel uboot buildroot image firmware clean distclean flash serial

help:
	@echo "RK3568B2 板级支持"
	@echo ""
	@echo "  make deps        检查主机依赖"
	@echo "  make install     安装板级文件到 SDK ($(SDK))"
	@echo "  make check       只编译 dtb，验证设备树语法"
	@echo "  make kernel      编译内核"
	@echo "  make uboot       编译 u-boot"
	@echo "  make buildroot   编译根文件系统"
	@echo "  make firmware    打包 boot/uboot/loader"
	@echo "  make image       全量编译并生成 update.img"
	@echo "  make clean       清理 buildroot 输出（下次全量重编）"
	@echo "  make flash       烧录到板子（需 MaskROM + upgrade_tool）"
	@echo "  make serial      打开串口监视器 ($(SERIAL_PORT) @ $(SERIAL_BAUD))"
	@echo "                   可覆盖：make serial SERIAL_PORT=/dev/ttyACM0 SERIAL_BAUD=115200"
	@echo ""
	@echo "  当前 SDK: $(SDK)"

# ---------- 前置检查 ----------
# 路径含非 ASCII 时 buildroot 会把路径解析成 ??????，
# 这里提前 1 秒拦住，而不是等 40 分钟。
define ensure_sdk
	@test -d "$(SDK)" || { \
		echo "❌ SDK 目录不存在: $(SDK)"; \
		echo "   用 make SDK=/path/to/sdk 指定"; exit 1; }
	@if printf '%s' "$(SDK)" | LC_ALL=C grep -q '[^ -~]'; then \
		echo "❌ SDK 路径含非 ASCII 字符: $(SDK)"; \
		echo "   buildroot 内部 LC_ALL=C，会报 could not create directory '??????'"; \
		echo "   请移到纯英文路径，例如 ~/rk3568-sdk"; exit 1; fi
	@test -d "$(SDK)/kernel-6.1" || { \
		echo "❌ $(SDK) 不像 SDK 根目录（缺 kernel-6.1）"; exit 1; }
endef

deps:
	@miss=0; \
	for c in python python3 make gcc flex bison bc dtc msgmerge makeinfo gawk \
	         cmake chrpath patchelf diffstat lz4 zstd; do \
		if ! command -v $$c >/dev/null 2>&1; then \
			echo "  ❌ $$c"; miss=1; \
		else \
			echo "  ✅ $$c"; \
		fi; \
	done; \
	echo ""; \
	if [ $$miss -eq 1 ]; then \
		echo "缺依赖，Ubuntu 下可执行："; \
		echo "  sudo apt-get install -y python-is-python3 gettext texinfo gawk \\"; \
		echo "       cmake chrpath patchelf expect diffstat lz4 device-tree-compiler"; \
		exit 1; \
	fi; \
	echo "依赖齐全"

# ---------- 板级文件 ----------
install:
	@$(call ensure_sdk)
	@./apply-to-sdk.sh "$(SDK)" | sed 's/^/  /'

check:
	@$(call ensure_sdk)
	@./apply-to-sdk.sh "$(SDK)" --build 2>&1 | tail -5

# ---------- 构建 ----------
kernel: install
	@echo "==> 编译内核"
	@cd "$(SDK)" && ./build.sh kernel

uboot: install
	@echo "==> 编译 u-boot"
	@cd "$(SDK)" && ./build.sh uboot

buildroot: install
	@echo "==> 编译 buildroot（首次约 40 分钟）"
	@cd "$(SDK)" && ./build.sh buildroot

firmware:
	@cd "$(SDK)" && ./build.sh firmware

image: install
	@echo "==> 全量编译（kernel + uboot + buildroot + update.img）"
	@cd "$(SDK)" && ./build.sh all
	@echo ""
	@ls -lh "$(IMAGE)" 2>/dev/null || true
	@echo "产物: $(IMAGE)"

serial:
	@python3 scripts/serial_monitor.py -p $(SERIAL_PORT) -b $(SERIAL_BAUD) -l $(LOG)

# ---------- 清理与烧录 ----------
clean:
	@test -d "$(SDK)/buildroot/output" && rm -rf "$(SDK)/buildroot/output" || true
	@echo "已清理 buildroot 输出（下次 make image 将全量重编）"

distclean: clean
	@rm -rf "$(SDK)/output" "$(SDK)/rockdev"
	@echo "已清理 SDK output/ 与 rockdev/（会丢失 lunch 选择）"

# Rockchip 官方流程：MaskROM → db 下 boot → ssd 选存储 → uf 烧固件
# 本板无 eMMC，存储固定选 SD（ssd 列表里的 No=3）
# 不需要 sudo：/etc/udev/rules.d/99-rockchip-usb.rules 已把 VID 2207 设为 0666
STORAGE_NO ?= 3
flash:
	@test -f "$(IMAGE)" || { echo "❌ 还没有 $(IMAGE)，先 make image"; exit 1; }
	@test -x "$(UT)"    || { echo "❌ 找不到 upgrade_tool: $(UT)"; exit 1; }
	@echo "0) 当前连接的 rockusb 设备："
	@"$(UT)" ld
	@echo ""
	@echo "   列表为 0 时：板子断电 → USB OTG 接电脑 → 上电（无启动介质会自动进 MaskROM）"
	@echo "   'Download IDB Fail' 多为 USB 供电/线材问题，换直连口和短线再试"
	@echo ""
	@echo "1) 下载 boot（MaskROM 下必须先做这步才能通讯）"
	@"$(UT)" db "$(LOADER)"
	@echo ""
	@echo "2) 选择存储 = SD（No=$(STORAGE_NO)）"
	@echo "$(STORAGE_NO)" | "$(UT)" ssd
	@echo ""
	@echo "3) 烧录固件（会擦掉 SD 上所有分区，rootfs 一并换成干净的 ext4）"
	@"$(UT)" uf "$(IMAGE)"
