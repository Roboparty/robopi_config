# robopi-config

RoboParty 板卡系统配置工具，基于 [raspi-config](https://github.com/RPi-Distro/raspi-config) 改造，适配 RK3588 / Orange Pi 平台。

`robopi-config` 通过终端图形界面（whiptail）提供系统设置、外设接口配置和硬件测试功能，无需手动修改配置文件。

## 功能

### 系统设置
- WiFi 及网络管理
- 用户密码、主机名、启动方式
- 开机自动登录（命令行 / 桌面）
- CPU 调频策略及频率上下限
- 只读根文件系统（Overlay FS）
- SSH 服务及 sudo 密码开关
- 固件更新（`apt update && apt upgrade`）

### 显示设置
- HDMI / 显示器连接状态查看
- 屏幕休眠开关
- 分辨率信息查看（DRM + X11/Wayland）

### 外设接口
- 设备树叠加管理（SPI、I2C、UART、CAN、PWM 等），勾选即启用
- SSH、VNC 服务开关

### 高级设置
- 可预测网卡名开关
- 网络代理（HTTP/HTTPS/FTP/RSYNC）
- 稳定版 / 测试版软件源切换
- X11 / Wayland 显示后端切换
- 系统日志存储位置
- WiFi 省电模式
- 本地链路地址回退

### 硬件测试
- RoboPi Addon 测试：WS2812 灯带演示/红绿蓝/关闭，以及 SIG 上升沿触发 LED
- 头部电机只读 CAN-FD 通信测试：可选择 CAN 接口并输入 1～8 个电机 ID，仅发送厂商查询命令，不发送运动命令
- 头部电机主动串联测试：可选择 CAN 接口和电机数量，电机 ID 按 1～N 连续生成

附加测试依赖 `robopi_addon` 提供的 `robopi-ws2812` 和
`robopi-sig-key`。进入 **硬件测试 -> RoboPi Addon** 后选择测试项目；动画和
SIG 监听测试会在终端显示运行状态，按 **Ctrl+C** 可停止并返回菜单。

> 电气安全：GPIO1_D5 不能直接承受 5V。SIG 信号必须先转换到板卡 GPIO
> 电压范围，再连接 RK3588S 引脚。

> 电机安全：主动串联测试会使能、标零并向电机发送 MIT 控制帧，电机可能立即运动。程序执行前有两次确认，正常退出或按 Ctrl+C 时会失能已配置的电机。
- WiFi 与以太网实时 ping 监控
- USB 2.0 / 3.0 设备检测
- CAN 总线接口状态
- ADB 调试端口状态
- 串口列表及回环测试
- RS485 收发测试（支持 GPIO 方向控制）
- GPIO 引脚状态查看

### 本地化
- 语言及区域格式
- 时区

## 环境要求

- **硬件**：RK3588S RoboPi2 CM5 Tablet（或兼容的 Orange Pi / RoboParty 板卡）
- **系统**：Orange Pi 1.0.9 Jammy（基于 Ubuntu 22.04），Linux 6.1+ RT 内核
- **依赖**：`whiptail`、`parted`、`psmisc`、`ethtool`、`usbutils`、`iw`、`wireless-tools`、`iproute2`、`can-utils`
- **可选**：`gpiod`、`adb`、`nmtui`（NetworkManager）

## 快速开始

```bash
# 以 root 运行
sudo robopi-config

# 或直接调用指定功能
sudo robopi-config do_wifi_ssid_passphrase
```

使用 **↑ ↓** 方向键选择，**Enter** 确认，**Tab** 切换按钮，**Esc** 返回。

## 编译安装

```bash
# 编译 .deb 包
dpkg-buildpackage -us -uc -b

# 在目标板卡上安装
sudo dpkg -i robopi-config_0.1.0_all.deb
```

## 设备树叠加说明

`robopi-config` 通过管理 `/boot/dtb/rockchip/overlay/` 目录下的设备树叠加文件来开关硬件模块。勾选的叠加写入 `/boot/orangepiEnv.txt` 的 `overlays=` 行，**重启后生效**。

## 许可证

MIT License — 基于 Alex Bradbury 的 raspi-config。

## 相关项目

- [raspi-config](https://github.com/RPi-Distro/raspi-config) — 上游项目
- [orangepi-config](https://github.com/orangepi-xunlong/orangepi-config) — Orange Pi 参考实现
