# 移植笔记

> 记录这块板从 Rockchip RK3568 EVB1 参考设计移植到 Linux 6.1 的全部改动、
> 踩过的坑，以及验证过程。给后来者（也包括三个月后的自己）看。

## 1. 基线

| 项 | 值 |
|---|---|
| SDK | 立创·泰山派 1M kernel6.1 SDK `20260807` |
| 分支 | `rk3566_rk3568-linux-6.1-stan-rkr7`（系列通用树，含 RK3568 EVB 配置） |
| 内核 | Linux 6.1.141 |
| device/rockchip 提交 | `cf9addc` |
| kernel 提交 | `1e5deed` |
| 参照 defconfig | `rockchip_rk3568_evb1_ddr4_v10_defconfig` |
| 参照 DTS | `rk3568-evb1-ddr4-v10.dts` → `rk3568-evb1-ddr4-v10.dtsi` → `rk3568-evb.dtsi` |

这份 SDK 虽然名字带 `rk3566`，但 `device/rockchip` 里同时有
`rockchip_rk3568_evb1_ddr4_v10_defconfig`、`rk3568_pcie_ep_lp4x_v10_defconfig`，
`docs/cn/RK3566_RK3568` 也在包内，是通用树而不是 3566 专用，可直接作为 RK3568 基线。

## 2. 与 EVB1 的差异

| 项 | EVB1 | 本板 | 处理 |
|---|---|---|---|
| DDR | DDR4 2GB | LPDDR4X 4GB | 只换 rkbin 的 DDR bin |
| 以太网 | 双口 | 单口 RTL8211F | 关 `gmac1` / `mdio1` |
| 存储 | eMMC + SD + SPI NAND | 只有 SD | 关 `sdhci` / `sfc` / `nandc0` |
| 显示 | eDP + DSI + HDMI | 只有 HDMI | 关 `dsi0/dsi1/edp/route_*` |
| 摄像头 / 触摸 | 有 | 无 | 全部 disabled |
| 板载 codec | RK809 codec | 未使用 | 关 `rk809_sound` |
| WiFi SDIO | SDMMC2 | **SDMMC1** | 换节点 + 重定义 pwrseq |
| BT | UART8 | **UART1 (m0)** | 换节点，带 RTS/CTS |
| WL_REG_ON | GPIO3_D5 | **GPIO2_B1** | 新 pinctrl 组 |
| WL_HOST_WAKE | GPIO3_D4 | **GPIO2_B2** | 新 pinctrl 组 |
| BT_REG_ON | — | **GPIO2_B7** | 新 pinctrl 组 |
| VCCIO4 / VCCIO6 | 3.3V | **1.8V** | 覆盖 `pmu_io_domains` |
| 电源树（SW/LDO） | — | 完全一致 | 不修改 |

结论：**电源树零改动**，工作量集中在"关掉没有的外设 + 重接无线"。

## 3. 踩过的坑

### 坑 1：UART2 默认是关的

`rk356x.dtsi` 里 `serial@fe660000`（UART2）的 `status = "disabled"`，
所有参考板都靠板上 dts 显式打开：

```dts
&uart2 {
	status = "okay";
};
```

漏掉这句，板子能正常启动，但**串口一个字节都没有**，第一次上电会非常难受。

### 坑 2：DTS 节点名相同会被合并，改 label 没用

最初想覆盖 EVB 的蓝牙节点，写成了：

```dts
bt_platdata: wireless-bluetooth {   /* ← 节点名和 EVB 的一样 */
	compatible = "bluetooth-platdata";
	bt_port = "/dev/ttyS1";
	...
};
```

dtc 把两个同名节点**合并**了，结果 EVB 的残留属性混进来：

```
uart_rts_gpios = <&gpio2 RK_PB1 GPIO_ACTIVE_LOW>   ← 本板的 WL_REG_ON！
pinctrl-1 = <&uart8_gpios>
```

`bluetooth-platdata` 会去申请 GPIO2_B1，而 `sdio_pwrseq` 已经持有它，
必然 `-EBUSY`。改成节点名 `bt-platdata`（label 也要跟着改）之后才彻底分离。

**教训**：用 include 方式继承参考设计时，新增节点必须换一个和参考 dts 不同的**节点名**。

### 坑 3：VCCIO4 / VCCIO6 是 1.8V，不是 3.3V

EVB 里：

```dts
vccio4-supply = <&vcc_3v3>;
vccio6-supply = <&vcc_3v3>;
```

本板这两路实际接 `VCC_1V8`，必须覆盖：

```dts
vccio4-supply = <&vcc_1v8>;
vccio6-supply = <&vcc_1v8>;
```

`vccio4` 同时是 SDIO 的 IO 域，配错会导致 WiFi 枚举不到，
长期还可能让 IO 工作在错误电平上。

另外 `vccio2` 在 `drivers/soc/rockchip/io-domain.c` 的 `soc_data_rk3568_pmu`
里是空实现（`case 3: /* vccio2 */ break;`），写了也不生效，不必配。

### 坑 4：DDR 跑不到颗粒的额定频率

颗粒标称 3733Mbps，但 RK3568 的 rkbin 只有 920 / 1056 / 1332 / 1560MHz 四档，
没有 1600 以上。1560MHz = 3120Mbps，是这颗 SoC 的实际上限。

`rkbin/RKBOOT/RK3568MINIALL.ini` 默认就是 `rk3568_ddr_1560MHz_v1.25.bin`，
**不需要改**。

## 4. 编译验证记录

