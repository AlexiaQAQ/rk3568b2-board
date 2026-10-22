# 移植笔记

> 记录这块板从 Rockchip RK3568 EVB1 参考设计移植到 Linux 6.1 的全部改动、
> 踩过的坑，以及验证过程。给后来者（也包括三个月后的自己）看。

## 1. 基线

| 项 | 值 |
|---|---|
| SDK | 立创·泰山派 1M kernel6.1 SDK `20260807` |
| 分支 | `rk3566_rk3568-linux-6.1-stan-rkr7`（系列通用树，含 RK3568 EVB 配置） |
| 内核 | Linux 6.1.141 |
| device/rockchip 提交 | `cf9addc` |
| kernel 提交 | `1e5deed` |
| 参照 defconfig | `rockchip_rk3568_evb1_ddr4_v10_defconfig` |
| 参照 DTS | `rk3568-evb1-ddr4-v10.dts` → `rk3568-evb1-ddr4-v10.dtsi` → `rk3568-evb.dtsi` |

这份 SDK 虽然名字带 `rk3566`，但 `device/rockchip` 里同时有
`rockchip_rk3568_evb1_ddr4_v10_defconfig`、`rk3568_pcie_ep_lp4x_v10_defconfig`，
`docs/cn/RK3566_RK3568` 也在包内，是通用树而不是 3566 专用，可直接作为 RK3568 基线。

## 2. 与 EVB1 的差异

| 项 | EVB1 | 本板 | 处理 |
|---|---|---|---|
| DDR | DDR4 2GB | LPDDR4X 4GB | 只换 rkbin 的 DDR bin |
| 以太网 | 双口 | 单口 RTL8211F | 关 `gmac1` / `mdio1` |
| 存储 | eMMC + SD + SPI NAND | 只有 SD | 关 `sdhci` / `sfc` / `nandc0` |
| 显示 | eDP + DSI + HDMI | 只有 HDMI | 关 `dsi0/dsi1/edp/route_*` |
| 摄像头 / 触摸 | 有 | 无 | 全部 disabled |
| 板载 codec | RK809 codec | 未使用 | 关 `rk809_sound` |
| WiFi SDIO | SDMMC2 | **SDMMC1** | 换节点 + 重定义 pwrseq |
| BT | UART8 | **UART1 (m0)** | 换节点，带 RTS/CTS |
| WL_REG_ON | GPIO3_D5 | **GPIO2_B1** | 新 pinctrl 组 |
| WL_HOST_WAKE | GPIO3_D4 | **GPIO2_B2** | 新 pinctrl 组 |
| BT_REG_ON | — | **GPIO2_B7** | 新 pinctrl 组 |
| VCCIO4 / VCCIO6 | 3.3V | **1.8V** | 覆盖 `pmu_io_domains` |
| 电源树（SW/LDO） | — | 完全一致 | 不修改 |

结论：**电源树零改动**，工作量集中在"关掉没有的外设 + 重接无线"。

## 3. 踩过的坑

### 坑 1：UART2 默认是关的

`rk356x.dtsi` 里 `serial@fe660000`（UART2）的 `status = "disabled"`，
所有参考板都靠板上 dts 显式打开：

```dts
&uart2 {
	status = "okay";
};
```

漏掉这句，板子能正常启动，但**串口一个字节都没有**，第一次上电会非常难受。

### 坑 2：DTS 节点名相同会被合并，改 label 没用

最初想覆盖 EVB 的蓝牙节点，写成了：

```dts
bt_platdata: wireless-bluetooth {   /* ← 节点名和 EVB 的一样 */
	compatible = "bluetooth-platdata";
	bt_port = "/dev/ttyS1";
	...
};
```

dtc 把两个同名节点**合并**了，结果 EVB 的残留属性混进来：

```
uart_rts_gpios = <&gpio2 RK_PB1 GPIO_ACTIVE_LOW>   ← 本板的 WL_REG_ON！
pinctrl-1 = <&uart8_gpios>
```

`bluetooth-platdata` 会去申请 GPIO2_B1，而 `sdio_pwrseq` 已经持有它，
必然 `-EBUSY`。改成节点名 `bt-platdata`（label 也要跟着改）之后才彻底分离。

