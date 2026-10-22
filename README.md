# RK3568B2 自定义开发板 Linux 6.1 板级支持

> 一块自制的 RK3568B2 开发板，基于 Rockchip Linux 6.1 SDK 的板级移植。
> 当前状态：**设备树编译验证通过，硬件配置已按原理图核对，尚未上板实测**。

[English summary](#english-summary)

## 这是什么

本仓库只包含**板级差异**，不含 SDK 本体：

| 内容 | 说明 |
|---|---|
| `rk3568-myboard-v10.dts` | 板级设备树，`#include` Rockchip RVB1 参考设计后做减法 |
| `rockchip_rk3568_myboard_v10_defconfig` | SDK 板级配置（两行） |
| `patch/` | 可直接 `git apply` 到 SDK 的补丁 |
| `docs/hardware.md` | 硬件规格、电源树、IO 电压域、引脚分配 |
| `docs/porting-notes.md` | 移植思路、与 EVB 的差异、踩过的坑、验证记录 |

**为什么要基于 EVB 做减法**：这块板的电源树（RK809-5 + TCS4525）、AP6212、HDMI、USB 拓扑和 Rockchip RK3568 EVB1 高度一致，直接继承 1200 多行已验证配置，只覆盖差异项，比从零写可靠得多。

## 硬件概要

| 项 | 配置 |
|---|---|
| SoC | RK3568B2（FCCSP，最高 2.0GHz） |
| 内存 | LPDDR4X 4GB x32（`RS1G32LO4D2BDS-53BT`，实跑 1560MHz） |
| PMIC | RK809-5 @ I2C0 0x20 + TCS4525 @ I2C0 0x1c（VDD_CPU） |
| 存储 | SD 卡启动；eMMC（U5）与 SPI Flash（U19）有焊接位 |
| 以太网 | 1x RTL8211F-CG（GMAC0 / RGMII） |
| 无线 | AP6212：WiFi = SDMMC1，BT = UART1（m0 + 硬件流控） |
| 显示 | HDMI |
| 音频 | RK809 内置 codec（耳机 + MIC） |
| 扩展 | M.2 插槽（PCIe 2.1 x1，NVMe SSD） |
| USB | USB2.0 Type-C OTG + USB3.0 Host |
| 调试 | UART2 @ 1500000 |

详细引脚与电源分配见 [docs/hardware.md](docs/hardware.md)。

## 快速开始

### 1. 准备 SDK

使用立创·泰山派 1M 的 kernel 6.1 SDK（`tspi_1m_linux_kernel6.1_sdk_20260807`），
它本质上是通用的 `rk3566_rk3568-linux-6.1-stan-rkr7` 系列树，包含 RK3568 的 EVB 配置。

```bash
./extract_sdk.sh
cd extracted_sdk
python3 .repo/repo/repo sync -l -j$(nproc)
```

> `repo sync` 依赖 Python `multiprocessing` 的 `/dev/shm`。在受限沙箱/容器里会报
> `PermissionError: /dev/shm/pym-*`，需要放开该目录。

### 2. 安装板级文件

```bash
cd board-port
./apply-to-sdk.sh /path/to/extracted_sdk        # 只安装
./apply-to-sdk.sh /path/to/extracted_sdk --build # 安装并单独编译 dtb 验证
```

脚本会做四件事：拷 DTS、拷 defconfig、往 `dts/rockchip/Makefile` 追加一行、可选编译 dtb。

也可以手工打补丁：

```bash
cd extracted_sdk/kernel-6.1  && git apply ../../patch/0001-*.patch
cd ../device/rockchip        && git apply ../../patch/0002-*.patch
```

补丁已用 `git apply --check -R` 反向校验过，与当前 SDK 树一致。

### 3. 编译

```bash
cd extracted_sdk
./build.sh lunch:rockchip_rk3568_myboard_v10_defconfig
./build.sh kernel     # 先单独编内核，最快暴露 DTS/config 问题
./build.sh uboot
./build.sh all        # 编 rootfs 并打包 update.img
```

产物在 `rockdev/`，`update.img` 为整包。

### 4. 烧录

MaskROM 模式 + `upgrade_tool`（Linux）或瑞芯微工具（Windows），烧 `update.img`。

## 改名

板名统一用了占位符 `myboard`。改名为你的板子（例如 `taishan`）：

```bash
cd board-port
grep -rl myboard . | xargs sed -i 's/myboard/taishan/g'
# 然后把 rk3568-taishan-v10.dts 等文件名一起改掉
```

注意同时改 DTS 的 `model` / `compatible`。

## 已知问题 / TODO

软件侧已验证到"能编译"为止，以下是**上板前需要人工确认**的项：

- [ ] **DDR 的 VDDQ 电压**（LPDDR4X 应为 0.6V，图中 0.6V buck 标 NC，见 hardware.md 2.5）
- [ ] eMMC 未贴片（预留）；M.2 插槽待实测
- [ ] **RTL8211F** 的 PHY 地址（PHYAD strap）与复位脚 GPIO2_PD3
- [ ] **u-boot 仍使用 EVB 设备树**（`rk3568-evb`），必要时需单独建一份
- [ ] **分区表**沿用 EVB 的 `parameter-buildroot-fit.txt`，偏移未按本板存储调整
- [ ] LDO8（`vcca1v8_pmu`）同时供 DDR VDD1，需实测满载纹波

## 许可与溯源

- 板级 DTS 衍生自 Rockchip 的 `rk3568-evb1-ddr4-v10.dtsi` / `rk3568-evb.dtsi`，
  沿用其 `GPL-2.0+ OR MIT` 双许可声明（文件头 SPDX 已保留）。
- 本仓库的文档与脚本建议使用 MIT 或 CC-BY-4.0。
- **请勿转载 SDK 本体**（约 25GB 压缩包 + 25GB 源码树），只分发本仓库的板级差异。

## English summary

Board support for a custom **RK3568B2** board running Rockchip Linux 6.1.
The device tree includes Rockchip's RK3568 EVB1 reference design and only
overrides the differences: 4GB LPDDR4X, SD-only boot, a single RTL8211F PHY,
AP6212 on SDMMC1/UART1, HDMI, and USB2 Type-C OTG + USB3 host.

Status: **device tree compiles and the resulting DTB was verified, not yet
tested on hardware.** See [docs/porting-notes.md](docs/porting-notes.md) for
the pin-level differences and pitfalls.