2026-10-21，`extract_sdk.sh` + `repo sync -l` 完成后实测：

```
DTC     arch/arm64/boot/dts/rockchip/rk3568-myboard-v10.dtb
✓ 编译通过（191 KB）
```

反编译 dtb 后逐项核对：

| 检查项 | 结果 |
|---|---|
| `vccio4` / `vccio6` → `vcc_1v8`（DCDC_REG5） | ✅ |
| `vccio5` / `vccio7` → `vcc_3v3`（SWITCH_REG1） | ✅ |
| `pmuio2` → LDO6、`vccio1` → LDO4、`vccio3` → LDO5 | ✅ |
| `sdmmc1`：4-bit + non-removable + SDR104 + pwrseq | ✅ okay |
| `sdio_pwrseq` reset = GPIO2_B1，ACTIVE_LOW | ✅ |
| `sdmmc2` / `sdhci` / `sfc` 关闭 | ✅ disabled |
| `gmac0` okay（RGMII），`gmac1` disabled | ✅ |
| `uart1` m0 + RTS/CTS 三组 pinctrl | ✅ |
| `uart2` 调试口 | ✅ okay |
| BT 节点：`/dev/ttyS1`，reset=GPIO2_B7，wake=GPIO2_C1，host_wake=GPIO2_C0 | ✅ |
| EVB 遗留 `wireless-bluetooth` | ✅ disabled |

> 注意：以上是**编译与 DTB 内容**的验证，不等于上板可用。
> 硬件相关的项（PHY 地址、VBUS、DDR 稳定性）仍须实测。

## 5. u-boot 说明

本移植**没有**改 u-boot 设备树，仍用：

```
CONFIG_UBOOT_CFG    = "rk3568"
CONFIG_DEFAULT_DEVICE_TREE = "rk3568-evb"
```

首次点亮通常没问题（u-boot 主要需要 SD 和串口，两者引脚与 EVB 一致）。
如果出现在 u-boot 阶段 SD 枚举不到、或 SPL 之后停住，再为 u-boot 单独建板级 dts：

```bash
cd u-boot
cp arch/arm/dts/rk3568-evb.dts arch/arm/dts/rk3568-myboard.dts
# 改 model/compatible，并把 configs/rk3568_defconfig 里的
# CONFIG_DEFAULT_DEVICE_TREE 指过去
```

## 6. 上板验证顺序

1. **UART2 @ 1500000** 看 loader 是否有输出（无输出 → DDR bin 或电源问题）
2. u-boot：`mmc list` 确认 SD 识别
3. 内核：`dmesg | grep -i ddr` 确认 1560MHz；`/proc/cpuinfo` 确认 4 核
4. `ip link` 看 eth0（RTL8211F 的 PHY 地址/复位最容易错）
5. `ifconfig wlan0 up && iwlist wlan0 scan` 验证 AP6212
6. `hciconfig -a` 验证 BT；若无反应，先把 `BT,reset_gpio` 的极性从
   `GPIO_ACTIVE_HIGH` 改为 `GPIO_ACTIVE_LOW` 再试

## 7. 原理图核对（2026-10-22）

拿 `sch.pdf`（14 页，嘉立创 EDA 导出）逐页对了一遍，结论如下。

### 7.1 被证实的判断

| 项 | 原理图证据 |
|---|---|
| PMUIO2 = 3.3V | 第 2 页 U1.7：PMUIO2 引脚 W19 接 `VCC3V3_PMU`；PMUIO1 标注 "3.3V Only" |
| USB OTG VBUS 使能 = GPIO0_A5 | 第 2 页 `USB_OTG_PWREN_H_GPIO0_A5`，第 12 页驱动 U37(SY6280) |
| USB HOST1 VBUS 使能 = GPIO0_A6 | 第 2 页 `USB_HOST_PWREN_H_GPIO0_A6` |
| VCCIO_WL = 1.8V | 第 10 页：`VCC_1V8 → R55 0Ω → VCCIO_WL`，`VCC_3V3 → R56 NC` |
| SD 卡检测 = SDMMC0_DET | 第 2 页 `SDMMC0_DET/SATA_CP_DET/.../GPIO0_A4`，第 9 页接 TF 座 CD |
| 电源树与 EVB 一致 | 第 10 页 RK809 四路 DCDC + 九路 LDO 与 EVB 完全对应 |
| TCS4525 供 VDD_CPU | 第 11 页 U3，I2C0，默认 0.9V |

### 7.2 与口头描述不一致的地方

**a) 板上有 eMMC（U5）和 SPI Flash 位（U19）。**
之前说"存储只有 SD 卡"。图上是 SD + eMMC + SPI NOR/NAND 三个位，
eMMC 当前**未贴片**，属于预留。设备树里 `sdhci` / `sfc` 保持关闭，
将来贴片后打开 `sdhci` 即可。

**b) 有一个 M.2 插槽，主要用途是 NVMe SSD。**
第 14 页：座子是 M.2（3.3V 在 70/72/74 脚），只接了 **一对 PCIe lane**
（`PCIE20_TX/RX/REFCLK`）+ 一组 USB3.1（这一版打叉未接）+ UIM。
所以对应的是 **`pcie2x1`**（PCIe 2.1 x1，专用引脚），不是 `pcie3x2`。

`PCIE20_PERSTN_M1` / `CLKREQN_M1` / `WAKEN_M1` 是 SoC 的专用功能引脚，
经 22Ω 串阻直达座子，**不是 GPIO**，所以 `pcie2x1` 里不需要 `reset-gpios`。

