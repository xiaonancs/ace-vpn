#!/usr/bin/env bash
# ace-vpn · 反 GFW 探测硬化（一台或多台 VPS 一键检查 + 加固）
#
# 用途：
#   减少 VPS IP 被 GFW 封锁的概率。所有改动都是 idempotent（重复跑安全）。
#
# 用法：
#   bash scripts/deploy/harden-vps.sh                  # VPS_IP_LIST 里所有节点
#   bash scripts/deploy/harden-vps.sh --vps name|ip    # 指定一台
#   bash scripts/deploy/harden-vps.sh --check          # 只检查不改（最先跑一次看现状）
#   bash scripts/deploy/harden-vps.sh --apply          # 真正改（默认模式）
#   bash scripts/deploy/harden-vps.sh --aggressive     # 含激进项（关 ICMP / 改端口建议等）
#   bash scripts/deploy/harden-vps.sh --disable-password  # 才会关 sshd 密码登录（默认保留）
#
# 硬化项（自动）：
#   [1] UFW deny 80/tcp inbound       → 消除 HTTP 主动探测面
#   [2] UFW deny panel/2096 inbound   → 面板和 3x-ui 原生订阅只走 localhost/SSH 隧道
#   [3] UFW deny 25,465,587 out       → 不让 GFW 把你识别成发垃圾邮件源
#   [4] fail2ban 启用 + sshd jail     → 拒爆破，降低被扫描后被封的概率
#   [5] sysctl 网络栈硬化              → 拒非常规分片 / icmp_redirect
#   [6] BBR 已开 + tcp_max_syn_backlog 调高
#   [7] sshd disable PasswordAuth     → 强制 key（仅在已检测到至少一个 authorized_key 时）
#   --aggressive 才做：
#   [8] icmp_echo_ignore_all=1        → 关 ICMP 回应（部分诊断变难）
#   [9] 改 sshd 默认端口建议（不强改）
#
# 硬化项（仅检查 + 报告）：
#   [A] 3x-ui 面板端口（< 30000 告警）
#   [B] 3x-ui 面板路径长度（< 16 字符告警）
#   [C] 3x-ui inbound reality dest（非 microsoft/apple/cloudflare 告警）
#   [D] IP 段 abuse 分（bgp.tools 拉）—— 信息性
#   [E] ICMP 当前从国内云能否 ping 通 —— 信息性
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"

color_red=$'\033[31m'; color_grn=$'\033[32m'; color_ylw=$'\033[33m'
color_cyn=$'\033[36m'; color_bld=$'\033[1m'; color_off=$'\033[0m'
die()  { echo "${color_red}ERROR${color_off} $*" >&2; exit 1; }
info() { echo "${color_grn}→${color_off} $*"; }
ok()   { echo "  ${color_grn}✓${color_off} $*"; }
no()   { echo "  ${color_red}✗${color_off} $*"; }
warn() { echo "  ${color_ylw}!${color_off} $*"; }
hdr()  { echo; echo "${color_cyn}━━━ $* ━━━${color_off}"; }
step() { echo; echo "${color_bld}${color_cyn}▶ $*${color_off}"; }

# ────────── 参数 ──────────
MODE="apply"                # check | apply
AGGRESSIVE=0
DISABLE_PASSWORD=0          # 默认不动 sshd 密码登录，避免把自己锁在外面
ONE_TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)            MODE="check"; shift ;;
    --apply)            MODE="apply"; shift ;;
    --aggressive)       AGGRESSIVE=1; shift ;;
    --disable-password) DISABLE_PASSWORD=1; shift ;;
    --vps)              ONE_TARGET="$2"; shift 2 ;;
    --vps=*)            ONE_TARGET="${1#*=}"; shift ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | sed -n '/^#/p' | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) die "未知参数：$1（--help 查用法）" ;;
  esac
done

