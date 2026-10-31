# 硬件说明

> 板名：`board` v1.0（占位符，发布前请替换）
> SoC：RK3568B2　内核：Linux 6.1.141
> 本文内容已按 `sch.pdf`（嘉立创 EDA 导出，14 页）逐页核对。

## 1. 总体规格

| 项 | 配置 | 备注 |
|---|---|---|
| SoC | RK3568B2 | FCCSP 塑料封装，最高 2.0GHz，GPU Mali-G52 2EE MC2 |
| 内存 | LPDDR4X 4GB，x32 | 颗粒 `RS1G32LO4D2BDS-53BT`，额定 3733Mbps，实跑 **1560MHz**（RK3568 上限） |
| PMIC | RK809-5 + TCS4525 | RK809 @ I2C0 0x20，TCS4525 @ I2C0 0x1c（VDD_CPU） |
| 存储 | SD 卡（SDMMC0）**+ eMMC（U5，焊接位）** | 另有 SPI NOR/NAND 位（U19），未使用 |
| 以太网 | 1x RTL8211F-CG | GMAC0，RGMII |
| WiFi/BT | AP6212 | WiFi = SDMMC1（1.8V IO），BT = UART1 |
| 显示 | HDMI | 无 MIPI-DSI / eDP / LVDS |
| 音频 | RK809 内置 codec | 3.5mm 耳机座 + MIC 电路 |
| USB | USB2.0 Type-C OTG + USB3.0 Host | OTG 口只走 D+/D-，无 SS 对 |
| 扩展 | M.2 插槽（PCIe x1） | 主用途 NVMe SSD；PCIe 2.1 x1（`pcie2x1`），3.3V 由 GPIO0_C6 使能 |
| 调试 | UART2 (m0) | 1500000 8N1 |

## 2. 供电结构

### 2.1 输入

**只从 DC 座供电，USB 口不供电**（USB 仅用于数据 / 烧录 / OTG）。

```
DC 座(5~24V) ──> SMBJ33A(TVS) ──> TPS54540DDAR ──> VCC5V0_SYS(5V) ──┬──> SY8113 ──> VCC3V3_SYS(3.3V)
                                                                  ├──> SY8113(U31) ──> VCC3V3_M2 (M.2)
                                                                  └──> VCC5V0_USB ──> (SY6280) ──> OTG/HOST VBUS
```

| 项 | 值 |
|---|---|
| 输入范围 | **5 ~ 24V**（DC 座） |
| 一次降压 | TPS54540DDAR（42V 耐压，5A）→ VCC5V0_SYS 5V |
| 二次降压 | SY8113 → VCC3V3_SYS 3.3V |
| 输入保护 | SMBJ33A（33V 关断电压 TVS，钳位约 53V） |

> TVS 选型核对：24V 最大输入 vs SMBJ33A 的 33V 关断电压，**余量约 1.4 倍**，
> 属于合理的保护设计。TPS54540 本身耐压 42V，整板上限由 24V 输入规格决定。

M.2 插槽的 3.3V（`VCC3V3_M2`）由 `4G_PWREN_H_GPIO0_C6` 控制，
设备树里做成了 `always-on` 的固定稳压器，否则硬盘不上电。

### 2.2 RK809 DCDC

| 路 | regulator 名 | 默认电压 | 供电对象 |
|---|---|---|---|
| SW1 | `vdd_logic` | **FB 直连输出**，等于 PMIC 内部基准（无外部分压） | SoC 逻辑域 VDD_LOGIC |
| SW2 | `vdd_gpu` | FB 直连，PMIC 内部基准 | GPU |
| SW3 | `vcc_ddr` | **1.1V**（R44 47k / R45 120k 分压设定） | DDR VDD2 |
| SW4 | `vdd_npu` | FB 直连，PMIC 内部基准 | NPU |
| — | `vcc_1v8`（DCDC_REG5） | 1.8V | 1.8V 系统电源，含 VCCIO4/VCCIO6 |

### 2.3 RK809 LDO

