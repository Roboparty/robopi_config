# robopi-config

A system configuration tool for RoboParty boards, forked from [raspi-config](https://github.com/RPi-Distro/raspi-config) and adapted for RK3588 / Orange Pi platforms.

`robopi-config` provides a terminal-based GUI (whiptail) for system setup, interface configuration, and hardware testing — without editing config files by hand.

## Features

### System Configuration
- WiFi & network management
- User password, hostname, boot target
- Auto login (console / desktop)
- CPU governor & frequency limits
- Read-only root filesystem (Overlay FS)
- SSH & sudo configuration
- Firmware update (`apt update && apt upgrade`)

### Display
- HDMI / display connection status
- Screen blanking (screensaver timeout)
- Resolution information (DRM + X11/Wayland)

### Interface Options
- Device tree overlay management (SPI, I2C, UART, CAN, PWM, etc.)
- SSH & VNC toggle

### Advanced
- Predictable network interface names
- Network proxy (HTTP/HTTPS/FTP/RSYNC)
- Beta / release software repository
- X11 / Wayland backend switch
- Journald log storage location
- WLAN power save
- Link-local fallback

### Hardware Test
- WiFi & Ethernet ping monitor (real-time)
- USB 2.0 / 3.0 device detection
- CAN bus interface check
- ADB debug port status
- Serial port list & loopback test
- RS485 send/receive test with GPIO direction control
- GPIO pin state viewer
- RoboPi Addon test menu for WS2812 effects and SIG rising-edge/LED checks
- Read-only head-motor communication test with selectable CAN interface and IDs
- Active daisy-chain test with selectable CAN interface and motor count

The read-only head-motor test sends manufacturer queries only and supports one
to eight explicitly selected motor IDs. The active daisy-chain test assigns
motor IDs consecutively from 1 to the selected count. It enables and zeroes the
motors and sends MIT control frames, so motors may move immediately. Two safety
confirmations are required, and configured motors are disabled when the test
exits or is interrupted with **Ctrl+C**.

The addon entries require `roboparty-ws2812` and `robopi-sig-key` from
`robopi_addon`. Open **Hardware Test -> RoboPi Addon**, then select a WS2812
color/demo or a SIG/LED mode. Animated and edge-monitor tests show progress in
the terminal and can be stopped with **Ctrl+C**.

> Electrical safety: GPIO1_D5 is not 5 V tolerant. The SIG input must be
> converted to the board's GPIO voltage before it reaches the RK3588S pin.

### Localisation
- Locale (language & regional format)
- Timezone

## Requirements

- **Board**: RK3588S RoboPi2 CM5 Tablet (or compatible Orange Pi / RoboParty boards)
- **OS**: Orange Pi 1.0.9 Jammy (Ubuntu 22.04 based) with Linux 6.1+ RT kernel
- **Dependencies**: `whiptail`, `parted`, `psmisc`, `ethtool`, `usbutils`, `iw`, `wireless-tools`, `iproute2`, `can-utils`
- **Optional**: `gpiod`, `adb`, `nmtui` (NetworkManager)

## Quick Start

```bash
# Run as root
sudo robopi-config

# Or run with a specific function directly
sudo robopi-config do_wifi_ssid_passphrase
```

Navigate with **↑ ↓** arrow keys, **Enter** to select, **Tab** to switch buttons, **Esc** to go back.

## Build & Install

```bash
# Build the .deb package
dpkg-buildpackage -us -uc -b

# Install on target board
sudo dpkg -i robopi-config_0.1.0_all.deb
```

## Device Tree Overlays

`robopi-config` manages hardware module toggles via device tree overlays in `/boot/dtb/rockchip/overlay/`. Selected overlays are written to `overlays=` in `/boot/orangepiEnv.txt` and take effect after a reboot.

## License

MIT License — based on raspi-config by Alex Bradbury.

## Related

- [raspi-config](https://github.com/RPi-Distro/raspi-config) — upstream project
- [orangepi-config](https://github.com/orangepi-xunlong/orangepi-config) — Orange Pi reference
