# 硬件说明

> 原理图 / PCB / BOM / Gerber 发布在**立创开源硬件平台（OSHWHub）**，
> 仓库里不重复维护二进制文件。开源工程链接：`<待补充>`
> （设计工具：嘉立创 EDA 专业版；原理图 V1.0，A3 14 页）
>
> `hardware/` 目录已加入 `.gitignore`，本地可放 PDF 副本，不会误提交。


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
| SD 卡 | SDMMC0 | **当前 1-bit**（DAT1~3 走线不稳），VDD = VCC3V3_SD，IO = VCCIO3 |
| eMMC | SDHCI（U5） | 64GB `SDINBDA4-64G`，8-bit HS200 200MHz |
| WiFi | SDMMC1 | 4-bit SDIO，IO = VCCIO4（VCCIO_WL，选 3.3V）|
| BT | UART1 m0 | 带硬件流控 RTS/CTS |
| 以太网 | **GMAC1** | RGMII，RTL8211F（GMAC0 的引脚被 WiFi/BT 占用）|
| HDMI | HDMI TX | 含 CEC / DDC / HPD |
| 音频 | RK809 codec | HP_OUT_L/R、MIC |
| USB2 OTG | Type-C | 仅 D+/D-，CC 用 5.1K 下拉 |
| USB3 Host | Type-A | USB3_HOST1 |
| M.2 插槽 | **pcie2x1** | 1 lane（`PCIE20_TX/RX/REFCLK`），专供 NVMe SSD（未实测）；座上的 USB3.1 对未连接 |

未使用：MIPI-DSI、eDP、LVDS、摄像头（CSI）、CAN、SPI NOR/NAND。

## 6. 硬件确认记录

| 项 | 状态 |
|---|---|
| eMMC（U5）| ✅ 已贴片 `SDINBDA4-64G`（64GB），HS200 8-bit 200MHz，错误计数全 0 |
| RTL8211F | ✅ PHYAD = 0，25MHz 晶振已补焊，1Gbps 全双工 |
| M.2 NVMe | ⏳ 未实测（`lspci` 能否枚举待验证）|
| HDMI | ✅ 1080p60（补齐 1µH 滤波电感 + 1.62kΩ REXT）|
| 音频 | ✅ 3.5mm 耳机 + MIC（RK809 内置 codec）|

eMMC 对应 IO 域是 **VCCIO2**（VCCIO_FLASH），板上 0Ω 短接 VCC_1V8，
`FLASH_VOL_SEL` 接 VCC3V3_PMU（高电平），与 1.8V 供电匹配。


## 7. 首板上电检查表

### 7.0 准备

- 万用表（二极管档 + 直流电压档）
- **可调限流电源**（5V，限流 300~500mA）—— 没有的话用带电流显示的 USB 表也行
- 串口已接好并打开（UART2 @ 1500000）
- 板子不插 SD 卡（第一次先看 loader，不急着启动）

### 7.1 断电检查（不上电）

| 检查 | 方法 | 期望 |
|---|---|---|
| 5V 对地 | 二极管档，红笔 GND 黑笔 5V | > 0.3V 压降，不能接近 0 |
| 3.3V 对地 | 同上 | 同上 |
| **VDD_CPU 对地** | 同上 | 不能为 0（0 就是短路，TCS4525 或 SoC 挂了） |
| **VCC_DDR 对地** | 同上 | 不能为 0 |
| **VCC0V6_DDR 对地** | 同上 | 不能为 0 |
| BGA 底部 | 目视 + 放大镜 | 无连锡、无漏焊 |

> 短路测试**必须在所有电源都断电**的情况下做，且先给大电容放电。

### 7.2 首次上电（限流 500mA）

1. 串口先打开
2. 上电，**盯住电流**
3. 正常：空载 100~300mA，可能有轻微跳动
4. **电流瞬间打满 500mA** → 立刻断电，说明有短路

### 7.3 逐路测电压（关键）

按这个表量，**每一项都要对**。测点找对应的电感/电容。

