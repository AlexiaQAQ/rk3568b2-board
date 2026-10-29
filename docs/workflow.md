# 完整工作流程

从零到"能用的板子"的完整步骤。按顺序走一遍即可。

---

## 一、一次性准备

### 1.1 主机依赖

```bash
sudo apt-get install -y \
  build-essential git python3 python-is-python3 cmake \
  bison flex bc libssl-dev libelf-dev libncurses-dev device-tree-compiler \
  gawk texinfo diffstat chrpath patchelf expect gettext rsync unzip bzip2 lz4
```

三个容易漏的：

| 包 | 漏了会怎样 |
|---|---|
| `python-is-python3` | SDK 的 `check-kernel.sh` 报 `Your python is missing` |
| `gawk` | 只有 mawk 时，内核编译到中途失败 |
| `device-tree-compiler` | 无法单独编译/反编译 dtb、做 dtbo 覆盖层 |

### 1.2 SDK 与工具链

```bash
cd ~/rk3568-sdk
export PATH="$HOME/.local/opt/sdk-deps/bin:$PATH"
```

每个新 shell 都要 export 一次（或写进 `~/.bashrc`）。

---

## 二、把板级文件装进 SDK

```bash
cd ~/MyProject/board-port
./apply-to-sdk.sh
```

脚本做的事：

| 步骤 | 内容 |
|---|---|
| 1 | 拷贝 `rk3568-myboard-v10.dts` 到 `kernel-6.1/arch/arm64/boot/dts/rockchip/` |
| 2 | 应用 `patch/0001~0006` |
| 3 | 注册 dtb 到 Makefile、追加 defconfig 片段 |
| 4 | 安装板级 buildroot 配置 |
| 5 | 修补 u-boot 的默认 bootargs |
| 6 | 打开 `CONFIG_DRM_IGNORE_IOTCL_PERMIT`（SDK 打包脚本强制要求） |
| 7 | bcmdhd 改用带内中断（不依赖 WL_HOST_WAKE） |

**这是整个项目最重要的一步。** 板级差异全部集中在一个 dts 里，其余继承 EVB1 参考设计。

> 为什么"做减法"：这块板的电源树（RK809-5 + TCS4525）、AP6212、HDMI、USB 拓扑和
> Rockchip RK3568 EVB1 高度一致，直接继承 1200 多行已验证配置，只覆盖差异项，
> 比从零写可靠得多。

---

## 三、编译

### 3.1 常规方式

```bash
cd ~/rk3568-sdk
export PATH="$HOME/.local/opt/sdk-deps/bin:$PATH"

./build.sh kernel       # 内核 + dtb + boot.img
./build.sh firmware     # 组装 boot.img / rootfs.img / update.img
```

### 3.2 用仓库的 Makefile

```bash
cd ~/MyProject/board-port
make kernel        # = ./build.sh kernel
make firmware      # = ./build.sh firmware
make image         # 组装 update.img
make check         # 检查环境依赖
```

### 3.3 ⚠️ 不要跑 `./build.sh all`

它会去联网下载 buildroot 的源码包（`sources.buildroot.net`），断网环境必然失败，
而且卡在最后一步，前面几十分钟全白等。

正确做法：分开跑 `kernel` 和 `firmware`。

### 3.4 产物

```
output/firmware/boot.img      39.7 MB   内核 + dtb
output/firmware/rootfs.img    896 MB    rootfs
output/firmware/update.img    ~960 MB   整包（含分区表）
```

---

## 四、烧录

### 4.1 进入 MaskROM

按住 **MASKROM 键** → 上电 → 松开。

确认：

```bash
UT=~/rk3568-sdk/tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool
$UT ld        # 必须显示 Mode=Maskrom
```

### 4.2 方式一：只烧某个分区（最常用）

分区偏移（单位：512 字节扇区）：

| 分区 | 起始扇区 | 典型大小 |
|---|---|---|
| uboot | 16384 | 4 MB |
| boot | **32768** | 40 MB |
| rootfs | **491520** | 896 MB |

```bash
$UT db ~/rk3568-sdk/u-boot/rk356x_spl_loader_v1.25.114.bin
$UT ssd                          # 输入 2 = eMMC
$UT wl 32768  ~/rk3568-sdk/output/firmware/boot.img
$UT wl 491520 ~/rk3568-sdk/output/firmware/rootfs.img
$UT rd
```

### 4.3 方式二：整包（会重写分区表）

```bash
$UT uf ~/rk3568-sdk/output/firmware/update.img
```

### 4.4 方式三：Loader 模式（不用按键）

系统里执行 `reboot loader`，然后直接 `$UT wl ...`。

### 4.5 烧录的坑

