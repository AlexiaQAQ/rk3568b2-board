#!/bin/bash
# 从 SDK 里移除本仓库安装的板级文件
#
# 用法：
#   ./scripts/uninstall-from-sdk.sh /path/to/sdk
#
# 只删「加进去的东西」，不碰 SDK 原有文件。buildroot 输出目录（几十 GB）
# 需要另外用 make clean 或手动删除。
set -euo pipefail

SDK="${1:-}"
if [ -z "$SDK" ]; then
	echo "用法: $0 <SDK根目录>"
	exit 1
fi
SDK="$(cd "$SDK" && pwd)"
[ -d "$SDK/kernel-6.1" ] || { echo "错误: $SDK 下没有 kernel-6.1"; exit 1; }

CHIP_DIR="$SDK/device/rockchip/rk3566_rk3568"
DTS_DIR="$SDK/kernel-6.1/arch/arm64/boot/dts/rockchip"
NAME="rk3568-board-v10"
DEFCONFIG="rockchip_rk3568_board_v10_defconfig"

echo "[1/5] 删除设备树"
rm -fv "$DTS_DIR/$NAME.dts" "$DTS_DIR/$NAME.dtb"

echo "[2/5] 删除 defconfig"
rm -fv "$CHIP_DIR/$DEFCONFIG"

echo "[3/5] 从 dts Makefile 移除注册行"
if [ -f "$DTS_DIR/Makefile" ] && grep -q "$NAME.dtb" "$DTS_DIR/Makefile"; then
	sed -i "/$NAME.dtb/d" "$DTS_DIR/Makefile"
	echo "      已移除 $NAME.dtb"
else
	echo "      无需处理"
fi

echo "[4/5] 恢复 bcmdhd 的 OOB 中断配置"
BCM_MK="$SDK/kernel-6.1/drivers/net/wireless/rockchip_wlan/rkwifi/bcmdhd/Makefile"
if [ -f "$BCM_MK" ] && grep -q '^CONFIG_BCMDHD_OOB := n' "$BCM_MK"; then
	sed -i 's/^CONFIG_BCMDHD_OOB := n/CONFIG_BCMDHD_OOB := y/' "$BCM_MK"
	echo "      已改回 y"
else
	echo "      无需处理"
fi

echo "[5/5] 提示"
cat <<'TIP'
      以下是 patch 打进去、但本脚本不自动回滚的内容（按需手动处理）：
        - u-boot 的默认 bootargs
        - 内核电源域不 panic
        - kernel .config 里的 CONFIG_DRM_IGNORE_IOTCL_PERMIT
      以及需要手动清理的构建产物：
        make clean      # 删 buildroot/output（几十 GB）
        make distclean  # 再删 SDK 的 output/

      板级文件已从 SDK 移除完毕。
TIP
