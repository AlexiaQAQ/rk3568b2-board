# RK3568B2 自定义开发板 Linux 6.1 板级支持

> 一块自制的 RK3568B2 开发板，基于 Rockchip Linux 6.1 SDK 的板级移植。
> 当前状态：**已在实物上跑通并长期使用** —— 能进 Weston 桌面、GPU 硬件加速、
> HDMI 1080p、以太网、NPU、键鼠输入全部正常；WiFi 因 SoC 焊接问题暂未通。

> 首板调试过程踩了 9 个硬件坑（漏贴元件、虚焊、供电余量），全部记录在
> [docs/bom-checklist.md](docs/bom-checklist.md)，想复刻的话**先看这份清单**。

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
| `hardware/README.md` | 硬件资料说明 + 原理图页面索引（**原理图/PCB 见立创开源平台**） |
| `docs/bringup-checklist.md` | **首板上电检查表**：短路测试、逐路电压、时钟复位 |

**为什么要基于 EVB 做减法**：这块板的电源树（RK809-5 + TCS4525）、AP6212、HDMI、USB 拓扑和 Rockchip RK3568 EVB1 高度一致，直接继承 1200 多行已验证配置，只覆盖差异项，比从零写可靠得多。

## 硬件概要

| 项 | 配置 |
|---|---|
| SoC | RK3568B2（FCCSP，最高 2.0GHz） |
| 内存 | LPDDR4X 4GB x32（`RS1G32LO4D2BDS-53BT`，实跑 1560MHz） |
| PMIC | RK809-5 @ I2C0 0x20 + TCS4525 @ I2C0 0x1c（VDD_CPU） |
| 存储 | **eMMC 64GB（SDINBDA4-64G，HS200 8bit）** 启动；SD 卡备用 |
| 以太网 | 1x RTL8211F-CG（GMAC0 / RGMII） |
| 无线 | AP6212：WiFi = SDMMC1，BT = UART1（m0 + 硬件流控） |
| 显示 | HDMI |
| 音频 | RK809 内置 codec（耳机 + MIC） |
| 扩展 | M.2 插槽（PCIe 2.1 x1，NVMe SSD） |
| USB | USB2.0 Type-C OTG + USB3.0 Host |
| 调试 | UART2 @ 1500000 |

详细引脚与电源分配见 [docs/hardware.md](docs/hardware.md)。

## 实测验证状态

以下是**在实物上跑出来的结果**，不是"编译通过"：

| 功能 | 状态 | 验证方式 |
|---|---|---|
| eMMC 启动 | ✅ | 4GB 双 rank，HS200 200MHz，`err_stats` 全 0 |
| Weston 桌面 | ✅ | 开机自启，键鼠可操作 |
| GPU（Mali-G52） | ✅ | `glmark2-es2-drm` @1080p **Score 102** |
| HDMI | ✅ | 1080p60，EDID/热插拔正常，`dclk 148.5MHz` |
| NPU | ✅ | rknpu v0.9.8，900MHz，`/dev/dri/renderD128` |
| 以太网 | ✅ | RTL8211F 千兆，ping **0% 丢包** |
| USB | ✅ | 开机自动供电，2.4G 键鼠正常（hub 需外接电源） |
| WiFi/BT | ❌ | SDIO CMD5 超时：SoC 的 gpio2-3~9 球虚焊 |
| M.2 / 摄像头 | — | 未使用，未验证 |

调试过程与每个坑的排查方法见 [docs/porting-notes.md](docs/porting-notes.md)（13 个实战案例）。

## 快速开始

### 0. 主机依赖

Ubuntu 22.04/24.04 上至少需要：

```bash
sudo apt-get install -y \
  build-essential git python3 python-is-python3 cmake \
  bison flex bc libssl-dev libelf-dev libncurses-dev device-tree-compiler \
  gawk texinfo diffstat chrpath patchelf expect gettext rsync unzip bzip2 lz4
```

几个容易漏的点：

- **`python-is-python3`**：SDK 的 `check-kernel.sh` 会检查 `python` 这个命令，
  只有 `python3` 的机器会直接报 `Your python is missing`。
- **`gawk`**：内核脚本里用了 gawk 的扩展语法，只有 mawk 时会在编译中途失败。
- **`gettext`（`msgmerge`）**：编 buildroot 时会检查 `msgmerge`，
  缺了会在 rootfs 阶段报 `Your msgmerge is missing`。
- **`repo sync` 需要 `/dev/shm`**：受限容器/沙箱里会报
  `PermissionError: /dev/shm/pym-*`，需放开该目录或换到普通主机环境。

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

推荐用仓库根目录的 `Makefile`，它会自动处理依赖 PATH、SDK 路径检查和板级文件安装：

```bash
cd board-port
make deps          # 检查主机依赖
make image         # 全量编译 + 打包 update.img
```

常用目标：

| 命令 | 作用 | 耗时 |
|---|---|---|
| `make deps` | 检查依赖，缺什么直接列出来 | 秒 |
| `make install` | 把 DTS / defconfig 装进 SDK | 秒 |
| `make check` | 只编 dtb，验证设备树语法 | ~3 秒 |
| `make kernel` | 编内核 | 1~2 分钟（增量） |
| `make uboot` | 编 u-boot | ~1 分钟 |
| `make buildroot` | 编根文件系统 | 首次 40 分钟 |
| `make image` | 全量编译并生成 `update.img` | 首次约 1 小时 |
| `make flash` | 用 `upgrade_tool` 烧录 | — |

SDK 不在默认位置（`~/rk3568-sdk`）时：

```bash
make image SDK=/path/to/sdk
```

`make` 会做两项前置检查，避免浪费时间：