# source env.sh
PRESET_VPS_SSH_KEY="${VPS_SSH_KEY:-}"
PRESET_VPS_SSH_USER="${VPS_SSH_USER:-}"
PRESET_PANEL_PORTS="${PANEL_PORTS:-}"
PRESET_XUI_SUB_PORTS="${XUI_SUB_PORTS:-}"
if [[ -z "${VPS_IP_LIST:-}" && -f "$ROOT_DIR/private/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/private/env.sh"
fi
[[ -n "$PRESET_VPS_SSH_KEY" ]] && VPS_SSH_KEY="$PRESET_VPS_SSH_KEY"
[[ -n "$PRESET_VPS_SSH_USER" ]] && VPS_SSH_USER="$PRESET_VPS_SSH_USER"
[[ -n "$PRESET_PANEL_PORTS" ]] && PANEL_PORTS="$PRESET_PANEL_PORTS"
[[ -n "$PRESET_XUI_SUB_PORTS" ]] && XUI_SUB_PORTS="$PRESET_XUI_SUB_PORTS"
VPS_SSH_USER=${VPS_SSH_USER:-root}
PANEL_PORTS="${PANEL_PORTS:-${PANEL_PORT:-52031}}"
XUI_SUB_PORTS="${XUI_SUB_PORTS:-${SUB_PORT:-2096}}"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
if [[ -n "${VPS_SSH_KEY:-}" ]]; then
  expanded=${VPS_SSH_KEY/#~/$HOME}
  [[ -f "$expanded" ]] && SSH_OPTS+=(-i "$expanded")
fi

# ────────── 解析目标节点 ──────────
declare -a TARGETS  # name|ip
if [[ -n "$ONE_TARGET" ]]; then
  for entry in $VPS_IP_LIST; do
    n="${entry%%:*}"; i="${entry##*:}"
    [[ "$n" == "$i" ]] && n="vps"
    if [[ "$ONE_TARGET" == "$n" || "$ONE_TARGET" == "$i" ]]; then
      TARGETS=("$n|$i"); break
    fi
  done
  if [[ ${#TARGETS[@]} -eq 0 ]]; then
    TARGETS=("custom|$ONE_TARGET")
  fi
else
  idx=1
  for entry in $VPS_IP_LIST; do
    if [[ "$entry" == *:* ]]; then
      n="${entry%%:*}"; i="${entry##*:}"
    else
      n="vps${idx}"; i="$entry"
    fi
    TARGETS+=("$n|$i")
    idx=$((idx + 1))
  done
fi
[[ ${#TARGETS[@]} -eq 0 ]] && die "没有可硬化的目标（VPS_IP_LIST 为空 + 没传 --vps）"

hdr "硬化目标"
for t in "${TARGETS[@]}"; do echo "  • ${t%|*} → ${t#*|}"; done
echo "  模式：$MODE$( [[ $AGGRESSIVE -eq 1 ]] && echo '，含 --aggressive 激进项')"

# ────────── 本机预检：bgp.tools 拉每个 IP 的 ASN abuse 信息 ──────────
hdr "[D] IP / ASN abuse 信息（信息性）"
for t in "${TARGETS[@]}"; do
  ip="${t#*|}"
  info "$ip"
  # 公开 IP 信息 API（无需鉴权）
  jget() {
    local key=$1 json=$2
    echo "$json" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    v = d.get('$key', '')
    print(v if isinstance(v, str) else str(v))
except: print('')" 2>/dev/null
  }
  raw=$(curl -fsS --max-time 6 "https://ipinfo.io/$ip/json" 2>/dev/null || echo '{}')
  org=$(jget org "$raw")
  city=$(jget city "$raw")
  country=$(jget country "$raw")
  echo "    org=$org  city=$city  country=$country"
  # AbuseIPDB 需要 token，跳过；这里给一个简单的 datacenter 标签判断
  if echo "$org" | grep -qiE 'amazon|google|microsoft|oracle|akamai|hosting|datacenter|colocation|cdn|aliyun|tencent|baremetal'; then
    warn "  此 IP 段是已知 datacenter / cloud，GFW 风控等级高（无解，但要更小心）"
  fi
done

# ────────── 远端硬化（单台执行）──────────
harden_one() {
  local name=$1 ip=$2
  step "${name} (${ip})"

  if ! ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip" 'echo OK' >/dev/null 2>&1; then
    no "SSH 不通，跳过"
    return 1
  fi
  ok "SSH 通"

  ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip" \
    "MODE=$MODE AGGRESSIVE=$AGGRESSIVE DISABLE_PASSWORD=$DISABLE_PASSWORD PANEL_PORTS='$PANEL_PORTS' XUI_SUB_PORTS='$XUI_SUB_PORTS' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail
MODE=${MODE:-check}
AGGRESSIVE=${AGGRESSIVE:-0}
DISABLE_PASSWORD=${DISABLE_PASSWORD:-0}
PANEL_PORTS=${PANEL_PORTS:-52031}
XUI_SUB_PORTS=${XUI_SUB_PORTS:-2096}

c_grn=$'\033[32m'; c_red=$'\033[31m'; c_ylw=$'\033[33m'; c_off=$'\033[0m'
yes()  { echo "    ${c_grn}✓${c_off} $*"; }
fix()  { echo "    ${c_ylw}↻${c_off} $*"; }
note() { echo "    ${c_red}!${c_off} $*"; }

run() {
  # 仅 apply 模式真改；check 模式只打印
  if [[ "$MODE" == "check" ]]; then
    echo "    [would] $*"
  else
    eval "$@"
  fi
}

# [1] UFW deny 80/tcp inbound（关闭 HTTP 探测面）
echo
echo "  [1] UFW deny 80/tcp inbound"
if command -v ufw >/dev/null; then
  if ufw status | grep -qE "^80/tcp\s+DENY"; then
    yes "已 deny 80/tcp"
  else
    fix "ufw deny 80/tcp"
    run "ufw deny 80/tcp >/dev/null && ufw reload >/dev/null"
    yes "完成"
  fi
else
  note "未装 ufw，跳过（建议 apt install ufw）"
fi

# [2] UFW deny panel / 3x-ui native subscription inbound
echo "  [2] UFW deny panel / 3x-ui native subscription inbound"
if command -v ufw >/dev/null; then
  for p in $PANEL_PORTS $XUI_SUB_PORTS; do
    [[ -z "$p" ]] && continue
    if ufw status | grep -qE "^${p}/tcp\s+DENY"; then
      yes "${p}/tcp inbound 已 deny"
    else
      fix "ufw deny ${p}/tcp"
      run "ufw deny ${p}/tcp >/dev/null"
    fi
  done
  run "ufw reload >/dev/null"
fi

# [3] UFW deny 25/465/587 out（杜绝发邮件假象）
echo "  [3] UFW deny SMTP out (25/465/587)"
if command -v ufw >/dev/null; then
  for p in 25 465 587; do
    if ufw status | grep -qE "^${p}/tcp\s+DENY OUT"; then
      yes "${p}/tcp out 已 deny"
    else
      fix "ufw deny out ${p}/tcp"
      run "ufw deny out ${p}/tcp >/dev/null"
    fi
  done
  run "ufw reload >/dev/null"
fi

# [4] fail2ban
echo "  [4] fail2ban"
if ! dpkg -l fail2ban 2>/dev/null | grep -q ^ii; then
  fix "apt install fail2ban"
  run "DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban >/dev/null"
fi
if [[ ! -f /etc/fail2ban/jail.d/sshd.local ]]; then
  fix "写 /etc/fail2ban/jail.d/sshd.local"
  if [[ "$MODE" == "apply" ]]; then
    cat >/etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
mode    = aggressive
maxretry = 3
findtime = 10m
bantime  = 24h
EOF
    systemctl restart fail2ban
  fi
fi
if systemctl is-active fail2ban >/dev/null 2>&1; then
  yes "fail2ban running"
else
  note "fail2ban 未启动"
fi

# [5] sysctl 网络栈硬化
echo "  [5] sysctl 网络栈硬化"
SYSCTL_FILE=/etc/sysctl.d/99-ace-vpn-harden.conf
desired=$(cat <<'EOF'
# ace-vpn harden
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.tcp_max_syn_backlog=8192
net.core.netdev_max_backlog=16384
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
)
if [[ ! -f "$SYSCTL_FILE" ]] || ! diff -q <(echo "$desired") "$SYSCTL_FILE" >/dev/null 2>&1; then
  fix "写 $SYSCTL_FILE"
  if [[ "$MODE" == "apply" ]]; then
    echo "$desired" > "$SYSCTL_FILE"
    sysctl -p "$SYSCTL_FILE" >/dev/null
  fi
else
  yes "sysctl 已最新"
fi

# [6] BBR 验证
if [[ "$(sysctl -n net.ipv4.tcp_congestion_control)" == "bbr" ]]; then
  yes "BBR 已开"
else
  note "BBR 未开（步骤 [4] 重启网络 / 重启机器后生效）"
fi

# [7] sshd 强制 key（默认不动；需 --disable-password 且已有 authorized_keys 才关）
echo "  [7] sshd 关 PasswordAuthentication"
keys_found=0
for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
  [[ -s "$f" ]] && keys_found=$((keys_found + 1))
done
if [[ "$DISABLE_PASSWORD" != "1" ]]; then
  note "(skip) 默认保留密码登录；确认所有常用机器都配好 key 后再加 --disable-password"
elif [[ $keys_found -eq 0 ]]; then
  note "未检测到任何 authorized_keys，拒绝关密码（否则你会被锁死在 VNC 外）"
elif sshd -T 2>/dev/null | grep -qE "^passwordauthentication no$"; then
  yes "PasswordAuthentication 已 no"
else
  fix "写 /etc/ssh/sshd_config.d/00-ace-vpn-hardening.conf: PasswordAuthentication no"
  if [[ "$MODE" == "apply" ]]; then
    cat >/etc/ssh/sshd_config.d/00-ace-vpn-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin prohibit-password
EOF
    sshd -t && systemctl reload sshd
  fi
fi

# [8] ICMP echo（aggressive）
echo "  [8] ICMP echo（aggressive）"
if [[ "$AGGRESSIVE" == "1" ]]; then
  if [[ "$(sysctl -n net.ipv4.icmp_echo_ignore_all)" == "1" ]]; then
    yes "ICMP echo 已关"
  else
    fix "关 ICMP echo"
    if [[ "$MODE" == "apply" ]]; then
      echo 'net.ipv4.icmp_echo_ignore_all=1' >>"$SYSCTL_FILE"
      sysctl -w net.ipv4.icmp_echo_ignore_all=1 >/dev/null
    fi
  fi
else
  note "(skip) 加 --aggressive 才关 ICMP（关掉后你 ping IP 都不通）"
fi

# [A] 3x-ui 面板端口
echo "  [A] 3x-ui 面板检查"
if command -v x-ui >/dev/null && [[ -f /etc/x-ui/x-ui.db ]]; then
  panel_port=$(sqlite3 /etc/x-ui/x-ui.db "SELECT value FROM settings WHERE key='webPort'" 2>/dev/null || echo "?")
  panel_path=$(sqlite3 /etc/x-ui/x-ui.db "SELECT value FROM settings WHERE key='webBasePath'" 2>/dev/null || echo "?")
  panel_user=$(sqlite3 /etc/x-ui/x-ui.db "SELECT username FROM users LIMIT 1" 2>/dev/null || echo "?")

  if [[ "$panel_port" =~ ^[0-9]+$ ]] && (( panel_port >= 30000 )); then
    yes "面板端口 $panel_port ≥ 30000"
  else
    note "面板端口 $panel_port（< 30000，GFW / 扫描器更易发现，建议改高位随机）"
  fi
  # 面板路径：希望非默认 + 长度 >= 16
  pp_no_slash=$(echo "$panel_path" | tr -d '/')
  if [[ "$pp_no_slash" == "panel" || "$pp_no_slash" == "xui" || "$pp_no_slash" == "" ]]; then
    note "面板路径 '$panel_path' 是默认/空，必改！（面板设置 → web base path → /随机字符串/）"
  elif [[ ${#pp_no_slash} -lt 16 ]]; then
    note "面板路径长度 ${#pp_no_slash} 字符，< 16，建议改长（>=20 字符随机）"
  else
    yes "面板路径长度 ${#pp_no_slash} 字符"
  fi
  if [[ "$panel_user" == "admin" || -z "$panel_user" ]]; then
    note "面板用户名 '$panel_user' 是默认/空，必改"
  else
    yes "面板用户名已非默认"
  fi
else
  note "未检测到 3x-ui，跳过"
fi

# [C] Reality dest 检查
if [[ -f /etc/x-ui/x-ui.db ]]; then
  echo "  [C] Reality dest（应模仿真实大站）"
  dests=$(sqlite3 /etc/x-ui/x-ui.db \
    "SELECT json_extract(stream_settings,'\$.realitySettings.dest') FROM inbounds WHERE protocol='vless'" \
    2>/dev/null || true)
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    case "$d" in
      *microsoft*|*apple*|*cloudflare*|*amazon*|*windows*|*adobe*)
        yes "dest=$d"
        ;;
      *google*)
        note "dest=$d  → Google 域名被 GFW 重点监视，换成 www.microsoft.com:443"
        ;;
      *)
        note "dest=$d  → 建议改成 www.microsoft.com:443 / www.apple.com:443 等高曝光大站"
        ;;
    esac
  done <<< "$dests"
fi

echo
echo "  ${c_grn}该节点硬化完成${c_off}"
REMOTE_SCRIPT
}

declare -a OK_LIST FAIL_LIST
for entry in "${TARGETS[@]}"; do
  name="${entry%|*}"
  ip="${entry#*|}"
  if harden_one "$name" "$ip"; then
    OK_LIST+=("$entry")
  else
    FAIL_LIST+=("$entry")
  fi
done

hdr "汇总"
for t in "${OK_LIST[@]-}"; do
  [[ -n "$t" ]] && echo "  ${color_grn}✓${color_off} ${t%|*}  ${t#*|}"
done
for t in "${FAIL_LIST[@]-}"; do
  [[ -n "$t" ]] && echo "  ${color_red}✗${color_off} ${t%|*}  ${t#*|}"
done

cat <<EOF

${color_bld}硬化项之外，你还需要做${color_off}：

  ${color_bld}1. 客户端层${color_off}：把 ⚡ AUTO 节点组延迟测试间隔调到 5 分钟
     某台 VPS 被封 → AUTO 自动切到下一台，家人无感

  ${color_bld}2. 多 VPS 池${color_off}：尽快开第三家厂商（BuyVM LA / Velia DE / GreenCloud SG）
     当前 VPS_IP_LIST 里只有 ${#TARGETS[@]} 台，被同时封的概率 = 单点风险

  ${color_bld}3. 早期预警${color_off}：scripts/test/vps-watch-urls.sh 用 launchd 跑（每 5min）
     被封那一刻飞书 / Bark 推送，比家人吐槽早 30 分钟发现

  ${color_bld}4. 让 IP 不公开${color_off}：
     - 不要把 IP 写进任何公开仓库 / 微信群 / 推
     - 订阅 URL 只发给本人 + 家人，不要在多人群组
     - 给家人的 SubId 每月轮换一次

  ${color_bld}5. 进阶${color_off}：把订阅 URL 和 reality server 字段全部换成域名
     用 Cloudflare DNS 托管，被封时改 A 记录即可，客户端 0 改动
     （需要把 SERVER_OVERRIDE 改成域名 → reality 客户端能解析）
EOF
