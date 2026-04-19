#!/usr/bin/env bash
# ============================================================
# ace-vpn - 系统初始化
# ============================================================
# 完成：apt update/upgrade → 基础工具 → 时区 → BBR + fq
# 幂等：重复执行安全
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_root

TZ_VALUE="${TZ:-Asia/Shanghai}"

# ---------- 1. 系统更新 ----------
log_step "更新系统包列表"
apt_update

log_step "升级已安装的包（可能耗时 1-3 分钟）"
apt_upgrade

# ---------- 2. 安装基础工具 ----------
log_step "安装基础工具"
apt_install \
  curl wget ca-certificates \
  unzip tar \
  vim nano \
  htop iotop \
  net-tools dnsutils iputils-ping \
  ufw \
  fail2ban \
  openssl \
  cron \
  lsb-release

log_ok "基础工具安装完成"

# ---------- 3. 时区 ----------
log_step "设置时区为 ${TZ_VALUE}"
if [[ "$(timedatectl show --property=Timezone --value)" != "${TZ_VALUE}" ]]; then
  timedatectl set-timezone "${TZ_VALUE}"
  log_ok "时区已设为 ${TZ_VALUE}"
else
  log_info "时区已经是 ${TZ_VALUE}，跳过"
fi

# ---------- 4. 开启 BBR + fq ----------
log_step "配置 BBR 拥塞控制 + fq 队列"

SYSCTL_CONF="/etc/sysctl.d/99-ace-vpn.conf"
cat > "${SYSCTL_CONF}" <<'EOF'
# ace-vpn 网络优化
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 提高连接数上限
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 250000

# 提高缓冲区（大带宽延迟积）
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# 开启 TCP Fast Open
net.ipv4.tcp_fastopen = 3

# 防 SYN flood
net.ipv4.tcp_syncookies = 1

# 减少 TIME_WAIT
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
EOF

sysctl --system >/dev/null 2>&1 || true

# 验证 BBR
if lsmod | grep -q bbr || sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
  log_ok "BBR 已启用：$(sysctl -n net.ipv4.tcp_congestion_control)"
else
  log_warn "BBR 未生效，可能需要重启内核。当前拥塞算法：$(sysctl -n net.ipv4.tcp_congestion_control)"
fi

# ---------- 5. 开启 IP 转发（Hysteria2 / WireGuard 将来用） ----------
log_step "开启 IP 转发"
cat > /etc/sysctl.d/98-ace-vpn-forward.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl --system >/dev/null 2>&1 || true
log_ok "IP 转发已开启"

# ---------- 6. 文件句柄上限 ----------
log_step "提高文件句柄上限"
LIMITS_CONF="/etc/security/limits.d/99-ace-vpn.conf"
cat > "${LIMITS_CONF}" <<'EOF'
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
log_ok "文件句柄上限已配置（下次登录生效）"

log_ok "系统初始化完成"