1. **SDK 路径含非 ASCII 字符**直接报错 —— buildroot 的 `LC_ALL=C` 会让 Perl
   把中文路径解析成 `??????`，否则要等 40 分钟才在 glibc 阶段失败。
2. SDK 目录结构不对（缺 `kernel-6.1`）立即报错。

#### 不用 Makefile 的手动方式

```bash
export PATH="$HOME/.local/opt/sdk-deps/bin:$PATH"
cd "$SDK"
./build.sh lunch:rockchip_rk3568_myboard_v10_defconfig   # 换配置时执行一次
./build.sh kernel      # 或 uboot / buildroot / firmware / updateimg / all
```

### 4. 烧录

本板**没有 eMMC**，只能从 SD 卡启动，所以烧录目标就是 SD 卡。

#### 方式一：Linux + upgrade_tool（推荐）

```bash
# 1. 插好 SD 卡，板子进入 MaskROM（无启动介质时上电通常会自动进入）
# 2. 连 USB
cd ~/rk3568-sdk/tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool

sudo ./upgrade_tool ld                                       # 确认设备
sudo ./upgrade_tool db ../../../../u-boot/rk356x_spl_loader_v1.25.114.bin
sudo ./upgrade_tool ssd                                      # 选 SD 卡
sudo ./upgrade_tool uf ../../../../output/update/Image/update.img
```

或者直接：

```bash
cd board-port
make flash
```

它会把上面四步按顺序跑一遍。

**关键点**：MaskROM 状态下必须先 `db` 下载 boot，之后才能用 `ssd` / `uf` 通讯。
`ssd` 会列出可用存储（eMMC / SD / NAND），选 SD 卡前面的编号。

#### 方式二：Windows + RKDevTool

1. 装 Rockchip USB 驱动（DriverAssistant）
2. 打开 `RKDevTool.exe`，正常情况下会显示"发现一个 MASKROM 设备"
3. 点"升级固件" → "固件" → 选 `update.img` → "升级"
4. 若目标是 SD 卡，先点"高级功能"→ 切换存储到 SD

#### 进 MaskROM 的办法

- **首选**：板子上电时 BootROM 找不到可启动介质（无 eMMC、SD 为空），会**自动停在 MaskROM**
- 板上有 RECOVERY/UPDATE 按键时：按住不放再上电
- 已有系统时：`adb shell reboot loader` 或 `reboot loader`

#### 烧完怎么验证

串口（UART2 @ 1500000）应该能看到 loader 日志，内核起来后：

```bash
cat /proc/cpuinfo                    # 4 核
dmesg | grep -i ddr                  # 1560MHz
ip link                              # eth0
lspci                                # M.2 上的 NVMe
```

## 改名

板名统一用了占位符 `myboard`。改名为你的板子（例如 `taishan`）：

```bash
cd board-port
grep -rl myboard . | xargs sed -i 's/myboard/taishan/g'
# 然后把 rk3568-taishan-v10.dts 等文件名一起改掉
```

注意同时改 DTS 的 `model` / `compatible`。

## 已知问题 / TODO

### 硬件（下一版 PCB 要改的）

- [ ] **USB VBUS 使能接错脚**：两个口都接到 GPIO0_A5，应有一个改到 GPIO0_A6
- [ ] **USB VBUS 电容过大**：原设计两颗 100µF 钽电容，上电冲击会拖垮 5V，建议 22µF×2
- [ ] **USB 负载开关无软启动**：建议 EN 加 RC 缓启动，或换带软启动的型号
- [ ] **5V 输入通路载流能力**需评估（适配器规格、走线宽度、连接器额定值）
- [ ] **SoC 焊接**：gpio2-3~9 一片球虚焊导致 WiFi 不通（需重新植球/回流）

### 软件

- [ ] WiFi 待 SoC 焊接修好后验证（驱动、固件、SDIO 枚举链路本身已确认正常）
- [ ] M.2 NVMe 未实测
- [ ] u-boot 仍用 EVB 设备树（`rk3568-evb`）
- [ ] MAC 地址目前是随机生成的，正式产品应从 OTP 读取或固定

### 已经解决、仅作记录

- [x] eMMC 贴片并验证（HS200，4GB 双 rank）
- [x] RTL8211F PHY 地址 = 0，25MHz 晶振已补焊
- [x] HDMI 点亮（补齐 1µH 电感 + 1.62kΩ REXT）
- [x] GPU 可用（换掉一颗 GPU 电源域损坏的 SoC）

## 许可与溯源

- 板级 DTS 衍生自 Rockchip 的 `rk3568-evb1-ddr4-v10.dtsi` / `rk3568-evb.dtsi`，
  沿用其 `GPL-2.0+ OR MIT` 双许可声明（文件头 SPDX 已保留）。
- 本仓库的文档与脚本建议使用 MIT 或 CC-BY-4.0。
- **请勿转载 SDK 本体**（约 25GB 压缩包 + 25GB 源码树），只分发本仓库的板级差异。
- 原理图 / PCB / BOM 发布在**立创开源硬件平台（OSHWHub）**，见 [hardware/README.md](hardware/README.md)。

## English summary

Board support for a custom **RK3568B2** board running Rockchip Linux 6.1.
The device tree includes Rockchip's RK3568 EVB1 reference design and only
overrides the differences: 4GB LPDDR4X, SD-only boot, a single RTL8211F PHY,
AP6212 on SDMMC1/UART1, HDMI, and USB2 Type-C OTG + USB3 host.

Status: **device tree compiles and the resulting DTB was verified, not yet
tested on hardware.** See [docs/porting-notes.md](docs/porting-notes.md) for
the pin-level differences and pitfalls.
