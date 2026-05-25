#!/usr/bin/env bash
set -euo pipefail
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
#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/aimilivpn"

show_help() {
    echo "使用说明:"
    echo "  ml start      - 启动服务"
    echo "  ml stop       - 停止服务"
    echo "  ml restart    - 重启服务"
    echo "  ml logs       - 查看实时服务运行日志"
    echo "  ml status     - 查看运行状态"
    echo "  ml uninstall  - 卸载服务及清除源码文件"
}

if [[ "$(id -u)" != "0" ]]; then
    echo "错误: 必须以 root 权限运行此命令。"
    exit 1
fi

case "${1:-}" in
    start)
        systemctl start aimilivpn.service
        echo "AimiliVPN 服务已启动。"
        ;;
    stop)
        systemctl stop aimilivpn.service
        echo "AimiliVPN 服务已停止。"
        ;;
    restart)
        systemctl restart aimilivpn.service
        echo "AimiliVPN 服务已重启。"
        ;;
    status)
        systemctl status aimilivpn.service || true
        ;;
    logs)
        echo "正在查看 AimiliVPN 日志 (按 Ctrl+C 退出)..."
        journalctl -u aimilivpn.service -f -n 50
        ;;
    uninstall)
        echo "正在完全卸载 AimiliVPN..."
        systemctl stop aimilivpn.service || true
        systemctl disable aimilivpn.service || true
        rm -f /lib/systemd/system/aimilivpn.service
        rm -f /usr/bin/ml
        rm -rf "${INSTALL_DIR}"
        echo "AimiliVPN 卸载完毕！"
        ;;
    *)
        show_help
        ;;
esac
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

echo -e "\n${GREEN}==========================================================${PLAIN}"
echo -e "${GREEN}             AimiliVPN 源码一键部署已完成！${PLAIN}"
echo -e "${GREEN}==========================================================${PLAIN}"
echo -e "  * 网页控制面板 (Web UI): ${BLUE}http://你的VPS公网IP:8787/${SECRET_PATH}/${PLAIN}"
echo -e "  * HTTP/SOCKS5 代理端口:  ${BLUE}http://127.0.0.1:7928/${PLAIN}"
echo -e " --------------------------------------------------------"
echo -e "  * 快速状态指令:   ${YELLOW}ml status${PLAIN}  或  ${YELLOW}ml${PLAIN}"
echo -e "  * 查看实时日志:   ${YELLOW}ml logs${PLAIN}"
echo -e "  * 停止服务:       ${YELLOW}ml stop${PLAIN}"
echo -e "  * 重启服务:       ${YELLOW}ml restart${PLAIN}"
echo -e "=========================================================="
echo
