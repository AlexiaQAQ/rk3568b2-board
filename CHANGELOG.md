# 更新日志

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/) 的简化形式，
版本号对应板级硬件版本 + 修订。

## [0.8.0] - 2026-10-29

**以太网确认 1Gbps 全双工；WiFi 硬件通路问题定性**

### 以太网

之前多次只协商到 10/100Mbps 并频繁掉线，板子自己的日志就写着
`Downshift ... check cabling`。重新处理 RJ45 连接器后恢复：

```
eth0: Link is Up - 1Gbps/Full - flow control rx/tx
speed = 1000, duplex = full
```

排障时踩过一个坑：**PC 侧的 YT8531S 厂商驱动也会「亮几秒就断」**，
一开始误判成板子问题。双端排查很重要。

吞吐实测 `ssh` 管道约 20MB/s（≈160Mbps）——瓶颈是 A55 的 SSH 加密，
不是链路本身。

### WiFi

用主线 `brcmfmac` 驱动做了交叉验证（内核开 `CONFIG_BRCMFMAC=m`，
固件重命名为 `brcmfmac43430-sdio.bin/.txt`）：

```
brcmfmac: using brcm/brcmfmac43430-sdio for chip BCM43430/1
brcmfmac: Firmware: BCM43430/1 wl0: Jun 13 2018 version 7.45.96.24
```

**依然是 0 个 AP。** 两套独立驱动 × 三颗模组（含别处验证正常的）= 全部失败，
软件层面可以完全排除，问题锁定在板子的 RF 物理通路。

待办：量「模组天线焊盘 ↔ 天线座中心针」通断，确认是走线断还是引脚虚焊。

## [0.7.0] - 2026-10-27

**USB 供电修复：根因是电容冲击电流，不是短路**

### 两个问题

| 现象 | 原因 | 修复 |
|---|---|---|
| USB3.0 Host（A 口）完全没 5V | 原理图笔误，两个口的 VBUS EN 都接到 GPIO0_A5；而 EVB 里 `vcc5v0_otg` 不常开 | DT 里加 `regulator-always-on` |
| 一加 always-on 就无限重启（掉电复位） | SY6280 输出后级 **两颗 100µF 钽电容**，上电瞬间 200µF 冲击电流把 5V 拉到 UVLO 以下 | 拆掉一颗，剩 100µF（符合 USB 规范） |

A 口 VBUS 对地实测 **2MΩ**——万用表看不出电容的冲击问题，这点很有迷惑性。

### 调试手法

调试阶段用 sysfs 手动拉高 GPIO0_A5，掉电重启后自动恢复、不会锁死：

```sh
echo vcc5v0-otg-regulator > /sys/bus/platform/drivers/reg-fixed-voltage/unbind
echo 5 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio5/direction
echo 1 > /sys/class/gpio/gpio5/value
```

`/sys/class/regulator/*/state` 是只读的，不能用来使能。

### 补充：USB hub 需要外部供电

拆掉 100µF 后空载正常，但插「hub + 键鼠接收器」仍会复位——hub 自身的输入电容
叠加后，热插拔冲击依然超出 SY6280 限流，开关进入打嗝保护拖垮 5V 主轨。

**实测给 hub 接辅助供电后键鼠立即正常。** 结论：板载 USB 只能带低功耗设备，
带 hub 必须用带电源的 hub。根因是 5V 通路余量不足（适配器功率 + 走线阻抗 +
负载开关无软启动），不是软件问题。

### 下一版 PCB

- 其中一个口的 EN 改回 GPIO0_A6
- VBUS 电容改 22µF×2，或换带软启动的负载开关
- 评估 5V 输入通路的载流能力（适配器规格、走线宽度、连接器额定电流）

## [0.6.1] - 2026-10-27

**以太网打通：RTL8211F 链路建立，ping 0% 丢包**

### 两个硬件问题

| 问题 | 现象 | 修复 |
|---|---|---|
| RTL8211F 缺 25MHz 晶振 | `MDIO device at address 0 is missing` | 补焊晶振，PHY 识别为 `stmmac-1:00` |
| RJ45 座虚焊 | PHY 识别正常但 `carrier: 0`，无链路 | 补焊 RJ45，`carrier` 变 1 |