**教训**：用 include 方式继承参考设计时，新增节点必须换一个和参考 dts 不同的**节点名**。

### 坑 3：VCCIO4 / VCCIO6 是 1.8V，不是 3.3V

EVB 里：

```dts
vccio4-supply = <&vcc_3v3>;
vccio6-supply = <&vcc_3v3>;
```

本板这两路实际接 `VCC_1V8`，必须覆盖：

```dts
vccio4-supply = <&vcc_1v8>;
vccio6-supply = <&vcc_1v8>;
```

`vccio4` 同时是 SDIO 的 IO 域，配错会导致 WiFi 枚举不到，
长期还可能让 IO 工作在错误电平上。

另外 `vccio2` 在 `drivers/soc/rockchip/io-domain.c` 的 `soc_data_rk3568_pmu`
里是空实现（`case 3: /* vccio2 */ break;`），写了也不生效，不必配。

### 坑 4：DDR 跑不到颗粒的额定频率

颗粒标称 3733Mbps，但 RK3568 的 rkbin 只有 920 / 1056 / 1332 / 1560MHz 四档，
没有 1600 以上。1560MHz = 3120Mbps，是这颗 SoC 的实际上限。

`rkbin/RKBOOT/RK3568MINIALL.ini` 默认就是 `rk3568_ddr_1560MHz_v1.25.bin`，
**不需要改**。

## 4. 编译验证记录

2026-10-21，`extract_sdk.sh` + `repo sync -l` 完成后实测：

```
DTC     arch/arm64/boot/dts/rockchip/rk3568-myboard-v10.dtb
✓ 编译通过（191 KB）
```

反编译 dtb 后逐项核对：

| 检查项 | 结果 |
|---|---|
| `vccio4` / `vccio6` → `vcc_1v8`（DCDC_REG5） | ✅ |
| `vccio5` / `vccio7` → `vcc_3v3`（SWITCH_REG1） | ✅ |
| `pmuio2` → LDO6、`vccio1` → LDO4、`vccio3` → LDO5 | ✅ |
| `sdmmc1`：4-bit + non-removable + SDR104 + pwrseq | ✅ okay |
| `sdio_pwrseq` reset = GPIO2_B1，ACTIVE_LOW | ✅ |
| `sdmmc2` / `sdhci` / `sfc` 关闭 | ✅ disabled |
| `gmac0` okay（RGMII），`gmac1` disabled | ✅ |
| `uart1` m0 + RTS/CTS 三组 pinctrl | ✅ |
| `uart2` 调试口 | ✅ okay |
| BT 节点：`/dev/ttyS1`，reset=GPIO2_B7，wake=GPIO2_C1，host_wake=GPIO2_C0 | ✅ |
| EVB 遗留 `wireless-bluetooth` | ✅ disabled |

> 注意：以上是**编译与 DTB 内容**的验证，不等于上板可用。
> 硬件相关的项（PHY 地址、VBUS、DDR 稳定性）仍须实测。

## 5. u-boot 说明

本移植**没有**改 u-boot 设备树，仍用：

```
CONFIG_UBOOT_CFG    = "rk3568"
CONFIG_DEFAULT_DEVICE_TREE = "rk3568-evb"
```

首次点亮通常没问题（u-boot 主要需要 SD 和串口，两者引脚与 EVB 一致）。
如果出现在 u-boot 阶段 SD 枚举不到、或 SPL 之后停住，再为 u-boot 单独建板级 dts：

```bash
cd u-boot
cp arch/arm/dts/rk3568-evb.dts arch/arm/dts/rk3568-myboard.dts
# 改 model/compatible，并把 configs/rk3568_defconfig 里的
# CONFIG_DEFAULT_DEVICE_TREE 指过去
```

## 6. 上板验证顺序

1. **UART2 @ 1500000** 看 loader 是否有输出（无输出 → DDR bin 或电源问题）
2. u-boot：`mmc list` 确认 SD 识别
3. 内核：`dmesg | grep -i ddr` 确认 1560MHz；`/proc/cpuinfo` 确认 4 核
4. `ip link` 看 eth0（RTL8211F 的 PHY 地址/复位最容易错）
5. `ifconfig wlan0 up && iwlist wlan0 scan` 验证 AP6212
6. `hciconfig -a` 验证 BT；若无反应，先把 `BT,reset_gpio` 的极性从
   `GPIO_ACTIVE_HIGH` 改为 `GPIO_ACTIVE_LOW` 再试