| 路 | regulator 名 | 电压 | 供电对象 |
|---|---|---|---|
| LDO1 | `vdda0v9_image` | 0.9V | eDP/HDMI TX AVDD 0V9 |
| LDO2 | `vdda_0v9` | 0.9V | MULT1_PHY / SYSPLL AVDD 0V9 |
| LDO3 | `vdda0v9_pmu` | 0.9V | PMUPLL AVDD 0V9 |
| LDO4 | `vccio_acodec` | 3.0V | VCCIO1 |
| LDO5 | `vccio_sd` | 1.8~3.3V | VCCIO3（SD 卡 IO，可变） |
| LDO6 | `vcc3v3_pmu` | 3.3V | PMU 域（PMUIO1 / PMUIO2） |
| LDO7 | `vcca_1v8` | 1.8V | SYSPLL / SARADC / MULT1_PHY AVDD 1V8 |
| LDO8 | `vcca1v8_pmu` | 1.8V | PMUPLL AVDD 1V8 + **VCC1V8_DDR**（0Ω 短接） |
| LDO9 | `vcca1v8_image` | 1.8V | eDP/HDMI TX AVDD 1V8 |

### 2.4 TCS4525（VDD_CPU）

| 项 | 值 |
|---|---|
| 挂载 | I2C0，地址 0x1c |
| 输入 | VCC5V0_SYS |
| 输出 | VDD_CPU，默认 0.9V，范围 712.5mV ~ 1390mV |
| 驱动 | `drivers/regulator/fan53555.c`，compatible `tcs,tcs4525` |

### 2.5 DDR 供电（已确认）

LPDDR4X 需要三路，本板全部正确：

| 轨 | 电压 | 来源 |
|---|---|---|
| VDD1 | 1.8V | `VCC1V8_DDR`（RK809 LDO8 `vcca1v8_pmu`，0Ω 短接） |
| VDD2 | 1.1V | `VCC_DDR`（RK809 SW3，R44 47k / R45 120k） |
| **VDDQ** | **0.6V** | `VCC0V6_DDR`（U4 SY8089AAAC 独立 buck） |

> 初看原理图时 U4 旁边标了 `NC`，曾误判为"未贴片、VDDQ 被短到 1.1V"。
> 经设计者确认：**SY8089AAAC 正常输出 0.6V**，NC 标注是模板残留。

因此 DDR 侧不需要任何软件特殊配置，用 rkbin 默认的
`rk3568_ddr_1560MHz_v1.25.bin` 即可（该 bin 支持 LPDDR4/4X 自动检测）。

## 3. IO 电压域

`pmu_io_domains` 里驱动实际只处理 `pmuio2` 和 `vccio1/3/4/5/6/7`
（`pmuio1` 与 `vccio2` 在 `soc_data_rk3568_pmu` 中是空实现）。

| 域 | 电压 | 来源 | 与 EVB 差异 |
|---|---|---|---|
| PMUIO1 | 3.3V | VCC3V3_PMU | 固定 3.3V，驱动不处理 |
| **PMUIO2** | **3.3V** | VCC3V3_PMU（W19） | 同 EVB（已按图确认） |
| VCCIO1 | 3.0V | LDO4 | 同 |
| VCCIO2（FLASH） | 1.8V | VCC_1V8 | 驱动不处理 |
| VCCIO3（SD） | 1.8~3.3V | LDO5 | 同 |
| **VCCIO4（WL）** | **1.8V** | VCC_1V8，经 R55 0Ω（R56 到 3.3V 为 NC） | **EVB 是 3.3V** |
| VCCIO5 | 3.3V | VCC_3V3 | 同 |
| **VCCIO6** | **1.8V** | VCC_1V8 | **EVB 是 3.3V** |
| VCCIO7 | 3.3V | VCC_3V3 | 同 |

VCCIO4 是 1.8V 这点同时决定 SDIO 的信号电平，因此 WiFi 可直接开
`sd-uhs-sdr104`，不需要 `vqmmc` 动态切换。

## 4. 关键引脚分配

### GPIO2（无线功能整组）

