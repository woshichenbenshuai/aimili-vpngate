#!/usr/bin/env bash
set -e
export DEBIAN_FRONTEND=noninteractive

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

# 1. Check root permissions
if [[ "$(id -u)" != "0" ]]; then
    echo -e "${RED}错误: 必须以 root 权限运行此脚本。请使用: sudo bash $0${PLAIN}"
    exit 1
fi

# 2. Check OS distribution (Ubuntu only)
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        echo -e "${RED}错误: 本系统不是 Ubuntu！目前 AimiliVPN 仅支持 Ubuntu 系统。${PLAIN}"
        exit 1
    fi
else
    echo -e "${RED}错误: 无法确定操作系统版本，缺少 /etc/os-release 文件。${PLAIN}"
    exit 1
fi

echo -e "${BLUE}==========================================================${PLAIN}"
echo -e "${BLUE}        欢迎使用 AimiliVPN 一键源码部署与管理脚本${PLAIN}"
echo -e "${BLUE}==========================================================${PLAIN}"

# 3. Configure GitHub Repository URL
# Default to the official repository (baoweise-bot/aimili-vpngate)
DEFAULT_USER="baoweise-bot"
DEFAULT_REPO="aimili-vpngate"

# Allow custom repository override via command line arguments
GITHUB_USER="${1:-${DEFAULT_USER}}"
GITHUB_REPO="${2:-${DEFAULT_REPO}}"

GITHUB_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"

echo -e "\n${YELLOW}[1/4] 正在安装系统基础依赖...${PLAIN}"
echo -e "  -> 正在运行 apt-get update 更新软件源清单..."
apt-get update -q || true
echo -e "  -> 正在运行 apt-get install 安装基础依赖包 (openvpn, curl, git, iptables, iproute2, psmisc, python3)..."
apt-get install -y openvpn curl git ca-certificates iptables iproute2 psmisc python3

# 4. Clone or pull the repository
INSTALL_DIR="/opt/aimilivpn"
echo -e "\n${YELLOW}[2/4] 正在从 GitHub 部署源代码到 ${INSTALL_DIR}...${PLAIN}"
if [ -f "${INSTALL_DIR}/.local_dev" ]; then
    echo -e "${GREEN}检测到本地开发模式 (.local_dev)，跳过 git pull/reset 保持本地修改。${PLAIN}"
else
    if [ -d "${INSTALL_DIR}" ]; then
        echo -e "  -> 目录 ${INSTALL_DIR} 已存在，正在更新并强制覆盖本地源码..."
        cd "${INSTALL_DIR}"
        git reset --hard || true
        if git pull; then
            echo -e "${GREEN}  -> 源码更新成功！${PLAIN}"
        else
            echo -e "${YELLOW}  -> 警告: git pull 失败，将保留当前本地源码并继续安装。${PLAIN}"
        fi
    else
        echo -e "  -> 正在克隆 GitHub 仓库 ${GITHUB_URL} ..."
        if git clone "${GITHUB_URL}" "${INSTALL_DIR}"; then
            echo -e "${GREEN}  -> 克隆成功！${PLAIN}"
        else
            echo -e "${RED}  -> 错误: 无法克隆仓库 ${GITHUB_URL}，请检查网络！${PLAIN}"
            exit 1
        fi
    fi
fi

# 5. Configure Systemd Service (direct python3 run)
echo -e "\n${YELLOW}[3/4] 正在配置 systemd 系统服务...${PLAIN}"
echo -e "  -> 正在创建服务配置 /lib/systemd/system/aimilivpn.service ..."
cat > /lib/systemd/system/aimilivpn.service <<EOF
[Unit]
Description=AimiliVPN OpenVPN Manager with HTTP/SOCKS5 Proxy
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/python3 vpngate_manager.py
Restart=always
RestartSec=5
EnvironmentFile=-/etc/default/aimilivpn

[Install]
WantedBy=multi-user.target
EOF

echo -e "  -> 正在重新加载 systemd 系统服务列表并启用开机自启..."
systemctl daemon-reload
systemctl enable aimilivpn.service

# 6. Configure global command shortcut "ml"
echo -e "\n${YELLOW}[4/4] 正在创建全局命令快捷接口 'ml'...${PLAIN}"
echo -e "  -> 正在写入管理脚本 /usr/bin/ml ..."
cat > /usr/bin/ml <<'EOF'
#!/usr/bin/env python3
import sys
import os
import socket
import subprocess
import time
import tty
import termios
import select

