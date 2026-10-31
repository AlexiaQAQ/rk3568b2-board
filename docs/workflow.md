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

**SDK 下载**：<https://wiki.lckfb.com/zh-hans/tspi-rk3566/download-center.html>

**官方编译教程**：<https://wiki.lckfb.com/zh-hans/tspi-rk3566/sdk-compilation/linux-compilation.html>

**buildroot 软件包镜像**：<https://mirror.nju.edu.cn/buildroot/>（见 3.8 节）

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

### 3.1 build.sh 的子命令

| 命令 | 产物 | 耗时 |
|---|---|---|
| `./build.sh kernel` | `boot.img`（内核 + dtb） | 首次约 10 分钟，改 dts 后约 2 分钟 |
| `./build.sh uboot` | `uboot.img` / `trust.img` | 约 2 分钟 |
| `./build.sh rootfs` | `rootfs.img` | 依赖 buildroot，**需联网** |
| `./build.sh firmware` | 组装 `boot.img` / `rootfs.img` / `update.img` | 约 1 分钟 |
| `./build.sh all` | 全部 | ⚠️ 见下方 |

### 3.2 ⚠️ 不要跑 `./build.sh all`

它会去 buildroot 下载源码包（`sources.buildroot.net`），断网环境必然失败，
而且卡在最后一步，前面几十分钟全白等。

正确做法：

```bash
./build.sh kernel       # 先编内核
./build.sh firmware     # 再组装固件
```

### 3.3 用仓库的 Makefile

```bash
cd ~/MyProject/board-port
make kernel        # = ./build.sh kernel
make firmware      # = ./build.sh firmware
make image         # 组装 update.img
make check         # 检查主机依赖
make serial        # 串口终端
```

### 3.4 只改设备树时

改完 `rk3568-myboard-v10.dts` 后：

```bash
cd ~/MyProject/board-port
make install       # 把 dts 拷到 SDK 并注册
cd ~/rk3568-sdk && ./build.sh kernel
```

**不需要重编 buildroot**，几分钟就好。

### 3.5 只重编某个内核模块

```bash
cd ~/rk3568-sdk/kernel-6.1
export PATH="$HOME/.local/opt/sdk-deps/bin:$PATH"

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     M=drivers/net/wireless/rockchip_wlan/rkwifi/bcmdhd modules
```

产物：`drivers/net/wireless/rockchip_wlan/rkwifi/bcmdhd/bcmdhd.ko`

> `M=` 方式有时不生效（只跑 MODPOST 不编译）。可靠的做法是全量 `make modules`，
> 虽然慢但不会漏。

### 3.6 改内核配置

```bash
cd ~/rk3568-sdk/kernel-6.1
./scripts/config --module BRCMFMAC --enable BRCMFMAC_SDIO
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
./build.sh kernel        # 在 SDK 根目录执行
```

> ⚠️ `build.sh` 可能会用 defconfig 片段重新生成 `.config`，把手工改的选项覆盖掉。
> 需要长期生效的配置应该写进 `rockchip_rk3568_myboard_v10_defconfig` 或
> `arch/arm64/configs/rk3568.config`。

### 3.7 产物对应关系

| 文件 | 内容 | 什么时候变 |
|---|---|---|
| `output/firmware/boot.img` | 内核 + dtb | 每次 `build.sh kernel` |
| `output/firmware/rootfs.img` | 根文件系统 | 只有 `build.sh rootfs` 才变 |
| `output/firmware/update.img` | 整包（分区表 + 所有分区） | 每次 `build.sh firmware` |

> ⚠️ **重要**：`build.sh kernel` 和 `build.sh firmware` **都不会重编 rootfs**。
> 所以 `rootfs.img` 的时间戳可能停留在很久以前——这是正常的，但也意味着
> rootfs 里的手动改动（新增脚本、改配置）不会自动进 `update.img`，
> 需要用 4.8 节的 `debugfs` 手工写进去。

### 3.8 用国内镜像加速 buildroot

`build.sh all` / `build.sh rootfs` 会从 `sources.buildroot.net` 下载所有软件包源码，
国内网络经常超时。

**这不是 SDK 镜像站**——`mirror.nju.edu.cn/buildroot/` 是 buildroot 的
**软件包源码镜像**（相当于官方 `sources.buildroot.net` 的国内副本），
里面只有 `busybox-1.37.0.tar.bz2` 这类包，**没有 Rockchip SDK 本身**。