供电 `VCC3V3_M2` 由 SY8113(U31) 从 VCC5V0_SYS 产生，使能脚
`4G_PWREN_H_GPIO0_C6`；设备树里做成了 always-on 的 `vcc3v3_m2`。
否则插上 SSD 也不会转 —— 这是很容易漏的一步。

**c) 板载音频是有的。**
第 10 页 RK809 CODEC 段有 HP_OUT_L/R、MIC；第 8 页有 3.5mm 耳机座和 MIC 电路。
之前把 `rk809_sound` 关掉了，现已改为 `okay`。

**d) 主输入是 5V VBUS，不是 12V。**
第 11 页：DC 座/USB → SMBJ33A → **TPS54540DDAR** → `VCC5V0_SYS` → SY8113 → `VCC3V3_SYS`。
EVB 的 `dc_12v` 在本板根本不存在，设备树里已用自定义 `vbus` 5V 稳压器替代。

### 7.3 DDR 的 VDDQ（曾经的误判，已澄清）

第 11 页 `VCC_LPDDR4_VCC` 段：U4（SY8089AAAC）产生 `VCC0V6_DDR`，
但图上标了 `NC`，同时 `R64 = 0Ω`，注释写「Default: LPDDR4=1.1V」，
当时据此判断"VDDQ 可能被短到 1.1V、对 LPDDR4X 属超压"。

**经设计者确认：U4 正常贴片并输出 0.6V**，`NC` 是模板残留标注。
LPDDR4X 的三路供电（1.8/1.1/0.6V）都正确，DDR 侧无需软件干预。

教训：原理图上的 `NC` / `Default:` 注释可能是从参考设计抄来的残留，
涉及电源的关键判断应当直接问设计者或查 BOM，不要只看图注。

### 7.4 SD 卡 4-bit 数据线问题（实测）

首板在内核里读 SD 卡持续报错，表现为：

```
I/O error, dev mmcblk1, sector 492127 op 0x0:(READ)
EXT4-fs error (device mmcblk1p6): Error while async write back metadata
EXT4-fs error: Detected aborted journal
WARNING: CPU: 0 ... dw_mci_request_end (WARN_ON(host->cmd || host->data))
```

同时总线速度在 375kHz 与 50MHz 之间反复跳（每次失败后重新初始化）。

| 配置 | 结果 |
|---|---|
| 150MHz + SDR104（EVB 默认） | 大量 I/O 错误，文件系统损坏 |
| 50MHz + 4-bit | 仍有 I/O 错误（扇区 0 都读失败） |
| **50MHz + 1-bit** | **零 I/O 错误，正常启动** |

**结论：DAT1/DAT2/DAT3 至少一条有硬件问题**（虚焊 / 短路 / 走线）。
u-boot 能读 40MB 内核而内核读不了，是因为两者对总线位宽与时序的处理不同。

临时规避：设备树里 `bus-width = <1>;`。
根治：查 SD 座到 SoC 的 DAT1~DAT3 走线与焊接，修好后改回 `<4>` 提速。

残余现象：改成 1-bit 后仍有少量 `dw_mci_request_end` WARN + 偶发重新初始化，
但不产生数据错误，暂不阻塞使用（疑似卡检测或 VCC3V3_SD 供电瞬态）。

### 7.5 以太网 PHY 未应答（硬件未焊完整）

GMAC1 控制器正常起来，但 MDIO 上找不到 PHY：

```
mdio_bus stmmac-1: MDIO device at address 0 is missing
rk_gmac-dwmac fe010000.ethernet eth0: Cannot attach to PHY (error: -19)
```

**原因：RTL8211F 的 25MHz 晶振尚未焊接**，PHY 无时钟故不应答。
与设备树配置无关，焊上晶振后 PHY 立刻被识别（PHYAD = 0）：

```
eth0: PHY [stmmac-1:00] driver [RTL8211F Gigabit Ethernet] (irq=POLL)
Read rgmii delayline from vendor: tx = 0x42, rx = 0x25
```

晶振焊上后 PHY 识别正常，但**链路仍然起不来**（`carrier: 0`，`operstate: down`，网口灯不亮）。
补焊 RJ45 座之后 `carrier` 变成 1，链路建立。

> 注意：网口 LED 不亮**不能**作为「没链路」的判据——很多集成变压器的 RJ45，
> LED 由 PHY 的 LED0/LED1 引脚驱动，那两根线没接时灯永远不亮，但链路可以是好的。
> 判断链路要看 `cat /sys/class/net/eth0/carrier`。

#### 直连电脑的验证方法（无 DHCP）

网线直连 PC 时没有 DHCP 服务器，`udhcpc` 会一直 `broadcasting discover`，这是正常的。
两端手配静态 IP 即可：

```sh
# 板子
ip addr add 192.168.1.100/24 dev eth0
ip link set eth0 up

# 电脑（Linux）
sudo ip addr add 192.168.1.1/24 dev enp44s0

# 验证
ping -c3 192.168.1.100     # 电脑 → 板子
```

实测 `0% packet loss, rtt avg 1.3ms`。通了之后直接用 scp 传文件，
调试完全不需要再经过串口。

### 7.6 一次“看起来更糟”的启动失败：其实是 rootfs 日志损坏

4-bit 复测失败后重新烧过一次 1-bit 镜像，串口里出现的是这样一串：

