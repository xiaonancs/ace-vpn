#!/usr/bin/env bash
# 在 VPS 上安装 ace-vpn 订阅转换器（systemd 服务）
# 依赖：Python 3 + PyYAML
#
# 模式 A：单 token（老部署兼容）
#   sudo UPSTREAM_SUB='https://127.0.0.1:2096/<sub-path>/<sub-id>' \
#        SUB_TOKEN='sub-hxn' \
#        bash install-sub-converter.sh
#
# 模式 B：多 token（推荐，一个实例服务全家）
#   sudo UPSTREAM_BASE='https://127.0.0.1:2096/<sub-path>' \
#        SUB_TOKENS='sub-hxn,sub-hxn01' \
#        SERVER_OVERRIDE='<VPS_IP>' \
#        bash install-sub-converter.sh
#
# 所有设备访问 http://<VPS>:25500/clash/<token>，token 必须在白名单里。

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

require_root
require_ubuntu

UPSTREAM_SUB=${UPSTREAM_SUB:-}
UPSTREAM_BASE=${UPSTREAM_BASE:-}
SUB_TOKEN=${SUB_TOKEN:-}
SUB_TOKENS=${SUB_TOKENS:-}
LISTEN_PORT=${LISTEN_PORT:-25500}
COMPANY_CIDRS=${COMPANY_CIDRS:-}
COMPANY_SFX=${COMPANY_SFX:-}
SERVER_OVERRIDE=${SERVER_OVERRIDE:-}

if [[ -n "$UPSTREAM_BASE" ]]; then
  if [[ -z "$SUB_TOKENS" ]]; then
    log_error "UPSTREAM_BASE 模式下必须设置 SUB_TOKENS（逗号分隔的 3x-ui SubId 白名单）"
    log_error "例：SUB_TOKENS='sub-hxn,sub-hxn01'"
    exit 1
  fi
  log_info "模式：多 token（UPSTREAM_BASE + SUB_TOKENS）"
elif [[ -n "$UPSTREAM_SUB" ]]; then
  if [[ -z "$SUB_TOKEN" ]]; then
    SUB_TOKEN=$(openssl rand -hex 12)
    log_warn "未设 SUB_TOKEN，自动生成：$SUB_TOKEN"
  fi
  log_info "模式：单 token（UPSTREAM_SUB + SUB_TOKEN）"
else
  log_error "必须设置 UPSTREAM_BASE+SUB_TOKENS（推荐）或 UPSTREAM_SUB+SUB_TOKEN"
  exit 1
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
Environment=UPSTREAM_BASE=$UPSTREAM_BASE
Environment=SUB_TOKEN=$SUB_TOKEN
Environment=SUB_TOKENS=$SUB_TOKENS
Environment=LISTEN_PORT=$LISTEN_PORT
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
systemctl enable ace-vpn-sub.service
# 强制重启（而不是 --now），确保环境变量 / 代码变更都生效
systemctl restart ace-vpn-sub.service
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

log_step "自检每条 token 的节点数"
if [[ -n "$UPSTREAM_BASE" ]]; then
  IFS=',' read -r -a _check_tokens <<< "$SUB_TOKENS"
  _any_fail=0
  for _t in "${_check_tokens[@]}"; do
    _t=$(echo "$_t" | xargs)
    _cnt=$(curl -s "http://127.0.0.1:${LISTEN_PORT}/clash/${_t}" | grep -c '^- name:' || true)
    if [[ "$_cnt" -gt 0 ]]; then
      log_ok "  ${_t}: ${_cnt} 个节点"
    else
      log_warn "  ${_t}: 0 个节点（检查 3x-ui 里是否存在该 SubId 且已 Enable）"
      _any_fail=1
    fi
  done
  [[ "$_any_fail" -eq 1 ]] && log_warn "部分 token 节点数为 0，请登录面板核对"
fi

PUBLIC_IP=$(curl -s -4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo
log_ok "安装完成 ✓"
echo
if [[ -n "$UPSTREAM_BASE" ]]; then
  echo "  Clash 订阅 URL（每个 token 一条）："
  IFS=',' read -r -a _tokens <<< "$SUB_TOKENS"
  for _t in "${_tokens[@]}"; do
    _t=$(echo "$_t" | xargs)
    echo "    http://${PUBLIC_IP}:${LISTEN_PORT}/clash/${_t}"
  done
else
  echo "  Clash 订阅 URL："
  echo "  http://${PUBLIC_IP}:${LISTEN_PORT}/clash/${SUB_TOKEN}"
  echo
  echo "  iPhone Shadowrocket 用 3x-ui 原订阅："
  echo "  $UPSTREAM_SUB"
fi
echo
echo "  日志查看： journalctl -u ace-vpn-sub -f"
echo "  修改配置： systemctl edit ace-vpn-sub"