> SDK 要从立创的下载中心拿：
> <https://wiki.lckfb.com/zh-hans/tspi-rk3566/download-center.html>

配置方法（改 SDK 里的文件）：

```bash
cd ~/rk3568-sdk/buildroot

# 1. 改配置片段（以后重新生成 defconfig 也生效）
sed -i 's|^BR2_PRIMARY_SITE=.*|BR2_PRIMARY_SITE="https://mirror.nju.edu.cn/buildroot/"|' \
    configs/rockchip/base/common.config
sed -i 's|^BR2_BACKUP_SITE=.*|BR2_BACKUP_SITE="https://sources.buildroot.net"|' \
    configs/rockchip/base/common.config

# 2. 同步到已经生成的 build 配置（立即生效）
for f in output/*/*/.config; do
    sed -i 's|^BR2_PRIMARY_SITE=.*|BR2_PRIMARY_SITE="https://mirror.nju.edu.cn/buildroot/"|' "$f"
    sed -i 's|^BR2_BACKUP_SITE=.*|BR2_BACKUP_SITE="https://sources.buildroot.net"|' "$f"
done
```

验证：

```bash
cd ~/rk3568-sdk/buildroot
make busybox-source        # 应能看到从 mirror.nju.edu.cn 下载
```

> 保留 `BR2_BACKUP_SITE` 指向官方站——镜像个别新版本可能没同步
> （实测 weston 14.0.2 就缺），会自动回落到官方。

其他可用镜像：

| 地址 | 说明 |
|---|---|
| `https://mirror.nju.edu.cn/buildroot/` | 南京大学，实测 ~1 MB/s |
| `https://mirrors.tuna.tsinghua.edu.cn/buildroot/` | 清华（如可用）|
| `https://mirrors.ustc.edu.cn/` | 中科大（GNU 包）|

### 3.8 编译常见错误

| 报错 | 原因 |
|---|---|
| `Your python is missing` | 缺 `python-is-python3` |
| `gawk: command not found` 或语法错 | 只装了 mawk，需要 `gawk` |
| `Your network is not able to access sources.buildroot.net` | 跑了 `all`/`rootfs`，改跑 `kernel`+`firmware` |
| `No rule to make target 'xxx.dtb'` | dts 没注册到 Makefile，重跑 `make install` |
| `failed to parse loader memory` | 正常提示，不影响 |

## 四、烧录

### 4.1 准备 upgrade_tool

```bash
UT=~/rk3568-sdk/tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool
```

**每开一个新 shell 都要重新设置**（或者写进 `~/.bashrc`）：

```bash
echo 'export UT=~/rk3568-sdk/tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool' >> ~/.bashrc
```

> ⚠️ 变量没设时 `$UT ld` 会变成系统的 `ld` 命令，报 **`ld: no input files`**。
> 看到这个报错就是变量忘了设。

### 4.2 非 root 用户访问 USB 设备