```
mmc1: new high speed SDXC card at address b36b
mmcblk1: mmc1:b36b SDABC 58.2 GiB
 mmcblk1: p1 p2 p3 p4 p5 p6 p7 p8        <- 8 个分区全部读到
JBD2: Invalid checksum recovering data block 148 in log
JBD2: Invalid checksum recovering data block 119 in log
...（连续几十条）
JBD2: recovery failed
EXT4-fs (mmcblk1p6): error loading journal
VFS: Cannot open root device "PARTUUID=614e0000-..." error -5
Kernel panic - not syncing: VFS: Unable to mount root fs
```

要点：

- 卡枚举、分区表、PARTUUID **全部正常**，没有任何 `I/O error` / `dw_mci_request_end` WARN
  —— 说明此时 SD 链路是好的（1-bit@50MHz 生效了）。
- 真正挂掉的是 **ext4 日志**：之前 4-bit 那几次 I/O 错误 + 非正常断电，
  把 `mmcblk1p6` 的 journal 写坏了。日志回放校验不过 → `error loading journal`
  → 内核找不到可挂载的根 → panic。
- 所以这一版**不是** SD 硬件进一步恶化，而是上几次失败留下的文件系统后果。

处理：

| 做法 | 说明 |
|---|---|
| **重烧镜像（推荐）** | `update.img` 里是干净的 ext4，烧完即恢复 |
| 临时救急 | bootargs 加 `rootflags=noload` 跳过日志回放，进系统后 `e2fsck -fy /dev/mmcblk1p6` |

经验：调试 SD/存储问题时，**先分清是链路错误还是文件系统后果**。
出现 `JBD2 ... recovery failed` 这类日志时不要再怀疑引脚，直接查文件系统/重烧。

### 7.7 eMMC 贴片后：SD 烧录失败的真正原因是卡座

2026-10-25 贴上 eMMC（SDINBDA4-64G）后，同样的 `upgrade_tool` 命令一次成功：

```
Prepare IDB Start
Prepare IDB Success
Download IDB Start
Download IDB Success
Download Firmware Success
Upgrade firmware ok.
```

而在此之前，SD 上是三种不同的失败：

| 命令 | 报错 |
|---|---|
| `uf`（整包） | `Download IDB Fail` |
| `di -p`（写参数） | `Writing master gpt failed!` |
| `wl 16384`（任意 LBA） | `Write LBA failed!` |

全都在**写**阶段失败，读一直正常。当时怀疑过"我们自己编的 u-boot 的 MMC 写驱动坏了"，
eMMC 一次通过就否掉了这个猜测——**问题在 SD 卡座那条链路**。

结论：调试存储问题时，先用另一种介质交叉验证，比死磕一种通路快得多。

### 7.8 IO 电源域脚本的 vccio2 是误报

启动时 `/usr/bin/list-iodomain.sh` 会刷一屏红字，其中 `vccio2_vsel: 3.3V` 看着像配错了。
实际是驱动空实现导致寄存器保持复位默认值：

```c
/* drivers/soc/rockchip/io-domain.c : rk3568_iodomain_write() */
case 3: /* vccio2 */
        break;
```

RK3568 的 VCCIO2 电压由 `FLASH_VOL_SEL` 引脚硬件决定：

| VCCIO2 供电 | FLASH_VOL_SEL |
|---|---|
| 1.8V | 高 |
| 3.3V | 低 |

本板 VCCIO2 = VCC_1V8(1.8V)，FLASH_VOL_SEL = VCC3V3_PMU(高)，一致，无需改动。
**这一行在 RK3568 上没有参考价值，不要被它带偏。**

### 7.9 NPU 打开后的两条"错误"是噪声

```
RKNPU fde40000.npu: can't request region for resource [mem 0xfde40000-0xfde4ffff]
RKNPU fde40000.npu: error -ENXIO: IRQ npu_irq not found
```

- 第一条：`rknpu_mmu` 在 `0xfde4b000`，落在 NPU 的 64KB 区段内。
  驱动对 -EBUSY 有回退：
  ```c
  base = devm_ioremap_resource(dev, res);
  if (PTR_ERR(base) == -EBUSY)
          base = devm_ioremap(dev, res->start, resource_size(res));
  ```
- 第二条：6.1 分支先 `platform_get_irq_byname("npu_irq")`，失败后回退
  `platform_get_irq(pdev, i)`。回退成功，驱动照常工作。
  在设备树补 `interrupt-names = "npu_irq";` 可以消掉这条。

判据不是这两条日志，而是：

```
NPU load: 0%     freq: 900000000
/dev/dri/renderD128、renderD129
```

### 7.10 换 SoC 之后：GPU 复活，内存变成间歇性 2GB

前面 7.9 之后又走了一段弯路，根因是 **SoC 本身有问题**。

#### 现象链

| 阶段 | 现象 |
|---|---|
| 旧 SoC | GPU 电源域 `failed to get ack on domain 'gpu'`，kbase 读寄存器触发 `synchronous external abort` |
| 旧 SoC | VDD_GPU 实测 **0.18V**（PMIC 侧 enabled、900mV、有 consumer，完全正常） |
| 旧 SoC | 拆掉电感量 SW2 = 3.3V（buck 能满占空比输出），装上电感就被拉低 → **负载侧异常** |

结论是 GPU 域被内部拉低。换一片 RK3568 后，同一块板、同一版固件：

```
mali fde60000.gpu: Register LUT 00070200 initialized for GPU arch 0x00070400
mali fde60000.gpu: GPU identified as 0x2 arch 7.4.0 r1p0 status 0
/dev/mali0 存在
/sys/class/devfreq/fde60000.gpu  cur_freq=200MHz  available=800/700/600/400/300/200
```

