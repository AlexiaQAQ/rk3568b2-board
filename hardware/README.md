# 硬件资料

本板的**原理图、PCB、BOM、Gerber 发布在立创开源硬件平台（OSHWHub）**，
仓库里不重复维护二进制文件。

- **开源工程链接**：`<待补充：https://oshwhub.com/...>`
- 设计工具：嘉立创 EDA（专业版）
- 原理图版本：**V1.0**（A3，14 页）
- PCB 版本：V1.0

## 为什么不在仓库里放 PDF

1. 立创开源平台可以**在线查看、直接克隆工程、看 BOM 与坐标**，比一堆 PDF 好用。
2. 原理图会随改版更新，仓库里存 PDF 容易出现"文档和代码不同步"。
3. 二进制文件进 git 历史后无法真正删干净。

`hardware/` 目录已加入 `.gitignore`，本地可以放自己的 PDF 副本，不会误提交。

## 原理图页面索引

查图时按这个表定位，比一页页翻快得多。

| 页 | 内容 | 关键信息 |
|---|---|---|
| 1 | 封面 | 版本、日期、图纸信息 |
| 2 | SOC LOGIC | PMUIO1/PMUIO2/VCCIO1 电压域、I2C0/PMIC 中断、USB VBUS 使能、SD 检测 |
| 3 | SOC PWR | VDD_CPU / VDD_LOGIC / VDD_GPU / VDD_NPU 去耦与 VSS 球 |
| 4 | SOC DDR | LPDDR4X 1x32bit（`RS1G32LO4D2BDS-53BT`）、VDD1/VDD2/VDDQ 三路 |
| 5 | EMMC/FLASH | eMMC（U5，**当前未贴片**）+ SPI NOR/NAND 位（U19） |
| 6 | SOC DISPLAY | eDP / MIPI-DSI / HDMI TX、VCCIO3 域引脚 |
| 7 | PMIC 与 CPU 电源 | RK809 外围、TCS4525（VDD_CPU）、上电相关 |
| 8 | HDMI 与音频 | HDMI ESD/连接器/CEC、3.5mm 耳机座、MIC 电路 |
| 9 | MicroSD | SDMMC0、卡座、CD 检测、VCC3V3_SD |
| 10 | PMIC RK809 | DCDC（SW1~SW4）、LDO1~LDO9、管理脚、内置 CODEC、VCCIO_WL 选择 |
| 11 | 电源输入 | VBUS→TPS54540→VCC5V0_SYS→VCC3V3_SYS、VDD_CPU_EXT、LPDDR4 VDDQ buck |
| 12 | USB | Type-C OTG（仅 USB2）、USB3 Host、VBUS 开关（SY6280） |
| 13 | SDIO WIFI/BT | AP6212：SDMMC1 + UART1 + WL/BT_REG_ON + 唤醒脚 |
| 14 | PCIe / M.2 | M.2 插槽（NVMe），`PCIE20_*` 单 lane、4G_PWREN、SIM 座 |

## 复现时容易看错的地方

1. **U4（SY8089AAAC）旁边标了 `NC`，但实际是贴片的**，负责给 LPDDR4X 的 VDDQ
   供 **0.6V**。照图直读会误以为 VDDQ 被短到 1.1V（那是 LPDDR4 的配置）。
2. **`4G_PWREN_H_GPIO0_C6` 实际控制 M.2 插槽的 3.3V**（`VCC3V3_M2`），
   不是 4G 模块专用 —— 插 NVMe 硬盘也必须拉高，否则硬盘不上电。
3. **`PCIE20_PERSTN_M1` 是 SoC 专用引脚**，不是 GPIO，设备树里不需要 `reset-gpios`。
4. eMMC 位置（U5）有焊盘但**当前未贴片**，启动靠 SD 卡。

## 许可

原理图 / PCB 的许可以立创开源平台上发布时选择的协议为准。
仓库内的软件部分（设备树、脚本、文档）见根目录 `LICENSE`。