INSTALL_DIR = "/opt/aimilivpn"
LOG_FILE = "/opt/aimilivpn/vpngate_data/vpngate.log"

def generate_random_password():
    import random
    import string
    symbols = "!@#$%^&*"
    chars = string.ascii_letters + string.digits + symbols
    while True:
        pwd = "".join(random.choices(chars, k=12))
        if any(c.islower() for c in pwd) and any(c.isupper() for c in pwd) and any(c.isdigit() for c in pwd) and any(c in symbols for c in pwd):
            return pwd

def generate_random_suffix():
    import random
    import string
    return "".join(random.choices(string.ascii_letters + string.digits, k=12))

def load_ui_cfg():
    import json
    path = "/opt/aimilivpn/vpngate_data/ui_auth.json"
    cfg = {"host": "0.0.0.0", "port": 8787, "secret_path": "EJsW2EeBo9lY", "password": ""}
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
                for k, v in data.items():
                    cfg[k] = v
        except Exception:
            pass
    return cfg

def save_ui_cfg(cfg):
    import json
    path = "/opt/aimilivpn/vpngate_data/ui_auth.json"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
        return True
    except Exception:
        return False

def load_state():
    import json
    path = "/opt/aimilivpn/vpngate_data/state.json"
    state = {"active_openvpn_node_id": "", "last_check_message": "", "is_connecting": False}
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
                for k, v in data.items():
                    state[k] = v
        except Exception:
            pass
    return state

def get_active_node_info():
    import json
    path = "/opt/aimilivpn/vpngate_data/nodes.json"
    state = load_state()
    active_id = state.get("active_openvpn_node_id")
    if not active_id:
        return None, None
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                nodes = json.load(f)
                for n in nodes:
                    if n.get("id") == active_id:
                        ip = n.get("ip") or n.get("remote_host")
                        loc = n.get("location") or n.get("country") or "未知"
                        return ip, loc
        except Exception:
            pass
    return None, None

def ping_ip(ip):
    if not ip:
        return None
    try:
        # Run standard linux ping command with 1 packet and 2 seconds timeout
        res = subprocess.run(["ping", "-c", "1", "-W", "2", ip], capture_output=True, text=True, timeout=3)
        if res.returncode == 0:
            out = res.stdout
            lines = out.splitlines()
            for line in lines:
                if "rtt" in line or "min/avg" in line:
                    parts = line.split("=")[1].strip().split("/")
                    if len(parts) >= 2:
                        avg_rtt = float(parts[1])
                        return f"{int(avg_rtt)} ms"
            return "已响应"
        else:
            return "检测超时"
    except Exception:
        return "无法连接"

def get_public_ip():
    path = "/opt/aimilivpn/vpngate_data/public_ip.txt"
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                ip = f.read().strip()
                if ip:
                    return ip
        except Exception:
            pass
    import urllib.request
    try:
        req = urllib.request.Request("https://api.ipify.org", headers={"User-Agent": "curl/7.68.0"})
        with urllib.request.urlopen(req, timeout=1.5) as r:
            ip = r.read().decode().strip()
            if ip:
                try:
                    os.makedirs(os.path.dirname(path), exist_ok=True)
                    with open(path, "w", encoding="utf-8") as f:
                        f.write(ip)
                except Exception:
                    pass
                return ip
    except Exception:
        pass
    return "您的服务器公网IP"

def check_port_listening(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.2)
    try:
        s.connect(("127.0.0.1", port))
        s.close()
        return True
    except Exception:
        return False

def check_service_active(service_name="aimilivpn.service"):
    try:
        res = subprocess.run(["systemctl", "is-active", service_name], capture_output=True, text=True, timeout=2)
        return res.stdout.strip() == "active"
    except Exception:
        return False

def check_openvpn_process():
    try:
        res = subprocess.run(["pgrep", "openvpn"], capture_output=True, text=True, timeout=2)
        return bool(res.stdout.strip())
    except Exception:
        return False

def get_service_pid(service_name="aimilivpn.service"):
    try:
        res = subprocess.run(["systemctl", "show", service_name, "--property=MainPID"], capture_output=True, text=True, timeout=2)
        out = res.stdout.strip()
        if out.startswith("MainPID="):
            pid = out.split("=")[1]
            if pid and pid != "0":
                return pid
    except Exception:
        pass
    return None