```bash
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="2207", MODE="0666", GROUP="plugdev"' | \
  sudo tee /etc/udev/rules.d/99-rockchip-usb.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### 4.3 三种设备模式

| 模式 | 怎么进 | `lsusb` | 能用的命令 |
|---|---|---|---|
| **MaskROM** | 按住 MASKROM 键上电 | `2207:350a` | 全部 |
| **Loader** | 系统里 `reboot loader` | `2207:350a` | 除 `db` 外都能用 |
| **正常 Linux** | 默认启动 | `2207:0006` | **不能烧录** |

`$UT ld` 必须显示 `Mode=Maskrom`（或 Loader）才能继续。

> `db` 只能在 MaskROM 下用。Loader 模式执行会报
> `The Device did not support this operation!`，跳过即可。

### 4.4 命令详解

| 命令 | 作用 |
|---|---|
| `ld` | 列出设备，确认当前模式 |
| `db <loader.bin>` | 下载 loader（仅 MaskROM 需要） |
| `ssd` | 选择存储介质（交互式，**必须有 tty**） |
| `wl <扇区> <文件>` | 从指定扇区开始写文件 |
| `uf <update.img>` | 烧写整包（含分区表） |
| `di -p <parameter.txt>` | 下载分区表 |
| `rd` | 重启设备 |

> `ssd` 是交互式的，**管道输入不行**：`echo 2 | $UT ssd` 会报 `Switch Storage failed!`。
> 必须在真实终端里手输 `2`；写脚本需要用 `pty.openpty()` 模拟 tty。

### 4.5 三种烧录场景

**A. 只更新内核**（最常用，不动 rootfs）

```bash
$UT ld
$UT db ~/rk3568-sdk/u-boot/rk356x_spl_loader_v1.25.114.bin
$UT ssd                    # 终端输入 2 = eMMC
$UT wl 32768 ~/rk3568-sdk/output/firmware/boot.img
$UT rd
```

**B. 整包烧写**（给别人用的标准做法）

```bash
$UT ld
$UT uf ~/rk3568-sdk/output/firmware/update.img
$UT rd
```

整包会重写分区表 + 所有分区，**rootfs 里手工改过的内容全部丢失**。

**C. 只更新 rootfs**

```bash
$UT wl 491520 ~/rk3568-sdk/output/firmware/rootfs.img
```

### 4.6 分区偏移表

单位：512 字节扇区（来自 `parameter-buildroot-fit.txt`）。

| 分区 | 十六进制 | 十进制 |
|---|---|---|
| uboot | 0x4000 | 16384 |
| misc | 0x6000 | 24576 |
| boot | 0x8000 | **32768** |
| recovery | 0x28000 | 163840 |
| backup | 0x68000 | 425984 |
| rootfs | 0x78000 | **491520** |
| oem | 0x1878000 | 25657344 |
| userdata | 0x18b8000 | 25952256 |

### 4.7 烧录常见错误

| 报错 | 原因 | 解决 |
|---|---|---|
| `ld: no input files` | `$UT` 没设，跑的是系统 `ld` | 重新 export `UT` |
| `No found any rockusb device` | 板子不在 MaskROM/Loader | 按 MASKROM 键上电，或 `reboot loader` |
| `Download Firmware Fail` 卡在 2% | **USB 经过了 hub** | 直插主板后置口 |
| `parameter is invalid,please check!` | 没先下分区表 | `$UT di -p parameter.txt` |
| `The Device did not support this operation!` | Loader 模式下执行了 `db` | 跳过 `db` |
| `Switch Storage failed!` | `ssd` 没有 tty | 在终端里手输 `2` |
| `can't read flash id from device` | 板子不在烧录模式 | 同上 |
| `Download IDB Fail` / `Writing master gpt failed!` | 存储介质问题 | eMMC 查焊接；SD 卡要**插到底** |

### 4.8 往 rootfs 镜像里加文件（不用重新编译）

`build.sh firmware` 只会重新打包**已存在**的 rootfs 镜像，不会重编 buildroot。
想给镜像加文件时，可以用 `debugfs` 直接写（**不需要 root 权限、不需要挂载**）：

```bash
IMG=~/rk3568-sdk/output/firmware/rootfs.img     # 软链到 rootfs.ext2

# 1. 准备文件
cp ~/rk3568-sdk/buildroot/package/weston/S49weston /tmp/S49weston
chmod 755 /tmp/S49weston

# 2. 写入镜像
debugfs -w -R "write /tmp/S49weston /etc/init.d/S49weston" "$IMG"
debugfs -w -R "sif /etc/init.d/S49weston mode 0100755" "$IMG"

# 3. 验证
debugfs -R "ls -l /etc/init.d" "$IMG" | grep -i weston

# 4. 重新打包 update.img
cd ~/rk3568-sdk && ./build.sh firmware
```

`debugfs` 常用命令：

| 命令 | 作用 |
|---|---|
| `ls /path` | 列目录 |
| `stat /path` | 看 inode/权限 |
| `write <host> <img>` | 把宿主机文件写进镜像 |
| `sif <img> mode 0100755` | 改权限（`sif` = set inode field） |
| `rm /path` | 删除文件 |

> 注意：`mode` 是八进制，普通可执行文件是 `0100755`，普通文件 `0100644`。

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

## 七点五、时间与网络

### 时间为什么会变成 2017 年

板子**没有 RTC 备用电池**，断电后 RK809 的 RTC 不保存时间，每次上电回到出厂
默认值 `2017-08-04`。浏览器、HTTPS、包管理器都会因为时间错误而报错。