| 电源 | 期望值 | 来源 | 不对的后果 |
|---|---|---|---|
| DC 输入 | 5~24V（按适配器实测） | DC 座 | — |
| VCC5V0_SYS | 5.0V | TPS54540 | 全板不工作 |
| VCC3V3_SYS | 3.3V | SY8113 | 全板不工作 |
| VCC3V3_PMU | 3.3V | LDO6 | PMU 域异常，无法开机 |
| VDD_LOGIC | FB 直连，等于 PMIC 基准（实测确认，常见 0.9V） | SW1 | SoC 不跑 |
| **VDD_CPU** | **0.9V**（TCS4525 默认） | TCS4525 | 偏低会死机/不启动 |
| VDD_GPU | RK809 默认值 | SW2 | 内核起来后才会调整 |
| VDD_NPU | RK809 默认值 | SW4 | 同上 |
| **VCC_DDR** | **1.1V** | SW3（R44 47k/R45 120k） | DDR 不工作 |
| **VCC1V8_DDR** | **1.8V** | LDO8 | DDR 不工作 |
| **VCC0V6_DDR** | **0.6V** | U4 SY8089 | **超压会损坏 LPDDR4X** |
| VCCIO1 | 3.0V | LDO4 | 相关外设异常 |
| VCCIO3（SD） | 3.3V（默认） | LDO5 | SD 不识别 |
| VCCIO4（WL） | 1.8V | VCC_1V8 | WiFi/BT IO 异常 |
| VCCIO6 | 1.8V | VCC_1V8 | 相关外设异常 |
| VCCIO7 | 3.3V | VCC_3V3 | 相关外设异常 |
| VCC3V3_SD | 3.3V | 负载开关 | SD 不上电 |
| VCC3V3_M2 | **0V（正常）** | SY8113 + GPIO0_C6 | 系统起来后才会被拉高 |

> **VCC3V3_M2 上电初期是 0V 属于正常**，因为它的使能脚 GPIO0_C6 默认是低，
> 要等内核里的 `vcc3v3_m2` 稳压器去拉高。别误判成故障。

#### 三路 DDR 供电是重中之重

LPDDR4X 需要 **VDD1=1.8V / VDD2=1.1V / VDDQ=0.6V**，任何一路错了都可能：

- 偏低 → DDR 训练失败，loader 卡在 `DDR` 阶段
- **VDDQ 被加上 1.1V（LPDDR4 的电压）→ 颗粒超压，可能永久损坏**

所以这三路**在第一次上电后要立刻测**，不对马上断电。

### 7.4 时钟与复位

| 项 | 检查 |
|---|---|
| 24MHz 主晶振 | 示波器看 XIN24M，应该有正弦波；没有则 SoC 不启动 |
| 32.768kHz | RK809 的 CLK32KOUT，供 WiFi/BT 休眠用，不影响首次启动 |
| RECOVERY 键 | 不按下时应为高电平 |
| 复位脚 | 上电后应释放（高） |

### 7.5 上电后的判断

| 现象 | 含义 | 下一步 |
|---|---|---|
| 串口有 `DDR` 输出 | **DDR 初始化通过** ✅ | 可以烧录了 |
| 串口无任何输出 | loader 没跑起来 | 查 24MHz、VDD_CPU、VCC_DDR、串口接线 |
| 电流打满 | 短路 | 断电，从 5V 往回查 |
| 电压都对但无输出 | 可能 BootROM 没跑 | 查复位、晶振、SPI/eMMC 是否有残留 |

### 7.6 确认无误后再烧录

```bash
make flash
```

烧录完成后重新上电，卡里就会启动 buildroot。

### 7.7 记录

首次上电建议记下：各路电压实测值、电流、串口前 20 行输出。
出问题时这些数据比"板子不启动"有用得多。

## 8. 硬件检查清单（9 个检查点）



### 一、上电前：元件是否贴齐

