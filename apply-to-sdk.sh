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
NAME="rk3568-myboard-v10"

echo "[1/4] 安装设备树 -> $DTS_DIR/$NAME.dts"
cp "$PORT/$NAME.dts" "$DTS_DIR/"

echo "[2/4] 安装 defconfig -> $CHIP_DIR"
cp "$PORT/rockchip_rk3568_myboard_v10_defconfig" "$CHIP_DIR/"

echo "[3/4] 注册到 Makefile"
if grep -q "$NAME.dtb" "$DTS_DIR/Makefile"; then
	echo "      已存在，跳过"
else
	echo "dtb-\$(CONFIG_ARCH_ROCKCHIP) += $NAME.dtb" >> "$DTS_DIR/Makefile"
	echo "      已追加"
fi

if [ "${2:-}" != "--build" ]; then
	echo "[4/4] 跳过编译（加 --build 可编译验证）"
	exit 0
fi

echo "[4/4] 编译 dtb 验证"
CROSS="$SDK/prebuilts/gcc/linux-x86/aarch64/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-"
[ -x "${CROSS}gcc" ] || CROSS="aarch64-linux-gnu-"

cd "$SDK/kernel-6.1"
make ARCH=arm64 CROSS_COMPILE="$CROSS" rockchip_linux_defconfig
make ARCH=arm64 CROSS_COMPILE="$CROSS" \
	"rockchip/$NAME.dtb" -j"$(nproc)"

echo
echo "✓ 编译通过: $SDK/kernel-6.1/arch/arm64/boot/dts/rockchip/$NAME.dtb"
echo "  如果报 'undeclared'，多半是 pinctrl 组名写错或某个 label 在 EVB dtsi 里不存在"
