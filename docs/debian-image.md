# Debian 桌面镜像

板子除了 Buildroot，还可以跑 **Debian 12 (bookworm) 桌面版**（XFCE + lightdm + Chromium）。

## 一、两套固件的对比

| 项目 | Buildroot | Debian |
|---|---|---|
| 大小 | 961 MB | **4513 MB** |
| 启动 | ~8 秒 | 30~60 秒 |
| 桌面 | Weston（Wayland，轻量） | **XFCE（X11，完整）** |
| 包管理 | 无 | **apt** |
| 默认用户 | root（无密码） | **linaro / linaro** |
| 自动登录 | 是 | 是（lightdm 已配）|

## 二、切换方法

```bash
cd ~/rk3568-sdk

# 方式一：交互菜单
./build.sh config        # Rootfs → default rootfs system → Debian

# 方式二：直接改 output/.config
sed -i 's|^RK_ROOTFS_SYSTEM="buildroot"|RK_ROOTFS_SYSTEM="debian"|' output/.config
sed -i 's|^RK_ROOTFS_SYSTEM_BUILDROOT=y|# RK_ROOTFS_SYSTEM_BUILDROOT is not set|' output/.config
echo 'RK_ROOTFS_SYSTEM_DEBIAN=y' >> output/.config
touch output/.config     # 必须比 output/defconfig 新，否则会被重新生成

./build.sh rootfs        # ~20 分钟（解压预构建 tarball + 装包）
./build.sh firmware      # ~2 分钟
```

切回 Buildroot 就把 `buildroot` / `debian` 对调，再跑一遍。

## 三、⚠️ 两个必须改的坑

### 3.1 bcmdhd 驱动和设备树不匹配

SDK 生成的 Debian 里是 **OOB 版** `bcmdhd.ko`，但本板设备树删掉了
`WIFI,host_wake_irq`，驱动初始化直接失败：

```
[dhd] wifi_platform_bus_enumerate device present 0
[dhd] _dhd_module_init: Failed to load driver max retry reached**
[dhd] _dhd_module_init: Exit err=-62
```

`err=-62`（ETIME）看着像超时，实际是 **OOB 中断注册失败**。

修复：把带内中断版 `bcmdhd.ko` 换进镜像（见第五节）。

### 3.2 wlan0 显示「未托管」

`/etc/network/interfaces.d/network-priority` 里有：

```
auto wlan0
iface wlan0 inet dhcp
```

而 `/etc/NetworkManager/NetworkManager.conf` 是：

```ini
[ifupdown]
managed=false
```

**只要接口出现在 `/etc/network/interfaces` 里，NetworkManager 就当成别人的，
标记为「未托管」**，桌面右上角的网络菜单里看不到它。

修复：把 `auto wlan0` 那段注释掉。

> ⚠️ **备份文件不能放在 `/etc/network/interfaces.d/` 里！**
> 因为 `/etc/network/interfaces` 用的是 `source /etc/network/interfaces.d/*`，
> 通配符会把 `xxx.bak` 也读进去。这个坑花了很久才找到。

## 四、依赖

Debian rootfs 是解压 SDK 自带的 `debian/linaro-bookworm-alip-*.tar.gz`（664 MB），
**不需要联网拉取**。但需要两个主机工具：

```bash
sudo apt-get install -y qemu-user-static
```

`check-debian.sh` 还会检查 live-build / debootstrap——**只有在你没有预构建 tarball
时才需要**。SDK 自带的 tarball 存在时可以跳过这些检查：

```bash
# device/rockchip/common/scripts/check-debian.sh
PREBUILT=$(ls "$RK_SDK_DIR"/debian/linaro-$RK_DEBIAN_VERSION-alip-*.tar.gz 2>/dev/null | head -1)
if [ -n "$PREBUILT" ]; then
	echo "Found prebuilt rootfs, skip live-build/debootstrap check"
fi
```

## 五、用 debugfs 修改镜像（不用重编）

```bash
cd ~/rk3568-sdk
IMG=debian/linaro-rootfs.img          # 注意是 root 权限，操作要 sudo

# 1. 换驱动
cp kernel-6.1/drivers/net/wireless/rockchip_wlan/rkwifi/bcmdhd/bcmdhd.ko /tmp/bcmdhd-inband.ko
sudo debugfs -w -R "rm /lib/modules/bcmdhd.ko" $IMG
sudo debugfs -w -R "write /tmp/bcmdhd-inband.ko /lib/modules/bcmdhd.ko" $IMG
sudo debugfs -w -R "sif /lib/modules/bcmdhd.ko mode 0100644" $IMG

# 2. 注释掉 auto wlan0
sudo debugfs -R "dump /etc/network/interfaces.d/network-priority /tmp/np" $IMG
sed -i 's|^auto wlan0|#auto wlan0|; s|^iface wlan0 inet dhcp|#iface wlan0 inet dhcp|' /tmp/np
sudo debugfs -w -R "rm /etc/network/interfaces.d/network-priority" $IMG
sudo debugfs -w -R "write /tmp/np /etc/network/interfaces.d/network-priority" $IMG
sudo debugfs -w -R "sif /etc/network/interfaces.d/network-priority mode 0100644" $IMG

# 3. 重新打包
./build.sh firmware
```

## 六、实测状态（Debian 12.15）

| 项目 | 状态 | 说明 |
|---|---|---|
| 启动 | ✅ | 内核 6.1.141（本仓库的 dts）|
| 桌面 | ✅ | XFCE + lightdm 自动登录 |
| GPU | ✅ | `/dev/mali0`、`renderD128` |
| HDMI | ✅ | connected，1920x1080 |
| NPU | ✅ | `renderD129`，rknpu 0.9.8 |
| 有线网络 | ✅ | NetworkManager 管理 |
| USB 供电 | ✅ | `gpio-5 out hi` |
| WiFi 驱动 | ✅ | 换带内版后正常加载 |
| **WiFi 扫描** | ❌ | **0 个 AP（射频硬件问题，与系统无关）** |

WiFi 在 Buildroot 和 Debian 下表现完全一致，进一步确认是硬件问题——
详见 `porting-notes.md` 7.14 节。