> 网口 LED 不亮**不能**作为没链路的判据：集成变压器的 RJ45，LED 由 PHY 的
> LED0/LED1 驱动，那两根线没接时灯永远不亮。判断链路看 `carrier`。

### 验证

直连 PC（无 DHCP，手配静态 IP）：

```
ping 192.168.1.100 → 3 packets transmitted, 3 received, 0% packet loss, avg 1.36ms
```

通了之后可直接 ssh/scp，调试不再依赖串口。

## [0.6.0] - 2026-10-26

**HDMI 点亮，GPU 验收通过（glmark2 Score 102 @1080p）**

### HDMI 三个漏贴元件（现象完全相同）

| 问题 | 现象 | 修复 |
|---|---|---|
| DDC/线材接触 | EDID 0 字节，`i2cdetect` 只见假应答 | 换线 / 检查接触 |
| `HDMI_TX_AVDD_0V9` 缺 **1µH** 滤波电感 | 该轨只有 **0.7V** | 补电感，恢复 0.9V |
| `HDMI_TX_REXT` 缺 **1.62kΩ** 基准电阻 | **TMDS 完全无输出** | 补 1.62kΩ ±1% 到地 |

三个故障表现都是「显示器无信号」，而 VOP、DDC、HPD、驱动 probe 全程正常、日志无报错。

判别要点：**「无信号」= TMDS 不在跑（查 PHY 供电/REXT）；「黑屏有背光」= TMDS 在跑，查 VOP 图层。**

注意：量到 TMDS 引脚 3.3V 不能证明 PHY 工作——那是显示器端 50Ω 端接的上拉电压。

### GPU 验收

```
glmark2-es2-drm @ 1920x1080
  shading/pulsar/ideas   : 120~121 fps
  effect2d (5x5 kernel)  : 38 fps
  terrain                : 13 fps
  shadow                 : 74 fps
  glmark2 Score: 102
```

Mali-G52 2EE @1080p 全屏，属正常水平（重负载项是 terrain 和 5×5 卷积）。

### 其它

- 屏幕停在 Rockchip logo 属正常：无 compositor 接管，内核控制台在串口 ttyS2
- `dw-hdmi: error -ENXIO: IRQ index 1 not found` 无害（CEC 唤醒中断，RK3568 无此线）
- HDMI 驱动为老版 `dw-hdmi.c`（非 QP 变体），设备树 `rockchip,phy-table` 继承自 EVB

## [0.5.0] - 2026-10-26

**换 SoC 后 GPU 复活；以太网通了；4GB 内存恢复**

### 关键结论：旧 SoC 的 GPU 电源域损坏

前一版把 GPU 归因为「板子供电问题」。换一片 RK3568 后，同一块板、同一版固件：

```
mali fde60000.gpu: Register LUT 00070200 initialized for GPU arch 0x00070400
mali fde60000.gpu: GPU identified as 0x2 arch 7.4.0 r1p0 status 0
/dev/mali0 存在，devfreq 200~800MHz
```

所以 `&gpu` 现在正式打开。之前的判断——`failed to get ack on domain 'gpu'`、
`synchronous external abort`、VDD_GPU 只有 0.18V——是**旧 SoC 内部损坏**导致的，
不是板级设计问题。

### 硬件变更

| 项 | 结果 |
|---|---|
| RK3568 | 换了一片（旧片 GPU 域损坏） |
| 25MHz 晶振 | 焊上 → **RTL8211F 应答，以太网 PHY 正常** |
| SoC 补焊 | DDR 从 2GB 恢复到 **4GB 双 rank** |

### 新 SoC 的两点差异

- **speed bin 2 → 1**：内核按 OTP 自动降档，暂时不用干预
- **DDR 4GB 是间歇性的**：连续两次启动出现过 2GB / 4GB 各一次，
  CS1 的球还在临界状态，容量不对时优先怀疑虚焊

### 新增调试手段：/boot 下的 dtbo 覆盖层

u-boot 支持从 rootfs 动态加载设备树覆盖层，改完重启即生效：

```sh
echo '...' | base64 -d > /boot/overlays/gpu-on.dtbo
sed -i 's/^# overlays=leds-test.dtbo/overlays=gpu-on.dtbo/' /boot/ubootEnv.txt
sync && reboot
```