## 7. 原理图核对（2026-10-22）

拿 `sch.pdf`（14 页，嘉立创 EDA 导出）逐页对了一遍，结论如下。

### 7.1 被证实的判断

| 项 | 原理图证据 |
|---|---|
| PMUIO2 = 3.3V | 第 2 页 U1.7：PMUIO2 引脚 W19 接 `VCC3V3_PMU`；PMUIO1 标注 "3.3V Only" |
| USB OTG VBUS 使能 = GPIO0_A5 | 第 2 页 `USB_OTG_PWREN_H_GPIO0_A5`，第 12 页驱动 U37(SY6280) |
| USB HOST1 VBUS 使能 = GPIO0_A6 | 第 2 页 `USB_HOST_PWREN_H_GPIO0_A6` |
| VCCIO_WL = 1.8V | 第 10 页：`VCC_1V8 → R55 0Ω → VCCIO_WL`，`VCC_3V3 → R56 NC` |
| SD 卡检测 = SDMMC0_DET | 第 2 页 `SDMMC0_DET/SATA_CP_DET/.../GPIO0_A4`，第 9 页接 TF 座 CD |
| 电源树与 EVB 一致 | 第 10 页 RK809 四路 DCDC + 九路 LDO 与 EVB 完全对应 |
| TCS4525 供 VDD_CPU | 第 11 页 U3，I2C0，默认 0.9V |

### 7.2 与口头描述不一致的地方

**a) 板上有 eMMC（U5）和 SPI Flash 位（U19）。**
之前说"存储只有 SD 卡"。图上是 SD + eMMC + SPI NOR/NAND 三个位。
当前设备树里 `sdhci` / `sfc` 仍是关闭的（按 SD 启动处理），若 eMMC 已贴片可再打开。

**b) 有一个 mini-PCIe / M.2 4G 模块座。**
第 14 页：Quectel RM500Q 类模块，走 PCIe x1 + USB3 + UIM，
电源 `VCC3V3_M2` 由 SY8113 产生，使能脚 `4G_PWREN_H_GPIO0_C6`。
当前设备树把 `pcie3x2` / `pcie30phy` 关了 —— 不用 4G 没问题，要用就得开。

**c) 板载音频是有的。**
第 10 页 RK809 CODEC 段有 HP_OUT_L/R、MIC；第 8 页有 3.5mm 耳机座和 MIC 电路。
之前把 `rk809_sound` 关掉了，现已改为 `okay`。

**d) 主输入是 5V VBUS，不是 12V。**
第 11 页：DC 座/USB → SMBJ33A → **TPS54540DDAR** → `VCC5V0_SYS` → SY8113 → `VCC3V3_SYS`。
EVB 的 `dc_12v` 在本板根本不存在，设备树里已用自定义 `vbus` 5V 稳压器替代。

### 7.3 新发现的风险：LPDDR4X 的 VDDQ

第 11 页 `VCC_LPDDR4_VCC` 段：U4（SY8089AAAC）用于产生 `VCC0V6_DDR`，
但**图中标注 NC（不贴）**，同时 `R64 = 0Ω`，注释写「Default: LPDDR4=1.1V」。

LPDDR4X 的 VDDQ 规范是 **0.6V**，LPDDR4 才是 1.1V。
颗粒 `RS1G32LO4D2BDS-53BT` 是 LPDDR4X。
若真的把 1.1V 加到 VDDQ 上属于超压。**需要确认 BOM / 贴片选项**，
不能靠软件规避（软件只能改 SW3 的输出，改不了这颗外部 buck）。

## 8. 后续

- [ ] 确认 DDR VDDQ 电压（见 7.3，最高优先级）
- [ ] 补一份 u-boot 板级 dts
- [ ] 按实际 SD 容量重算 `parameter-buildroot-fit.txt`
- [ ] 若 eMMC 已贴片，打开 `sdhci` 并调整启动顺序
- [ ] 若要上 4G 模块，打开 `pcie3x2` 并加 `4G_PWREN`(GPIO0_C6) 控制
- [ ] 硬件确认项见 [hardware.md](hardware.md) 第 6 节
