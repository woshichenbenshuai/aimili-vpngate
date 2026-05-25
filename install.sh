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

echo -e "\n${YELLOW}[1/4] 正在安装系统基础依赖 (openvpn, curl, git, iptables...)${PLAIN}"
apt-get update -q || true
apt-get install -y openvpn curl git ca-certificates iptables iproute2 psmisc python3

# 4. Clone or pull the repository
INSTALL_DIR="/opt/aimilivpn"
echo -e "\n${YELLOW}[2/4] 正在从 GitHub 部署源代码到 ${INSTALL_DIR}...${PLAIN}"
if [ -d "${INSTALL_DIR}" ]; then
    echo -e "目录 ${INSTALL_DIR} 已存在，正在更新源码..."
    cd "${INSTALL_DIR}"
    git reset --hard || true
    if git pull; then
        echo -e "${GREEN}源码更新成功！${PLAIN}"
    else
        echo -e "${YELLOW}警告: git pull 失败，将保留当前本地源码并继续安装。${PLAIN}"
    fi
else
    echo -e "正在克隆仓库 ${GITHUB_URL} ..."
    if git clone "${GITHUB_URL}" "${INSTALL_DIR}"; then
        echo -e "${GREEN}克隆成功！${PLAIN}"
    else
        echo -e "${RED}错误: 无法克隆仓库 ${GITHUB_URL}，请检查用户名是否正确及 VPS 访问 GitHub 网络！${PLAIN}"
        exit 1
    fi
fi

# 5. Configure Systemd Service (direct python3 run)
echo -e "\n${YELLOW}[3/4] 正在配置 systemd 系统服务...${PLAIN}"
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

systemctl daemon-reload
systemctl enable aimilivpn.service

# 6. Configure global command shortcut "ml"
echo -e "\n${YELLOW}[4/4] 正在创建全局命令快捷接口 'ml'...${PLAIN}"
cat > /usr/bin/ml <<'EOF'
#!/usr/bin/env python3
import sys
import os
import socket
import subprocess
import time
import tty
import termios

INSTALL_DIR = "/opt/aimilivpn"
LOG_FILE = "/opt/aimilivpn/vpngate_data/vpngate.log"

def check_port_listening(port=7928):
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

def print_status():
    gateway_ok = check_port_listening(7928)
    service_ok = check_service_active("aimilivpn.service")
    pid = get_service_pid("aimilivpn.service")
    
    green = "\033[1;32m"
    red = "\033[1;31m"
    reset = "\033[0m"
    bold = "\033[1m"
    
    gateway_status = f"{green}运行中{reset}" if gateway_ok else f"{red}未运行{reset}"
    if service_ok:
        pid_info = f" (PID: {pid})" if pid else ""
        service_status = f"{green}运行中{reset}{pid_info}"
    else:
        service_status = f"{red}未运行{reset}"
        
    print(f"{bold}Aimili运行状态：{reset}")
    print(f"  网关7928 - {gateway_status}")
    print(f"  Aimili   - {service_status}")
    print()

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

def get_key():
    ch = getch()
    if ch == '\x1b':
        ch2 = getch()
        if ch2 == '[':
            ch3 = getch()
            if ch3 == 'A':
                return 'up'
            elif ch3 == 'B':
                return 'down'
    elif ch == '\r' or ch == '\n':
        return 'enter'
    elif ch == '\x03':
        return 'ctrl+c'
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
        elif cmd == "logs":
            show_logs()
        elif cmd == "update":
            update_service()
        elif cmd == "uninstall":
            uninstall_service()
        else:
            print("未知命令。可用命令: start, stop, restart, status, logs, update, uninstall")
        sys.exit(0)
        
    options = [
        ("启动", start_service),
        ("停止", stop_service),
        ("重启", restart_service),
        ("日志", show_logs),
        ("更新", update_service),
        ("卸载", uninstall_service),
        ("退出", None)
    ]
    
    selected_idx = 0
    while True:
        print("\033[H\033[J", end="")
        print_status()
        
        for i, (name, _) in enumerate(options):
            cmd_hint = ""
            if name == "启动": cmd_hint = "start"
            elif name == "停止": cmd_hint = "stop"
            elif name == "重启": cmd_hint = "restart"
            elif name == "日志": cmd_hint = "logs"
            elif name == "更新": cmd_hint = "update"
            elif name == "卸载": cmd_hint = "uninstall"
            elif name == "退出": cmd_hint = "exit"
            
            if i == selected_idx:
                print(f" \033[1;32m> ml {cmd_hint:<9} - {name}\033[0m")
            else:
                print(f"   ml {cmd_hint:<9} - {name}")
        print()
        
        try:
            key = get_key()
        except KeyboardInterrupt:
            break
            
        if key == 'up':
            selected_idx = (selected_idx - 1) % len(options)
        elif key == 'down':
            selected_idx = (selected_idx + 1) % len(options)
        elif key == 'enter':
            _, func = options[selected_idx]
            if func is None:
                break
            print("\033[H\033[J", end="")
            func()
            if func in (start_service, stop_service, restart_service):
                continue
            break
        elif key == 'ctrl+c' or key == 'q':
            break

if __name__ == "__main__":
    main()
EOF
chmod +x /usr/bin/ml

# 7. Start service
echo -e "\n正在启动 AimiliVPN 服务并检测网络..."
systemctl restart aimilivpn.service || true

# Wait for database/auth files generation
sleep 2

SECRET_PATH="EJsW2EeBo9lY"
AUTH_FILE="${INSTALL_DIR}/vpngate_data/ui_auth.json"
if [ -f "$AUTH_FILE" ]; then
    SECRET_PATH=$(python3 -c "import json; print(json.load(open('$AUTH_FILE'))['secret_path'])" 2>/dev/null || echo "EJsW2EeBo9lY")
fi

# Get VPS public IP
echo -e "正在获取 VPS 公网 IP..."
PUBLIC_IP=$(curl -s --max-time 3 https://api.ipify.org || curl -s --max-time 3 https://ifconfig.me || curl -s --max-time 3 icanhazip.com || echo "你的VPS公网IP")

echo -e "\n${GREEN}==========================================================${PLAIN}"
echo -e "${GREEN}             AimiliVPN 源码一键部署已完成！${PLAIN}"
echo -e "${GREEN}==========================================================${PLAIN}"
echo -e "  * 网页控制面板 (Web UI): ${BLUE}http://${PUBLIC_IP}:8787/${SECRET_PATH}/${PLAIN}"
echo -e "  * HTTP/SOCKS5 代理端口:  ${BLUE}http://127.0.0.1:7928/${PLAIN}"
echo -e " --------------------------------------------------------"
echo -e "  * 快速状态指令:   ${YELLOW}ml status${PLAIN}  或  ${YELLOW}ml${PLAIN}"
echo -e "  * 查看实时日志:   ${YELLOW}ml logs${PLAIN}"
echo -e "  * 停止服务:       ${YELLOW}ml stop${PLAIN}"
echo -e "  * 重启服务:       ${YELLOW}ml restart${PLAIN}"
echo -e "=========================================================="
echo
