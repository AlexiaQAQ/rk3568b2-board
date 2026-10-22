# 硬件说明

> 板名：`myboard` v1.0（占位符，发布前请替换）
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
| 扩展 | mini-PCIe / M.2 4G 模块座 | 复用以太网之外的 PCIe x1 + USB；`4G_PWREN` = GPIO0_C6 |
| 调试 | UART2 (m0) | 1500000 8N1 |

## 2. 供电结构

### 2.1 输入

```
DC 座 / USB VBUS (5V) ──> TPS54540DDAR ──> VCC5V0_SYS ──> SY8113 ──> VCC3V3_SYS
                                  │
                                  └──> VCC5V0_USB ──> (SY6280) ──> VCC5V0_USB_OTG0 / HOST1
```

**注意**：EVB 用的是 12V（`dc_12v`）输入，本板是 **VBUS 5V**。
设备树里已用自定义的 `vbus` 固定 5V 稳压器替换 `dc_12v` 作为 `vcc3v3_sys` / `vcc5v0_sys` 的上游。

### 2.2 RK809 DCDC

| 路 | regulator 名 | 默认电压 | 供电对象 |
|---|---|---|---|
| SW1 | `vdd_logic` | 由 FB 电阻决定 | SoC 逻辑域 VDD_LOGIC |
| SW2 | `vdd_gpu` | — | GPU |
| SW3 | `vcc_ddr` | **1.1V**（R44 47k / R45 120k） | DDR VDD2 |
| SW4 | `vdd_npu` | — | NPU |
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

### 2.5 ⚠️ DDR 的 VDDQ 需要人工确认

LPDDR4X 需要三路：VDD1 = 1.8V、VDD2 = 1.1V、**VDDQ = 0.6V**。

原理图上：

- `VCC_DDR`（SW3）= 1.1V → VDD2 ✔
- `VCC1V8_DDR`（LDO8）= 1.8V → VDD1 ✔
- **`VCC0V6_DDR` = 0.6V 由 U4（SY8089AAAC）产生，但图中标注 `NC`（不贴）**，
  且 `R64` 为 0Ω，看起来把 `VCC0V6_DDR` 并到了 `VCC_DDR`（1.1V），
  旁边注释写的是「Default: LPDDR4=1.1V」。

如果颗粒确实是 **LPDDR4X**（VDDQ 0.6V），而实际给的是 1.1V，**属于超压，可能损坏颗粒**。
这可能是贴片选项标注残留，也可能是真的按 LPDDR4 配置的 BOM —— **打样前必须确认**。

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
| 4G 模块 | mini-PCIe/M.2 | PCIe x1 + USB3 + UIM，电源由 SY8113 供 VCC3V3_M2 |

未使用：MIPI-DSI、eDP、LVDS、摄像头（CSI）、CAN、SPI NOR/NAND。

## 6. 待确认硬件项

- [ ] **DDR VDDQ 到底 0.6V 还是 1.1V**（见 2.5，优先级最高）
- [ ] eMMC 是否贴片；若贴了，是否要作为启动介质
- [ ] 4G 模块座是否使用（用了就要开 `pcie3x2` + `4G_PWREN` GPIO0_C6）
- [ ] RTL8211F 的 PHYAD strap 与复位脚确认
