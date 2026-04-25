#!/usr/bin/env bash
# ace-vpn · 分流链路诊断工具
#
# 用法：
#   bash scripts/test/test-route.sh <URL 或 host>
#
# 例：
#   bash scripts/test/test-route.sh https://portal.corp-a.example/       # 公司内网
#   bash scripts/test/test-route.sh claude.ai                            # 海外 AI
#   bash scripts/test/test-route.sh youtube.com                          # 海外视频
#   bash scripts/test/test-route.sh 10.0.0.53                            # 内网 IP
#
# 前置：
#   source private/env.sh       # 需要 $VPS_IP（或显式设 VPS_IP 环境变量）
#   Mihomo Party / Clash 已启动 System Proxy（127.0.0.1:7890）——[3/3] 实测需要
#
# 输出：
#   [1/3] 查服务端权威规则（/match）—— 命中哪条规则、目标代理组
#   [2/3] 查本地 DNS 解析结果
#   [3/3] 通过本机 Clash 代理发 HTTP 请求，打印各阶段耗时 + 出口 IP
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)

# 颜色
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
  YLW=$'\033[33m'; BLU=$'\033[34m'; CYN=$'\033[36m'; RST=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; BLU=""; CYN=""; RST=""
fi

die()  { echo "${RED}ERROR${RST} $*" >&2; exit 1; }
hdr()  { echo; echo "${BOLD}${CYN}━━━ $* ━━━${RST}"; }
kv()   { printf "  ${DIM}%-14s${RST} %s\n" "$1" "$2"; }
warn() { echo "  ${YLW}!${RST} $*"; }

