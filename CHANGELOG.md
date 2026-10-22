# 更新日志

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/) 的简化形式，
版本号对应板级硬件版本 + 修订。

## [0.1.3] - 2026-10-22

### 澄清

- DDR VDDQ 确认由 U4（SY8089AAAC）输出 **0.6V**，符合 LPDDR4X 规范；
  此前依据图中 `NC` 标注做出的"超压"判断系误判，已从文档移除，
  并记录误判原因（模板残留注释）

## [0.1.2] - 2026-10-22

确认 M.2 插槽用途为 NVMe SSD 后的板级补充。

### 新增

- 启用 `pcie2x1`（PCIe 2.1 x1，1 lane），对应 M.2 座的 `PCIE20_*`
- 新增 `vcc3v3_m2` 固定稳压器：GPIO0_C6 使能、always-on，
  否则 M.2 插槽的 3.3V 不会上电

### 变更

- `pcie3x2` / `pcie30phy` / `sata2` 保持关闭（本板未使用）
- M.2 座的 USB3.1 差分对本版未连接，仅 PCIe 可用

### 说明

- `PCIE20_PERSTN_M1` 等为 SoC 专用引脚，非 GPIO，故 `pcie2x1` 不设 `reset-gpios`

## [0.1.1] - 2026-10-22

根据原理图 `sch.pdf` 复核后的修正。

### 修复

- 主输入电源：EVB 的 `dc_12v`(12V) 在本板不存在，改为自定义 `vbus`(5V) 稳压器
  作为 `vcc3v3_sys` / `vcc5v0_sys` 的上游
- 音频：原理图确认有耳机座与 MIC，`rk809_sound` 由 disabled 改为 **okay**

### 确认

- PMUIO2 = 3.3V（接 VCC3V3_PMU）
- USB VBUS 使能：OTG = GPIO0_A5，HOST1 = GPIO0_A6
- VCCIO_WL = 1.8V（R55 0Ω 到 VCC_1V8，R56 到 3.3V 为 NC）
- SD 卡检测走 SDMMC0_DET（GPIO0_A4）
- 电源树（RK809 4x DCDC + 9x LDO + TCS4525）与 EVB1 一致

### 新增发现

- 板上有 eMMC（U5）与 SPI Flash（U19）焊接位，当前仍按 SD 启动处理
- 有 mini-PCIe / M.2 4G 模块座（PCIe x1 + USB3，`4G_PWREN` = GPIO0_C6）
- ⚠️ DDR 的 VDDQ：LPDDR4X 应为 0.6V，但 0.6V buck（U4）标注 NC，
  需确认 BOM，详见 `docs/hardware.md` 2.5

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