**GPU 完全正常**（Mali-G52，arch 7.4.0）。所以之前的结论要更正：
不是板子供电设计问题，是**旧 SoC 的 GPU 电源域损坏**。

#### 新 SoC 带来的两个变化

1. **speed bin 从 2 降到 1**（`idc=20 / pvtm=86650 / soc version=0, speed=1`）
   内核会按 OTP 自动选低一档的 OPP 表，一般不用干预。
2. **DDR 只认出 2GB、CS=1**（单 rank）

第 2 点是补焊问题：给 SoC 重新加热后恢复 4GB：

```
ddrconfig:7
CS0 Row=16 CS1 Row=16 CS=2  Size=4096MB
DRAM: 4 GiB
```

但**同一台机器连续两次启动出现过一次 2GB、一次 4GB**，说明 CS1 那几个球还在临界状态，
温度变化或振动后可能复发。遇到内存容量不对，先怀疑 CS1 虚焊。

#### 顺带：25MHz 晶振焊上后以太网通了

```
eth0: PHY [stmmac-1:00] driver [RTL8211F Gigabit Ethernet] (irq=POLL)
Read rgmii delayline from vendor: tx = 0x42, rx = 0x25
```

### 7.11 不烧录调试设备树：/boot 下的 dtbo 覆盖层

Rockchip 的 u-boot 支持从 rootfs 动态加载设备树覆盖层，日志里能看到：

```
[TaishanPi] Dynamic Device Tree Overlay Loader
  Using partition: rootfs (part 6)
  Read 826 bytes from /boot/ubootEnv.txt
```

用法（改完重启即生效，**不用编译 boot.img、不用 MaskROM**）：

```sh
# 1. 放覆盖层
mkdir -p /boot/overlays
# gpu-on.dtbo 之类的文件放这里

# 2. 在 /boot/ubootEnv.txt 里启用
sed -i 's/^# overlays=leds-test.dtbo/overlays=gpu-on.dtbo/' /boot/ubootEnv.txt

# 3. 重启
sync && reboot
```

写 overlay 时**用 `target-path` 而不是 label 引用**，可以不依赖基座 DTB 的 `__symbols__`：

```dts
/dts-v1/;
/plugin/;

/ {
	fragment@0 {
		target-path = "/gpu@fde60000";
		__overlay__ {
			status = "okay";
		};
	};
};
```

这对这块板子意义很大：串口是唯一的人机通道，烧录又要 MaskROM，
用覆盖层可以几分钟试一个设备树改动。

### 7.12 HDMI 点不亮：三个漏贴元件，现象一模一样

这块板子的 HDMI 走了很长一段弯路，因为**三种完全不同的故障，表现都是「显示器无信号 / 黑屏」**。
系统侧（VOP、DDC、HPD、驱动 probe）全程正常，日志里没有任何报错。

#### 判别方法：先分清「无信号」还是「黑屏」

| 显示器表现 | 含义 | 排查方向 |
|---|---|---|
| **「无信号 / No Signal」** | 显示器连 TMDS 时钟都收不到 | PHY 物理层、供电、TMDS 通路 |
| **纯黑有背光** | TMDS 在跑，只是画面内容是黑的 | VOP 图层、帧缓冲 |

这一步能砍掉一半的排查范围，非常关键。

#### 坑 1：EDID 读不到（线材/接触）

```sh
cat /sys/class/drm/card0-HDMI-A-1/edid | wc -c   # 0
i2cdetect -y -r 6                                # 只见假应答 0x30，没有 0x50
i2cdump -y 6 0x30                                # 全 0x0a → 总线悬空
```

`i2cdump` 读回**所有字节都相同**（如全 `0x0a`），说明这是**总线悬空时控制器的固定读数**，
不是真实器件。HDMI DDC 上 EDID 固定是 **0x50**，其它地址出现应答基本都是假象。

另外量到 DDC 引脚 2.6V / 0.8V 这种「中间电平」，也是悬空的典型特征（无供电芯片的
ESD 二极管会把线钳到 0.6~0.9V）。

#### 坑 2：HDMI_TX_AVDD_0V9 缺 1µH 滤波电感 → 只有 0.7V

RK3568 的 **HDMI 和 eDP 共用同一个 TX PHY**，其 0.9V 模拟电源在原理图上常叫
`eDP_TX_AVDD_0V9` / `HDMI_TX_AVDD_0V9_1`（注意 `_1` 后缀说明一般还有 `_0` 等多组，
每组各自经电感隔离，**要逐组量**）。

现象：该网络只有 **0.7V**（应为 0.9V ±5%）。补上 1µH 电感后恢复 0.9V。

0.7V 的成因：这一支靠电感/磁珠从主 0.9V 隔离出来，电感缺失时只剩漏电通路，
被 PHY 的静态电流拉低。

#### 坑 3：HDMI_TX_REXT 缺 1.62kΩ 基准电阻 → TMDS 完全无输出

这是最终的真凶。`HDMI_TX_REXT` 是 TX PHY 的**基准电阻**，PHY 靠它设定 TMDS 驱动器的
输出电流。缺了它：

- 数字部分（VOP、DDC、HPD、寄存器）**一切正常**
- TMDS 驱动器没有正确偏置，**物理层一个信号都不出**
- 显示器只会说「无信号」

补一颗 **1.62kΩ ±1%** 到地，立即点亮。

#### 一个反直觉的点