| 现象 | 原因 |
|---|---|
| `Download Firmware Fail` 卡在 2% | **USB 经过了 hub**，必须直插主板后置口 |
| `parameter is invalid,please check!` | `di` 之前要先 `di -p parameter.txt` |
| `The Device did not support this operation!` | 在 Loader 模式下执行了 `db`，跳过即可 |
| `No found any rockusb device` | 板子还在跑 Linux，需要先 `reboot loader` 或按 MASKROM |

---

## 五、首次上电验证

接串口：

```bash
cd ~/MyProject/board-port
make serial        # /dev/ttyUSB0 @ 1500000 8N1
```

### 5.1 DDR 训练

```
LPDDR4X, 324MHz
BW=32 Col=10 Bk=8 CS0 Row=16 CS1 Row=16 CS=2 Die BW=16 Size=4096MB
DRAM:  4 GiB
```

**必须是 `CS=2` / `4096MB`。** 如果是 `CS=1` / `2048MB`，说明 SoC 的 CS1 球虚焊，
需要补焊 SoC（详见 `bom-checklist.md`）。

### 5.2 逐项验证

```sh
# 存储
cat /sys/class/mmc_host/mmc0/mmc0:0001/name      # 应显示 eMMC 型号

# GPU
ls /dev/mali0
dmesg | grep 'Probed as mali0'

# HDMI
cat /sys/class/drm/card0-HDMI-A-1/status         # connected
cat /sys/class/drm/card0-HDMI-A-1/modes | head   # 支持的分辨率列表

# 桌面
pgrep -a weston

# 以太网
udhcpc -i eth0
cat /sys/class/net/eth0/speed                    # 1000

# USB 供电
grep 'gpio-5 ' /sys/kernel/debug/gpio            # out hi

# NPU
dmesg | grep RKNPU
```

### 5.3 屏幕停在开机 logo 是正常的

没有 compositor 接管时，屏幕会停在最后一帧（Rockchip logo）。内核控制台在串口上，
不在 HDMI 上。手动验证显示：

```sh
modetest -M rockchip                             # 查 connector / crtc id
modetest -M rockchip -s 177@74:1920x1080         # 点亮测试图
glmark2-es2-drm                                  # GPU 跑分
```

---

## 六、日常调试手段

### 6.1 串口

```bash
make serial        # Ctrl+] 退出
```

**同一时间只能一个进程占用串口。** 用其他工具前先退出。

### 6.2 SSH（强烈推荐）

板子上配一次：

```sh
ip addr add 192.168.1.100/24 dev eth0
passwd root
```

电脑上：

```bash
ssh-copy-id root@192.168.1.100
ssh root@192.168.1.100
scp 文件 root@192.168.1.100:/lib/modules/
```

**有了 SSH 之后所有调试都方便十倍**，不用再往串口粘贴长命令。

> 直连电脑时没有 DHCP，两端手配静态 IP 即可。
> PC 侧如果装了 NetworkManager，可能反复清掉手动 IP，用
> `nmcli device set <if> managed no` 锁住。

### 6.3 dtbo 覆盖层（不烧录改设备树）

u-boot 支持从 rootfs 动态加载设备树覆盖层，**改完重启就生效**：

```sh
mkdir -p /boot/overlays
echo '<base64>' | base64 -d > /boot/overlays/xxx.dtbo
sed -i 's/^# overlays=leds-test.dtbo/overlays=xxx.dtbo/' /boot/ubootEnv.txt
sync && reboot
```

写 overlay 用 **`target-path` 而不是 label 引用**，不依赖基座 DTB 的 `__symbols__`：

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

> ⚠️ 这个机制**不能删属性**（dtc 在 overlay 里 `/delete-property/` 不生效），
> 要删属性只能改 dts 重编。

### 6.4 驱动调试（动态调试）

```sh
echo 'file dw-hdmi.c +p' > /sys/kernel/debug/dynamic_debug/control
echo -n 'file dw-hdmi-qp.c +p' > /sys/kernel/debug/dynamic_debug/control
dmesg -c > /dev/null
# ...复现问题...
dmesg
```

### 6.5 MMC/SDIO 调试

```sh
# 重新探测 SDIO 控制器（不用重启）
echo fe2c0000.mmc > /sys/bus/platform/drivers/dwmmc_rockchip/unbind
sleep 1
echo fe2c0000.mmc > /sys/bus/platform/drivers/dwmmc_rockchip/bind

# 看命令级日志
echo 'file core.c +p' > /sys/kernel/debug/dynamic_debug/control
```

---

## 七、出问题时的排查顺序

### 7.1 先分清现象类型