**不用编译 boot.img、不用 MaskROM**。串口是唯一人机通道的情况下，这个非常关键。
详见 `docs/porting-notes.md` 7.11。

## [0.4.0] - 2026-10-25

**eMMC 贴片 + 从 eMMC 启动 + GPU/NPU 供电澄清 + NPU 打开**

### 硬件变更

- 贴片 eMMC：**SDINBDA4-64G**（SanDisk iNAND，64GB，8-bit，VDDF=3.3V / VDD=1.8V）
- 更换板子 UART2 的 RX 排母（此前串口只能收不能发）

### eMMC

| 项 | 结果 |
|---|---|
| 识别 | `mmc0:0001 DA4064 58.2 GiB`，含 boot0/boot1/rpmb |
| 速率 | **HS200 / 200MHz / 8-bit / 1.8V** |
| 错误计数 | Command/Data Timeout、CRC、Tuning 全部 **0** |
| 分区 | rootfs 12G、userdata 46G（首次启动自动扩容） |
| 烧录 | MaskROM + `upgrade_tool uf`，`Download IDB Success` 一次通过 |

### 之前 SD 烧录全部失败的真正原因

`Download IDB Fail` / `Writing master gpt failed` / `Write LBA failed` 这三个错误，
只发生在 **SD 通路**；同样的代码在 eMMC 上一次成功。所以不是 u-boot 的 MMC 写驱动问题，
而是 SD 卡座那条链路。**换 eMMC 后彻底绕开。**

### IO 电源域澄清

`list-iodomain.sh` 会打印 `vccio2_vsel: 3.3V` 并刷一屏红色警告，但那是**误报**：

```c
/* drivers/soc/rockchip/io-domain.c */
case 3: /* vccio2 */
        break;        /* 空实现，GRF 的 vsel 位永远是复位默认 0 */
```

RK3568 的 VCCIO2 电压由 **FLASH_VOL_SEL 引脚**硬件决定，不由寄存器控制。
本板 VCCIO2 = 1.8V（0Ω 接 VCC_1V8），FLASH_VOL_SEL 接 VCC3V3_PMU（高电平）= 1.8V 模式，
**配置正确**。

### NPU

`&rknpu` 打开后工作正常：

```
RKNPU fde40000.npu: rknpu iommu is enabled, using iommu mode
[drm] Initialized rknpu 0.9.8 for fde40000.npu on minor 1
NPU load: 0%    freq: 900000000
/dev/dri/renderD128、renderD129
```

dmesg 里两条报错都是**无害噪声**：

- `can't request region for resource [mem 0xfde40000-0xfde4ffff]`
  —— `rknpu_mmu`(0xfde4b000) 落在 NPU 的 64KB 区段内，驱动遇到 -EBUSY 会回退到 `devm_ioremap`
- `error -ENXIO: IRQ npu_irq not found`
  —— 6.1 分支先按名字取中断、失败后回退到按索引取，回退是成功的。
  本版已在设备树补 `interrupt-names = "npu_irq"` 消除（需烧入 12:01 之后的 boot.img）

### GPU：确认为硬件供电问题，保持禁用

2026-10-25 打开 `&gpu` 实测，日志给出定性结论：

```
rockchip-pm-domain: failed to get ack on domain 'gpu',
                    target_idle = 0, target_ack = 0, val=0x4e
rockchip_pmu_set_idle_request: power domain 'gpu' failed (idle=0), continue anyway
mali fde60000.gpu: Kernel DDK version g25p0-00eac0
Internal error: synchronous external abort: 0000000096000010
pc : kbase_reg_get_gpu_id+0xc/0x40
```

**GPU 电源域上电握手拿不到 ack**，随后 kbase 第一次读 GPU 寄存器就总线 abort。

注意 `regulator_summary` 里的 `vdd_gpu = 900mV` 只是**稳压器设定值**，
不代表 SoC 侧真的收到电压；实测 VDD_GPU = 0V，与"电源域起不来"完全吻合。

待查硬件：GPU buck 的**电感 / 反馈分压 / 使能脚**。
供电恢复后把 `&gpu` 的 `status` 改回 `okay` 即可，其余沿用 EVB 配置。

## [0.3.1] - 2026-10-24