def get_display_width(s):
    import re
    ansi_escape = re.compile(r'\x1b\[[0-9;]*[mGKH]')
    s_clean = ansi_escape.sub('', s)
    width = 0
    for char in s_clean:
        if ord(char) > 127:
            width += 2
        else:
            width += 1
    return width

def format_line(label, value, target_width=26):
    prefix = "  ● "
    w = get_display_width(label)
    padding = " " * max(0, target_width - w)
    return f"{prefix}{label}{padding}:  {value}"

def get_proxy_egress_state():
    """从 state.json 读取后台代理检测结果 (proxy_ok/proxy_ip/proxy_latency_ms)"""
    import json
    path = "/opt/aimilivpn/vpngate_data/state.json"
    try:
        with open(path, "r", encoding="utf-8") as f:
            s = json.load(f)
        return s.get("proxy_ok"), s.get("proxy_ip", "-"), s.get("proxy_latency_ms", 0), s.get("proxy_error", "")
    except Exception:
        return None, "-", 0, ""

def build_status_lines():
    """构建并返回状态面板的所有文本行（用于静态输出和实时刷新共用）"""
    cfg = load_ui_cfg()
    ui_port = cfg.get("port", 8787)
    secret_path = cfg.get("secret_path", "EJsW2EeBo9lY")
    state = load_state()
    is_connecting = state.get("is_connecting", False)

    gateway_ok = check_port_listening(7928)
    service_ok = check_service_active("aimilivpn.service")
    openvpn_ok = check_openvpn_process()
    pid = get_service_pid("aimilivpn.service")

    active_ip, active_loc = get_active_node_info()
    latency = state.get("active_node_latency", "测试中...") if active_ip else "无活动连接"

    proxy_ok, proxy_ip, proxy_lat, proxy_err = get_proxy_egress_state()

    green  = "\033[1;32m"
    red    = "\033[1;31m"
    reset  = "\033[0m"
    bold   = "\033[1m"
    yellow = "\033[1;33m"
    cyan   = "\033[1;36m"

    gateway_status = f"{green}[已激活]{reset}" if gateway_ok else f"{red}[未启动]{reset}"
    backend_status = (f"{green}[已激活] (PID: {pid}){reset}"
                      if (service_ok and pid) else f"{red}[未启动]{reset}")

    if is_connecting:
        openvpn_status = f"{yellow}[切换中 · {state.get('active_node_latency') or '建立连接'}...]{reset}"
    else:
        openvpn_status = f"{green}[已连接]{reset}" if openvpn_ok else f"{red}[未连接]{reset}"

    # 出口 IP 状态
    if is_connecting:
        egress_status = f"{yellow}[切换中] 正在重新建立出站通道...{reset}"
    elif proxy_ok is True:
        lat_str = f"{proxy_lat} ms" if proxy_lat else "-"
        egress_status = f"{green}[正常] 出口 IP: {proxy_ip}  延迟: {lat_str}{reset}"
    elif proxy_ok is False:
        short_err = (proxy_err or "未知错误")[:60]
        egress_status = f"{red}[不可用] {short_err}{reset}"
    else:
        egress_status = f"{yellow}[未检测] 等待后台代理检测...{reset}"

    login_ip = "127.0.0.1" if cfg.get("host") == "127.0.0.1" else get_public_ip()
    login_url = f"{yellow}http://{login_ip}:{ui_port}/{secret_path}/{reset}"

    lines = []
    lines.append("=======================================================")
    lines.append(f"               {bold}AimiliVPN 管理终端 v2.0{reset}                  ")
    lines.append("=======================================================")
    lines.append("【核心服务状态】")
    lines.append(format_line("代理网关 (Port 7928)", gateway_status))
    lines.append(format_line(f"管理后台 (Port {ui_port})", backend_status))
    lines.append(format_line("连接核心 (OpenVPN)", openvpn_status))
    lines.append(format_line("网页登录地址", login_url))
    lines.append("")
    lines.append("【活动节点 & 出站状态】")

    if is_connecting:
        connecting_msg = state.get("last_check_message") or "正在建立加密隧道并验证路由规则..."
        lines.append(format_line("连接进度", f"{yellow}{connecting_msg}{reset}"))
        lines.append(format_line("出口检测", egress_status))
    elif active_ip:
        lines.append(format_line("节点 IP", active_ip))
        lines.append(format_line("节点地区", active_loc))
        lines.append(format_line("直连延迟", latency))
        lines.append(format_line("出口检测", egress_status))
    else:
        lines.append(format_line("节点状态", f"{red}无活动连接{reset}"))
        lines.append(format_line("出口检测", egress_status))

    lines.append("")
    lines.append("【使用方法】")
    lines.append(f"  export http_proxy=socks5://127.0.0.1:7928")
    lines.append(f"  export https_proxy=socks5://127.0.0.1:7928")
    lines.append("=======================================================")
    return lines

