#!/usr/bin/env bash
# ============================================================
# ace-vpn - 一键部署入口
# ============================================================
# 用途：在任意 Ubuntu 22.04/24.04 VPS（Vultr / Oracle / HostDare / RackNerd）上
#       自动完成：系统初始化 → 防火墙 → 3x-ui 安装
#
# 使用：
#   sudo bash scripts/deploy/install.sh
#
# 可选环境变量：
#   TCP_PORT=443       主代理 TCP 端口（默认 443）
#   UDP_PORT=443       Hysteria2 UDP 端口（默认 443）
#   PANEL_PORT=2053    3x-ui 面板端口（默认 2053）
#   SUB_PORT=2096      订阅端口（默认 2096）
#   TZ=Asia/Shanghai   时区（默认上海）
#   SKIP_3XUI=1        跳过 3x-ui 安装（仅做系统初始化）
#   AUTO_CONFIGURE=1   跳过交互，自动配置 3x-ui 入站
#                      （前提：3x-ui 已安装且账号密码可用）
# ============================================================

set -euo pipefail

# ---------- 引入工具函数 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "${ROOT_DIR}/scripts/lib/common.sh"

# ---------- 参数 ----------
TCP_PORT="${TCP_PORT:-443}"
UDP_PORT="${UDP_PORT:-8443}"   # 与 TCP_PORT 分开（3x-ui 端口占用不分 TCP/UDP）
PANEL_PORT="${PANEL_PORT:-2053}"
SUB_PORT="${SUB_PORT:-2096}"
TZ_VALUE="${TZ:-Asia/Shanghai}"

# ---------- 前置检查 ----------
require_root
require_ubuntu
log_info "检测到系统：$(lsb_release -ds)"
log_info "架构：$(uname -m)"

# ---------- Step 1：系统初始化 ----------
log_step "Step 1/3  系统初始化（更新 + 时区 + BBR）"
bash "${SCRIPT_DIR}/setup-system.sh"

# ---------- Step 2：防火墙 ----------
log_step "Step 2/3  配置防火墙（UFW）"
TCP_PORT="${TCP_PORT}" \
UDP_PORT="${UDP_PORT}" \
PANEL_PORT="${PANEL_PORT}" \
SUB_PORT="${SUB_PORT}" \
bash "${SCRIPT_DIR}/setup-firewall.sh"

# ---------- Step 3：3x-ui ----------
if [[ "${SKIP_3XUI:-0}" == "1" ]]; then
  log_warn "SKIP_3XUI=1，跳过 3x-ui 安装"
else
  log_step "Step 3/4  安装 3x-ui"
  bash "${SCRIPT_DIR}/install-3xui.sh"
fi

# ---------- Step 4（可选）：3x-ui 自动化配置 ----------
if [[ "${AUTO_CONFIGURE:-0}" == "1" ]]; then
  log_step "Step 4/4  自动化配置 3x-ui 入站"
  log_warn "需确认面板账号密码可用（默认 admin/admin）"
  sleep 3
  TCP_PORT="${TCP_PORT}" \
  UDP_PORT="${UDP_PORT}" \
  PANEL_PORT="${PANEL_PORT}" \
  bash "${SCRIPT_DIR}/configure-3xui.sh" || {
    log_warn "自动配置失败，请手动在面板里添加入站"
    log_warn "详见 docs/开发者日志.md（3x-ui 入站与订阅）"
  }
else
  log_info "跳过自动化配置（可单独运行 bash scripts/deploy/configure-3xui.sh）"
fi

# ---------- 完成提示 ----------
PUBLIC_IP="$(curl -s --max-time 5 https://api.ipify.org || echo 'YOUR_VPS_IP')"

cat <<EOF

${COLOR_GREEN}============================================================${COLOR_RESET}
${COLOR_GREEN} ace-vpn 部署完成 ✓${COLOR_RESET}
${COLOR_GREEN}============================================================${COLOR_RESET}

  公网 IP     : ${PUBLIC_IP}
  面板端口    : ${PANEL_PORT}
  主代理端口  : ${TCP_PORT}/tcp  ${UDP_PORT}/udp
  订阅端口    : ${SUB_PORT}/tcp

${COLOR_YELLOW}下一步（手动）${COLOR_RESET}

  1. 浏览器打开 3x-ui 面板：
       http://${PUBLIC_IP}:${PANEL_PORT}/
     默认账号密码：admin / admin

  2. 立即改 3 项：
       - 用户名（改成非 admin）
       - 密码（≥ 16 位）
       - 面板路径（改成 /随机路径/）

  3. 添加入站（按 docs/开发者日志.md 中 3x-ui / Reality 说明）：
       - VLESS + Reality（TCP ${TCP_PORT}）
       - Hysteria2        （UDP ${UDP_PORT}）

  4. 开启订阅（§4.3），把生成的 URL 导入客户端

  详细步骤见：docs/开发者日志.md

EOF
