# 更新日志

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/) 的简化形式，
版本号对应板级硬件版本 + 修订。

## [0.1.0] - 2026-10-21

首个可编译的板级支持，尚未上板实测。

### 新增

- `rk3568-myboard-v10.dts`：基于 Rockchip RK3568 EVB1 参考设计的板级设备树
- `rockchip_rk3568_myboard_v10_defconfig`：SDK 板级配置
- `patch/0001-kernel-add-rk3568-myboard-v10-dts.patch`：内核侧补丁
- `patch/0002-device-add-myboard-defconfig.patch`：device/rockchip 侧补丁
- `apply-to-sdk.sh`：一键安装板级文件并可选编译 dtb 验证
- `docs/hardware.md`、`docs/porting-notes.md`

### 板级适配

- 4GB LPDDR4X（`RS1G32LO4D2BDS-53BT`），DDR 频率 1560MHz
- 仅 SD 卡启动：关闭 `sdhci`、`sfc`、`nandc0`
- 单网口 RTL8211F：关闭 `gmac1`、`mdio1`
- 仅 HDMI：关闭 `dsi0`、`dsi1`、`edp` 及对应 route
- 关闭摄像头、触摸、板载 codec、心跳灯
- AP6212：WiFi 从 SDMMC2 改为 **SDMMC1**，BT 从 UART8 改为 **UART1 (m0, RTC/CTS)**
- 新增 WL_REG_ON(GPIO2_B1)、WL_HOST_WAKE(GPIO2_B2)、BT_REG_ON(GPIO2_B7) 的 pinctrl
- IO 电压域：`vccio4` / `vccio6` 由 3.3V 改为 **1.8V**
- 显式打开调试串口 UART2

### 修复

- 蓝牙节点与 EVB 同名导致属性被 dtc 合并（`uart_rts_gpios` 误占 WL_REG_ON），
  改为独立的 `bt-platdata` 节点
- UART2 默认关闭导致无串口输出

### 验证

- 设备树编译通过，生成的 DTB 反编译后逐项核对（详见 `docs/porting-notes.md` 第 4 节）
- **未上板实测**
