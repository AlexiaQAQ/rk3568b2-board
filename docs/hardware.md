# 硬件说明

> 板名：`myboard` v1.0（占位符，发布前请替换）
> SoC：RK3568B2　内核：Linux 6.1.141

## 1. 总体规格

| 项 | 配置 | 备注 |
|---|---|---|
| SoC | RK3568B2 | FCCSP 塑料封装，最高 2.0GHz，GPU Mali-G52 2EE MC2 |
| 内存 | LPDDR4X 4GB，x32 | 颗粒 `RS1G32LO4D2BDS-53BT`，额定 3733Mbps，实跑 **1560MHz**（RK3568 上限） |
| PMIC | RK809-5 + TCS4525 | 均在 I2C0：RK809 @ 0x20，TCS4525 @ 0x1c |
| 存储 | SD 卡（SDMMC0） | 无 eMMC / SPI NAND |
| 以太网 | 1x RTL8211F-CG | GMAC0，RGMII |
| WiFi/BT | AP6212 | WiFi = SDMMC1（SDIO 1.8V），BT = UART1 |
| 显示 | HDMI | 无 MIPI-DSI / eDP / LVDS |
| USB | USB2.0 Type-C OTG + USB3.0 Host | OTG 口只走 D+/D-，无 SS 对 |
| 调试 | UART2 | 1500000 8N1 |

## 2. 电源树

RK809-5 四路 DCDC + 九路 LDO，外加一颗 TCS4525 单独供 CPU。
**与 Rockchip RK3568 EVB1 参考设计完全一致**，因此设备树里直接继承，不做修改。

### DCDC（RK809）

| 路 | regulator 名 | 供电对象 |
|---|---|---|
| SW1 | `vdd_logic` | SoC 逻辑域 VDD_LOGIC |
| SW2 | `vdd_gpu` | GPU |
| SW3 | `vcc_ddr` | DDR 主供电（VDD2 / VDDQ） |
| SW4 | `vdd_npu` | NPU |
| — | `vcc_1v8`（DCDC_REG5） | 1.8V 系统电源，含 VCCIO4/VCCIO6 |

### LDO（RK809）

| 路 | regulator 名 | 电压 | 供电对象 |
|---|---|---|---|
| LDO1 | `vdda0v9_image` | 0.9V | eDP/HDMI TX AVDD 0V9 |
| LDO2 | `vdda_0v9` | 0.9V | MULT1_PHY / SYSPLL AVDD 0V9 |
| LDO3 | `vdda0v9_pmu` | 0.9V | PMUPLL AVDD 0V9 |
| LDO4 | `vccio_acodec` | 3.0V | VCCIO1 |
| LDO5 | `vccio_sd` | 1.8~3.3V | VCCIO3（SD 卡 IO，可变） |
| LDO6 | `vcc3v3_pmu` | 3.3V | PMU 域（PMUIO2） |
| LDO7 | `vcca_1v8` | 1.8V | SYSPLL / SARADC / MULT1_PHY AVDD 1V8 |
| LDO8 | `vcca1v8_pmu` | 1.8V | PMUPLL AVDD 1V8 + **VCC1V8_DDR**（0Ω 短接） |
| LDO9 | `vcca1v8_image` | 1.8V | eDP/HDMI TX AVDD 1V8 |

### TCS4525

| 项 | 值 |
|---|---|
| 挂载 | I2C0，地址 0x1c |
| 输出 | VDD_CPU |
| 范围 | 712.5mV ~ 1390mV，`regulator-init-microvolt = 900mV` |
| 驱动 | `drivers/regulator/fan53555.c`，compatible `tcs,tcs4525` |

> ⚠️ **LDO8 同时给 DDR 的 VDD1 供电**。这样待机时 DDR 能保持自刷新，
> 设计合理，但 LDO 电流余量需实测确认（DDR 满载纹波）。

## 3. IO 电压域

`pmu_io_domains` 里驱动实际只处理 `pmuio2` 和 `vccio1/3/4/5/6/7`
（`pmuio1` 与 `vccio2` 在 `soc_data_rk3568_pmu` 中是空实现）。

| 域 | 电压 | 来源 | 与 EVB 差异 |
|---|---|---|---|
| PMUIO2 | 3.3V | LDO6 | 同 |
| VCCIO1 | 3.0V | LDO4 | 同 |
| VCCIO2（FLASH） | 1.8V | VCC_1V8（0Ω） | 驱动不处理 |
| VCCIO3（SD） | 1.8~3.3V | LDO5 | 同 |
| **VCCIO4（WL）** | **1.8V** | VCC_1V8（0Ω） | **EVB 是 3.3V** |
| VCCIO5 | 3.3V | VCC_3V3 | 同 |
| **VCCIO6** | **1.8V** | VCC_1V8 | **EVB 是 3.3V** |
| VCCIO7 | 3.3V | VCC_3V3 | 同 |

VCCIO4 是 1.8V 这点很重要：它同时决定了 SDIO 的 1.8V 信号电平，
因此 WiFi 可以直接开 `sd-uhs-sdr104`，不需要 `vqmmc` 动态切换。

## 4. 关键引脚分配

### GPIO2（无线功能整组）

| 引脚 | 功能 | 网络名 |
|---|---|---|
| GPIO2_A3~A6 | SDMMC1 D0~D3 | SDIO_D0~D3 |
| GPIO2_A7 | SDMMC1 CMD | SDIO_CMD |
| GPIO2_B0 | SDMMC1 CLK | SDIO_CLK |
| GPIO2_B1 | WL_REG_ON | `WIFI_REG_ON_H` |
| GPIO2_B2 | WL_HOST_WAKE | `WIFI_WAKE_HOST_H` |
| GPIO2_B3 | UART1 RX | — |
| GPIO2_B4 | UART1 TX | — |
| GPIO2_B5 | UART1 RTSN | `UART1_RTSN_M0` |
| GPIO2_B6 | UART1 CTSN | `UART1_CTSN_M0` |
| GPIO2_B7 | BT_REG_ON | `BT_REG_ON_H`（引脚名 `BT_RST_N`） |
| GPIO2_C0 | BT_HOST_WAKE | `BT_WAKE_HOST_H` |
| GPIO2_C1 | BT_WAKE | `HOST_WAKE_BT_H` |

> WL_REG_ON 与 BT_REG_ON 是**两个独立引脚**，不是共用。

### 其它

| 功能 | 引脚 | 备注 |
|---|---|---|
| PMIC_INT | GPIO0_A3 | RK809 中断 |
| 以太网 PHY 复位 | GPIO2_PD3 | 沿用 EVB，待确认 |
| 调试串口 | UART2 m0 | 1500000 8N1 |
| SD 卡 | SDMMC0 | 4-bit |

## 5. 接口清单

- HDMI 输出（音频走 HDMI）
- 1x 千兆以太网（RTL8211F）
- WiFi 2.4G + BT（AP6212）
- USB2.0 Type-C（OTG）、USB3.0 Type-A（Host）
- SD 卡槽（启动介质）
- 调试串口

未使用：PCIe、SATA、MIPI-DSI、eDP、LVDS、摄像头、CAN、板载 codec。

## 6. 待确认硬件项

- [ ] VCCIO2/4/5/6/7 与原理图逐条复核
- [ ] PMUIO2 实际电压（当前按 3.3V）
- [ ] 主输入电压（EVB 为 12V，本板未确认）
- [ ] VBUS 使能脚（当前仍用 EVB 的 GPIO0_A6 / GPIO0_A5）
- [ ] RTL8211F 的 PHYAD strap 与复位脚
- [ ] SD 卡 CD（卡检测）引脚是否连接