| # | 位置 | 现象 | 定位方法 |
|---|---|---|---|
| 1 | **以太网 25MHz 晶振** | `mdio_bus: MDIO device at address 0 is missing`，PHY 完全不应答 | 补焊后立刻识别为 `stmmac-1:00` |
| 2 | **eMMC** | 只能从 SD 卡启动，`Trying to boot from MMC2` 失败 | 贴片后 `mmc0:0001 DA4064` |
| 3 | **HDMI TX PHY 的 1µH 滤波电感** | 该轨只有 **0.7V**（应为 0.9V），显示器「无信号」 | 量 `HDMI_TX_AVDD_0V9`，正常 0.9V ±5% |
| 4 | **HDMI_TX_REXT 的 1.62kΩ ±1% 电阻** | VOP 正常输出、DDC/EDID 正常，但 **TMDS 一个信号都不出** | PHY 靠这颗电阻设定 TMDS 驱动电流，缺了物理层不工作 |
| 5 | **RJ45 座虚焊** | PHY 识别正常、`carrier: 0`、网口灯不亮 | 补焊后 `carrier` 变 1 |

> **注意第 3、4 项**：这两个缺件时，VOP、DDC、HPD、驱动 probe **全部正常**，日志没有一行报错，
> 唯一现象就是显示器说「无信号」。极容易误判成驱动问题。

> **注意第 5 项**：网口 LED 不亮**不能**作为没链路的判据——很多集成变压器的 RJ45，
> LED 由 PHY 的 LED0/LED1 驱动，那两根线没接时灯永远不亮。要看 `cat /sys/class/net/eth0/carrier`。

---

### 二、焊接质量

| # | 位置 | 现象 | 定位方法 |
|---|---|---|---|
| 6 | **SoC 的 CS1 球** | DDR 只认 **2GB / CS=1**（应为 4GB / CS=2） | 补焊后恢复；**注意可能是间歇性的**，连续两次启动一次 2GB 一次 4GB 就是临界 |
| 7 | **SoC 的 gpio2-3~9 一片球** | SDIO（WiFi）CMD5 永远超时 | 见下方"如何判断一整片引脚都断了" |

### 如何判断一整片引脚都断了

这是本项目最有价值的一条经验：

| 信号 | 引脚 | 状态 |
|---|---|---|
| SD 卡 D0-D3 / CMD / CLK | gpio2-**0~2** | ✅ 正常 |
| WiFi SDIO D0-D3 / CMD / CLK | gpio2-**3~8** | ❌ 全部断开 |
| WL_REG_ON | gpio2-**9** | ❌ 断开 |

**连续的引脚段全部失效，而相邻的低编号引脚正常** → 不是走线或器件问题，
而是 **SoC 这一侧的 BGA 球整片没回流**。

验证方法：万用表通断档，从模组焊盘量回 SoC 一侧；或在正常工作时用示波器看
SDIO_CLK 有没有波形（探测阶段应为 375kHz）。

---

### 三、供电设计

| # | 问题 | 现象 | 说明 |
|---|---|---|---|
| 8 | **两个 USB 通路各挂一颗 100µF 钽电容** | 一使能 VBUS 就**掉电复位**（DDR 重新训练）| **最终解法：每路 100µF → 47µF**（见下）|
| 9 | **两个 USB 口的 VBUS EN 都接到 GPIO0_A5** | USB3.0 Host 的 A 口**永远没电** | EVB 里 `vcc5v0_otg`(A5) 不常开，`vcc5v0_host`(A6) 才是 always-on |

### 为什么 2MΩ 也会拖垮电源

量 A 口 VBUS 对地是 **2MΩ**（看起来完全正常），但一使能就复位。

原因：**万用表量的是电容充满后的静态阻抗**。EN 拉高的瞬间电容是空的，
100µF 按负载开关（SY6280，2A 限流）充电约 0.25ms，这期间输入侧要瞬时提供
2A，把 5V 主轨拉到 PMIC 的 UVLO 以下 → 掉电复位。

> **注意：两个 USB 通路各有一颗 100µF，不是并联在同一个输出上。**
> 每个通路的负载开关各自限流，所以是**每一路**都在按 2A 充电，
> 两路同时上电时主轨压力更大。

**判断掉电复位还是芯片复位**：看串口复位后有没有重新打印 DDR 训练日志。
有 = 掉电；直接从 `U-Boot SPL board init` 开始 = 芯片复位。

