#!/bin/bash
# 把 board-port 里的板级文件装进 SDK
#
# 用法：
#   ./apply-to-sdk.sh /path/to/sdk          # 只安装
#   ./apply-to-sdk.sh /path/to/sdk --build  # 安装并编译 dtb 验证
#
# 全部用 cp/sed 完成，不依赖 SDK 是不是 git 仓库；每一步都可重复执行。
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

echo "[1/7] 安装设备树 -> $DTS_DIR/$NAME.dts"
cp "$PORT/$NAME.dts" "$DTS_DIR/"

echo "[2/7] 安装 defconfig -> $CHIP_DIR"
cp "$PORT/$DEFCONFIG" "$CHIP_DIR/"

echo "[3/7] u-boot：写入默认 bootargs"
UB_H="$UB/include/configs/rk3568_common.h"
if [ ! -f "$UB_H" ]; then
	echo "      没有 $UB_H，跳过"
elif grep -q 'root=PARTUUID=614e0000-0000-4b53' "$UB_H"; then
	echo "      已存在，跳过"
else
	sed -i 's|^\tENV_MEM_LAYOUT_SETTINGS \\$|\tENV_MEM_LAYOUT_SETTINGS \\\n\t"bootargs=console=ttyS2,1500000n8 earlycon=uart8250,mmio32,0xfe660000 " \\\n\t"root=PARTUUID=614e0000-0000-4b53-8000-1d28000054a9 rootwait rw\\0" \\|' "$UB_H"
	echo "      已写入"
fi

echo "[4/7] 内核：电源域握手失败不 panic"
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
    print("      未找到目标行，跳过（SDK 版本可能不同）")
PY
fi

echo "[5/7] 内核配置：CONFIG_DRM_IGNORE_IOTCL_PERMIT"
FRAG="$K/arch/arm64/configs/rk3568.config"
if grep -q '^CONFIG_DRM_IGNORE_IOTCL_PERMIT=y' "$FRAG" 2>/dev/null; then
	echo "      已存在，跳过"
else
	printf '\n# Rockchip SDK 打包要求（check-kernel.sh）\nCONFIG_DRM_IGNORE_IOTCL_PERMIT=y\n' >> "$FRAG"
	echo "      已追加"
fi

echo "[6/7] bcmdhd：改用 SDIO 带内中断（不依赖 WL_HOST_WAKE）"
BCM_MK="$K/drivers/net/wireless/rockchip_wlan/rkwifi/bcmdhd/Makefile"
if [ ! -f "$BCM_MK" ]; then
	echo "      找不到 bcmdhd Makefile，跳过"
elif grep -q '^CONFIG_BCMDHD_OOB := y' "$BCM_MK"; then
	sed -i 's/^CONFIG_BCMDHD_OOB := y/CONFIG_BCMDHD_OOB := n/' "$BCM_MK"
	echo "      已改为 n（走 -DSDIO_ISR_THREAD）"
else
	echo "      已是修改后的版本，跳过"
fi

echo "[7/7] 注册 dtb 到 dts Makefile"
if grep -q "$NAME.dtb" "$DTS_DIR/Makefile"; then
	echo "      已存在，跳过"
else
	echo "dtb-\$(CONFIG_ARCH_ROCKCHIP) += $NAME.dtb" >> "$DTS_DIR/Makefile"
	echo "      已追加"
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
make ARCH=arm64 CROSS_COMPILE="$CROSS" rockchip_linux_defconfig
make ARCH=arm64 CROSS_COMPILE="$CROSS" "rockchip/$NAME.dtb" -j"$(nproc)"

echo
echo "✓ 编译通过: $DTS_DIR/$NAME.dtb"
