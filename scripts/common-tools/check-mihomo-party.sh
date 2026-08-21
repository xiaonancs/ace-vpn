#!/usr/bin/env bash
# ace-vpn · local Mihomo/Clash Party health check and stale-core cleanup.
#
# Usage:
#   bash scripts/common-tools/check-mihomo-party.sh
#   bash scripts/common-tools/check-mihomo-party.sh --fix
#   bash scripts/common-tools/check-mihomo-party.sh --domain dt.mi.com
set +e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)

PARTY_DIR="${MIHOMO_PARTY_DIR:-$HOME/Library/Application Support/mihomo-party}"
PROFILE_YAML="$PARTY_DIR/profile.yaml"
PROFILES_DIR="$PARTY_DIR/profiles"
BASE_CFG="$PARTY_DIR/mihomo.yaml"
WORK_CFG="$PARTY_DIR/work/config.yaml"
WORK_DIR="$PARTY_DIR/work"
PROXY="${LOCAL_PROXY:-http://127.0.0.1:7890}"
CONTROLLER="${MIHOMO_CONTROLLER:-http://127.0.0.1:9090}"
FIX=0
REOPEN=0
DOMAINS=("dt.mi.com" "mi-dun.com" "llm.mioffice.cn" "api.llm.mioffice.cn" "cas.mioffice.cn" "p.dun.mioffice.cn")

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
  YLW=$'\033[33m'; CYN=$'\033[36m'; RST=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; CYN=""; RST=""
fi

usage() {
  sed -n '2,/^set +e/p' "$0" | sed -n '/^#/p' | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Options:
  --fix              Quit Clash Party, kill stale mihomo/helper processes,
                     remove stale sockets/cache, and fix work dir ownership.
                     Requires sudo for root-owned processes/cache.
  --reopen           Reopen Clash Party after --fix.
  --domain host      Add an extra host to check in local config and proxy curl.
  --party-dir path   Override Mihomo Party config dir.
  --proxy url        Override local proxy. Default: http://127.0.0.1:7890
  -h, --help         Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix) FIX=1; shift ;;
    --reopen) REOPEN=1; shift ;;
    --domain) DOMAINS+=("$2"); shift 2 ;;
    --domain=*) DOMAINS+=("${1#*=}"); shift ;;
    --party-dir) PARTY_DIR="$2"; PROFILE_YAML="$PARTY_DIR/profile.yaml"; PROFILES_DIR="$PARTY_DIR/profiles"; BASE_CFG="$PARTY_DIR/mihomo.yaml"; WORK_CFG="$PARTY_DIR/work/config.yaml"; WORK_DIR="$PARTY_DIR/work"; shift 2 ;;
    --party-dir=*) PARTY_DIR="${1#*=}"; PROFILE_YAML="$PARTY_DIR/profile.yaml"; PROFILES_DIR="$PARTY_DIR/profiles"; BASE_CFG="$PARTY_DIR/mihomo.yaml"; WORK_CFG="$PARTY_DIR/work/config.yaml"; WORK_DIR="$PARTY_DIR/work"; shift ;;
    --proxy) PROXY="$2"; shift 2 ;;
    --proxy=*) PROXY="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