def print_status():
    for line in build_status_lines():
        print(line)

def watch_status():
    """实时监控模式：每 3 秒刷新一次，显示出站 IP / 连接进度。按 q 或 Ctrl+C 退出"""
    import sys
    import select

    bold  = "\033[1m"
    reset = "\033[0m"
    green = "\033[1;32m"
    yellow = "\033[1;33m"

    print(f"进入{bold}实时监控模式{reset}（每 3 秒刷新，按 {green}q{reset} 或 {yellow}Ctrl+C{reset} 退出）")
    time.sleep(0.5)

    # 保存终端设置并切换到 raw 模式以实现非阻塞按键检测
    fd = sys.stdin.fileno()
    try:
        old_settings = termios.tcgetattr(fd)
        tty.setraw(fd)
        raw_mode = True
    except Exception:
        raw_mode = False
        old_settings = None

    try:
        while True:
            # 清屏并重绘
            sys.stdout.write("\033[H\033[J")
            sys.stdout.flush()
            for line in build_status_lines():
                print(line)
            now_str = time.strftime("%H:%M:%S")
            print(f"\n  {yellow}↺ 实时监控中  最近刷新: {now_str}  按 q 退出{reset}")
            sys.stdout.flush()

            # 等待 3 秒，同时响应按键
            deadline = time.time() + 3.0
            while time.time() < deadline:
                remaining = deadline - time.time()
                if raw_mode:
                    rlist, _, _ = select.select([sys.stdin], [], [], min(0.1, remaining))
                    if rlist:
                        ch = sys.stdin.read(1)
                        if ch in ('q', 'Q', '\x03', '\x1b'):
                            return
                else:
                    time.sleep(min(0.2, remaining))
    except KeyboardInterrupt:
        pass
    finally:
        if raw_mode and old_settings is not None:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
        sys.stdout.write("\033[H\033[J")
        sys.stdout.flush()
        print("已退出实时监控模式。")

def start_service():
    print("正在启动 AimiliVPN 服务...", flush=True)
    subprocess.run(["systemctl", "start", "aimilivpn.service"])
    print("已发送启动指令。")
    time.sleep(1)

def stop_service():
    print("正在停止 AimiliVPN 服务...", flush=True)
    subprocess.run(["systemctl", "stop", "aimilivpn.service"])
    print("已发送停止指令。")
    time.sleep(1)

def restart_service():
    print("正在重启 AimiliVPN 服务...", flush=True)
    subprocess.run(["systemctl", "restart", "aimilivpn.service"])
    print("已发送重启指令。")
    time.sleep(1)

def show_logs():
    print("正在查看 AimiliVPN 日志 (按 Ctrl+C 退出)...", flush=True)
    if os.path.exists(LOG_FILE):
        try:
            subprocess.run(["tail", "-f", "-n", "50", LOG_FILE])
        except KeyboardInterrupt:
            pass
    else:
        print(f"日志文件不存在: {LOG_FILE}")
        time.sleep(2)

def update_service():
    print("正在一键更新 AimiliVPN 至最新版本并清理旧代码...", flush=True)
    if os.path.exists(INSTALL_DIR):
        try:
            os.chdir(INSTALL_DIR)
            subprocess.run(["git", "fetch", "--all"], check=True)
            res = subprocess.run(["git", "symbolic-ref", "--short", "-q", "HEAD"], capture_output=True, text=True)
            branch = res.stdout.strip() or "main"
            subprocess.run(["git", "reset", "--hard", f"origin/{branch}"], check=True)
            print("代码拉取成功，正在重新运行安装脚本...", flush=True)
            subprocess.run(["bash", "install.sh"])
        except Exception as e:
            print(f"更新失败: {e}")
            time.sleep(3)
    else:
        print(f"未找到安装目录: {INSTALL_DIR}")
        time.sleep(2)

