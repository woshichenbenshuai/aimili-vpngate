# AimiliVPN 🌐

Bilingual: [中文](#中文) | [English](#english)

---

## 中文

[![Telegram](https://img.shields.io/badge/TG交流群-arestemple-2CA5E0?style=flat-square&logo=telegram&logoColor=white)](https://t.me/arestemple)
[![Forum](https://img.shields.io/badge/交流论坛-339936.xyz-orange?style=flat-square&logo=discourse&logoColor=white)](https://339936.xyz)
[![Email](https://img.shields.io/badge/Bug反馈-yaohunse7@gmail.com-red?style=flat-square&logo=gmail&logoColor=white)](mailto:yaohunse7@gmail.com)

---

**AimiliVPN** 是一个专为 Linux VPS（如 Ubuntu）设计的智能 VPN 代理网关管理器。它能够自动采集 VPNGate 开放节点，进行多线程可用性测试与延迟过滤，利用 OpenVPN 隧道与策略路由（Policy Routing）实现**安全防失联**的出站网络，并在本地提供高性能的 HTTP/SOCKS5 代理网关服务，非常适合用作 3x-ui / Xray 的落地出站代理。

### ✨ 核心特性

1. ⚡ **自动采集与多线程探活**：
   * 自动定期获取最新的 VPNGate 节点列表。
   * 使用多线程并发对节点进行 Ping 延迟测试与 OpenVPN 握手测试，动态筛选出优质节点。
2. 🔒 **安全防失联（策略路由）**：
   * 采用 Linux 路由表策略，仅将虚拟网卡 `tun0` 的出站流量绑定到自定义路由表（Table 100），不篡改系统默认网关。
   * 确保 VPS 本身的 SSH 连接、Web 服务等依然走物理网卡，**绝不断连失联**。
3. 🚫 **防泄漏阻断（断网保护）**：
   * 本地代理接口在向目标网站发起 socket 连接时，强制通过 `SO_BINDTODEVICE` 绑定到 `tun0`。
   * 一旦 VPN 掉线或网口失效，代理流量将被直接阻断并返回 `502 Bad Gateway`，**严防流量泄漏回物理 IP**（非常适合需要强制锁区的落地节点）。
4. 🖥️ **现代响应式 Web UI 控制台**：
   * 包含精心设计的暗黑/明亮双色管理后台（默认端口 `8787`）。
   * 实时呈现节点状态（国家、ISP、ASN、延迟、直连状态、IP类型如住宅/机房等）。
   * 支持一键手动切换节点、清空黑名单、测试代理和重启后台。
   * 支持随机安全登录后缀路径（例如 `/EJsW2EeBo9lY/`）进行安全越权保护。
5. 🛠️ **CLI 管理终端（ml）**：
   * 全局注册 `ml` 管理命令行工具，内置交互式菜单。
   * 支持快速状态监控、服务启停、实时日志追踪、重置密码、修改绑定地址等。
6. 🩹 **WSL 优化与 DNS 自愈**：
   * 兼容 WSL 环境，内置 DNS 自动修复检测（如发现域名解析失效但 IP 连通，自动补齐公共 DNS 到 `/etc/resolv.conf`）。

---

### 🚀 快速开始

在您的 **Ubuntu** VPS 机器上，复制并运行以下一行指令即可完成自动安装部署：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/baoweise-bot/aimili-vpngate/main/install.sh)
```

---

### 🛠️ 快捷命令行 (CLI)

安装成功后，系统会在全局注册 `ml` 快捷管理指令，直接运行 `ml` 可打开图形化交互终端，也可通过以下指令执行：
* **`ml status`** 或 **`ml`**：查看当前运行状态（代理端口、活动 VPN 节点、直连延迟、网页后台登录地址等）。
* **`ml start`**：启动 AimiliVPN 服务。
* **`ml stop`**：停止 AimiliVPN 服务（并自动清理策略路由与 OpenVPN 进程）。
* **`ml restart`**：重启服务。
* **`ml logs`**：查看实时的 Systemd 服务运行日志。
* **`ml web`**：切换网页绑定地址（127.0.0.1 仅本地，或 0.0.0.0 允许公网访问）与重置安全后缀。
* **`ml port`**：修改网页管理控制台监听端口。
* **`ml password`**：生成新的 12 位安全管理密码。
* **`ml uninstall`**：完全卸载服务并清理相关环境。

---

### ⚙️ 系统架构

```
   [ 3x-ui / Xray ] 
         │ (HTTP / SOCKS5)
         ▼
   [ 本地代理服务器 ] (Port 7928) ──(强制绑定 SO_BINDTODEVICE)──► [ tun0 虚拟网卡 ]
         │                                                            │
         │ (SSH, Web UI, etc. 依然走物理路由)                           │ (策略路由表 100)
         ▼                                                            ▼
   [ 物理网卡 eth0 ] ◄───────────────────────────────────────── [ OpenVPN 加密隧道 ]
         │                                                            │
         ▼ (真实服务器 IP 出站)                                         ▼ (VPNGate 落地节点出站)
    (国内直连流量)                                               (解锁流媒体、锁区网站)
```

---

## English

[![Telegram](https://img.shields.io/badge/Telegram-arestemple-2CA5E0?style=flat-square&logo=telegram&logoColor=white)](https://t.me/arestemple)
[![Forum](https://img.shields.io/badge/Forum-339936.xyz-orange?style=flat-square&logo=discourse&logoColor=white)](https://339936.xyz)
[![Email](https://img.shields.io/badge/Bug%20Report-yaohunse7@gmail.com-red?style=flat-square&logo=gmail&logoColor=white)](mailto:yaohunse7@gmail.com)

---

**AimiliVPN** is an intelligent VPN proxy gateway manager designed specifically for Linux VPS (e.g. Ubuntu). It automatically collects open VPNGate nodes, conducts multi-threaded availability testing and latency filtering, establishes secure out-of-band routing via OpenVPN and policy routing to **prevent VPS lockouts**, and hosts a high-performance local SOCKS5/HTTP proxy gateway. It is highly optimized to serve as a residential/unlocked egress node for upstream proxies like 3x-ui / Xray.

### ✨ Key Features

1. ⚡ **Auto-Collection & Multi-Threaded Probing**:
   * Periodically fetches candidate nodes from VPNGate.
   * Performs concurrent ping latency and handshake tests to maintain a pool of high-quality nodes.
2. 🔒 **Anti-Lockout Routing (Policy Routing)**:
   * Directs traffic from the virtual adapter `tun0` to a customized routing table (Table 100) without altering the system's default gateway.
   * Keeps SSH sessions and server administration panels unaffected by the active VPN.
3. 🚫 **Fail-Safe Leak Protection**:
   * Outbound socket connections inside the local proxy server are strictly bound to `tun0` via `SO_BINDTODEVICE`.
   * If the VPN disconnects, proxy requests are instantly blocked with a `502 Bad Gateway` instead of falling back to the VPS physical IP address.
4. 🖥️ **Modern Web UI Panel**:
   * Sleek dark/light responsive console (default port `8787`).
   * Provides real-time geolocation, ISP, ASN, latency, and IP-type (residential/datacenter) detection.
   * Enables manual node selection, blacklist resets, proxy speed-testing, and logs query.
   * Secured by a random secret path suffix (e.g., `/EJsW2EeBo9lY/`) and password authentication.
5. 🛠️ **CLI Utility (ml)**:
   * Command-line helper tool `ml` with a menu-driven interface.
   * Provides quick statuses, starts/stops the daemon, resets passwords, and changes bind hosts.

---

### 🚀 Quick Start

To install and deploy AimiliVPN on your **Ubuntu** server, copy and paste the following command:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/baoweise-bot/aimili-vpngate/main/install.sh)
```

---

### 🛠️ CLI Helper Commands

Once installed, use the global command `ml` to launch the interactive helper menu, or use the shortcuts below:
* **`ml status`** or **`ml`**: Check running system status (active nodes, proxy ports, latency, URLs).
* **`ml start`**: Start the gateway service.
* **`ml stop`**: Stop the gateway service (and clean routing tables).
* **`ml restart`**: Restart the service.
* **`ml logs`**: View real-time Systemd output logs.
* **`ml web`**: Toggle Web UI accessibility (127.0.0.1 or 0.0.0.0) and reset suffix paths.
* **`ml port`**: Update the Web Console port.
* **`ml password`**: Regenerate a secure 12-character administration password.
* **`ml uninstall`**: Completely remove the service and repository files from your VPS.