hdr() { printf '\n%s%s━━ %s ━━%s\n' "$BOLD" "$CYN" "$*" "$RST"; }
ok() { printf '  %s✓%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '  %s!%s %s\n' "$YLW" "$RST" "$*"; }
bad() { printf '  %s✗%s %s\n' "$RED" "$RST" "$*"; }
kv() { printf '  %s%-22s%s %s\n' "$DIM" "$1" "$RST" "$2"; }

have() {
  command -v "$1" >/dev/null 2>&1
}

dedupe_domains() {
  printf '%s\n' "${DOMAINS[@]}" | awk 'NF && !seen[$0]++'
}

mihomo_rows() {
  ps ax -o pid= -o user= -o command= | awk '/[s]idecar\/mihomo/ && /mihomo-party/ {print}'
}

helper_rows() {
  ps ax -o pid= -o user= -o command= | awk '/[p]arty\.mihomo\.helper/ {print}'
}

current_profile_url() {
  [[ -f "$PROFILE_YAML" ]] || return 0
  python3 - "$PROFILE_YAML" <<'PY' 2>/dev/null
import sys
try:
    import yaml
    data = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    data = {}
cur = data.get("current")
for item in data.get("items") or []:
    if item.get("id") == cur:
        print(item.get("url") or "")
        break
PY
}

active_profile_id() {
  [[ -f "$PROFILE_YAML" ]] || return 0
  python3 - "$PROFILE_YAML" <<'PY' 2>/dev/null
import sys
try:
    import yaml
    data = yaml.safe_load(open(sys.argv[1])) or {}
    print(data.get("current") or "")
except Exception:
    pass
PY
}

profile_host() {
  python3 - "$1" <<'PY' 2>/dev/null
import sys, urllib.parse
u = urllib.parse.urlparse(sys.argv[1].strip())
print(u.hostname or "")
PY
}

secret_from_config() {
  for file in "$BASE_CFG" "$WORK_CFG"; do
    [[ -f "$file" ]] || continue
    awk -F: '/^secret:/ {
      v=$2
      sub(/^[[:space:]]+/, "", v)
      gsub(/"/, "", v)
      print v
      exit
    }' "$file"
    return 0
  done
}

curl_controller() {
  local secret=$1
  if [[ -n "$secret" ]]; then
    curl -sS --max-time 4 -H "Authorization: Bearer $secret" "$CONTROLLER/configs" 2>/dev/null
  else
    curl -sS --max-time 4 "$CONTROLLER/configs" 2>/dev/null
  fi
}

check_ports() {
  local port
  for port in 7890 7891 7892 9090 1053; do
    if have lsof; then
      local out
      out=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | tail -n +2)
      if [[ -n "$out" ]]; then
        kv "tcp:$port" "$(awk '{print $1"/"$2"/"$3}' <<<"$out" | paste -sd ', ' -)"
      fi
      if [[ "$port" == "1053" ]]; then
        out=$(lsof -nP -iUDP:"$port" 2>/dev/null | tail -n +2)
        [[ -n "$out" ]] && kv "udp:$port" "$(awk '{print $1"/"$2"/"$3}' <<<"$out" | paste -sd ', ' -)"
      fi
    fi
  done
}

file_owner_line() {
  local file=$1
  [[ -e "$file" ]] || return 0
  if stat -f '%Su:%Sg %Sp %N' "$file" >/dev/null 2>&1; then
    stat -f '%Su:%Sg %Sp %N' "$file"
  else
    stat -c '%U:%G %A %n' "$file" 2>/dev/null
  fi
}

