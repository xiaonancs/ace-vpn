#!/usr/bin/env bash
# 通用工具函数：日志、检查、辅助
# 被 scripts/*.sh 通过 source 引入

# ---------- 颜色 ----------
# 使用 ANSI-C quoting $'…' 让变量里就是真实的 ESC 字符，
# 这样 `cat <<EOF` / `printf %s` 都能正确染色，不需要再 echo -e。
if [[ -t 1 ]]; then
  COLOR_RED=$'\033[0;31m'
  COLOR_GREEN=$'\033[0;32m'
  COLOR_YELLOW=$'\033[0;33m'
  COLOR_BLUE=$'\033[0;34m'
  COLOR_CYAN=$'\033[0;36m'
  COLOR_BOLD=$'\033[1m'
  COLOR_RESET=$'\033[0m'
else
  COLOR_RED=''; COLOR_GREEN=''; COLOR_YELLOW=''
  COLOR_BLUE=''; COLOR_CYAN=''; COLOR_BOLD=''; COLOR_RESET=''
fi

# ---------- 日志 ----------
log_info()  { printf '%s[INFO]%s %s\n'  "${COLOR_CYAN}"   "${COLOR_RESET}" "$*"; }
log_warn()  { printf '%s[WARN]%s %s\n'  "${COLOR_YELLOW}" "${COLOR_RESET}" "$*" >&2; }
log_error() { printf '%s[ERROR]%s %s\n' "${COLOR_RED}"    "${COLOR_RESET}" "$*" >&2; }
log_step()  { printf '\n%s%s==>%s %s%s%s\n\n' "${COLOR_BOLD}" "${COLOR_BLUE}" "${COLOR_RESET}" "${COLOR_BOLD}" "$*" "${COLOR_RESET}"; }
log_ok()    { printf '%s✓%s %s\n' "${COLOR_GREEN}" "${COLOR_RESET}" "$*"; }

# ---------- 检查函数 ----------
require_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "必须 root 运行。请使用：sudo bash $0"
    exit 1
  fi
}

require_ubuntu() {
  if [[ ! -f /etc/os-release ]]; then
    log_error "未检测到 /etc/os-release，无法判断系统"
    exit 1
  fi
  . /etc/os-release
  if [[ "${ID}" != "ubuntu" && "${ID}" != "debian" ]]; then
    log_warn "当前系统是 ${PRETTY_NAME}，脚本针对 Ubuntu 22.04/24.04 测试；Debian 一般兼容，其它发行版未测试"
    read -rp "继续？[y/N] " ans
    [[ "${ans}" == "y" || "${ans}" == "Y" ]] || exit 1
  fi
}

# 等待 apt 锁释放（cloud-init / unattended-upgrades 可能占用）
wait_apt() {
  local max_wait=300
  local waited=0
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
     || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 \
     || fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
    if (( waited >= max_wait )); then
      log_error "等待 apt 锁超时（${max_wait}s），请手动检查"
      exit 1
    fi
    log_info "apt 被占用，等待中...（${waited}s / ${max_wait}s）"
    sleep 5
    waited=$((waited + 5))
  done
}

apt_install() {
  wait_apt
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

apt_update() {
  wait_apt
  DEBIAN_FRONTEND=noninteractive apt-get update -y
}

apt_upgrade() {
  wait_apt
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
}