def uninstall_service():
    confirm = input("确定要完全卸载 AimiliVPN 吗？(y/N): ")
    if confirm.lower() == 'y':
        print("正在完全卸载 AimiliVPN...", flush=True)
        subprocess.run(["systemctl", "stop", "aimilivpn.service"])
        subprocess.run(["systemctl", "disable", "aimilivpn.service"])
        try:
            os.unlink("/lib/systemd/system/aimilivpn.service")
        except Exception:
            pass
        try:
            os.unlink("/usr/bin/ml")
        except Exception:
            pass
        subprocess.run(["rm", "-rf", INSTALL_DIR])
        print("AimiliVPN 已卸载！")
        sys.exit(0)
    else:
        print("已取消卸载。")
        time.sleep(1)

def ask_restart():
    ans = input("配置已保存。是否立即重启服务生效？(Y/n): ").strip().lower()
    if ans in ('', 'y', 'yes'):
        print("正在重启 AimiliVPN 服务...", flush=True)
        subprocess.run(["systemctl", "restart", "aimilivpn.service"])
        print("服务已重启。")
        time.sleep(1.5)

def configure_web():
    cfg = load_ui_cfg()
    while True:
        print("\033[H\033[J", end="")
        print("=======================================================")
        print("               网页绑定与地址后缀配置                  ")
        print("=======================================================")
        print(f"  [1] 切换绑定地址 (当前: {cfg.get('host', '0.0.0.0')})")
        print(f"  [2] 随机重置安全后缀 (当前: {cfg.get('secret_path', '')})")
        print("  [3] 返回主菜单")
        print("=======================================================")
        print("请直接输入数字键 [1-3] 快速执行：", end="", flush=True)
        
        key = getch()
        if key == '1':
            print("\033[H\033[J", end="")
            print("选择网页登录绑定地址：")
            print("  1. 仅允许本地登录 (127.0.0.1 - 更安全)")
            print("  2. 允许公网IP登录 (0.0.0.0 - 方便远程)")
            sel = input("请选择 (1 或 2, 默认2): ").strip()
            if sel == '1':
                cfg['host'] = "127.0.0.1"
            else:
                cfg['host'] = "0.0.0.0"
            save_ui_cfg(cfg)
            print(f"绑定地址已更新为: {cfg['host']}")
            ask_restart()
            break
        elif key == '2':
            print("\033[H\033[J", end="")
            new_path = generate_random_suffix()
            cfg['secret_path'] = new_path
            save_ui_cfg(cfg)
            print("安全登录后缀已随机重置成功！")
            print(f"您的全新安全登录后缀为: {new_path}")
            print(f"新的访问路径为: http://{cfg['host']}:{cfg['port']}/{new_path}/")
            ask_restart()
            break
        elif key == '3' or key == 'q' or key == '\x03':
            break

def configure_port():
    cfg = load_ui_cfg()
    print("\033[H\033[J", end="")
    print("=======================================================")
    print("                      管理端口配置                     ")
    print("=======================================================")
    print(f"当前网页管理端口为: {cfg.get('port', 8787)}")
    try:
        val = input("请输入新的管理端口 (1-65535, 按回车取消): ").strip()
        if val:
            port = int(val)
            if 1 <= port <= 65535:
                cfg['port'] = port
                save_ui_cfg(cfg)
                print(f"管理端口已更新为: {port}")
                ask_restart()
            else:
                print("错误: 端口范围必须在 1 至 65535 之间。")
                time.sleep(2)
    except ValueError:
        print("错误: 输入必须是数字。")
        time.sleep(2)

def configure_password():
    cfg = load_ui_cfg()
    while True:
        print("\033[H\033[J", end="")
        print("=======================================================")
        print("                      管理密码管理                     ")
        print("=======================================================")
        curr_pwd = cfg.get('password', '')
        masked_pwd = curr_pwd if len(curr_pwd) <= 4 else curr_pwd[:3] + "********" + curr_pwd[-2:]
        print(f"当前管理密码为: {masked_pwd}")
        print("  [1] 随机重置密码 (12位数字+字母+符号)")
        print("  [2] 返回主菜单")
        print("=======================================================")
        print("请直接输入数字键 [1-2] 快速执行：", end="", flush=True)
        
        key = getch()
        if key == '1':
            print("\033[H\033[J", end="")
            new_pwd = generate_random_password()
            cfg['password'] = new_pwd
            save_ui_cfg(cfg)
            print("密码重置成功！")
            print(f"您的全新12位安全密码为: {new_pwd}")
            print("此密码已保存在本地，不需要重启服务，刷新浏览器即可登录。")
            input("\n按任意键返回密码菜单...")
        elif key == '2' or key == 'q' or key == '\x03':
            break

