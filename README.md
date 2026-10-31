# RK3568B2 自定义开发板 Linux 6.1 板级支持

> 一块自制的 RK3568B2 开发板，基于 Rockchip Linux 6.1 SDK 的板级移植。
>
> **当前状态：已在实物上跑通并长期使用。** Debian 12.15（XFCE 桌面）和
> Buildroot 两套系统都能跑，GPU 硬件加速、HDMI 1080p、以太网千兆、NPU、
> USB、3.5mm 耳机 + MIC、NTP 对时全部验证通过。
> 唯一未解决的是 WiFi 接收灵敏度（详见[已知问题](#已知问题--todo)）。

> 首板调试整理了 **9 个硬件检查点**（元件是否贴齐、连接可靠性、供电余量），
> 都写了现象和定位方法，见 [docs/bom-checklist.md](docs/bom-checklist.md)。
> **打算复刻这块板的话，建议上电前先对着这份清单核对一遍。**

[English summary](#english-summary)

## 这是什么

本仓库只包含**板级差异**，不含 SDK 本体（约 25GB）：

| 内容 | 说明 |
|---|---|
| `rk3568-myboard-v10.dts` | 板级设备树，`#include` Rockchip EVB1 参考设计后做减法 |
| `rockchip_rk3568_myboard_v10_defconfig` | SDK 板级配置 |
| `apply-to-sdk.sh` | 一键把板级文件装进 SDK（含 6 个补丁） |
| `Makefile` | `make kernel` / `firmware` / `flash` / `serial` 等 |
| `patch/0001~0006` | 可直接 `git apply` 的补丁 |
| `docs/workflow.md` | **完整流程**：环境 → 编译 → 烧录 → 验证 → 调试 → 排查方法论 |
| `docs/porting-notes.md` | **15 个实战案例**：每个坑的现象、排查、根因 |
| `docs/bom-checklist.md` | **9 个硬件检查点** + 现象描述 + 万用表定位方法 |
| `docs/hardware.md` | 硬件规格、电源树、IO 电压域、引脚分配 |
| `docs/debian-image.md` | **Debian 桌面镜像**：切换、构建、两个必改的坑 |
| `docs/bringup-checklist.md` | 首板上电检查表：短路测试、逐路电压、时钟复位 |
| `hardware/README.md` | 硬件资料说明（**原理图/PCB 见立创开源平台**）|

**为什么基于 EVB 做减法**：这块板的电源树（RK809-5 + TCS4525）、AP6212、
HDMI、USB 拓扑和 Rockchip RK3568 EVB1 高度一致，直接继承 1200 多行已验证配置，
只覆盖差异项，比从零写可靠得多。

## 硬件概要

| 项 | 配置 |
|---|---|
| SoC | RK3568B2（FCCSP，最高 2.0GHz） |
| 内存 | LPDDR4X **4GB** x32（`RS1G32LO4D2BDS-53BT`，实跑 1560MHz） |
| 存储 | **eMMC 64GB**（`SDINBDA4-64G`，HS200 8bit 200MHz）；SD 卡备用 |
| PMIC | RK809-5 @ I2C0 0x20 + TCS4525 @ I2C0 0x1c（VDD_CPU） |
| 以太网 | 1x RTL8211F-CG（GMAC0 / RGMII，1Gbps） |
| 无线 | AP6212：WiFi = SDMMC1，BT = UART1（m0 + 硬件流控） |
| 显示 | HDMI（1080p60） |
| 音频 | RK809 内置 codec（3.5mm 耳机 + MIC） |
| 扩展 | M.2 插槽（PCIe 2.1 x1，NVMe SSD，未实测） |
| USB | USB2.0 Type-C OTG + USB3.0 Host |
| 调试 | UART2 @ 1500000 |

详细引脚与电源分配见 [docs/hardware.md](docs/hardware.md)。

## 实测验证状态

以下都是**在实物上跑出来的结果**，不是"编译通过"：

| 功能 | 状态 | 验证方式 |
|---|---|---|
| eMMC 启动 | ✅ | 64GB，HS200 200MHz，`err_stats` 全 0 |
| Debian 桌面 | ✅ | Debian 12.15 + XFCE，lightdm 自动登录 |
| Buildroot 桌面 | ✅ | Weston 开机自启，8 秒进系统 |
| GPU（Mali-G52） | ✅ | `glmark2-es2-drm` @1080p **Score 102** |
| HDMI | ✅ | 1080p60，EDID/热插拔正常，`dclk 148.5MHz` |
| 3.5mm 耳机 | ✅ | `speaker-test -D hw:0,0`，插拔检测 + 自动切换 |
| MIC 录音 | ✅ | PipeWire 录音源，RMS 1178 / 峰值 12049 |
| NPU | ✅ | rknpu 0.9.8，900MHz，`/dev/dri/renderD129` |
| 以太网 | ✅ | RTL8211F **1Gbps 全双工**，ping 0% 丢包 |
| USB | ✅ | hub + 千兆网卡 + 键鼠，**无需外接电源** |
| 网络 + NTP | ✅ | DHCP 自动获取，chrony 误差 2 微秒 |
| WiFi/BT | ⚠️ | SDIO 通、**发射正常**（adhoc 可用），**接收灵敏度极低** |
| M.2 NVMe | — | 未实测 |

每个坑的现象与排查方法见 [docs/porting-notes.md](docs/porting-notes.md)。

## 快速开始

### 0. 主机依赖

Ubuntu 22.04/24.04 上至少需要：

```bash
sudo apt-get install -y \
  build-essential git python3 python-is-python3 cmake \
  bison flex bc libssl-dev libelf-dev libncurses-dev device-tree-compiler \
  gawk texinfo diffstat chrpath patchelf expect gettext rsync unzip bzip2 lz4

# 编 Debian rootfs 还需要
sudo apt-get install -y qemu-user-static
```

几个容易漏的点：

- **`python-is-python3`**：SDK 的 `check-kernel.sh` 会检查 `python` 命令，
  只有 `python3` 的机器会直接报 `Your python is missing`。
- **`gawk`**：内核脚本用了 gawk 扩展语法，只有 mawk 时会在编译中途失败。
- **`gettext`（`msgmerge`）**：编 buildroot 时会检查，缺了报 `msgmerge is missing`。
- **`qemu-user-static`**：编 Debian rootfs 必需（arm64 chroot）。

### 1. 准备 SDK

用立创·泰山派 1M 的 kernel 6.1 SDK（`tspi_1m_linux_kernel6.1_sdk_20260807`），
它本质上是通用的 `rk3566_rk3568-linux-6.1-stan-rkr7` 系列树。

**下载地址**（官方下载中心）：<https://wiki.lckfb.com/zh-hans/tspi-rk3566/download-center.html>

**官方编译教程**：<https://wiki.lckfb.com/zh-hans/tspi-rk3566/sdk-compilation/linux-compilation.html>

```bash
./extract_sdk.sh
cd extracted_sdk
python3 .repo/repo/repo sync -l -j$(nproc)
```

> `repo sync` 依赖 Python `multiprocessing` 的 `/dev/shm`，受限容器里会报
> `PermissionError: /dev/shm/pym-*`，需放开该目录。

### 2. 安装板级文件

```bash
cd board-port
./apply-to-sdk.sh                    # 默认 $HOME/rk3568-sdk
./apply-to-sdk.sh /path/to/sdk       # 指定路径
./apply-to-sdk.sh /path/to/sdk --build   # 装完顺便编 dtb 验证
```

脚本做 6 件事：

| 步骤 | 内容 |
|---|---|
| 1 | 拷 `rk3568-myboard-v10.dts` 到 `kernel-6.1/arch/arm64/boot/dts/rockchip/` |
| 2 | 拷 defconfig |
| 3 | 打 u-boot 补丁（默认 bootargs）|
| 3.5 | 打内核补丁（电源域失败不 panic）|
| 3.6 | 打开 `CONFIG_DRM_IGNORE_IOTCL_PERMIT`（SDK 打包脚本强制要求）|
| 3.7 | bcmdhd 改用 SDIO 带内中断（不依赖 WL_HOST_WAKE）|
| 4 | 注册 dtb 到 Makefile |

### 3. 编译

用仓库根目录的 `Makefile`，它处理 PATH、SDK 检查、板级文件安装：

```bash
cd board-port
make deps          # 检查主机依赖
make kernel        # 编内核 + dtb → boot.img
make firmware      # 组装 update.img
```

常用目标：

| 命令 | 作用 | 耗时 |
|---|---|---|
| `make deps` | 检查依赖，缺什么直接列出 | 秒 |
| `make install` | 把 DTS / defconfig 装进 SDK | 秒 |
| `make check` | 只编 dtb，验证设备树语法 | ~1 秒 |
| `make kernel` | 编内核 + dtb → `boot.img` | 1~2 分钟（增量）|
| `make uboot` | 编 u-boot | ~1 分钟 |
| `make buildroot` | 编 buildroot 根文件系统 | 首次 40 分钟 |
| `make firmware` | 组装 `update.img`（**不重编 rootfs**）| ~2 分钟 |
| `make image` | 全量编译并生成 `update.img` | 首次约 1 小时 |
| `make flash` | 用 `upgrade_tool` 烧录 | — |
| `make serial` | 串口终端（1500000 8N1）| — |

SDK 不在默认位置：

```bash
make kernel SDK=/path/to/sdk
```

> ⚠️ **不要直接跑 `./build.sh all`**——它会联网从 `sources.buildroot.net`
> 下载所有软件包，国内经常超时。分开跑 `kernel` 和 `firmware` 即可。

#### 国内镜像（编 buildroot / rootfs 才需要）

`buildroot` 的软件包源码可以用南京大学镜像代替官方站：

**镜像地址**：<https://mirror.nju.edu.cn/buildroot/>

配置方法：

```bash
cd ~/rk3568-sdk/buildroot

# 改配置片段（以后重新生成 defconfig 也生效）
sed -i 's|^BR2_PRIMARY_SITE=.*|BR2_PRIMARY_SITE="https://mirror.nju.edu.cn/buildroot/"|' \
    configs/rockchip/base/common.config
sed -i 's|^BR2_BACKUP_SITE=.*|BR2_BACKUP_SITE="https://sources.buildroot.net"|' \
    configs/rockchip/base/common.config

# 同步到已生成的 build 配置（立即生效）
for f in output/*/*/.config; do
    sed -i 's|^BR2_PRIMARY_SITE=.*|BR2_PRIMARY_SITE="https://mirror.nju.edu.cn/buildroot/"|' "$f"
done
```

保留 `BR2_BACKUP_SITE` 指向官方站，镜像个别新版本没同步时会自动回落。

> 详细说明见 [docs/workflow.md](docs/workflow.md) 3.8 节。

#### 不用 Makefile 的手动方式

```bash
export PATH="$HOME/.local/opt/sdk-deps/bin:$PATH"
cd "$SDK"
./build.sh rockchip_rk3568_myboard_v10_defconfig   # 换配置时执行一次
./build.sh kernel      # 或 uboot / rootfs / firmware
```

### 4. 烧录

本板从 **eMMC** 启动。

#### 分区偏移（512 字节扇区）

| 分区 | 起始扇区 | 大小 |
|---|---|---|
| uboot | 16384 (0x4000) | 4 MB |
| boot | **32768 (0x8000)** | 40 MB |
| rootfs | **491520 (0x78000)** | 12 GB |
| oem / userdata | — | — |

#### 方式一：upgrade_tool（推荐）

```bash
UT=~/rk3568-sdk/tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool

# 板子进 MaskROM（按住 MASKROM 键上电）
$UT ld          # 必须显示 Mode=Maskrom
$UT db ~/rk3568-sdk/u-boot/rk356x_spl_loader_v1.25.114.bin
$UT ssd         # 输入 2 = eMMC
$UT wl 32768 ~/rk3568-sdk/output/firmware/boot.img    # 只更新内核
$UT rd
```

整包烧写（含 rootfs，4.5 GB）：

```bash
$UT uf ~/rk3568-sdk/output/firmware/update.img
```

> **常见错误**：`Download boot failed / check ddr` 说明 MaskROM 放太久，
> **彻底断电**（拔电源等 10 秒）再按住 MASKROM 上电即可。
> 另外先 `sudo systemctl stop ModemManager`，它会抢 USB 设备。

#### 方式二：从系统里进 Loader 模式（最省事）

```bash
# 板子上
sudo reboot loader

# 电脑上（Loader 模式不需要 db）
$UT ld
$UT wl 32768 ~/rk3568-sdk/output/firmware/boot.img
$UT rd
```

#### 方式三：Windows + RKDevTool

1. 装 Rockchip USB 驱动（DriverAssistant）
2. 打开 `RKDevTool.exe`，应显示"发现一个 MASKROM 设备"
3. "升级固件" → 选 `update.img` → "升级"

#### 烧完验证

```bash
cat /proc/asound/cards                       # RK809 / SPDIF / HDMI
cat /sys/class/net/*/speed                   # 1000
dmesg | grep -i 'GPU identified'             # Mali-G52
cat /sys/class/drm/card0-HDMI-A-1/status     # connected
```

## 两套系统

| | Buildroot | Debian 12 |
|---|---|---|
| 大小 | 961 MB | 4513 MB |
| 启动 | ~8 秒 | 30~60 秒 |
| 桌面 | Weston（Wayland） | **XFCE（X11）** |
| 包管理 | 无 | **apt** |
| 默认用户 | root（无密码）| `linaro` / `linaro` |

切换方法见 [docs/debian-image.md](docs/debian-image.md)。

## 改名

板名统一用了占位符 `myboard`。改名为你的板子（例如 `taishan`）：

```bash
cd board-port
grep -rl myboard . | xargs sed -i 's/myboard/taishan/g'
# 然后把 rk3568-taishan-v10.dts 等文件名一起改掉
```

注意同时改 DTS 的 `model` / `compatible`。

## 已知问题 / TODO

### 硬件

- [ ] **WiFi 接收灵敏度极低**：SDIO 通、发射正常（adhoc 下手机能看到 SSID），
      但周围 AP 全部收不到，只偶尔收到近在咫尺的强信号。
      天线、走线、供电、时钟、监管域均已排除，需要频谱仪进一步定位。
- [ ] **M.2 NVMe** 未实测

### 硬件（下一版 PCB 建议）

- [ ] **USB VBUS 使能接错脚**：两个口都接到 GPIO0_A5，应有一个改到 GPIO0_A6
      （本板已在设备树里用 `regulator-always-on` 绕过）
- [ ] **USB VBUS 电容**：最终定为 **47µF**（太小带不动 hub，太大上电冲击超限流）
- [ ] **USB 负载开关无软启动**：建议 EN 加 RC 缓启动
- [ ] **5V 输入通路载流能力**需评估（适配器规格、走线宽度、连接器额定值）

### 软件

- [ ] u-boot 仍用 EVB 设备树（`rk3568-evb`）
- [ ] MAC 地址随机生成，正式产品应从 OTP 读取或固定
- [ ] HDMI 音频优先级高于 RK809，默认输出会被抢（可用 `pactl set-default-sink` 切）

### 已验证通过的硬件项

- [x] eMMC 64GB，HS200 200MHz
- [x] HDMI 1080p60（含 TMDS 基准电阻）
- [x] GPU Mali-G52 硬件加速
- [x] DDR 4GB 双 rank（CS1 已确认连通）
- [x] USB：hub + 千兆网卡 + 键鼠，无需外接电源
- [x] VCCIO4 电压域与板上 0Ω 选择一致（3.3V）
- [x] 3.5mm 耳机 + MIC
- [x] 以太网 1Gbps、NPU、NTP 对时

> 每一项的排查过程见 [docs/bom-checklist.md](docs/bom-checklist.md) 与
> [docs/porting-notes.md](docs/porting-notes.md)。

## 许可与溯源

- 板级 DTS 衍生自 Rockchip 的 `rk3568-evb1-ddr4-v10.dtsi` / `rk3568-evb.dtsi`，
  沿用其 `GPL-2.0+ OR MIT` 双许可声明（文件头 SPDX 已保留）。
- 本仓库的文档与脚本建议使用 MIT 或 CC-BY-4.0。
- **请勿转载 SDK 本体**（约 25GB），只分发本仓库的板级差异。
- 原理图 / PCB / BOM 发布在**立创开源硬件平台（OSHWHub）**，见 [hardware/README.md](hardware/README.md)。

## English summary

Board support for a custom **RK3568B2** board running Rockchip Linux 6.1.

The device tree includes Rockchip's RK3568 EVB1 reference design and only
overrides the differences: 4GB LPDDR4X, 64GB eMMC, a single RTL8211F PHY,
AP6212 on SDMMC1/UART1, HDMI, RK809 audio, and USB2 Type-C OTG + USB3 host.

**Status: fully working on hardware, in daily use.** Both Debian 12.15 (XFCE)
and Buildroot images boot and run. Verified: Mali-G52 GPU (glmark2 score 102),
HDMI 1080p60, Gigabit Ethernet, NPU, USB hubs with keyboard/mouse and a USB
Gigabit NIC (no external power needed), 3.5mm headphone + microphone, and
NTP-synced time.

The only unresolved issue is **WiFi receive sensitivity**: the SDIO bus,
firmware loading, and RF transmission all work (an ad-hoc network is visible
to nearby phones), but the receiver cannot hear normal access points.
Antenna, PCB trace, supply rails, clock, and regulatory domain have all been
ruled out — diagnosing further needs a spectrum analyzer.

Nine hardware defects were found during bring-up (missing parts, cold solder
joints, power margin); eight are fixed. Every one is documented with its
symptom, root cause, and how it was located in
[docs/bom-checklist.md](docs/bom-checklist.md) and
[docs/porting-notes.md](docs/porting-notes.md).
