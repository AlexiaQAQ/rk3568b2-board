#!/bin/bash
# 把 board-port 里的板级文件装进 SDK
#
# 用法：
#   ./apply-to-sdk.sh /path/to/sdk          # 只安装
#   ./apply-to-sdk.sh /path/to/sdk --build  # 安装并编译 dtb 验证
#
# 全部用 cp / sed / python3 完成，不依赖 SDK 是不是 git 仓库。
# 每一步都先检查再动手，可以重复执行。
#
# 一共装/改 8 处：
#   1  内核设备树        rk3568-board-v10.dts
#   2  板级配置          rockchip_rk3568_board_v10_defconfig
#   3  u-boot 默认 bootargs   root=PARTUUID 写死，换分区表也不会启动失败
#   4  内核电源域不 panic     手板调试时某个域起不来不该直接挂死
#   5  内核 DRM 配置          SDK 的 check-kernel.sh 强制要求
#   6  bcmdhd 带内中断        不依赖板上的 WL_HOST_WAKE 那根线
#   7  注册 dtb 到 Makefile
#   8  u-boot 板级设备树      串口日志里能认出自己的板子
set -euo pipefail

SDK="${1:-}"
if [ -z "$SDK" ]; then
	echo "用法: $0 <SDK根目录> [--build]"
	exit 1
fi
SDK="$(cd "$SDK" && pwd)"
[ -d "$SDK/kernel-6.1" ] || { echo "错误: $SDK 下没有 kernel-6.1"; exit 1; }

PORT="$(cd "$(dirname "$0")" && pwd)"
K="$SDK/kernel-6.1"
UB="$SDK/u-boot"
CHIP_DIR="$SDK/device/rockchip/rk3566_rk3568"
DTS_DIR="$K/arch/arm64/boot/dts/rockchip"
NAME="rk3568-board-v10"
DEFCONFIG="rockchip_rk3568_board_v10_defconfig"

echo "[1/8] 安装设备树 -> $DTS_DIR/$NAME.dts"
cp "$PORT/$NAME.dts" "$DTS_DIR/"

echo "[2/8] 安装板级配置 -> $CHIP_DIR"
cp "$PORT/$DEFCONFIG" "$CHIP_DIR/"

# u-boot 里写死 root=PARTUUID，避免依赖 u-boot 自己猜分区
echo "[3/8] u-boot：写入默认 bootargs"
UB_H="$UB/include/configs/rk3568_common.h"
if [ ! -f "$UB_H" ]; then
	echo "      没有 $UB_H，跳过"
elif grep -q 'root=PARTUUID=614e0000-0000-4b53' "$UB_H"; then
	echo "      已存在，跳过"
else
	sed -i 's|^\tENV_MEM_LAYOUT_SETTINGS \\$|\tENV_MEM_LAYOUT_SETTINGS \\\n\t"bootargs=console=ttyS2,1500000n8 earlycon=uart8250,mmio32,0xfe660000 " \\\n\t"root=PARTUUID=614e0000-0000-4b53-8000-1d28000054a9 rootwait rw\\0" \\|' "$UB_H"
	if grep -q 'root=PARTUUID=614e0000-0000-4b53' "$UB_H"; then
		echo "      已写入"
	else
		echo "      ⚠ 没找到 ENV_MEM_LAYOUT_SETTINGS 那一行，未修改"
		echo "        （SDK 版本不同？请手动在 CONFIG_EXTRA_ENV_SETTINGS 里加 bootargs）"
	fi
fi

# 原版在电源域握手失败时直接 panic()，手板调试时根本进不了用户态
echo "[4/8] 内核：电源域握手失败不 panic"
PMD="$K/drivers/soc/rockchip/pm_domains.c"
if [ ! -f "$PMD" ]; then
	echo "      找不到 pm_domains.c，跳过"
elif ! grep -q 'panic("panic_on_set_idle' "$PMD"; then
	echo "      已是修改后的版本，跳过"
else
	python3 - "$PMD" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = '\tpanic("panic_on_set_idle set ...\\n");'