量到 TMDS 引脚（pin 10/12）有 3.3V，**不能证明 PHY 在工作**——那是显示器端的
50Ω 端接上拉到 3.3V。即使板子这一侧完全断开，量出来也是 3.3V。

要定性必须用示波器看有没有 148.5MHz 差分波形，或者直接查供电和 REXT。


#### 桌面（Weston）启动

```sh
mkdir -p /tmp/weston && chmod 0700 /tmp/weston
export XDG_RUNTIME_DIR=/tmp/weston
weston --backend=drm &
```

跑起来后的关键日志：

```
EGL version: 1.5 Bifrost-"g24p0-00eac0"
GL renderer: Mali-G52
GL version: OpenGL ES 3.2
Output 'HDMI-A-1' enabled with head(s) HDMI-A-1
```

**坑：不要加 `--tty=1`**。weston 14 用的是 *direct launcher*（日志里 `Trying direct launcher...`），
它自己管理 DRM，会报 `fatal: unhandled option: --tty=1` 并退出。

`XDG_RUNTIME_DIR` 必须存在且权限 **0700**，否则会有警告（不致命但建议设对）。

开机自启用最小脚本即可（原版 `buildroot/package/weston/S49weston` 有 57 行）。
**注意 `XDG_RUNTIME_DIR` 必须显式设置**——init 脚本不会加载 `/etc/profile`，
所以 `/etc/profile.d/xdg.sh` 里的设置不生效，不设这个变量 weston 会直接启动失败：

```sh
printf '#!/bin/sh\nexport XDG_RUNTIME_DIR=/var/run\n/usr/bin/weston > /var/log/weston.log 2>&1 &\n' \
    > /etc/init.d/S49weston
chmod +x /etc/init.d/S49weston
```

（串口里用 `printf` 单行写文件比 heredoc 可靠，heredoc 容易被终端吞掉。）

验证：重启后屏幕直接进桌面，`pgrep -a weston` 有进程，`/var/log/weston.log` 有 EGL/GL 初始化记录。

SDK 里的 `buildroot/package/weston/S49weston` 会在重建 rootfs 时自动装回，
所以这个脚本只是本次手动恢复用的临时手段。

#### 修复后的验证

```sh
modetest -M rockchip -s 177@74:1920x1080     # 出彩条
glmark2-es2-drm                              # glmark2 Score: 102 @ 1080p
```

注意：屏幕停在 Rockchip logo 是**正常**的——没有 compositor 接管，控制台又在串口上。

### 7.13 USB 口没电 & 一使能就掉电复位

#### 症状一：USB3.0 Host（A 口）完全没 5V

原理图笔误：**两个 USB 口的 VBUS 使能都接到了 GPIO0_A5**（复制粘贴忘了把其中一个改成 A6），
GPIO0_A6 实际悬空。

EVB 里这两个稳压器分工不同：

| 稳压器 | GPIO | 默认行为 |
|---|---|---|
| `vcc5v0_host` | GPIO0_A6 | `always-on`，开机就有电 |
| `vcc5v0_otg` | GPIO0_A5 | 不常开，只有 OTG 处于 host 模式才被 dwc3 拉起 |

两个口都挂 A5，而 A5 平时是低的，所以 A 口永远没电。

#### 症状二：一加 always-on 就无限重启（掉电复位）

看起来像短路，但实测 **A 口 VBUS 对地 2MΩ**，Type-C 也没插东西。

真正原因：**SY6280 输出后级挂了两颗 100µF 钽电容**。

- 万用表量的是电容充满后的静态阻抗，看不出问题
- EN 拉高的瞬间电容是空的，200µF 按 SY6280 的 2A 限流充电约需 0.5ms
- 这 0.5ms 里输入侧要瞬时提供 2A，把 5V 主轨拉到 PMIC 的 UVLO 以下 → 掉电复位

判断方法：看串口复位后**有没有重新做 DDR 训练**——有就是掉电复位，没有就是芯片复位。

修复：拆掉其中一颗 100µF（剩 100µF，仍在 USB 主机口 120µF 规范内），复测正常。

#### 安全的调试手法

直接把 always-on 写进 DT 很危险——一旦掉电就是无限重启，连覆盖层都删不掉。
调试阶段建议：

```sh
# 解绑稳压器驱动，释放 GPIO
echo vcc5v0-otg-regulator > /sys/bus/platform/drivers/reg-fixed-voltage/unbind
echo 5 > /sys/class/gpio/export          # GPIO0_A5 = 5
echo out > /sys/class/gpio/gpio5/direction
echo 1 > /sys/class/gpio/gpio5/value     # 拉高 → 若掉电，重启后自动恢复
```

这样即使触发掉电，重启后寄存器默认是关的，**不会锁死**。

注意：`/sys/class/regulator/*/state` 是**只读**的，不能用来使能稳压器。

#### 直接写 GPIO 寄存器为什么不行

RK3568 的 GPIO 写数据要带写掩码（高 16 位），内核里的实现是：

```c
writel((val & 0xffff) | 0xffff0000, reg);
```

所以 `devmem 0xfdd60000 32 0x00200020` 这样写理论上只改 bit5。但实测读回不变，
该脚可能还受其他逻辑控制，最终用 sysfs GPIO 才成功。


#### 补充：插 USB hub 仍会复位 → 板载 USB 供电能力有限

拆掉 100µF 后空载正常，但插上「hub + 键鼠接收器」又会复位。

原因是 SY6280 没有软启动，而 hub 自身的输入电容（常见 100~470µF）叠加上来，
热插拔瞬间的冲击仍然超出限流，开关进入打嗝保护，把 5V 主轨一起拖垮。