def getch():
    fd = sys.stdin.fileno()
    try:
        old_settings = termios.tcgetattr(fd)
    except termios.error:
        return sys.stdin.read(1)
    try:
        tty.setraw(sys.stdin.fileno())
        ch = sys.stdin.read(1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    return ch

def main():
    if os.geteuid() != 0:
        print("错误: 必须以 root 权限运行此命令。")
        sys.exit(1)
        
    if len(sys.argv) > 1:
        cmd = sys.argv[1].lower()
        if cmd == "start":
            start_service()
        elif cmd == "stop":
            stop_service()
        elif cmd == "restart":
            restart_service()
        elif cmd == "status":
            print_status()
        elif cmd in ("watch", "monitor"):
            watch_status()
        elif cmd == "logs":
            show_logs()
        elif cmd == "update":
            update_service()
        elif cmd == "uninstall":
            uninstall_service()
        elif cmd == "web":
            configure_web()
        elif cmd == "port":
            configure_port()
        elif cmd == "password":
            configure_password()
        else:
            print("未知命令。可用命令: start, stop, restart, status, watch, logs, update, uninstall, web, port, password")
        sys.exit(0)
        
    options = {
        '1': ("启动服务 (ml start)", start_service),
        '2': ("停止服务 (ml stop)", stop_service),
        '3': ("重启服务 (ml restart)", restart_service),
        '4': ("日志监控 (ml logs)", show_logs),
        '5': ("网页配置 (ml web)", configure_web),
        '6': ("端口配置 (ml port)", configure_port),
        '7': ("密码管理 (ml password)", configure_password),
        '8': ("一键更新 (ml update)", update_service),
        '9': ("完全卸载 (ml uninstall)", uninstall_service),
        '0': ("退出终端", None)
    }

    bold  = "\033[1m"
    reset = "\033[0m"
    green = "\033[1;32m"
    yellow = "\033[1;33m"

    while True:
        # --- 实时状态面板：每 3 秒刷新，同时等待按键输入 ---
        fd = sys.stdin.fileno()
        try:
            old_settings = termios.tcgetattr(fd)
            tty.setraw(fd)
            raw_mode = True
        except Exception:
            raw_mode = False
            old_settings = None

        pressed_key = None
        try:
            while True:
                sys.stdout.write("\033[H\033[J")
                sys.stdout.flush()
                for line in build_status_lines():
                    print(line)
                print(f"【{bold}终端指令菜单栏{reset}】")
                for k in sorted(options.keys()):
                    if k == '0':
                        continue
                    nm, _ = options[k]
                    print(f"  {green}[{k}]{reset} {nm}")
                print(f"  {green}[0]{reset} {options['0'][0]}")
                print("=======================================================")
                now_str = time.strftime("%H:%M:%S")
                print(f"  {yellow}↺ 每 3 秒自动刷新  {now_str}{reset}  直接按数字键执行指令：", end="", flush=True)

                # 等待 3 秒，期间检测按键
                deadline = time.time() + 3.0
                key = None
                while time.time() < deadline:
                    remaining = deadline - time.time()
                    if raw_mode:
                        rlist, _, _ = select.select([sys.stdin], [], [], min(0.1, remaining))
                        if rlist:
                            key = sys.stdin.read(1)
                            break
                    else:
                        time.sleep(min(0.2, remaining))

                if key is not None:
                    pressed_key = key
                    break  # 收到按键，退出刷新循环，进入命令处理
        except KeyboardInterrupt:
            pressed_key = '\x03'
        finally:
            if raw_mode and old_settings is not None:
                termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

        key = pressed_key
        if key is None or key == '\x03':
            break

        if key in options:
            name, func = options[key]
            if func is None:
                break
            print("\033[H\033[J", end="")
            print(f"正在执行: {name}...\n")
            func()
            if func in (start_service, stop_service, restart_service):
                continue
            if func in (configure_web, configure_port, configure_password, show_logs, update_service):
                continue
            input("\n操作已完成，按回车键返回主菜单...")

if __name__ == "__main__":
    main()
EOF
chmod +x /usr/bin/ml

# 7. Start service
echo -e "\n正在启动 AimiliVPN 服务并初始化网络..."
systemctl restart aimilivpn.service || true

# Wait and poll for node loading and active connection
echo -e "\n正在等待 AimiliVPN 首次获取节点并建立加密通道 (此过程可能需要 5-30 秒)..."
ACTIVE_ID=""
LAST_MSG=""
for i in {1..90}; do
    if [ -f "${INSTALL_DIR}/vpngate_data/state.json" ]; then
        ACTIVE_ID=$(python3 -c "import json; print(json.load(open('${INSTALL_DIR}/vpngate_data/state.json')).get('active_openvpn_node_id', ''))" 2>/dev/null || echo "")
        IS_CONN=$(python3 -c "import json; print(json.load(open('${INSTALL_DIR}/vpngate_data/state.json')).get('is_connecting', False))" 2>/dev/null || echo "False")
        CUR_MSG=$(python3 -c "import json; print(json.load(open('${INSTALL_DIR}/vpngate_data/state.json')).get('last_check_message', ''))" 2>/dev/null || echo "")
        
        if [ "$IS_CONN" = "False" ] || [ "$IS_CONN" = "false" ]; then
            if [ -n "$ACTIVE_ID" ]; then
                echo -e "  -> ${GREEN}[已就绪]${PLAIN} 首次节点连接成功，活动节点: ${GREEN}$ACTIVE_ID${PLAIN}"
                break
            else
                if [ -n "$CUR_MSG" ] && [ "$CUR_MSG" != "$LAST_MSG" ]; then
                    echo -e "  -> 提示: ${YELLOW}${CUR_MSG}${PLAIN}"
                    LAST_MSG="$CUR_MSG"
                fi
            fi
        else
            if [ -n "$CUR_MSG" ] && [ "$CUR_MSG" != "$LAST_MSG" ]; then
                echo -e "  -> 状态: ${YELLOW}${CUR_MSG}${PLAIN}"
                LAST_MSG="$CUR_MSG"
            fi
        fi
    else
        echo -n "."
    fi
    sleep 1
done
if [ -z "$ACTIVE_ID" ]; then
    echo -e "  -> ${YELLOW}[加载超时]${PLAIN} 首次节点获取或连接超时，将在后台继续尝试..."
fi

SECRET_PATH="EJsW2EeBo9lY"
PASSWORD="未配置"
AUTH_FILE="${INSTALL_DIR}/vpngate_data/ui_auth.json"
if [ -f "$AUTH_FILE" ]; then
    SECRET_PATH=$(python3 -c "import json; print(json.load(open('$AUTH_FILE'))['secret_path'])" 2>/dev/null || echo "EJsW2EeBo9lY")
    PASSWORD=$(python3 -c "import json; print(json.load(open('$AUTH_FILE'))['password'])" 2>/dev/null || echo "未配置")
fi

# Get VPS public IP
echo -e "正在获取 VPS 公网 IP..."
PUBLIC_IP=$(curl -s --max-time 3 https://api.ipify.org || curl -s --max-time 3 https://ifconfig.me || curl -s --max-time 3 icanhazip.com || echo "您的服务器公网IP")
echo -n "$PUBLIC_IP" > "${INSTALL_DIR}/vpngate_data/public_ip.txt"

echo -e "\n${GREEN}==========================================================${PLAIN}"
echo -e "${GREEN}             AimiliVPN 源码一键部署已完成！${PLAIN}"
echo -e "${GREEN}==========================================================${PLAIN}"
echo -e "  * 网页控制面板:  ${BLUE}http://${PUBLIC_IP}:8787/${SECRET_PATH}/${PLAIN}"
echo -e "  * 网页管理密码:  ${YELLOW}${PASSWORD}${PLAIN}"
echo -e "  * HTTP/SOCKS5 代理端口:  ${BLUE}http://127.0.0.1:7928/${PLAIN}"
echo -e " --------------------------------------------------------"
echo -e "  * 快速状态指令:   ${YELLOW}ml status${PLAIN}  或  ${YELLOW}ml${PLAIN}"
echo -e "  * 查看实时日志:   ${YELLOW}ml logs${PLAIN}"
echo -e "  * 停止服务:       ${YELLOW}ml stop${PLAIN}"
echo -e "  * 重启服务:       ${YELLOW}ml restart${PLAIN}"
echo -e "=========================================================="
echo