| 现象 | 方向 |
|---|---|
| 显示器「无信号」 | TMDS 没输出 → 查 PHY 供电、REXT 基准电阻 |
| 显示器「黑屏有背光」 | TMDS 在跑 → 查 VOP 图层、帧缓冲 |
| 以太网只到 10/100Mbps | 某对差分不通 → 查线材、RJ45 |
| 能通信但收不到数据 | **中断线断了**（主机主动访问正常，异步通知丢失） |
| 设备能枚举但功能不工作 | 供电不足或 RF/模拟部分损坏 |

### 7.2 量电压 → 量通断 → 最后才怀疑软件

本项目的 9 个硬件问题里，**8 个是硬件，只有 1 个是软件配置**。

典型陷阱：

| 陷阱 | 真相 |
|---|---|
| 万用表量电容两端 2MΩ | 电容充满后就是开路，**测不出上电瞬间的冲击电流** |
| 量 TMDS 引脚有 3.3V | 那是显示器端的端接电压，**不能证明 PHY 在工作** |
| VOP 显示 ACTIVE、dclk 正常 | 只代表软件状态，**不代表画面真的送到了屏幕上** |
| 日志里一堆 `-23` `-29` EINVAL | 老固件不支持新驱动的特性，通常**无害** |
| 网口灯不亮 | 集成变压器的 RJ45，LED 由 PHY 的 LED 脚驱动，线没接就永远不亮 |

### 7.3 交叉验证

| 怀疑对象 | 怎么验证 |
|---|---|
| 驱动 | 换**完全不同的驱动**（bcmdhd ↔ 主线 brcmfmac） |
| 模组 | 换**一颗已知正常的模组** |
| PC 网口 | 换 **Windows** 试 |
| 线材 | 换一根确认好的线 |
| 供电 | 换一个更大功率的适配器 |

本项目的 WiFi 就是靠「两套独立驱动 × 三颗模组 = 全部失败」才把范围锁死到硬件的。

### 7.4 安全调试原则

改可能引起掉电/无法启动的配置时（如 USB VBUS 使能），**不要直接写进 DT**，
否则一旦出问题就是无限重启，连覆盖层都删不掉。

改用运行时方式：

```sh
echo vcc5v0-otg-regulator > /sys/bus/platform/drivers/reg-fixed-voltage/unbind
echo 5 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio5/direction
echo 1 > /sys/class/gpio/gpio5/value     # 若掉电，重启后默认关闭，不会锁死
```

---

## 八、当前已知问题

| 问题 | 状态 | 下一步 |
|---|---|---|
| WiFi 射频收不到 AP | 硬件 RF 通路 | 量「模组天线焊盘 ↔ 天线座中心针」通断 |
| USB hub 需外接电源 | 供电余量不足 | 下一版改 22µF×2 + 软启动 |
| 两个 USB 口 EN 接同一 GPIO | 原理图笔误 | 下一版改一个到 GPIO0_A6 |
| 其余 9 项 | 已解决 | 见 `bom-checklist.md` |

---

## 九、仓库结构

```
rk3568-myboard-v10.dts                板级 DTS（唯一需要改的文件）
rockchip_rk3568_myboard_v10_defconfig 板级配置
Makefile                              make kernel / firmware / flash / serial
apply-to-sdk.sh                       一键装进 SDK
patch/0001~0006                       可复现的补丁
docs/
  ├── workflow.md                     本文档：完整流程
  ├── porting-notes.md                14 个实战案例（最值得看）
  ├── bom-checklist.md                9 个硬件坑 + 定位方法
  ├── hardware.md                     器件与电源树
  └── bringup-checklist.md            首板上电检查表
CHANGELOG.md                          v0.1 ~ v0.8.0
```

---

## 十、命令速查

```bash
# ---- 构建 ----
./apply-to-sdk.sh                     # 装板级文件
make kernel                           # 编内核
make firmware                         # 组装固件
make serial                           # 串口终端

# ---- 烧录 ----
$UT ld                                # 确认 MaskROM
$UT wl 32768  boot.img                # 写 boot 分区
$UT wl 491520 rootfs.img              # 写 rootfs 分区
$UT rd                                # 重启

# ---- 系统内 ----
reboot loader                         # 进烧录模式
ip addr add 192.168.1.100/24 dev eth0
cat /sys/class/drm/card0-HDMI-A-1/status
cat /sys/class/net/eth0/speed
modetest -M rockchip -s 177@74:1920x1080
glmark2-es2-drm

# ---- 调试 ----
echo 'file xxx.c +p' > /sys/kernel/debug/dynamic_debug/control
dmesg -c > /dev/null
grep 'gpio-' /sys/kernel/debug/gpio
cat /sys/kernel/debug/regulator/regulator_summary
```
