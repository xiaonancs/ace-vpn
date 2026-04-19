#!/usr/bin/env bash
# 在 VPS 上安装 ace-vpn 订阅转换器（systemd 服务）
# 依赖：Python 3 + PyYAML
# 用法：
#   sudo UPSTREAM_SUB='https://127.0.0.1:2096/<your-sub-path>/<your-sub-id>' \
#        SUB_TOKEN='任意随机串' \
#        LISTEN_PORT=25500 \
#        COMPANY_CIDRS='10.0.0.0/8,172.16.0.0/12' \
#        COMPANY_SFX='corp.example.com' \
#        bash install-sub-converter.sh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

require_root
require_ubuntu

UPSTREAM_SUB=${UPSTREAM_SUB:-}
LISTEN_PORT=${LISTEN_PORT:-25500}
SUB_TOKEN=${SUB_TOKEN:-}
COMPANY_CIDRS=${COMPANY_CIDRS:-}
COMPANY_SFX=${COMPANY_SFX:-}
SERVER_OVERRIDE=${SERVER_OVERRIDE:-}

if [[ -z "$UPSTREAM_SUB" ]]; then
  log_error "必须设置 UPSTREAM_SUB=https://127.0.0.1:2096/xxx/xxx"
  exit 1
fi

if [[ -z "$SUB_TOKEN" ]]; then
  SUB_TOKEN=$(openssl rand -hex 12)
  log_warn "未设 SUB_TOKEN，自动生成：$SUB_TOKEN"
fi

log_step "安装依赖 python3-yaml"
apt_update
apt_install python3 python3-yaml

INSTALL_DIR=/opt/ace-vpn-sub
mkdir -p "$INSTALL_DIR"
install -m 0755 "$SCRIPT_DIR/sub-converter.py" "$INSTALL_DIR/sub-converter.py"

log_step "写入 systemd 服务"
cat >/etc/systemd/system/ace-vpn-sub.service <<EOF
[Unit]
Description=ace-vpn subscription converter (vless base64 -> Clash YAML)
After=network-online.target

[Service]
Type=simple
Environment=UPSTREAM_SUB=$UPSTREAM_SUB
Environment=LISTEN_PORT=$LISTEN_PORT
Environment=SUB_TOKEN=$SUB_TOKEN
Environment=COMPANY_CIDRS=$COMPANY_CIDRS
Environment=COMPANY_SFX=$COMPANY_SFX
Environment=SERVER_OVERRIDE=$SERVER_OVERRIDE
ExecStart=/usr/bin/python3 $INSTALL_DIR/sub-converter.py
Restart=on-failure
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/ace-vpn-sub.service
systemctl daemon-reload
systemctl enable --now ace-vpn-sub.service
sleep 2

log_step "放行端口 $LISTEN_PORT/tcp"
if command -v ufw &>/dev/null; then
  ufw allow "$LISTEN_PORT/tcp" || true
  ufw reload || true
fi

log_step "检查服务状态"
systemctl is-active ace-vpn-sub.service || {
  log_error "服务未启动，journalctl -u ace-vpn-sub -n 50 查错"
  exit 1
}

PUBLIC_IP=$(curl -s -4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo
log_ok "安装完成 ✓"
echo
echo "  Clash 订阅 URL（Mac/Win/Android 用这个）："
echo "  http://${PUBLIC_IP}:${LISTEN_PORT}/clash/${SUB_TOKEN}"
echo
echo "  iPhone Shadowrocket 仍用 3x-ui 原订阅："
echo "  $UPSTREAM_SUB"
echo
echo "  日志查看： journalctl -u ace-vpn-sub -f"
echo "  修改配置： systemctl edit ace-vpn-sub"
