#!/bin/bash
# 把 board-port 里的板级文件装进 SDK，并单独编译 dtb 做语法/引用校验
#
# 用法：
#   ./apply-to-sdk.sh /path/to/extracted_sdk          # 只安装
#   ./apply-to-sdk.sh /path/to/extracted_sdk --build  # 安装并编译 dtb
set -euo pipefail

SDK="${1:-}"
if [ -z "$SDK" ]; then
	echo "用法: $0 <SDK根目录> [--build]"
	exit 1
fi
SDK="$(cd "$SDK" && pwd)"          # 转成绝对路径，后面要 cd 进内核目录
[ -d "$SDK/kernel-6.1" ] || { echo "错误: $SDK 下没有 kernel-6.1"; exit 1; }

PORT="$(cd "$(dirname "$0")" && pwd)"
CHIP_DIR="$SDK/device/rockchip/rk3566_rk3568"
DTS_DIR="$SDK/kernel-6.1/arch/arm64/boot/dts/rockchip"
NAME="rk3568-board-v10"

echo "[1/5] 安装设备树 -> $DTS_DIR/$NAME.dts"
cp "$PORT/$NAME.dts" "$DTS_DIR/"

echo "[2/5] 安装 defconfig -> $CHIP_DIR"
cp "$PORT/rockchip_rk3568_board_v10_defconfig" "$CHIP_DIR/"

echo "[3/5] 打 u-boot 补丁（默认 bootargs）"
UB="$SDK/u-boot"
if [ -d "$UB/.git" ] && ! grep -q "root=PARTUUID=614e0000-0000-4b53" "$UB/include/configs/rk3568_common.h"; then
	(cd "$UB" && git apply "$PORT/patch/0003-u-boot-default-bootargs.patch") && echo "      已应用"
else
	echo "      已存在或非 git 仓库，跳过"
fi

echo "[3.5/5] 打内核补丁（电源域失败不 panic）"
K="$SDK/kernel-6.1"
if [ -d "$K/.git" ] && grep -q 'panic("panic_on_set_idle' "$K/drivers/soc/rockchip/pm_domains.c" 2>/dev/null; then
	(cd "$K" && git apply "$PORT/patch/0004-kernel-pm-domain-no-panic.patch") && echo "      已应用"
else
	echo "      已存在或非 git 仓库，跳过"
fi

echo "[3.6/5] 打开 CONFIG_DRM_IGNORE_IOTCL_PERMIT（SDK 打包脚本强制要求）"
FRAG="$K/arch/arm64/configs/rk3568.config"
if grep -q '^CONFIG_DRM_IGNORE_IOTCL_PERMIT=y' "$FRAG" 2>/dev/null; then
	echo "      已存在，跳过"
else
	printf '\nCONFIG_DRM_IGNORE_IOTCL_PERMIT=y\n' >> "$FRAG"
	echo "      已追加到 rk3568.config"
fi

echo "[3.7/5] bcmdhd 改用 SDIO 带内中断（不依赖 WL_HOST_WAKE）"
BCM_MK="$K/drivers/net/wireless/rockchip_wlan/rkwifi/bcmdhd/Makefile"
if grep -q '^CONFIG_BCMDHD_OOB := y' "$BCM_MK" 2>/dev/null; then
	(cd "$K" && git apply "$PORT/patch/0006-bcmdhd-inband-irq.patch") 2>/dev/null \
		|| sed -i 's/^CONFIG_BCMDHD_OOB := y/CONFIG_BCMDHD_OOB := n/' "$BCM_MK"
	echo "      已改为 n（走 -DSDIO_ISR_THREAD）"
else
	echo "      已存在，跳过"
fi

echo "[4/5] 注册到 Makefile"
if grep -q "$NAME.dtb" "$DTS_DIR/Makefile"; then
	echo "      已存在，跳过"
else
	echo "dtb-\$(CONFIG_ARCH_ROCKCHIP) += $NAME.dtb" >> "$DTS_DIR/Makefile"
	echo "      已追加"
fi

if [ "${2:-}" != "--build" ]; then
	echo "[5/5] 跳过编译（加 --build 可编译验证）"
	exit 0
fi

echo "[5/5] 编译 dtb 验证"
CROSS="$SDK/prebuilts/gcc/linux-x86/aarch64/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-"
[ -x "${CROSS}gcc" ] || CROSS="aarch64-linux-gnu-"

cd "$SDK/kernel-6.1"
make ARCH=arm64 CROSS_COMPILE="$CROSS" rockchip_linux_defconfig
make ARCH=arm64 CROSS_COMPILE="$CROSS" \
	"rockchip/$NAME.dtb" -j"$(nproc)"

echo
echo "✓ 编译通过: $SDK/kernel-6.1/arch/arm64/boot/dts/rockchip/$NAME.dtb"
echo "  如果报 'undeclared'，多半是 pinctrl 组名写错或某个 label 在 EVB dtsi 里不存在"