new = '''\t/*
\t * 原版这里是 panic()，只要某个电源域握手失败就无法启动，
\t * 对首板调试极不友好。改为报错继续，让系统能进用户态后再定位。
\t */
\tpr_err("%s: power domain '%s' failed (idle=%d), continue anyway\\n",
\t       __func__, genpd->name, idle);'''
if old in s:
    open(p, 'w').write(s.replace(old, new, 1))
    print("      已修改")
else:
    print("      ⚠ 没找到目标行，跳过（SDK 版本可能不同）")
PY
fi

# SDK 打包脚本会检查 .config 里有没有这一项
echo "[5/8] 内核配置：CONFIG_DRM_IGNORE_IOTCL_PERMIT"
FRAG="$K/arch/arm64/configs/rk3568.config"
if grep -q '^CONFIG_DRM_IGNORE_IOTCL_PERMIT=y' "$FRAG" 2>/dev/null; then
	echo "      已存在，跳过"
else
	printf '\n# Rockchip SDK 打包要求（check-kernel.sh）\nCONFIG_DRM_IGNORE_IOTCL_PERMIT=y\n' >> "$FRAG"
	echo "      已追加"
fi

# 驱动默认编译成 OOB 中断，要求 WL_HOST_WAKE 那根线是通的；
# 改成带内中断后只需要 SDIO 总线正常
echo "[6/8] bcmdhd：改用 SDIO 带内中断"
BCM_MK="$K/drivers/net/wireless/rockchip_wlan/rkwifi/bcmdhd/Makefile"
if [ ! -f "$BCM_MK" ]; then
	echo "      找不到 bcmdhd Makefile，跳过"
elif grep -q '^CONFIG_BCMDHD_OOB := y' "$BCM_MK"; then
	sed -i 's/^CONFIG_BCMDHD_OOB := y/CONFIG_BCMDHD_OOB := n/' "$BCM_MK"
	echo "      已改为 n（走 -DSDIO_ISR_THREAD）"
else
	echo "      已是修改后的版本，跳过"
fi

echo "[7/8] 注册 dtb 到 dts Makefile"
if grep -q "$NAME.dtb" "$DTS_DIR/Makefile"; then
	echo "      已存在，跳过"
else
	echo "dtb-\$(CONFIG_ARCH_ROCKCHIP) += $NAME.dtb" >> "$DTS_DIR/Makefile"
	echo "      已追加"
fi

# u-boot 用自己的一份设备树（和内核的两份是独立的），
# 不换的话串口里会一直打印 "Model: Rockchip RK3568 Evaluation Board"
echo "[8/8] u-boot：安装板级设备树"
UB_DTS_DIR="$UB/arch/arm/dts"
UB_CFG="$UB/configs/rk3568_defconfig"
if [ ! -d "$UB_DTS_DIR" ]; then
	echo "      没有 $UB_DTS_DIR，跳过"
else
	cp "$PORT/uboot/rk3568-board.dts" "$UB_DTS_DIR/"
	if grep -q '^CONFIG_DEFAULT_DEVICE_TREE="rk3568-board"' "$UB_CFG" 2>/dev/null; then
		echo "      已存在，跳过"
	else
		sed -i 's|^CONFIG_DEFAULT_DEVICE_TREE="rk3568-evb"|CONFIG_DEFAULT_DEVICE_TREE="rk3568-board"|' "$UB_CFG"
		echo "      已安装并切换到 rk3568-board"
	fi
fi

if [ "${2:-}" != "--build" ]; then
	echo
	echo "完成。下一步： cd $SDK && ./build.sh kernel"
	exit 0
fi

echo
echo "编译 dtb 验证"
CROSS="$SDK/prebuilts/gcc/linux-x86/aarch64/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-"
[ -x "${CROSS}gcc" ] || CROSS="aarch64-linux-gnu-"
export PATH="$HOME/.local/opt/sdk-deps/bin:$PATH"

cd "$K"
# 只在还没有 .config 时才生成，避免覆盖用户已经配好的东西
if [ ! -f .config ]; then
	make ARCH=arm64 CROSS_COMPILE="$CROSS" rockchip_linux_defconfig
fi
make ARCH=arm64 CROSS_COMPILE="$CROSS" "rockchip/$NAME.dtb" -j"$(nproc)"

echo
echo "✓ 编译通过: $DTS_DIR/$NAME.dtb"