解决只能靠 NTP，而 NTP 需要外网。

### 让板子通过电脑上网（NAT）

板子和电脑直连时没有路由器，板子默认没有网关。让电脑做 NAT：

```bash
# 电脑上（wlo1 换成你实际上网的网卡）
IFACE=$(ip route | awk '/^default/{print $5; exit}')
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE
sudo iptables -A FORWARD -i enp44s0 -o $IFACE -j ACCEPT
sudo iptables -A FORWARD -i $IFACE -o enp44s0 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

板子上加默认路由（`192.168.1.1` = 电脑那端的地址）：

```sh
ip route replace default via 192.168.1.1 dev eth0
printf 'nameserver 223.5.5.5\n' > /etc/resolv.conf
```

验证：

```sh
wget -q -O /dev/null http://www.baidu.com && echo ok
chronyc sources          # 应看到 ^* 标记的源
chronyc tracking
```

### ⚠️ 电脑那边的坑

NetworkManager 会把 `enp44s0` 当 DHCP 客户端，把手工配的 `192.168.1.1` 冲掉
（板子上的 dnsmasq 会发地址，电脑拿到 `192.168.1.91`，然后默认路由指向 `.1` 就全断了）。

正确做法是**锁住**：

```bash
sudo nmcli device set enp44s0 managed no
sudo ip addr flush dev enp44s0
sudo ip addr add 192.168.1.1/24 dev enp44s0
```

### 网络：默认 DHCP

镜像**不设静态 IP**，开机由 `S41dhcpcd`（dhcpcd `-AL`）自动获取 IP / 网关 / DNS。
接路由器时开箱即用。

验证：

```sh
ip -4 addr show eth0 | grep inet      # 应带 dynamic 标记
ip route | head -2                    # 应有 default
grep nameserver /etc/resolv.conf
```

### 直连电脑时怎么办

板子和电脑网线直连时，链路上没有 DHCP 服务器，板子拿不到地址。
需要在电脑上起 DHCP 服务，最省事的是做成一个可复用的脚本 + 服务：

**电脑上创建 `/usr/local/sbin/board-nat.sh`**（用 `board-nat.sh up|down|status` 管理）：

```bash
#!/bin/bash
set -u
LAN=enp44s0
LAN_IP=192.168.1.1/24
DHCP_CONF=/etc/dnsmasq.d/board-nat.conf
PIDFILE=/run/board-nat-dnsmasq.pid
LEASES=/var/lib/misc/board-nat.leases

wan_if() { ip route | awk '/^default/{print $5; exit}'; }

case "${1:-status}" in
up)
	WAN=$(wan_if); [ -z "$WAN" ] && { echo "找不到上网网卡"; exit 1; }
	nmcli device set "$LAN" managed no 2>/dev/null || true
	ip link set "$LAN" up
	ip addr replace "$LAN_IP" dev "$LAN"
	sysctl -qw net.ipv4.ip_forward=1
	iptables -t nat -C POSTROUTING -o "$WAN" -j MASQUERADE 2>/dev/null || \
		iptables -t nat -A POSTROUTING -o "$WAN" -j MASQUERADE
	iptables -C FORWARD -i "$LAN" -o "$WAN" -j ACCEPT 2>/dev/null || \
		iptables -A FORWARD -i "$LAN" -o "$WAN" -j ACCEPT
	iptables -C FORWARD -i "$WAN" -o "$LAN" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
		iptables -A FORWARD -i "$WAN" -o "$LAN" -m state --state RELATED,ESTABLISHED -j ACCEPT
	mkdir -p /etc/dnsmasq.d /var/lib/misc
	cat > "$DHCP_CONF" <<CONF