**安全调试手法**（不会把自己锁死）：

```sh
echo vcc5v0-otg-regulator > /sys/bus/platform/drivers/reg-fixed-voltage/unbind
echo 5 > /sys/class/gpio/export          # GPIO0_A5
echo out > /sys/class/gpio/gpio5/direction
echo 1 > /sys/class/gpio/gpio5/value     # 若掉电，重启后默认关闭，不会循环
```

> `/sys/class/regulator/*/state` 是**只读**的，不能用来使能稳压器。

### 电容不能太小：hub 的瞬态电流

容量减到能启动只是第一步。实测 10µF 时本板能进系统，但插「hub + 键鼠接收器」
仍会复位——hub 自身的输入电容（常见 100~470µF）在插入瞬间要吸取大量电流，
10µF 的储能扛不住，5V 跌落导致复位。

### ✅ 最终解法：每一路 VBUS 电容定为 47µF

把两个 USB 通路上的 **100µF 各换成 47µF** 后，**问题彻底解决**：

- hub（Genesys Logic）+ 千兆网卡（AX88179）+ 键鼠全部正常工作
- 不再需要给 hub 外接电源

**这个参数既不能太大也不能太小**：

| 每路容量 | 结果 | 原因 |
|---|---|---|
| 100µF（原设计）| 一使能就掉电复位 | 单路冲击 2A，超负载开关限流，拉塌 5V |
| 10µF | 能启动，但 hub 一插就复位 | 储能不够，扛不住 hub 的瞬态电流 |
| **47µF** | **稳定** | 冲击在限流内，同时储能够带 hub |

所以这块板的答案是 **每路 47µF**。

> 下一版 PCB 建议：两个 USB 通路**各**预留 47µF（低 ESR 陶瓷或钽电容），
> 并确认负载开关的限流点 ≥ 1.5A。

---|---|
| 拆掉 2×100µF 钽电容 | 本板能启动，但带 hub 仍复位 |
| 继续减小电容 | 治标——hub 自身的 100~470µF 还在 |
| **串 47µH 电感（本方案）** | **治本**——限制电流变化率，与负载电容大小无关 |

> 下一版 PCB 建议直接在 VBUS 上预留电感位（47µH，注意选低 DCR 的功率电感，
> 否则大电流时压降明显）。

---

### 四、下一版 PCB 必改项

1. 其中一个 USB 口的 VBUS EN 改回 **GPIO0_A6**
2. VBUS 电容改 **22µF×2**
3. 负载开关换**带软启动**的型号，或 EN 加 RC 缓启动（100k + 1µF）
4. 评估 **5V 输入通路**的载流能力（适配器、走线、连接器）
5. 首板务必**逐路量电压**再上 SoC

---

### 五、一条通用经验

这块板子 9 个问题里有 5 个是"**漏贴元件**"。现象全都表现为"软件没配好"：

- 没有晶振 → PHY 不应答，看起来像设备树 PHY 地址写错
- 没有 REXT → TMDS 无输出，看起来像显示驱动问题
- 没有滤波电感 → 电压差了 0.2V，万用表粗看还以为正常

**排查顺序建议**：先量电压 → 再量通断 → 最后才怀疑软件。
软件日志"完全正常"但功能不工作时，几乎可以断定是硬件。

## 9. 实板改动（相对 V1.0 原理图）

首板点亮过程中做了这些改动，**复刻时建议直接做进 PCB**：

| 位置 | 改动 | 原因 |
|---|---|---|
| USB VBUS 电容 | 两个通路**各**一颗 100µF → **各**一颗 **47µF** | 100µF 的单路冲击超负载开关限流会掉电复位；10µF 又扛不住 hub 瞬态 |
| WB_VCCIO4 的 0Ω | 选 **3.3V**（与 AP6212 的 VDDIO 共用 VCCIO_WL）| 与 EVB 一致；设备树的 `vccio4-supply` 必须同步 |
| eMMC（U5）| **已贴片** `SDINBDA4-64G` | 原设计预留 |
| SoC | **换过一颗** | 首颗的 GPU 电源域损坏 + 部分 GPIO 球虚焊 |
| MIPI CSI / DSI | **未贴连接器** | 本板不用摄像头和 MIPI 屏，设备树里已全部关闭 |

