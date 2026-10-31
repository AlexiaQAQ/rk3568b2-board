# 硬件资料

本板的**原理图、PCB、BOM、Gerber 发布在立创开源硬件平台（OSHWHub）**，
仓库里不重复维护二进制文件。

- **开源工程链接**：`<待补充：https://oshwhub.com/...>`
- 设计工具：嘉立创 EDA（专业版）
- 原理图版本：**V1.0**（A3，14 页）
- PCB 版本：V1.0
- 实板状态：**已点亮并在用**，改动记录见下方「实板改动」

## 为什么不在仓库里放 PDF

1. 立创开源平台可以**在线查看、直接克隆工程、看 BOM 与坐标**，比一堆 PDF 好用。
2. 原理图会随改版更新，仓库里存 PDF 容易出现"文档和代码不同步"。
3. 二进制文件进 git 历史后无法真正删干净。

`hardware/` 目录已加入 `.gitignore`，本地可以放自己的 PDF 副本，不会误提交。

## 关键器件

| 功能 | 型号 |
|---|---|
| SoC | RK3568B2（FCCSP，最高 2.0GHz） |
| 内存 | LPDDR4X 4GB x32 `RS1G32LO4D2BDS-53BT`（1560MHz） |
| eMMC | `SDINBDA4-64G`（64GB，HS200） |
| PMIC | RK809-5 + TCS4525（VDD_CPU） |
| 以太网 PHY | RTL8211F-CG |
| WiFi/BT | AP6212（SDIO + UART） |
| 音频 | RK809 内置 codec（3.5mm 耳机 + MIC） |

## 原理图页面索引

查图时按这个表定位，比一页页翻快得多。

| 页 | 内容 | 关键信息 |
|---|---|---|
| 1 | 封面 | 版本、日期、图纸信息 |
| 2 | SOC LOGIC | PMUIO1/PMUIO2/VCCIO1 电压域、I2C0/PMIC 中断、USB VBUS 使能、SD 检测 |
| 3 | SOC PWR | VDD_CPU / VDD_LOGIC / VDD_GPU / VDD_NPU 去耦与 VSS 球 |
| 4 | SOC DDR | LPDDR4X 1x32bit（`RS1G32LO4D2BDS-53BT`）、VDD1/VDD2/VDDQ 三路 |
| 5 | EMMC/FLASH | eMMC（U5，**已贴片**）+ SPI NOR/NAND 位（U19，未贴） |
| 6 | SOC DISPLAY | eDP / MIPI-DSI / HDMI TX、VCCIO3 域引脚（**本板只用 HDMI**）|
| 7 | PMIC 与 CPU 电源 | RK809 外围、TCS4525（VDD_CPU）、上电相关 |
| 8 | HDMI 与音频 | HDMI ESD/连接器/CEC、3.5mm 耳机座、MIC 电路 |
| 9 | MicroSD | SDMMC0、卡座、CD 检测、VCC3V3_SD |
| 10 | PMIC RK809 | DCDC（SW1~SW4）、LDO1~LDO9、管理脚、内置 CODEC、**VCCIO_WL 选择** |
| 11 | 电源输入 | VBUS→TPS54540→VCC5V0_SYS→VCC3V3_SYS、VDD_CPU_EXT、LPDDR4 VDDQ buck |
| 12 | USB | Type-C OTG（仅 USB2）、USB3 Host、VBUS 开关（SY6280）|
| 13 | SDIO WIFI/BT | AP6212：SDMMC1 + UART1 + WL/BT_REG_ON + 唤醒脚 |
| 14 | PCIe / M.2 | M.2 插槽（NVMe），`PCIE20_*` 单 lane、4G_PWREN、SIM 座 |

## 实板改动（相对 V1.0 原理图）

首板点亮过程中做了这些改动，**复刻时建议直接做进 PCB**：

| 位置 | 改动 | 原因 |
|---|---|---|
| USB VBUS 电容 | 100µF×2 → 保留 1 颗，最终定 **47µF** | 太大上电冲击超负载开关限流会掉电复位；太小扛不住 hub 的瞬态电流 |
| WB_VCCIO4 的 0Ω | 选 **3.3V**（与 AP6212 的 VDDIO 共用 VCCIO_WL）| 与 EVB 一致；设备树的 `vccio4-supply` 必须同步 |
| eMMC（U5）| **已贴片** `SDINBDA4-64G` | 原设计预留 |
| SoC | **换过一颗** | 首颗的 GPU 电源域损坏 + 部分 GPIO 球虚焊 |
| MIPI CSI / DSI | **未贴连接器** | 本板不用摄像头和 MIPI 屏，设备树里已全部关闭 |

> 更详细的每个问题的现象和定位方法见
> [../docs/bom-checklist.md](../docs/bom-checklist.md)。

## 复现时容易看错的地方

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

## 许可

原理图 / PCB 的许可以立创开源平台上发布时选择的协议为准。
仓库内的软件部分（设备树、脚本、文档）见根目录 `LICENSE`。
