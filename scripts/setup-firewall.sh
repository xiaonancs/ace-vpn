#!/usr/bin/env bash
# ============================================================
# ace-vpn - UFW 防火墙配置
# ============================================================
# 放行：SSH(22) + 主代理 TCP/UDP + 面板 + 订阅
# 默认策略：拒绝所有入站，放行所有出站
# 幂等：重复执行安全（ufw --force）
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_root

TCP_PORT="${TCP_PORT:-443}"
UDP_PORT="${UDP_PORT:-8443}"   # Hy2 UDP，与 TCP_PORT 分开，避免 3x-ui 报端口占用
PANEL_PORT="${PANEL_PORT:-2053}"
SUB_PORT="${SUB_PORT:-2096}"
SSH_PORT="${SSH_PORT:-22}"
HTTP_PORT="${HTTP_PORT:-80}"   # Let's Encrypt HTTP-01 验证 + 续签

# ---------- 1. 确保 ufw 已安装 ----------
if ! command -v ufw >/dev/null 2>&1; then
  log_info "安装 ufw"
  apt_install ufw
fi

# ---------- 2. 重置 + 默认策略 ----------
log_step "重置 UFW 并设置默认策略"
ufw --force reset >/dev/null

ufw default deny incoming
ufw default allow outgoing
ufw default deny routed

log_ok "默认策略：incoming=deny, outgoing=allow"

# ---------- 3. 放行端口 ----------
log_step "放行必要端口"

# SSH（最重要，先开）
ufw allow "${SSH_PORT}/tcp" comment 'SSH'
log_ok "SSH ${SSH_PORT}/tcp 已放行"

# HTTP 80 - Let's Encrypt HTTP-01 验证（3x-ui 强制 SSL + IP 证书 6 天续签）
ufw allow "${HTTP_PORT}/tcp" comment 'Lets Encrypt HTTP-01'
log_ok "HTTP ${HTTP_PORT}/tcp 已放行（Let\\'s Encrypt 续签用）"

# 主代理 - TCP（VLESS + Reality）
ufw allow "${TCP_PORT}/tcp" comment 'ace-vpn main TCP (VLESS+Reality)'
log_ok "主代理 ${TCP_PORT}/tcp 已放行"

# 主代理 - UDP（Hysteria2）
ufw allow "${UDP_PORT}/udp" comment 'ace-vpn main UDP (Hysteria2)'
log_ok "主代理 ${UDP_PORT}/udp 已放行"

# 3x-ui 面板
ufw allow "${PANEL_PORT}/tcp" comment 'ace-vpn 3x-ui panel'
log_ok "面板端口 ${PANEL_PORT}/tcp 已放行"

# 订阅端口
ufw allow "${SUB_PORT}/tcp" comment 'ace-vpn subscription'
log_ok "订阅端口 ${SUB_PORT}/tcp 已放行"

# ---------- 4. 启用 ----------
log_step "启用 UFW"
ufw --force enable

ufw status verbose

# ---------- 5. Oracle Cloud 特殊提示 ----------
if dmesg 2>/dev/null | grep -qi oracle || \
   [[ -f /etc/oracle-cloud-agent/plugins/oci-config ]] || \
   curl -s --max-time 2 http://169.254.169.254/opc/v1/instance/ >/dev/null 2>&1; then
  log_warn "检测到 Oracle Cloud 实例！"
  log_warn "Oracle 还有一层 VCN 安全列表（Security List），需要在 Web 控制台手动放行："
  log_warn "  Networking → Virtual Cloud Networks → 你的 VCN → Security Lists → Add Ingress Rules"
  log_warn "  放行：TCP ${TCP_PORT}, UDP ${UDP_PORT}, TCP ${PANEL_PORT}, TCP ${SUB_PORT}"
fi

log_ok "防火墙配置完成"