**实测：给 hub 接上辅助供电后，键鼠立刻正常。**

所以这块板子的 USB 口只能带**低功耗设备**（键鼠、U 盘），带 hub 必须用带电源的 hub。
根因是 5V 通路的余量不足（适配器功率 + 走线阻抗 + 无软启动），不是软件问题。

#### 下一版 PCB 建议

1. 其中一个口的 EN 改回 **GPIO0_A6**（`vcc5v0_host` 本来就 always-on，不用改软件）
2. VBUS 电容改成 **22µF × 2**，或者换用带**软启动**的负载开关
3. EN 脚加 RC 缓启动（如 100k + 1µF）

### 7.14 WiFi：SDIO 通了，但射频收不到任何信号

#### 第一阶段：SDIO 完全枚举不到（已解决）

现象：

```
mmc2: starting CMD5 arg 00000000
mmc2: req failed (CMD5): -110, retrying...     ← 模组完全不应答
mmc2: req done (CMD5): -110
```

软件侧逐个排除后确认都对：
- SDMMC1 引脚复用正确（`pinmux-pins` 里 gpio2-3~8 都是 `sdmmc1-*` 功能）
- `WL_REG_ON`（GPIO2_B1）为高
- 三个稳压器全部使能

最后发现是 **SoC 的 gpio2-3~9 一整片 BGA 球虚焊**——SD 卡用的 gpio2-0~2 正常，
WiFi 用的 gpio2-3~9 全断，**连续引脚段整体失效**就是整片球没回流的特征。

补焊 SoC 后 SDIO 立刻枚举成功：

```
mmc2: new high speed SDIO card at address 0001
mmc2: Bus speed = 50000000Hz
```

> 另外 `WL_REG_ON` 当时是飞线接到 VDDIO 才拉高的（SoC 那一侧断了）。

#### 第二阶段：扫描收不到任何信号（未解决）

SDIO 通了之后，驱动和固件全部正常：

```
F1 signature OK, chip:0xa9a6 rev:0x0 pkg:0x3
Firmware up: op_mode=0x0005, MAC=8c:f7:10:e5:ac:64
CLM: 7.10.15
Country code: CN (CN/0)
wlan0 存在，1~11 信道，20dBm
```

但 `iw dev wlan0 scan` 几乎恒为 **0 个 AP**（同一位置电脑能扫到 12 个，信号 60~100）。

排查过程（全部无效）：

| 尝试 | 结果 |
|---|---|
| a0 固件 + `nvram_ap6212.txt` | 0 AP |
| a1 固件 + `nvram_ap6212a.txt` | 0 AP |
| 换 NVRAM 的 PA 参数（ap6212 ↔ ap6212a）| 0 AP |
| 导线直连模组 RF 焊盘（3cm）| 0 AP |
| 检查 RF 网络对地电阻 | 开路，无短路 |
| 天线焊盘直流电压 | 0V，无偏置 |
| 改用带内中断（`CONFIG_BCMDHD_OOB := n`）| 0 AP |
| 单信道定向扫描（多信道都试）| 0 AP |
| 换监管域（00 / BO / US）| 0 AP |
| 主线 `brcmfmac` 驱动 | 0 AP |
| 换 Debian 12（完全不同的 rootfs）| 0 AP |
| 三颗模组（含别处验证正常的）| 0 AP |

#### 关键转折：发射是正常的

最后用 NetworkManager 建了一个 **adhoc（IBSS）** 网络，手机在 WiFi 列表里
**能看到这个 SSID** —— 说明**射频发射完全正常**，之前"模组 RF 前端损坏"的
判断是**错误的**。

进一步实测：

| 测试 | 结果 | 结论 |
|---|---|---|
| adhoc 发 beacon | ✅ 手机能看到 SSID | **TX 正常** |
| `iw scan` | ❌ 几乎恒为 0 | 扫描功能有问题 |
| IBSS 模式下扫描 | 只扫到自己的网络 | 不跳信道？ |
| 手机热点就在旁边时扫描 | ⚠️ **偶尔成功**（Alexia，信号 100）| 只收到极强的信号 |
| 周围 AP（信号 60~80）| ❌ 一个都收不到 | 接收灵敏度异常 |
| hostapd 建 AP | ❌ `Failed to set beacon parameters` | 固件不支持 AP 模式 |
| `iw reg set` 多个监管域 | 全部 0 | 与监管无关 |

**最终判断**：TX 正常、**RX 灵敏度极低**（只能听到近在咫尺、信号 100 的强信号）。
天线、走线、供电、时钟都已逐一确认正常，所以问题在**模组的射频前端**
（LNA 或内部收发开关），或者 **bcmdhd 2024 驱动 + 2018 固件之间扫描路径不兼容**。

远程排查到此为止——进一步定位需要频谱仪看模组实际收发什么。

> **实际影响**：WiFi 无法正常使用（扫不到网络也连不上）。
> 需要的场合建议用 USB WiFi 网卡（RTL8188/8192，内核驱动已内置），
> 或下一版改用 RTL8723DS / AIC8800 等不同方案的模组。

#### 附带改动：bcmdhd 改用带内中断

本板 `WL_HOST_WAKE`（GPIO2_B2，pin 74）紧邻虚焊的 gpio2-3~9，可靠性存疑。
驱动默认编译时带 `-DOOB_INTR_ONLY`，一旦这根线断了主机就收不到任何异步事件。

