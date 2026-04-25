#!/usr/bin/env bash
# ============================================================
# ace-vpn - 3x-ui 安装
# ============================================================
# 用途：调用 3x-ui 官方一键脚本 + 基本检查
# 幂等：若已安装会提示，不会重复覆盖
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "${ROOT_DIR}/scripts/lib/common.sh"

require_root

# ---------- 1. 已安装检查 ----------
if systemctl is-active --quiet x-ui 2>/dev/null; then
  log_warn "3x-ui 已经在运行（systemd: x-ui）"
  log_info "面板管理命令：x-ui"
  log_info "查看状态：  systemctl status x-ui"
  log_info "查看日志：  journalctl -u x-ui -f"
  read -rp "是否重新安装？[y/N] " ans
  if [[ "${ans}" != "y" && "${ans}" != "Y" ]]; then
    log_info "跳过 3x-ui 安装"
    exit 0
  fi
fi

# ---------- 2. 下载并执行官方脚本 ----------
log_step "下载并执行 3x-ui 官方安装脚本"
log_info "源：https://github.com/MHSanaei/3x-ui"

# 官方一键脚本（3x-ui 会交互式问账号密码和端口，
# 但我们希望能自动跑；它的最新脚本支持环境变量跳过交互）
INSTALL_URL="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"

# 先下载到临时文件（不直接 curl | bash，方便排查）
TMP_SCRIPT="$(mktemp)"
trap 'rm -f "${TMP_SCRIPT}"' EXIT

if ! curl -fsSL "${INSTALL_URL}" -o "${TMP_SCRIPT}"; then
  log_error "下载 3x-ui 安装脚本失败"
  log_error "请检查网络，或手动访问 https://github.com/MHSanaei/3x-ui"
  exit 1
fi

chmod +x "${TMP_SCRIPT}"

log_info "开始安装..."
bash "${TMP_SCRIPT}"

# ---------- 3. 验证 ----------
log_step "验证 3x-ui 安装"
if systemctl is-active --quiet x-ui 2>/dev/null; then
  log_ok "3x-ui 服务运行正常"
else
  log_warn "3x-ui 服务未运行，尝试启动..."
  systemctl start x-ui || true
  sleep 2
  if systemctl is-active --quiet x-ui; then
    log_ok "3x-ui 已启动"
  else
    log_error "3x-ui 启动失败，请查看 journalctl -u x-ui -xe"
    exit 1
  fi
fi

# 设置开机自启
systemctl enable x-ui >/dev/null 2>&1 || true

log_ok "3x-ui 安装完成"
log_info "管理命令：x-ui  （进入交互菜单）"