| 引脚 | 功能 | 网络名 |
|---|---|---|
| GPIO2_A3~A6 | SDMMC1 D0~D3 | SDIO_D0~D3 |
| GPIO2_A7 | SDMMC1 CMD | SDIO_CMD |
| GPIO2_B0 | SDMMC1 CLK | SDIO_CLK |
| GPIO2_B1 | WL_REG_ON | `WIFI_REG_ON_H` |
| GPIO2_B2 | WL_HOST_WAKE | `WIFI_WAKE_HOST_H` |
| GPIO2_B3 | UART1 RX | `UART1_RX_M0` |
| GPIO2_B4 | UART1 TX | `UART1_TX_M0` |
| GPIO2_B5 | UART1 RTSN | `UART1_RTSN_M0` |
| GPIO2_B6 | UART1 CTSN | `UART1_CTSN_M0` |
| GPIO2_B7 | BT_REG_ON | `BT_REG_ON_H`（引脚名 `BT_RST_N`） |
| GPIO2_C0 | BT_HOST_WAKE | `BT_WAKE_HOST_H` |
| GPIO2_C1 | BT_WAKE | `HOST_WAKE_BT_H` |

> WL_REG_ON 与 BT_REG_ON 是**两个独立引脚**，不是共用。
> CPU 序号：B1=9、B2=10、B7=15、C0=16、C1=17。

### 其它（PMUIO2 / 系统控制，均在 3.3V 域）

| 功能 | 引脚 | 网络名 |
|---|---|---|
| PMIC_INT | GPIO0_A3 | `PMIC_INT_L` |
| PMIC_SLEEP | GPIO0_A2 | `PMIC_SLEEP_H` |
| PMIC I2C | GPIO0_B0 / B1 | `I2C0_SCL/SDA_PMIC` |
| SD 卡检测 | GPIO0_A4 | `SDMMC0_DET_L`（走 SDMMC0_DET 功能，非 GPIO） |
| USB OTG VBUS 使能 | GPIO0_A5 | `USB_OTG_PWREN_H` |
| USB HOST1 VBUS 使能 | GPIO0_A6 | `USB_HOST_PWREN_H` |
| Flash 电压选择 | GPIO0_A7 | `FLASH_VOL_SEL` |
| 4G 模块电源使能 | GPIO0_C6 | `4G_PWREN_H` |
| 以太网 PHY 复位 | GPIO2_PD3 | 沿用 EVB |
| 调试串口 | UART2 m0 | GPIO0_D0/D1，1500000 8N1 |

## 5. 外设连接

| 外设 | 总线 | 说明 |
|---|---|---|
| SD 卡 | SDMMC0 | 4-bit，VDD = VCC3V3_SD，IO = VCCIO3 |
| eMMC | SDHCI（U5） | 焊接位存在，当前未使用（设备树里 `sdhci` 关闭） |
| WiFi | SDMMC1 | 4-bit SDIO，1.8V |
| BT | UART1 m0 | 带硬件流控 RTS/CTS |
| 以太网 | GMAC0 | RGMII，RTL8211F |
| HDMI | HDMI TX | 含 CEC / DDC / HPD |
| 音频 | RK809 codec | HP_OUT_L/R、MIC |
| USB2 OTG | Type-C | 仅 D+/D-，CC 用 5.1K 下拉 |
| USB3 Host | Type-A | USB3_HOST1 |
| M.2 插槽 | **pcie2x1** | 1 lane（`PCIE20_TX/RX/REFCLK`），专供 NVMe SSD；座上的 USB3.1 对未连接 |

未使用：MIPI-DSI、eDP、LVDS、摄像头（CSI）、CAN、SPI NOR/NAND。

## 6. 待确认硬件项

- [ ] eMMC（U5）当前未贴片，未来可能贴；届时需打开 `sdhci`
- [ ] M.2 插槽实测（`lspci` 能否枚举到 NVMe；PERST# 由专用引脚自动输出，无需 GPIO）
- [ ] RTL8211F 的 PHYAD strap 与复位脚确认

### eMMC（2026-10-25 贴片）

| 项 | 值 |
|---|---|
| 型号 | SDINBDA4-64G（SanDisk iNAND，64GB） |
| 总线 | 8-bit |
| VDDF（NAND） | 3.3V |
| VDD（I/O） | 1.8V |
| 控制器 | `sdhci@fe310000`（DWCMHSC） |
| 实测 | HS200 / 200MHz / 8-bit，错误计数全 0 |

对应 IO 域是 **VCCIO2**（VCCIO_FLASH），板上 0Ω 短接 VCC_1V8。
`FLASH_VOL_SEL` 必须为高电平（接 VCC3V3_PMU），与 1.8V 供电匹配。