**4-bit 复测失败回退到 1-bit，并修掉打包卡点**

### 修正 0.3.0 的错误结论

0.3.0 里写的“4-bit 补焊后正常”**不成立**。补焊后复测 4-bit：
`dw_mci_request_end` WARN 72 次 + 11 次 `I/O error`，`mount` 失败。
DAT1~DAT3 至少还有一条有问题，镜像统一改回 `bus-width = <1>`、`max-frequency = <50000000>`。

### 一次被误判为“更糟”的启动失败

日志里出现 `JBD2: recovery failed` / `EXT4-fs: error loading journal` / `VFS: Cannot open root device`，
看起来比之前更严重，实际是**之前 4-bit 的 I/O 错误把 `mmcblk1p6` 的 ext4 journal 写坏了**：
卡枚举、8 个分区、PARTUUID 全部正常，没有任何链路错误。重烧镜像即恢复。
详见 `docs/porting-notes.md` 7.6。

### 修复

- `patch/0005-kernel-enable-drm-ignore-iotcl.patch`：打开 `CONFIG_DRM_IGNORE_IOTCL_PERMIT`，
  否则 `device/rockchip/common/scripts/check-kernel.sh` 直接中止，`update.img` 根本打不出来
- `apply-to-sdk.sh` 增加 3.6 步，幂等追加该配置到 `kernel/arch/arm64/configs/rk3568.config`
  （该文件是每次构建都会重新套用的 fragment，直接改 `.config` 会在下次构建被覆盖）

## [0.3.0] - 2026-10-24

**首次上板启动到用户态 shell**（`root@rk3568-buildroot:/#`）。

### 板上实测结论

| 项 | 结果 |
|---|---|
| DDR | LPDDR4X 4GB @1560MHz，训练通过 |
| PMIC / IO 域 | RK809 + TCS4525 正常；vccio4/6=1.8V 生效 |
| SD 卡 | 4-bit 补焊后正常（此前 1-bit 规避） |
| 音频 | RK809 codec 加载 |
| WiFi/BT 控制脚 | rfkill 解析正确（GPIO2_B1/B2/B7/C0/C1） |
| 以太网 | GMAC1 控制器起来，**PHY 地址 0 无应答** |
| WiFi 模块 | SDIO 未识别（mmc2 停在 375kHz） |
| GPU | VDD_GPU 实测 0V → 暂时禁用，weston 无法启动 |

### 新增补丁

- `patch/0004-kernel-pm-domain-no-panic.patch`：电源域握手失败由 panic 改为报错继续

### 踩坑记录

- 设备树里加 `/chosen` 会导致内核零输出（由 u-boot 提供 bootargs 即可）
- SD SDR104/148.5MHz 在本板不可用；4-bit 50MHz 补焊后正常

## [0.2.0] - 2026-10-22

首次完成**端到端构建**（kernel → u-boot → buildroot → update.img）。

### 构建产物

| 文件 | 大小 | 说明 |
|---|---|---|
| `output/update/Image/update.img` | 1006 MB | 整包固件 |
| `boot.img` | 40 MB | 内核 + dtb + resource |
| `rootfs.ext2` | 761 MB | buildroot 根文件系统 |
| `MiniLoaderAll.bin` | 472 KB | loader（DDR 1560MHz） |

`boot.img` 内已确认包含 `model = "My RK3568B2 Board V10"`。

### 环境问题记录（都会在别人机器上复现）

1. 缺 `python` 命令（只有 `python3`）→ 装 `python-is-python3`
2. 缺 `msgmerge` → 装 `gettext`
3. `makeinfo` 缺 Perl 模块 `Text::Unidecode` → 装 `libtext-unidecode-perl`
4. **SDK 路径不能含中文**：buildroot 内部 `LC_ALL=C` 时 Perl 无法处理
   UTF-8 路径，报 `could not create directory '/home/alexia/??????/...'`。
   必须放在纯 ASCII 路径下构建。

## [0.1.3] - 2026-10-22

### 澄清

- DDR VDDQ 确认由 U4（SY8089AAAC）输出 **0.6V**，符合 LPDDR4X 规范；
  此前依据图中 `NC` 标注做出的"超压"判断系误判，已从文档移除，
  并记录误判原因（模板残留注释）

