#!/usr/bin/env bash
# ==============================================================================
#  PrintPulse Relay Agent - One-Line Installer
#  URL: https://support.goxtt.com/printpulse/install.sh
# ==============================================================================

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

INSTALL_DIR="/opt/printpulse-agent"
SERVICE_NAME="printpulse-agent"
BASE_URL="https://support.goxtt.com/printpulse"
PORT=8088

echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║              🖨️  PrintPulse Relay Agent Installer           ║"
echo "  ║           Remote 3D Printer & Camera Gateway Daemon          ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check for root / sudo
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${YELLOW}Notice: This script requires administrative privileges.${NC}"
    echo "Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

echo -e "➡️  [1/6] Detecting system package manager..."

if command -v apt-get >/dev/null 2>&1; then
    echo "Installing prerequisites via apt..."
    apt-get update -qq
    apt-get install -y -qq python3 python3-pip python3-venv curl tar
elif command -v dnf >/dev/null 2>&1; then
    echo "Installing prerequisites via dnf..."
    dnf install -y python3 python3-pip python3-virtualenv curl tar
elif command -v pacman >/dev/null 2>&1; then
    echo "Installing prerequisites via pacman..."
    pacman -Sy --noconfirm python python-pip python-virtualenv curl tar
elif command -v apk >/dev/null 2>&1; then
    echo "Installing prerequisites via apk..."
    apk add --no-cache python3 py3-pip py3-virtualenv curl tar bash
else
    echo -e "${YELLOW}Warning: Unknown package manager. Please ensure python3 and python3-venv are installed.${NC}"
fi

echo -e "➡️  [2/6] Preparing installation directory at ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}/data" "${INSTALL_DIR}/web"

# Stop existing service if running
if systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
    echo "Stopping existing PrintPulse service..."
    systemctl stop "${SERVICE_NAME}" || true
fi

echo -e "➡️  [3/6] Downloading PrintPulse Agent files..."
if curl -fsSL "${BASE_URL}/agent.tar.gz" -o "/tmp/printpulse-agent.tar.gz" 2>/dev/null; then
    tar -xzf "/tmp/printpulse-agent.tar.gz" -C "${INSTALL_DIR}"
    rm -f "/tmp/printpulse-agent.tar.gz"
else
    # Fallback to direct file download
    curl -fsSL "${BASE_URL}/agent.py" -o "${INSTALL_DIR}/agent.py"
    curl -fsSL "${BASE_URL}/requirements.txt" -o "${INSTALL_DIR}/requirements.txt"
    curl -fsSL "${BASE_URL}/start.sh" -o "${INSTALL_DIR}/start.sh"
    curl -fsSL "${BASE_URL}/web/index.html" -o "${INSTALL_DIR}/web/index.html"
fi

chmod +x "${INSTALL_DIR}/start.sh" "${INSTALL_DIR}/agent.py"

echo -e "➡️  [4/6] Setting up Python virtual environment..."
if [ ! -d "${INSTALL_DIR}/venv" ]; then
    python3 -m venv "${INSTALL_DIR}/venv"
fi

"${INSTALL_DIR}/venv/bin/pip" install --upgrade pip -q
"${INSTALL_DIR}/venv/bin/pip" install -q -r "${INSTALL_DIR}/requirements.txt"

echo -e "➡️  [5/6] Creating systemd service..."
cat <<EOF > /etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=PrintPulse 3D Printer Relay Agent
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/venv/bin/python ${INSTALL_DIR}/agent.py
Restart=always
RestartSec=5
Environment=PRINTPULSE_PORT=${PORT}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1
systemctl restart "${SERVICE_NAME}"

echo -e "➡️  [6/6] Verifying service status..."
sleep 2

if systemctl is-active --quiet "${SERVICE_NAME}"; then
    # Fetch pairing info
    PAIRING_INFO=$(curl -s --max-time 3 http://127.0.0.1:${PORT}/api/agent/info 2>/dev/null || echo "")
    PAIRING_CODE=$(echo "${PAIRING_INFO}" | grep -o '"pairingCode":"[^"]*' | cut -d'"' -f4 || echo "------")
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ PrintPulse Relay Agent Successfully Installed and Started!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  🌐 Web Dashboard:    ${CYAN}http://${LOCAL_IP}:${PORT}${NC}  or  ${CYAN}http://localhost:${PORT}${NC}"
    echo -e "  🔑 6-Digit Pairing Code: ${YELLOW}${PAIRING_CODE}${NC}"
    echo ""
    echo -e "  📱 In the PrintPulse Android App:"
    echo -e "     1. Tap ${CYAN}Add Agent 🌐${NC} (or the Remote Access banner)"
    echo -e "     2. Enter IP: ${CYAN}${LOCAL_IP}${NC} (or ZeroTier IP) and Code: ${YELLOW}${PAIRING_CODE}${NC}"
    echo -e "     3. Tap ${CYAN}Pair & Sync Printers${NC}"
    echo ""
    echo -e "  🔧 Service Commands:"
    echo "     - Check status:  systemctl status ${SERVICE_NAME}"
    echo "     - View logs:     journalctl -u ${SERVICE_NAME} -f"
    echo "     - Restart:       systemctl restart ${SERVICE_NAME}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
else
    echo -e "${RED}Error: Service failed to start. Check logs with 'journalctl -u ${SERVICE_NAME} -n 30'${NC}"
    exit 1
fi
EOF
