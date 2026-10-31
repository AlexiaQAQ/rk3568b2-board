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
NAME      := rk3568-board-v10
DEPS_BIN  := $(HOME)/.local/opt/sdk-deps/bin
IMAGE     := $(SDK)/output/update/Image/update.img
LOADER    := $(SDK)/u-boot/rk356x_spl_loader_v1.25.114.bin
UT        := $(SDK)/tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool

# 依赖工具解压在用户目录时自动挂到 PATH 前面
ifneq ($(wildcard $(DEPS_BIN)),)
export PATH := $(DEPS_BIN):$(PATH)
endif

.DEFAULT_GOAL := help
.PHONY: help deps install uninstall check kernel uboot buildroot image firmware clean distclean flash flash-di flash-wl serial

help:
	@echo "RK3568B2 板级支持"
	@echo ""
	@echo "  make deps        检查主机依赖"
	@echo "  make install     安装板级文件到 SDK ($(SDK))"
	@echo "  make uninstall   从 SDK 移除板级文件"
	@echo "  make check       只编译 dtb，验证设备树语法"
	@echo "  make kernel      编译内核 + dtb → boot.img"
	@echo "  make uboot       编译 u-boot"
	@echo "  make buildroot   编译根文件系统（需联网/镜像）"
	@echo "  make firmware    组装 update.img（不重编 rootfs）"
	@echo "  make image       kernel + firmware（推荐）"
	@echo "  make clean       清理 buildroot 输出（下次全量重编）"
	@echo "  make distclean   再清理 SDK output/"
	@echo "  make flash       烧录整包（MaskROM + upgrade_tool，含 IDB）"
	@echo "  make flash-di    只写 uboot/boot/rootfs 分区，跳过 IDB（IDB 写失败时用）"
	@echo "  make flash-wl    按扇区直写，绕开分区表（最底层退路）"
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

uninstall:
	@$(call ensure_sdk)
	@./scripts/uninstall-from-sdk.sh "$(SDK)"

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

# 注意：不用 ./build.sh all —— 它会从 sources.buildroot.net 下载所有软件包，
# 国内经常超时，而且前面跑完 kernel/uboot 也白等。
# 分成 kernel + firmware 两步即可；要重建 rootfs 请单独 make buildroot。
image: install
	@echo "==> 编译内核"
	@cd "$(SDK)" && ./build.sh kernel
	@echo "==> 组装固件"
	@cd "$(SDK)" && ./build.sh firmware
	@echo ""
	@ls -lh "$(IMAGE)" 2>/dev/null || true
	@echo "产物: $(IMAGE)"

serial:
	@python3 scripts/serial_monitor.py -p $(SERIAL_PORT) -b $(SERIAL_BAUD) -l $(LOG)

# ---------- 清理与烧录 ----------
clean:
	@if [ -d "$(SDK)/buildroot/output" ]; then \
		echo "删除 $(SDK)/buildroot/output（$$(du -sh $(SDK)/buildroot/output 2>/dev/null | cut -f1)）"; \
		rm -rf "$(SDK)/buildroot/output"; \
	fi
	@echo "已清理 buildroot 输出（下次 make buildroot 将全量重编）"

distclean: clean
	@rm -rf "$(SDK)/output" "$(SDK)/rockdev"
	@echo "已清理 SDK output/ 与 rockdev/（会丢失 lunch 选择）"

# Rockchip 官方流程：MaskROM → db 下 boot → ssd 选存储 → uf 烧固件
# 本板从 eMMC 启动，ssd 时选 2（EMMC）；SD 卡是 3
# 不需要 sudo：/etc/udev/rules.d/99-rockchip-usb.rules 已把 VID 2207 设为 0666
#
# 注意：ssd 只能交互输入。用 echo 2 | upgrade_tool ssd 会因为拿不到 tty 直接
# 返回 "Switch Storage failed!"（它内部要做终端处理），别再试管道了。
flash:
	@test -f "$(IMAGE)" || { echo "❌ 还没有 $(IMAGE)，先 make image"; exit 1; }
	@test -x "$(UT)"    || { echo "❌ 找不到 upgrade_tool: $(UT)"; exit 1; }
	@echo "0) 当前连接的 rockusb 设备："
	@"$(UT)" ld
	@echo ""
	@echo "   列表为 0 时：板子断电 → USB OTG 接电脑 → 上电（无启动介质会自动进 MaskROM）"
	@echo ""
	@echo "1) 下载 boot（MaskROM 下必须先做这步才能通讯）"
	@"$(UT)" db "$(LOADER)"
	@echo ""
	@echo "2) 选择存储 —— 输入 2（EMMC）；SD 备选输入 3"
	@"$(UT)" ssd
	@echo ""
	@echo "3) 烧录固件（会擦掉 SD 上所有分区，rootfs 一并换成干净的 ext4）"
	@"$(UT)" uf "$(IMAGE)"

# uf 会先写 IDB（idblock），这颗卡/这套 SD 写通路在 IDB 阶段就失败：
#   Prepare IDB Success → Download IDB Fail
# 但卡上的 IDB 本来是好的（能正常启动），只是要换 boot/rootfs。
# 所以改用 di 逐分区写，完全不碰 IDB。
FW := $(SDK)/output/firmware
PARAM := $(SDK)/device/rockchip/.chips/rk3566_rk3568/parameter-buildroot-fit.txt
flash-di:
	@test -x "$(UT)" || { echo "❌ 找不到 upgrade_tool: $(UT)"; exit 1; }
	@test -f "$(FW)/rootfs.img" || { echo "❌ 还没有 $(FW)/rootfs.img，先 make image"; exit 1; }
	@echo "0) 确认设备在 MaskROM："
	@"$(UT)" ld
	@echo ""
	@"$(UT)" db "$(LOADER)"
	@echo ""
	@echo "1) 选择存储 —— 输入 2（EMMC）"
	@"$(UT)" ssd
	@echo ""
	@echo "2) 逐分区写入（不写 IDB，卡能启动就行）"
	@echo "   2.1 先下发 parameter，不然 di 会报 'parameter is invalid'"
	@"$(UT)" di -p "$(PARAM)"
	@echo "   2.2 uboot / boot / rootfs"
	@"$(UT)" di -u "$(FW)/uboot.img"
	@"$(UT)" di -b "$(FW)/boot.img"
	@"$(UT)" di -s "$(FW)/rootfs.img"
	@echo ""
	@echo "3) 复位"
	@"$(UT)" rd

# 最底层的退路：绕开分区表和 parameter，直接按扇区写。
# 偏移来自 parameter-buildroot-fit.txt 的 CMDLINE（单位 512B 扇区）：
#   uboot  0x00002000@0x00004000  → 扇区 16384
#   boot   0x00020000@0x00008000  → 扇区 32768
#   rootfs 0x01800000@0x00078000  → 扇区 491520
UBOOT_SEC  := 16384
BOOT_SEC   := 32768
ROOTFS_SEC := 491520
flash-wl:
	@test -x "$(UT)" || { echo "❌ 找不到 upgrade_tool: $(UT)"; exit 1; }
	@"$(UT)" ld
	@"$(UT)" db "$(LOADER)"
	@echo "选择存储 —— 输入 2（EMMC）"
	@"$(UT)" ssd
	@echo "按扇区直写（不碰 IDB / GPT）"
	@"$(UT)" wl $(UBOOT_SEC)  "$(FW)/uboot.img"
	@"$(UT)" wl $(BOOT_SEC)   "$(FW)/boot.img"
	@"$(UT)" wl $(ROOTFS_SEC) "$(FW)/rootfs.img"
	@"$(UT)" rd
