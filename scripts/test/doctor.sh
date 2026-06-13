#!/usr/bin/env bash
# ace-vpn · 一键体检（本机 + 订阅 + VPS 可达性）
#
# 目标：
#   1. 判断当前系统流量是否真的走 Mihomo TUN / VPS。
#   2. 判断显式 7890 代理是否可用。
#   3. 识别公司 VPN 与 Mihomo TUN 的全局路由冲突。
#   4. 在 SSH 可达时检查 VPS 暴露面和服务状态；SSH 不可达不视为致命。
#
# 用法：
#   bash scripts/test/doctor.sh
#   EXPECTED_IP=167.254.242.54 bash scripts/test/doctor.sh
set +e

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
  YLW=$'\033[33m'; CYN=$'\033[36m'; RST=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; CYN=""; RST=""
fi

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PARTY_DIR="${MIHOMO_PARTY_DIR:-$HOME/Library/Application Support/mihomo-party}"
PROFILE_FILE="$PARTY_DIR/profile.yaml"
MIHOMO_FILE="$PARTY_DIR/mihomo.yaml"
WORK_FILE="$PARTY_DIR/work/config.yaml"
PROXY="${LOCAL_PROXY:-http://127.0.0.1:7890}"

if [[ -f "$ROOT_DIR/private/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/private/env.sh"
fi

hdr() { echo; echo "${BOLD}${CYN}━━ $* ━━${RST}"; }
ok() { echo "  ${GRN}✓${RST} $*"; }
warn() { echo "  ${YLW}!${RST} $*"; }
bad() { echo "  ${RED}✗${RST} $*"; }
kv() { printf "  ${DIM}%-22s${RST} %s\n" "$1" "$2"; }

json_get() {
  local key=$1
  python3 -c "import sys,json
try:
    d=json.load(sys.stdin)
    v=d
    for k in '$key'.split('.'):
        v=v.get(k) if isinstance(v, dict) else None
    print('' if v is None else v)
except Exception:
    print('')" 2>/dev/null
}

cf_trace() {
  local args=("$@")
  curl -4 -sS --max-time 12 "${args[@]}" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null
}

trace_ip() { awk -F= '/^ip=/ {print $2}' <<<"$1"; }
trace_loc() { awk -F= '/^loc=/ {print $2}' <<<"$1"; }
trace_colo() { awk -F= '/^colo=/ {print $2}' <<<"$1"; }

current_profile_url() {
  python3 - "$PROFILE_FILE" <<'PY' 2>/dev/null
import sys, yaml
fn=sys.argv[1]
d=yaml.safe_load(open(fn)) or {}
cur=d.get("current")
for item in d.get("items") or []:
    if item.get("id")==cur:
        print(item.get("url",""))
        break
PY
}

extract_ip_from_url() {
  python3 - "$1" <<'PY' 2>/dev/null
import sys, urllib.parse
u=urllib.parse.urlparse(sys.argv[1].strip())
print(u.hostname or "")
PY
}

extract_prefix_from_url() {
  python3 - "$1" <<'PY' 2>/dev/null
import sys, urllib.parse
u=urllib.parse.urlparse(sys.argv[1].strip())
parts=[p for p in u.path.split("/") if p]
print(parts[0] if parts else "")
PY
}

EXPECTED_IP="${EXPECTED_IP:-}"
PROFILE_URL=$(current_profile_url)
PROFILE_HOST=""
PROFILE_PREFIX=""
if [[ -n "$PROFILE_URL" ]]; then
  PROFILE_HOST=$(extract_ip_from_url "$PROFILE_URL")
  PROFILE_PREFIX=$(extract_prefix_from_url "$PROFILE_URL")
fi
if [[ -z "$EXPECTED_IP" && -n "${VPS_IP_LIST:-}" ]]; then
  first=${VPS_IP_LIST%% *}
  EXPECTED_IP=${first##*:}
fi
if [[ -z "$EXPECTED_IP" && -n "$PROFILE_URL" ]]; then
  EXPECTED_IP="$PROFILE_HOST"
fi

echo "${BOLD}ace-vpn doctor${RST}"
date '+  时间: %Y-%m-%d %H:%M:%S'
kv "期望 VPS IP" "${EXPECTED_IP:-未知}"
kv "当前订阅 URL" "${PROFILE_URL:-未知}"
kv "当前订阅 host" "${PROFILE_HOST:-未知}"
kv "当前订阅 prefix" "${PROFILE_PREFIX:-未知}"

hdr "1. Mihomo Party / 运行配置"
SECRET=""
[[ -f "$MIHOMO_FILE" ]] && SECRET=$(awk '/^secret:/ {gsub(/"/,"",$2); print $2}' "$MIHOMO_FILE")
API_JSON=""
if [[ -n "$SECRET" ]]; then
  API_JSON=$(curl -sS --max-time 5 -H "Authorization: Bearer $SECRET" http://127.0.0.1:9090/configs 2>/dev/null)
else
  API_JSON=$(curl -sS --max-time 5 http://127.0.0.1:9090/configs 2>/dev/null)
fi
if [[ -n "$API_JSON" ]]; then
  ok "external-controller 可用"
  kv "mode" "$(json_get mode <<<"$API_JSON")"
  kv "ipv6" "$(json_get ipv6 <<<"$API_JSON")"
  kv "tun.enable" "$(json_get tun.enable <<<"$API_JSON")"
  kv "tun.dns-hijack" "$(json_get tun.dns-hijack <<<"$API_JSON")"
else
  bad "external-controller 不可用；只能做黑盒网络检查"
fi

if [[ -f "$WORK_FILE" ]]; then
  work_tun=$(awk '/^tun:/{f=1} f && /enable:/{print $2; exit}' "$WORK_FILE")
  kv "work tun.enable" "${work_tun:-未知}"
fi

hdr "2. 出口与泄漏"
SYS_TRACE=$(cf_trace)
PROXY_TRACE=$(cf_trace -x "$PROXY")
SYS_IP=$(trace_ip "$SYS_TRACE"); SYS_LOC=$(trace_loc "$SYS_TRACE"); SYS_COLO=$(trace_colo "$SYS_TRACE")
PROXY_IP=$(trace_ip "$PROXY_TRACE"); PROXY_LOC=$(trace_loc "$PROXY_TRACE"); PROXY_COLO=$(trace_colo "$PROXY_TRACE")
kv "系统/TUN 出口" "${SYS_IP:-?} ${SYS_LOC:+loc=$SYS_LOC} ${SYS_COLO:+colo=$SYS_COLO}"
kv "显式 7890 出口" "${PROXY_IP:-?} ${PROXY_LOC:+loc=$PROXY_LOC} ${PROXY_COLO:+colo=$PROXY_COLO}"

if [[ -n "$EXPECTED_IP" && "$SYS_IP" == "$EXPECTED_IP" ]]; then
  ok "系统流量已走 VPS"
elif [[ -n "$EXPECTED_IP" && "$PROXY_IP" == "$EXPECTED_IP" ]]; then
  warn "显式 7890 走 VPS，但系统/TUN 没走 VPS。若公司 VPN 开着，这是预期冲突。"
else
  warn "系统和 7890 都未确认走期望 VPS；若公司 VPN 开着，优先看第 3 节路由冲突。"
fi

hdr "3. 公司 VPN / TUN 路由冲突"
route_1=$(route -n get 1.1.1.1 2>/dev/null)
iface_1=$(awk '/interface:/{print $2; exit}' <<<"$route_1")
dest_1=$(awk '/destination:/{print $2; exit}' <<<"$route_1")
kv "1.1.1.1 路由" "dest=${dest_1:-?} iface=${iface_1:-?}"
if [[ "$iface_1" == utun* && "$SYS_IP" != "$EXPECTED_IP" ]]; then
  warn "检测到其他 VPN/TUN 已占全局路由。Mihomo TUN 可能无法与它共存。"
  echo "  建议：公司 VPN 开着时，用显式 7890；要系统全局走 VPS，先关公司 VPN 再重启 Party。"
fi

hdr "4. 订阅服务"
if [[ -n "$PROFILE_URL" ]]; then
  if [[ -n "$EXPECTED_IP" && -n "$PROFILE_HOST" && "$PROFILE_HOST" != "$EXPECTED_IP" ]]; then
    warn "当前 Mihomo Party 订阅指向 $PROFILE_HOST，但 private/env.sh 首选 VPS 是 $EXPECTED_IP。"
    echo "  这通常发生在换 IP / 换主 VPS 后，本机 profile 还停在旧订阅。"
    echo "  可用 SSH 冷启动同步：bash scripts/common-tools/bootstrap-mihomo-party.sh --replace-current"
  fi
  sub_code=$(curl -sS --max-time 10 -o /tmp/ace-vpn-doctor-sub.yaml -w "%{http_code}" "$PROFILE_URL" 2>/dev/null)
  kv "订阅 HTTP" "$sub_code"
  if [[ "$sub_code" == "200" ]]; then
    sub_server=$(awk '/^[[:space:]]*server:/ {print $2; exit}' /tmp/ace-vpn-doctor-sub.yaml)
    sub_tun=$(awk '/^tun:/{f=1} f && /enable:/{print $2; exit}' /tmp/ace-vpn-doctor-sub.yaml)
    ok "订阅可拉取"
    kv "订阅 server" "$sub_server"
    kv "订阅 tun.enable" "$sub_tun"
  else
    warn "订阅不可拉取；若公司 VPN 阻断到 VPS，这是预期。"
  fi
else
  warn "找不到当前订阅 URL"
fi
rm -f /tmp/ace-vpn-doctor-sub.yaml

hdr "5. VPS 安全面（SSH 可达时）"
if [[ -n "$EXPECTED_IP" ]]; then
  SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)
  if [[ -n "${VPS_SSH_KEY:-}" ]]; then
    key=${VPS_SSH_KEY/#~/$HOME}
    [[ -f "$key" ]] && SSH_OPTS+=(-i "$key")
  fi
  ssh_check=$(ssh "${SSH_OPTS[@]}" "${VPS_SSH_USER:-root}@$EXPECTED_IP" 'echo OK' 2>&1 || true)
  if grep -q '^OK$' <<<"$ssh_check"; then
    ok "SSH key 可达"
    ssh "${SSH_OPTS[@]}" "${VPS_SSH_USER:-root}@$EXPECTED_IP" 'bash -s' <<'REMOTE'
echo "  服务: x-ui=$(systemctl is-active x-ui 2>/dev/null) ace-vpn-sub=$(systemctl is-active ace-vpn-sub 2>/dev/null) fail2ban=$(systemctl is-active fail2ban 2>/dev/null)"
echo "  监听:"
ss -tlnp | grep -E ":22|:443|:25500|:14285|:2096" | awk "{print \"    \" \$4}"
echo "  防火墙:"
ufw status | grep -E "22/tcp|443/tcp|25500/tcp|80/tcp|25/tcp|465/tcp|587/tcp" | sed "s/^/    /"
echo "  IPv6: $(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)"
sshd -T 2>/dev/null | awk '
  /^passwordauthentication / { print "  SSH 密码登录: " $2 }
  /^permitrootlogin / { print "  SSH root 登录: " $2 }
'
REMOTE
  else
    if grep -q 'REMOTE HOST IDENTIFICATION HAS CHANGED' <<<"$ssh_check"; then
      warn "SSH host key 冲突：known_hosts 里记录的 $EXPECTED_IP 旧指纹与当前 VPS 不一致。"
      echo "  先确认 $EXPECTED_IP 确实是你的 VPS，再运行：ssh-keygen -R $EXPECTED_IP"
    elif grep -qiE 'Permission denied|publickey|password' <<<"$ssh_check"; then
      warn "SSH 登录被拒：当前本机公钥没有被 $EXPECTED_IP 授权。"
      key_hint="${VPS_SSH_KEY:-$HOME/.ssh/id_ed25519}"
      key_hint="${key_hint/#~/$HOME}"
      echo "  若你有 root 密码，运行：ssh-copy-id -i ${key_hint}.pub ${VPS_SSH_USER:-root}@$EXPECTED_IP"
      echo "  或运行冷启动脚本交互安装 key：bash scripts/common-tools/bootstrap-mihomo-party.sh --install-ssh-key --replace-current"
    else
      warn "SSH 不可达；若公司 VPN 开着，这是预期，不代表 VPS 坏。"
    fi
  fi
fi

hdr "6. 建议"
if [[ -n "$EXPECTED_IP" && "$SYS_IP" != "$EXPECTED_IP" && "$PROXY_IP" == "$EXPECTED_IP" ]]; then
  echo "  - 当前建议模式：公司 VPN 开着 → 使用显式 7890；不要依赖 Mihomo TUN。"
fi
echo "  - 若要系统全局走 VPS：关闭公司 VPN，重启 Clash Party，再重跑 doctor。"
echo "  - 若要降低订阅暴露面：后续把 SUB_PATH_PREFIX 切成长随机路径，并同步更新家人订阅 URL。"