## [0.1.2] - 2026-10-22

确认 M.2 插槽用途为 NVMe SSD 后的板级补充。

### 新增

- 启用 `pcie2x1`（PCIe 2.1 x1，1 lane），对应 M.2 座的 `PCIE20_*`
- 新增 `vcc3v3_m2` 固定稳压器：GPIO0_C6 使能、always-on，
  否则 M.2 插槽的 3.3V 不会上电

### 变更

- `pcie3x2` / `pcie30phy` / `sata2` 保持关闭（本板未使用）
- M.2 座的 USB3.1 差分对本版未连接，仅 PCIe 可用

### 说明

- `PCIE20_PERSTN_M1` 等为 SoC 专用引脚，非 GPIO，故 `pcie2x1` 不设 `reset-gpios`

## [0.1.1] - 2026-10-22

根据原理图 `sch.pdf` 复核后的修正。

### 修复

- 主输入电源：EVB 的 `dc_12v`(12V) 在本板不存在，改为自定义 `vbus`(5V) 稳压器
  作为 `vcc3v3_sys` / `vcc5v0_sys` 的上游
- 音频：原理图确认有耳机座与 MIC，`rk809_sound` 由 disabled 改为 **okay**

### 确认

- PMUIO2 = 3.3V（接 VCC3V3_PMU）
- USB VBUS 使能：OTG = GPIO0_A5，HOST1 = GPIO0_A6
- VCCIO_WL = 1.8V（R55 0Ω 到 VCC_1V8，R56 到 3.3V 为 NC）
- SD 卡检测走 SDMMC0_DET（GPIO0_A4）
- 电源树（RK809 4x DCDC + 9x LDO + TCS4525）与 EVB1 一致

### 新增发现

- 板上有 eMMC（U5）与 SPI Flash（U19）焊接位，当前仍按 SD 启动处理
- 有 mini-PCIe / M.2 4G 模块座（PCIe x1 + USB3，`4G_PWREN` = GPIO0_C6）
- ⚠️ DDR 的 VDDQ：LPDDR4X 应为 0.6V，但 0.6V buck（U4）标注 NC，
  需确认 BOM，详见 `docs/hardware.md` 2.5

## [0.1.0] - 2026-10-21

首个可编译的板级支持，尚未上板实测。

### 新增

- `rk3568-myboard-v10.dts`：基于 Rockchip RK3568 EVB1 参考设计的板级设备树
- `rockchip_rk3568_myboard_v10_defconfig`：SDK 板级配置
- `patch/0001-kernel-add-rk3568-myboard-v10-dts.patch`：内核侧补丁
- `patch/0002-device-add-myboard-defconfig.patch`：device/rockchip 侧补丁
- `apply-to-sdk.sh`：一键安装板级文件并可选编译 dtb 验证
- `docs/hardware.md`、`docs/porting-notes.md`

### 板级适配

- 4GB LPDDR4X（`RS1G32LO4D2BDS-53BT`），DDR 频率 1560MHz
- 仅 SD 卡启动：关闭 `sdhci`、`sfc`、`nandc0`
- 单网口 RTL8211F：关闭 `gmac1`、`mdio1`
- 仅 HDMI：关闭 `dsi0`、`dsi1`、`edp` 及对应 route
- 关闭摄像头、触摸、板载 codec、心跳灯
- AP6212：WiFi 从 SDMMC2 改为 **SDMMC1**，BT 从 UART8 改为 **UART1 (m0, RTC/CTS)**
- 新增 WL_REG_ON(GPIO2_B1)、WL_HOST_WAKE(GPIO2_B2)、BT_REG_ON(GPIO2_B7) 的 pinctrl
- IO 电压域：`vccio4` / `vccio6` 由 3.3V 改为 **1.8V**
- 显式打开调试串口 UART2

### 修复

- 蓝牙节点与 EVB 同名导致属性被 dtc 合并（`uart_rts_gpios` 误占 WL_REG_ON），
  改为独立的 `bt-platdata` 节点
- UART2 默认关闭导致无串口输出

### 验证

- 设备树编译通过，生成的 DTB 反编译后逐项核对（详见 `docs/porting-notes.md` 第 4 节）
- **未上板实测**