interface=$LAN
bind-interfaces
dhcp-range=192.168.1.100,192.168.1.199,255.255.255.0,12h
dhcp-option=3,192.168.1.1
dhcp-option=6,223.5.5.5,119.29.29.29
dhcp-leasefile=$LEASES
CONF
	[ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null
	dnsmasq -C "$DHCP_CONF" --pid-file="$PIDFILE"
	;;
down)
	[ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null
	WAN=$(wan_if)
	iptables -t nat -D POSTROUTING -o "$WAN" -j MASQUERADE 2>/dev/null
	iptables -D FORWARD -i "$LAN" -o "$WAN" -j ACCEPT 2>/dev/null
	iptables -D FORWARD -i "$WAN" -o "$LAN" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
	;;
status)
	echo "LAN: $LAN $(ip -4 addr show "$LAN" 2>/dev/null | awk '/inet /{print $2}')"
	echo "WAN: $(wan_if)"
	echo "NAT: $(iptables -t nat -S POSTROUTING | grep -c MASQUERADE) 条"
	echo "DHCP: $([ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null && echo 运行中 || echo 未运行)"
	[ -f "$LEASES" ] && awk '{print "  租约 "$3" "$2}' "$LEASES"
	;;
esac
```

**做成开机自启**：

```ini
# /etc/systemd/system/board-nat.service
[Unit]
Description=Share internet to RK3568 dev board
After=network-online.target NetworkManager.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/board-nat.sh up
ExecStop=/usr/local/sbin/board-nat.sh down

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now board-nat.service
board-nat.sh status          # 查看板子分到的地址
```

**B. 临时手工设 IP**（不想装服务时）

```sh
ip addr add 192.168.1.100/24 dev eth0
ip route replace default via 192.168.1.1 dev eth0
printf 'nameserver 223.5.5.5\n' > /etc/resolv.conf
```

### 电脑上网关地址的坑

NetworkManager 会把 `enp44s0` 当 DHCP 客户端，把手工配的 `192.168.1.1` 冲掉。
必须锁住：

```bash
sudo nmcli device set enp44s0 managed no
sudo ip addr flush dev enp44s0
sudo ip addr add 192.168.1.1/24 dev enp44s0
```

> 板子的 MAC 是**随机生成**的（每次开机可能不同），所以 DHCP 租约地址不固定。
> 需要固定地址时应在设备树里写 `local-mac-address`，或在 dnsmasq 里按 MAC 绑定。

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
# ---- 一次性设置 ----
export UT=~/rk3568-sdk/tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool
export PATH="$HOME/.local/opt/sdk-deps/bin:$PATH"

# ---- 构建 ----
./apply-to-sdk.sh                     # 装板级文件到 SDK
make check                            # 检查主机依赖
make kernel                           # 编内核 + dtb → boot.img
make firmware                         # 组装 update.img
make serial                           # 串口终端（Ctrl+] 退出）

# ---- 烧录（板子需在 MaskROM / Loader）----
$UT ld                                # 确认模式，必须显示 Maskrom
$UT db ~/rk3568-sdk/u-boot/rk356x_spl_loader_v1.25.114.bin
$UT ssd                               # 终端输入 2 = eMMC
$UT wl 32768  boot.img                # 只写 boot 分区
$UT wl 491520 rootfs.img              # 只写 rootfs 分区
$UT uf update.img                     # 整包烧写
$UT rd                                # 重启

# ---- 修改 rootfs 镜像（不用重编）----
IMG=~/rk3568-sdk/output/firmware/rootfs.img
debugfs -w -R "write /tmp/f /etc/init.d/S49weston" "$IMG"
debugfs -w -R "sif /etc/init.d/S49weston mode 0100755" "$IMG"
debugfs -R "ls -l /etc/init.d" "$IMG"

# ---- 板子上 ----
reboot loader                         # 进烧录模式
ip addr add 192.168.1.100/24 dev eth0
cat /sys/class/drm/card0-HDMI-A-1/status     # HDMI 连接状态
cat /sys/class/net/eth0/speed                # 链路速率
grep 'gpio-' /sys/kernel/debug/gpio          # GPIO 状态
cat /sys/kernel/debug/regulator/regulator_summary
modetest -M rockchip -s 177@74:1920x1080     # 点亮显示
glmark2-es2-drm                              # GPU 跑分

# ---- 驱动调试 ----
echo 'file xxx.c +p' > /sys/kernel/debug/dynamic_debug/control
dmesg -c > /dev/null
dmesg
```

### 时间戳速查

| 疑问 | 命令 |
|---|---|
| 固件是什么时候编的 | `ls -lL ~/rk3568-sdk/output/firmware/*.img` |
| 校验完整性 | `md5sum ~/rk3568-sdk/output/firmware/update.img` |
| rootfs 里有没有某个文件 | `debugfs -R "ls -l /etc/init.d" "$IMG"` |
