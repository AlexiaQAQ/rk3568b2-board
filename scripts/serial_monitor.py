#!/usr/bin/env python3
"""极简串口终端 —— 只依赖 pyserial（Ubuntu 自带 python3-serial）。

特点：
  * 双向：键盘输入直接转发给板子（raw 模式），所以 Ctrl+C 能真正打断 u-boot
  * 可选日志：板子所有输出同时写入文件
  * 退出用 Ctrl+]（避免与发给板子的 Ctrl+C 冲突）

用法：
    python3 scripts/serial_monitor.py
    python3 scripts/serial_monitor.py -p /dev/ttyACM0 -b 115200
    python3 scripts/serial_monitor.py -l boot.log
"""
import argparse
import os
import select
import sys
import termios
import tty

try:
    import serial
except ImportError:
    sys.exit("缺少 pyserial，安装：sudo apt install python3-serial 或 pip install pyserial")

QUIT_KEY = b"\x1d"  # Ctrl+]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("-p", "--port", default="/dev/ttyUSB0")
    ap.add_argument("-b", "--baud", type=int, default=1500000)
    ap.add_argument("-l", "--log", default=None, help="同时写入日志文件")
    args = ap.parse_args()

    try:
        ser = serial.Serial(args.port, args.baud, timeout=0)
    except serial.SerialException as e:
        print(f"[serial] 打开 {args.port} 失败: {e}", file=sys.stderr)
        print("[serial] 检查：设备是否存在、是否被别的程序占用", file=sys.stderr)
        return 1

    log = open(args.log, "ab", buffering=0) if args.log else None
    print(
        f"[serial] {args.port} @ {args.baud} 8N1\n"
        "[serial] 键盘输入直连板子（Ctrl+C 会发给板子）\n"
        "[serial] 退出：Ctrl+]" + (f"　日志 -> {args.log}" if args.log else ""),
        file=sys.stderr,
    )

    fd = sys.stdin.fileno()
    old_attr = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        while True:
            rfds, _, _ = select.select([fd, ser.fileno()], [], [], 0.05)
            if fd in rfds:
                key = os.read(fd, 1024)
                if not key or QUIT_KEY in key:
                    break
                ser.write(key)
            if ser.fileno() in rfds:
                data = ser.read(4096)
                if data:
                    os.write(sys.stdout.fileno(), data)
                    if log:
                        log.write(data)
    except KeyboardInterrupt:
        pass
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_attr)
        if log:
            log.close()
        ser.close()
        print("\r\n[serial] 已退出", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