在 `drivers/net/wireless/rockchip_wlan/rkwifi/bcmdhd/Makefile` 里改成：

```makefile
CONFIG_BCMDHD_OOB := n      # 原来 := y，会走 -DSDIO_ISR_THREAD
```

重编后走 SDIO 带内中断，不再依赖那根 GPIO：

```sh
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     M=drivers/net/wireless/rockchip_wlan/rkwifi/bcmdhd modules
```

> `modprobe` 不可用（`/lib/modules/6.1.141` 目录不存在），要用
> `insmod /lib/modules/bcmdhd.ko`。

#### ⚠️ 设备树与驱动必须配套

这是一个很容易踩的连环坑：

| 设备树 | 驱动 | 结果 |
|---|---|---|
| 有 `WIFI,host_wake_irq` | OOB 版（默认） | 正常 |
| 有 `WIFI,host_wake_irq` | 带内版 | 正常 |
| **没有** `WIFI,host_wake_irq` | **OOB 版** | **加载失败** |

最后一种情况驱动日志：

```
[dhd] wifi_platform_bus_enumerate device present 0
[dhd] _dhd_module_init: Failed to load the driver, try cnt 0
[dhd] _dhd_module_init: Failed to load driver max retry reached**
[dhd] _dhd_module_init: Exit err=-62
```

`err=-62`（ETIME）看起来像超时，实际是 **OOB 中断注册失败**——因为设备树里
那个属性已经被 `/delete-property/` 删掉了。

**结论**：删掉 `WIFI,host_wake_irq` 之后，rootfs 里的 `bcmdhd.ko` 必须换成
带内中断版本（`CONFIG_BCMDHD_OOB := n`）。两者要同步改。

#### ⚠️ 开机自动加载：insmod 用绝对路径

`/etc/init.d/S36wifibt-init.sh` → `/usr/bin/wifibt-init.sh` 里是：

```sh
insmod "$MODULE"          # MODULE = "bcmdhd.ko"，没有路径
```

在 init 环境里工作目录不是 `/lib/modules`，所以**找不到模块**，而且失败是静默的
（`lsmod` 里看不到，`dmesg` 里也没有任何 dhd 日志）。

解决：加一个自己的启动脚本，用绝对路径：

```sh
#!/bin/sh
case "$1" in
start)
	[ -d /sys/class/net/wlan0 ] && exit 0
	[ -f /lib/modules/bcmdhd.ko ] || exit 0
	insmod /lib/modules/bcmdhd.ko 2>/dev/null
	sleep 2
	[ -d /sys/class/net/wlan0 ] && ip link set wlan0 up 2>/dev/null
	;;
stop) ;;
esac
exit 0
```

存成 `/etc/init.d/S37wifi`，`chmod 755`。比 S36 晚一位，S36 失败后它能兜底。

#### 以太网：只到 10/100Mbps 且频繁掉线（已解决）

调试初期链路频繁起落，多次只协商到 **10Mbps / 100Mbps**，从未上过千兆：

```
RTL8211F: Downshift occurred from negotiated speed 1Gbps to actual speed 100Mbps, check cabling!
eth0: Link is Up - 100Mbps/Full
eth0: Link is Down
```

板子自己的日志就在喊 `check cabling`。千兆需要四对差分全通，只到百兆说明有一对接触不良。

**最终确认是 RJ45 座接触问题**，重新处理连接器后：

```
eth0: Link is Up - 1Gbps/Full - flow control rx/tx
/sys/class/net/eth0/speed = 1000, duplex = full
```

同类现象还有一个干扰项：PC 侧的网卡（Motorcomm YT8531S + `dwmac-motorcomm` 厂商驱动）
也会出现「亮 1~4 秒就断」的假象，容易误判成板子问题。**双端排查**能省很多时间。

> 吞吐实测：`ssh` 管道约 20MB/s（≈160Mbps），瓶颈在 A55 的 SSH 加密而非链路。
> 要测真实带宽请用 `iperf3` / `nc`，不要用 scp 下结论。


### 7.15 音频（3.5mm 耳机）

本板音频走 **RK809 内置 codec**，3.5mm 耳机座的检测脚沿用 EVB 的 `GPIO3_A1`
（低有效）。

**踩的坑**：早期排查时把 `&rk809_sound` 关成了 `disabled`（当时以为本板没有音频），
结果 `/proc/asound/cards` 里只有 SPDIF 和 HDMI，以为硬件不存在。

正确配置：

```dts
&rk809_sound {
	status = "okay";
};
```

验证：

```sh
cat /proc/asound/cards            # 应有 rockchip-rk809
speaker-test -D hw:0,0 -t sine -f 1000 -c 2 -l 1
amixer -c 0 cget numid=20         # Headphone Jack，插拔时 on/off 变化
amixer -c 0 cget numid=12         # Playback Path，应为 HP (item 3)
```

> ⚠️ **声卡编号容易搞错**：RK809 = card 0，SPDIF = card 1，HDMI = card 2。
> 用 `hw:2,0` 测会没声音（声音走到 HDMI 了）。

## 8. 后续


- [ ] 补一份 u-boot 板级 dts
- [ ] GPU 供电复核后决定是否打开（weston 需要它）
- [ ] 按实际 SD 容量重算 `parameter-buildroot-fit.txt`
- [x] eMMC 已贴片（SDINBDA4-64G），`sdhci` 打开，从 eMMC 启动
- [ ] M.2 插槽实测 NVMe 枚举（`lspci -nn`）
- [ ] 硬件确认项见 [hardware.md](hardware.md) 第 6 节
