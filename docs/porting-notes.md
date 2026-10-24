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
之前说"存储只有 SD 卡"。图上是 SD + eMMC + SPI NOR/NAND 三个位，
eMMC 当前**未贴片**，属于预留。设备树里 `sdhci` / `sfc` 保持关闭，
将来贴片后打开 `sdhci` 即可。

**b) 有一个 M.2 插槽，主要用途是 NVMe SSD。**
第 14 页：座子是 M.2（3.3V 在 70/72/74 脚），只接了 **一对 PCIe lane**
（`PCIE20_TX/RX/REFCLK`）+ 一组 USB3.1（这一版打叉未接）+ UIM。
所以对应的是 **`pcie2x1`**（PCIe 2.1 x1，专用引脚），不是 `pcie3x2`。

`PCIE20_PERSTN_M1` / `CLKREQN_M1` / `WAKEN_M1` 是 SoC 的专用功能引脚，
经 22Ω 串阻直达座子，**不是 GPIO**，所以 `pcie2x1` 里不需要 `reset-gpios`。

供电 `VCC3V3_M2` 由 SY8113(U31) 从 VCC5V0_SYS 产生，使能脚
`4G_PWREN_H_GPIO0_C6`；设备树里做成了 always-on 的 `vcc3v3_m2`。
否则插上 SSD 也不会转 —— 这是很容易漏的一步。

**c) 板载音频是有的。**
第 10 页 RK809 CODEC 段有 HP_OUT_L/R、MIC；第 8 页有 3.5mm 耳机座和 MIC 电路。
之前把 `rk809_sound` 关掉了，现已改为 `okay`。

**d) 主输入是 5V VBUS，不是 12V。**
第 11 页：DC 座/USB → SMBJ33A → **TPS54540DDAR** → `VCC5V0_SYS` → SY8113 → `VCC3V3_SYS`。
EVB 的 `dc_12v` 在本板根本不存在，设备树里已用自定义 `vbus` 5V 稳压器替代。

### 7.3 DDR 的 VDDQ（曾经的误判，已澄清）

第 11 页 `VCC_LPDDR4_VCC` 段：U4（SY8089AAAC）产生 `VCC0V6_DDR`，
但图上标了 `NC`，同时 `R64 = 0Ω`，注释写「Default: LPDDR4=1.1V」，
当时据此判断"VDDQ 可能被短到 1.1V、对 LPDDR4X 属超压"。

**经设计者确认：U4 正常贴片并输出 0.6V**，`NC` 是模板残留标注。
LPDDR4X 的三路供电（1.8/1.1/0.6V）都正确，DDR 侧无需软件干预。

教训：原理图上的 `NC` / `Default:` 注释可能是从参考设计抄来的残留，
涉及电源的关键判断应当直接问设计者或查 BOM，不要只看图注。

### 7.4 SD 卡 4-bit 数据线问题（实测）

首板在内核里读 SD 卡持续报错，表现为：

```
I/O error, dev mmcblk1, sector 492127 op 0x0:(READ)
EXT4-fs error (device mmcblk1p6): Error while async write back metadata
EXT4-fs error: Detected aborted journal
WARNING: CPU: 0 ... dw_mci_request_end (WARN_ON(host->cmd || host->data))
```

同时总线速度在 375kHz 与 50MHz 之间反复跳（每次失败后重新初始化）。

| 配置 | 结果 |
|---|---|
| 150MHz + SDR104（EVB 默认） | 大量 I/O 错误，文件系统损坏 |
| 50MHz + 4-bit | 仍有 I/O 错误（扇区 0 都读失败） |
| **50MHz + 1-bit** | **零 I/O 错误，正常启动** |

**结论：DAT1/DAT2/DAT3 至少一条有硬件问题**（虚焊 / 短路 / 走线）。
u-boot 能读 40MB 内核而内核读不了，是因为两者对总线位宽与时序的处理不同。

临时规避：设备树里 `bus-width = <1>;`。
根治：查 SD 座到 SoC 的 DAT1~DAT3 走线与焊接，修好后改回 `<4>` 提速。

残余现象：改成 1-bit 后仍有少量 `dw_mci_request_end` WARN + 偶发重新初始化，
但不产生数据错误，暂不阻塞使用（疑似卡检测或 VCC3V3_SD 供电瞬态）。

## 8. 后续


- [ ] 补一份 u-boot 板级 dts
- [ ] 按实际 SD 容量重算 `parameter-buildroot-fit.txt`
- [ ] 若 eMMC 已贴片，打开 `sdhci` 并调整启动顺序
- [ ] M.2 插槽实测 NVMe 枚举（`lspci -nn`）
- [ ] 硬件确认项见 [hardware.md](hardware.md) 第 6 节