grep_domain_local() {
  local domain=$1
  local paths=()
  [[ -d "$PROFILES_DIR" ]] && paths+=("$PROFILES_DIR")
  [[ -f "$WORK_CFG" ]] && paths+=("$WORK_CFG")
  [[ ${#paths[@]} -gt 0 ]] || return 1
  grep -Rni -- "$domain" "${paths[@]}" 2>/dev/null | head -5
}

grep_domain_remote() {
  local domain=$1
  local file=$2
  grep -ni -- "$domain" "$file" 2>/dev/null | head -5
}

domain_parent_cover() {
  local domain=$1
  case "$domain" in
    *.mioffice.cn) printf '%s\n' "mioffice.cn" ;;
    *) return 1 ;;
  esac
}

grep_domain_local_cover() {
  local domain=$1
  local parent hits
  hits=$(grep_domain_local "$domain")
  if [[ -n "$hits" ]]; then
    printf '%s\n' "$hits"
    return 0
  fi
  parent=$(domain_parent_cover "$domain" || true)
  [[ -n "$parent" ]] || return 1
  hits=$(grep_domain_local "$parent")
  [[ -n "$hits" ]] || return 1
  printf '%s\n' "$hits"
}

grep_domain_remote_cover() {
  local domain=$1
  local file=$2
  local parent hits
  hits=$(grep_domain_remote "$domain" "$file")
  if [[ -n "$hits" ]]; then
    printf '%s\n' "$hits"
    return 0
  fi
  parent=$(domain_parent_cover "$domain" || true)
  [[ -n "$parent" ]] || return 1
  hits=$(grep_domain_remote "$parent" "$file")
  [[ -n "$hits" ]] || return 1
  printf '%s\n' "$hits"
}

proxy_head() {
  local url=$1
  curl -k -x "$PROXY" -I --connect-timeout 8 --max-time 16 "$url" 2>&1
}

run_fix() {
  hdr "Fix"
  warn "将退出 Clash Party、清理 mihomo core/socket/cache，并修复 $WORK_DIR 所有权。"
  osascript -e 'tell application "Clash Party" to quit' >/dev/null 2>&1
  osascript -e 'tell application "Mihomo Party" to quit' >/dev/null 2>&1
  sleep 2

  sudo pkill -f "/Applications/Clash Party.app/Contents/Resources/sidecar/mihomo"
  sudo pkill -f "/Applications/Mihomo Party.app/Contents/Resources/sidecar/mihomo"
  sudo pkill -f "party.mihomo.helper"
  rm -f /tmp/mihomo-party-"$(id -u)"-*.sock
  sudo rm -f "$WORK_DIR/cache.db"
  sudo chown -R "$USER":staff "$WORK_DIR"
  ok "清理完成"

  if [[ "$REOPEN" -eq 1 ]]; then
    open -a "Clash Party" >/dev/null 2>&1 || open -a "Mihomo Party" >/dev/null 2>&1
    ok "已尝试重新打开 Clash/Mihomo Party"
  else
    warn "现在手动重新打开 Clash Party，然后刷新订阅。"
  fi
}

if [[ "$FIX" -eq 1 ]]; then
  run_fix
fi

echo "${BOLD}ace-vpn local Mihomo Party check${RST}"
date '+  time: %Y-%m-%d %H:%M:%S %z'
kv "party dir" "$PARTY_DIR"
kv "proxy" "$PROXY"

hdr "1. Process"
core_rows=$(mihomo_rows)
core_count=$(printf '%s\n' "$core_rows" | awk 'NF {n++} END {print n+0}')
helper_rows_out=$(helper_rows)
helper_count=$(printf '%s\n' "$helper_rows_out" | awk 'NF {n++} END {print n+0}')
kv "mihomo core count" "$core_count"
[[ -n "$core_rows" ]] && printf '%s\n' "$core_rows" | sed 's/^/    /'
kv "helper count" "$helper_count"
[[ -n "$helper_rows_out" ]] && printf '%s\n' "$helper_rows_out" | sed 's/^/    /'

if [[ "$core_count" -eq 1 ]]; then
  ok "mihomo core 数量正常"
elif [[ "$core_count" -eq 0 ]]; then
  warn "未检测到 mihomo core；Clash Party 可能未启动或 core 已退出"
else
  bad "检测到多个 mihomo core；这会导致端口/TUN/cache 互相抢占"
  echo "  修复：bash scripts/ace-vpn.sh party --fix"
fi

hdr "2. Ports / Cache"
check_ports
cache_owner=$(file_owner_line "$WORK_DIR/cache.db")
work_owner=$(file_owner_line "$WORK_DIR")
kv "work owner" "${work_owner:-missing}"
kv "cache owner" "${cache_owner:-missing}"
if [[ "$cache_owner" == root:* || "$work_owner" == root:* ]]; then
  bad "work/cache 由 root 拥有，普通用户刷新配置可能失败"
  echo "  修复：bash scripts/ace-vpn.sh party --fix"
else
  ok "work/cache 所有权看起来正常"
fi

hdr "3. Active Profile"
profile_id=$(active_profile_id)
profile_url=$(current_profile_url)
kv "profile id" "${profile_id:-unknown}"
kv "profile url" "${profile_url:-unknown}"
[[ -n "$profile_url" ]] && kv "profile host" "$(profile_host "$profile_url")"

if [[ -n "$profile_url" ]]; then
  tmp_sub=$(mktemp /tmp/ace-vpn-party-sub.XXXXXX.yaml)
  code=$(curl -sS --max-time 10 -o "$tmp_sub" -w "%{http_code}" "$profile_url" 2>/dev/null)
  kv "remote sub http" "$code"
  if [[ "$code" == "200" ]]; then
    ok "远端订阅可直连拉取"
    for domain in $(dedupe_domains); do
      if grep_domain_remote_cover "$domain" "$tmp_sub" >/dev/null; then
        ok "remote subscription contains $domain"
      else
        warn "remote subscription missing $domain"
      fi
    done
  else
    warn "远端订阅直连拉取失败；若当前网络被公司 VPN 限制，可用 bootstrap 脚本通过 SSH 冷启动"
  fi
  rm -f "$tmp_sub"
else
  warn "找不到当前订阅 URL"
fi

hdr "4. Local Config Domains"
for domain in $(dedupe_domains); do
  hits=$(grep_domain_local_cover "$domain")
  if [[ -n "$hits" ]]; then
    ok "local config contains $domain"
    printf '%s\n' "$hits" | sed 's/^/    /'
  else
    bad "local config missing $domain"
    echo "  处理：先运行 --fix 清理旧 core/cache，再重新打开 Clash Party 并刷新订阅"
  fi
done

hdr "5. Controller / Proxy Smoke"
secret=$(secret_from_config)
api_json=$(curl_controller "$secret")
if [[ -n "$api_json" ]]; then
  ok "external-controller reachable at $CONTROLLER"
  mode=$(python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("mode",""))' <<<"$api_json" 2>/dev/null)
  tun=$(python3 -c 'import sys,json; d=json.load(sys.stdin); print(((d.get("tun") or {}).get("enable","")))' <<<"$api_json" 2>/dev/null)
  kv "mode" "${mode:-unknown}"
  kv "tun.enable" "${tun:-unknown}"
else
  warn "external-controller 不可达；如果端口被旧 core 占用，先跑 --fix"
fi

for domain in $(dedupe_domains); do
  url="https://$domain/"
  [[ "$domain" == "dt.mi.com" ]] && url="https://dt.mi.com/shared-libs-react-18/index.js"
  out=$(proxy_head "$url")
  curl_rc=$?
  status=$(awk '/^HTTP\// && $0 !~ /Connection established/ {last=$0} END {print last}' <<<"$out")
  if [[ "$curl_rc" -eq 0 && "$status" =~ HTTP/[0-9.]+[[:space:]]+[234][0-9][0-9] ]]; then
    ok "proxy curl $domain: $status"
  else
    bad "proxy curl $domain failed"
    printf '%s\n' "$out" | tail -8 | sed 's/^/    /'
  fi
done

hdr "6. Next Actions"
if [[ "$core_count" -gt 1 || "$cache_owner" == root:* || "$work_owner" == root:* ]]; then
  echo "  1. bash scripts/ace-vpn.sh party --fix"
  echo "  2. 重新打开 Clash Party，刷新订阅"
  echo "  3. bash scripts/ace-vpn.sh party"
elif grep_domain_local_cover "dt.mi.com" >/dev/null; then
  echo "  - 本地关键域名已存在；若网页仍空白，清理浏览器站点缓存后重试。"
else
  echo "  1. 在 Clash Party 里刷新当前订阅"
  echo "  2. 若刷新后仍缺域名，先跑：bash scripts/ace-vpn.sh party --fix"
  echo "  3. 重新打开 Clash Party，刷新订阅，再运行：bash scripts/ace-vpn.sh party"
fi