# 自动 source private/env.sh
if [[ -z "${VPS_IP:-}" && -f "$ROOT_DIR/private/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/private/env.sh"
fi

[[ $# -ge 1 ]] || die "用法: $0 <URL 或 host>"
URL_ARG="$1"
: "${VPS_IP:?VPS_IP 未设置；先 source private/env.sh}"
SUB_PORT=${SUB_PORT_CLASH:-25500}
LOCAL_PROXY=${LOCAL_PROXY:-http://127.0.0.1:7890}

# ─────────────── 目标是什么 ───────────────
if [[ "$URL_ARG" == *://* ]]; then
  TEST_URL="$URL_ARG"
else
  TEST_URL="https://$URL_ARG"
fi
HOST=$(python3 -c "
import sys, urllib.parse
u = sys.argv[1]
if '://' not in u: u = 'http://' + u
p = urllib.parse.urlparse(u)
print(p.hostname or '')" "$TEST_URL")

echo
echo "${BOLD}ace-vpn · Route Tester${RST}  ${DIM}($TEST_URL)${RST}"
kv "Host"        "$HOST"
kv "VPS"         "$VPS_IP:$SUB_PORT"
kv "Local proxy" "$LOCAL_PROXY"

# ─────────────── [1/3] 查 /match（服务端权威） ───────────────
hdr "[1/3] 服务端规则匹配（/match 权威查询）"

URLENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$TEST_URL")
MATCH_URL="http://$VPS_IP:$SUB_PORT/match?url=$URLENC"

if ! MATCH_JSON=$(curl -fsS --max-time 8 "$MATCH_URL" 2>&1); then
  warn "调 /match 失败：$MATCH_JSON"
  warn "旧版 sub-converter 没有这个接口，先升级："
  echo "    scp scripts/server/sub-converter.py root@$VPS_IP:/opt/ace-vpn-sub/sub-converter.py"
  echo "    ssh root@$VPS_IP 'systemctl restart ace-vpn-sub'"
  MATCH_JSON=""
fi

TARGET=""
RULE=""
RULE_IDX=""
RESOLVED=""
ACTIVE_PROFILES=""
if [[ -n "$MATCH_JSON" ]]; then
  # 用 python 解析最稳
  eval "$(python3 - <<PY "$MATCH_JSON"
import json, sys, shlex
d = json.loads(sys.argv[1])
out = {
  "TARGET":          d.get("target") or "",
  "RULE":            d.get("rule") or "",
  "RULE_IDX":        str(d.get("rule_index") or 0),
  "RESOLVED":        d.get("resolved_ip") or "",
  "ACTIVE_PROFILES": ",".join(d.get("active_profiles") or []),
}
for k, v in out.items():
  print(f"{k}={shlex.quote(v)}")
PY
)"

  kv "命中规则"     "#$RULE_IDX  ${BOLD}$RULE${RST}"
  case "$TARGET" in
    DIRECT)    kv "目标组"      "${GRN}DIRECT${RST}（直连，不经 VPS）" ;;
    *AI*|*PROXY*|*MEDIA*|*FINAL*)
               kv "目标组"      "${BLU}$TARGET${RST}（经代理组）" ;;
    *)         kv "目标组"      "$TARGET" ;;
  esac
  [[ -n "$RESOLVED" ]]       && kv "服务端 DNS"   "$RESOLVED"
  [[ -n "$ACTIVE_PROFILES" ]] && kv "激活 profile" "$ACTIVE_PROFILES"
fi

# ─────────────── [2/3] 本地 DNS ───────────────
hdr "[2/3] 本机 DNS 解析（Mac 当前网络）"

if command -v dig >/dev/null 2>&1; then
  SYS_IP=$(dig +short +time=3 "$HOST" A 2>/dev/null | grep -E '^[0-9]' | head -1 || true)
else
  SYS_IP=$(python3 -c "import socket,sys;
try: print(socket.gethostbyname(sys.argv[1]))
except: pass" "$HOST" || true)
fi

if [[ -z "$SYS_IP" ]]; then
  kv "系统 DNS"    "${YLW}解析失败${RST}（外网 DNS 可能查不到内网域名，正常）"
elif [[ "$SYS_IP" == 198.18.* ]]; then
  kv "系统 DNS"    "$SYS_IP  ${DIM}(Clash fake-ip，真实 IP 在代理内部)${RST}"
else
  kv "系统 DNS"    "$SYS_IP"
fi

# ─────────────── [3/3] 代理实测 ───────────────
hdr "[3/3] 通过本机代理实测延时（$LOCAL_PROXY）"

# 先检查代理是否在跑
if ! curl -sS --max-time 2 -o /dev/null -x "$LOCAL_PROXY" "http://captive.apple.com/" 2>/dev/null; then
  warn "本机代理 $LOCAL_PROXY 不响应；跳过实测"
  warn "请确认 Mihomo Party / Clash Verge 已打开，且 System Proxy 端口 = 7890"
else
  WFMT='| DNS解析 %{time_namelookup}s | TCP连接 %{time_connect}s | TLS握手 %{time_appconnect}s | TTFB %{time_starttransfer}s | 总计 %{time_total}s | HTTP %{http_code} | 出口 %{remote_ip} |'
  TIMING=$(curl -sS -o /dev/null \
    --max-time 15 \
    -x "$LOCAL_PROXY" \
    -w "$WFMT" \
    "$TEST_URL" 2>&1 || echo "$WFMT (请求失败)")
  echo "  $TIMING" | sed "s/| /\n  ${DIM}  ${RST}/g" | head -20
  echo

  # 出口 IP（通过代理看到的自己是啥 IP）
  EXIT_IP=$(curl -fsS --max-time 5 -x "$LOCAL_PROXY" https://api.ipify.org 2>/dev/null || echo "")
  if [[ -n "$EXIT_IP" ]]; then
    kv "客户端出口 IP" "$EXIT_IP (这是 https://api.ipify.org 看到的你)"
  fi
fi

# ─────────────── 结论 ───────────────
hdr "结论"
case "$TARGET" in
  DIRECT)
    echo "  ${GRN}✓${RST} 规则决策 ${BOLD}DIRECT${RST}：流量走本机网络，不经过 VPS"
    echo "    → 如果是内网域名，本机能通 = 正常（需在公司网络 / 公司 VPN 下）"
    ;;
  *AI*)
    echo "  ${BLU}→${RST} 规则决策 ${BOLD}$TARGET${RST}：AI 类站点经 VPS 代理"
    ;;
  *PROXY*|*MEDIA*)
    echo "  ${BLU}→${RST} 规则决策 ${BOLD}$TARGET${RST}：经 VPS 代理"
    ;;
  *FINAL*)
    echo "  ${YLW}?${RST} 规则决策 ${BOLD}$TARGET${RST}：没匹到任何明确规则，走 FINAL（默认代理，可手动切直连）"
    ;;
  "")
    echo "  ${YLW}!${RST} 未拿到服务端决策；看 [2]/[3] 结果判断"
    ;;
  *)
    echo "  规则决策 ${BOLD}$TARGET${RST}"
    ;;
esac
echo
echo "  ${DIM}如果本地 Mihomo 的实际行为和服务端 /match 不一致，"
echo "  说明客户端订阅缓存旧，去 Profile 页点刷新即可。${RST}"
echo