> 更详细的每个问题的现象和定位方法见
> 本文档第 8 节。

## 10. 复现时容易看错的地方

1. **U4（SY8089AAAC）旁边标了 `NC`，但实际是贴片的**，负责给 LPDDR4X 的 VDDQ
   供 **0.6V**。照图直读会误以为 VDDQ 被短到 1.1V（那是 LPDDR4 的配置）。
2. **`4G_PWREN_H_GPIO0_C6` 实际控制 M.2 插槽的 3.3V**（`VCC3V3_M2`），
   不是 4G 模块专用 —— 插 NVMe 硬盘也必须拉高，否则硬盘不上电。
3. **`PCIE20_PERSTN_M1` 是 SoC 专用引脚**，不是 GPIO，设备树里不需要 `reset-gpios`。
4. **两个 USB 口的 VBUS 使能都接到了 GPIO0_A5**（画图时复制粘贴笔误），
   GPIO0_A6 悬空。设备树里用 `regulator-always-on` 绕过。
5. **VCCIO4 与 AP6212 的 VDDIO 共用 `VCCIO_WL`**，用 0Ω 在 1.8V/3.3V 之间切换。
   设备树的 `vccio4-supply` 必须和实物选择一致，否则 SoC 的 IO 单元会过驱。
6. **AP6212 的 WL_REG_ON（GPIO2_B1）有下拉**，无人驱动时保持低电平。
   设备树里改用独立的 always-on 稳压器驱动，避免和 pwrseq 抢同一个 GPIO。

## 11. 原理图页面索引

查图时按这个表定位，比一页页翻快得多。

| 页 | 内容 | 关键信息 |
|---|---|---|
| 1 | 封面 | 版本、日期、图纸信息 |
| 2 | SOC LOGIC | PMUIO1/PMUIO2/VCCIO1 电压域、I2C0/PMIC 中断、USB VBUS 使能、SD 检测 |
| 3 | SOC PWR | VDD_CPU / VDD_LOGIC / VDD_GPU / VDD_NPU 去耦与 VSS 球 |
| 4 | SOC DDR | LPDDR4X 1x32bit（`RS1G32LO4D2BDS-53BT`）、VDD1/VDD2/VDDQ 三路 |
| 5 | EMMC/FLASH | eMMC（U5，**已贴片**）+ SPI NOR/NAND 位（U19，未贴）|
| 6 | SOC DISPLAY | eDP / MIPI-DSI / HDMI TX、VCCIO3 域引脚（**本板只用 HDMI**）|
| 7 | PMIC 与 CPU 电源 | RK809 外围、TCS4525（VDD_CPU）、上电相关 |
| 8 | HDMI 与音频 | HDMI ESD/连接器/CEC、3.5mm 耳机座、MIC 电路 |
| 9 | MicroSD | SDMMC0、卡座、CD 检测、VCC3V3_SD |
| 10 | PMIC RK809 | DCDC（SW1~SW4）、LDO1~LDO9、管理脚、内置 CODEC、**VCCIO_WL 选择** |
| 11 | 电源输入 | VBUS→TPS54540→VCC5V0_SYS→VCC3V3_SYS、VDD_CPU_EXT、LPDDR4 VDDQ buck |
| 12 | USB | Type-C OTG（仅 USB2）、USB3 Host、VBUS 开关（SY6280）|
| 13 | SDIO WIFI/BT | AP6212：SDMMC1 + UART1 + WL/BT_REG_ON + 唤醒脚 |
| 14 | PCIe / M.2 | M.2 插槽（NVMe），`PCIE20_*` 单 lane、4G_PWREN、SIM 座 |

## 12. 许可

原理图 / PCB 的许可以立创开源平台上发布时选择的协议为准。
仓库内的软件部分（设备树、脚本、文档）见根目录 `LICENSE`。
