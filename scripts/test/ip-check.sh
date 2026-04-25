#!/usr/bin/env bash
# ace-vpn · 出口 IP 国家身份 + AI 服务可达性诊断
#
# 解决问题：
#   "YouTube 能开但 Gemini / Cursor / ChatGPT / Claude 用不了"
#   "提示 'not supported in your country'"
#   "Cursor 报海外 IP 检测失败"
#
# 这种情况绝大多数是 VPS 出口 IP 被相关服务标成了：
#   1. 不支持的国家（HK / CN / RU 等）          → 换节点
#   2. datacenter ASN 风控                     → 大概率全网 datacenter IP 都被屏，需要换"住宅 IP"或加 warp
#   3. CF 边缘节点拿到的国家跟 IP 数据库国家不一致 → 看具体哪个服务用哪个数据源
#
# 用法：
#   bash scripts/test/ip-check.sh                    # 测当前 Mihomo Party 选中节点的出口
#   bash scripts/test/ip-check.sh --no-proxy         # 测裸机出口（不走代理）
#   bash scripts/test/ip-check.sh --proxy 127.0.0.1:7890   # 显式指定代理
#
# 流程：
#   [1] 拿当前出口 IP（curl ifconfig.me）
#   [2] 多源查 IP 国家归属（ipinfo / ipapi / ifconfig.co / cloudflare-trace）
#   [3] Google / OpenAI / Anthropic 各自看到的国家（CF / 服务端 header）
#   [4] 关键 AI 服务实测：HTTP 状态 + 是否被国家屏蔽
#   [5] 综合判定 + 建议
set -euo pipefail

# ─────────────────────────────────────────────────────────────────
# 颜色 / 输出 helper
# ─────────────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
  YLW=$'\033[33m'; BLU=$'\033[34m'; CYN=$'\033[36m'; RST=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; BLU=""; CYN=""; RST=""
fi

die()  { echo "${RED}ERROR${RST} $*" >&2; exit 1; }
hdr()  { echo; echo "${BOLD}${CYN}━━━ $* ━━━${RST}"; }
kv()   { printf "  ${DIM}%-22s${RST} %s\n" "$1" "$2"; }
ok()   { echo "  ${GRN}✓${RST} $*"; }
no()   { echo "  ${RED}✗${RST} $*"; }
warn() { echo "  ${YLW}!${RST} $*"; }

# ─────────────────────────────────────────────────────────────────
# 解析参数
# ─────────────────────────────────────────────────────────────────

PROXY="${LOCAL_PROXY:-http://127.0.0.1:7890}"
USE_PROXY=1
case "${1:-}" in
  --no-proxy) USE_PROXY=0 ;;
  --proxy)    PROXY="$2"; [[ "$PROXY" != http* ]] && PROXY="http://$PROXY" ;;
  --proxy=*)  PROXY="${1#--proxy=}"; [[ "$PROXY" != http* ]] && PROXY="http://$PROXY" ;;
  -h|--help)  grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
  "") ;;
  *)  die "未知参数：$1（--help 看用法）" ;;
esac

CURL_OPTS=(--max-time 8 --connect-timeout 5 -sS)
if [[ $USE_PROXY -eq 1 ]]; then
  CURL_OPTS+=(--proxy "$PROXY")
  PROXY_LABEL="走代理 $PROXY"
else
  PROXY_LABEL="${YLW}不走代理（裸机出口）${RST}"
fi

# 让 curl 容错：失败返回空串而不是 set -e 中断
fetch() { curl "${CURL_OPTS[@]}" "$@" 2>/dev/null || true; }

# 提取 JSON 字段（不依赖 jq）
jget() {
  local key=$1 json=$2
  echo "$json" | python3 -c "import sys, json
try:
    d = json.load(sys.stdin)
    v = d
    for k in '$key'.split('.'):
        v = v.get(k) if isinstance(v, dict) else None
        if v is None: break
    print(v if v is not None else '')
except Exception:
    print('')
" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────
# 0. 前置探测
# ─────────────────────────────────────────────────────────────────

hdr "0. 探测代理"

if [[ $USE_PROXY -eq 1 ]]; then
  proxy_host=${PROXY#http://}; proxy_host=${proxy_host%/}
  if ! curl --max-time 2 -sS --proxy "$PROXY" -o /dev/null http://127.0.0.1:7890 2>/dev/null \
      && ! nc -z "${proxy_host%:*}" "${proxy_host##*:}" 2>/dev/null; then
    warn "代理 $PROXY 不通；改用 --no-proxy 重跑可测裸机出口"
  fi
fi
kv "代理状态" "$PROXY_LABEL"

# ─────────────────────────────────────────────────────────────────
# 1. 当前出口 IP
# ─────────────────────────────────────────────────────────────────

hdr "1. 当前出口 IP"

# 多源对照（防止单一服务挂掉）
EXIT_IP=""
for src in "https://ifconfig.me/ip" "https://ipinfo.io/ip" "https://api.ipify.org" "https://icanhazip.com"; do
  ip=$(fetch "$src" | tr -d '[:space:]')
  if [[ -n "$ip" && "$ip" =~ ^[0-9a-fA-F.:]+$ ]]; then
    [[ -z "$EXIT_IP" ]] && EXIT_IP="$ip"
    kv "via $(echo "$src" | awk -F/ '{print $3}')" "$ip"
  fi
done

if [[ -z "$EXIT_IP" ]]; then
  die "完全拿不到出口 IP；要么代理不通，要么这些公网服务都被墙"
fi

# ─────────────────────────────────────────────────────────────────
# 2. IP 国家归属（多源）
# ─────────────────────────────────────────────────────────────────

hdr "2. IP 在各数据源里的国家归属"

# 2.1 ipinfo.io —— 公认最权威的 IP 注册库（含 ASN / org）
info=$(fetch "https://ipinfo.io/${EXIT_IP}/json")
IPINFO_COUNTRY=$(jget country "$info")
IPINFO_REGION=$(jget region "$info")
IPINFO_CITY=$(jget city "$info")
IPINFO_ORG=$(jget org "$info")
kv "ipinfo.io 国家"   "${IPINFO_COUNTRY:-?}  ${IPINFO_CITY:-} ${IPINFO_REGION:+(}${IPINFO_REGION:-}${IPINFO_REGION:+)}"
kv "ipinfo.io ASN"    "${IPINFO_ORG:-?}"

# 2.2 ipapi.co
info2=$(fetch "https://ipapi.co/${EXIT_IP}/json/")
IPAPI_COUNTRY=$(jget country_code "$info2")
IPAPI_ORG=$(jget org "$info2")
kv "ipapi.co 国家"    "${IPAPI_COUNTRY:-?}"
kv "ipapi.co ASN"     "${IPAPI_ORG:-?}"

# 2.3 ifconfig.co
info3=$(fetch "https://ifconfig.co/json")
IFCO_COUNTRY=$(jget country_iso "$info3")
kv "ifconfig.co 国家" "${IFCO_COUNTRY:-?}"

# 2.4 Cloudflare 边缘节点角度（很多服务用 CF 做地理判定，这个值最关键）
cf_trace=$(fetch "https://www.cloudflare.com/cdn-cgi/trace")
CF_LOC=$(echo "$cf_trace" | awk -F= '/^loc=/ {print $2}')
CF_COLO=$(echo "$cf_trace" | awk -F= '/^colo=/ {print $2}')
kv "Cloudflare loc"   "${CF_LOC:-?}  (边缘 colo: ${CF_COLO:-?})"

# 2.5 一致性检查
declare -a all_countries=("$IPINFO_COUNTRY" "$IPAPI_COUNTRY" "$IFCO_COUNTRY" "$CF_LOC")
unique_countries=$(printf "%s\n" "${all_countries[@]}" | grep -v '^$' | sort -u | tr '\n' ' ')
country_count=$(echo "$unique_countries" | wc -w | tr -d ' ')

if [[ "$country_count" -eq 1 ]]; then
  ok "四个数据源国家一致：${BOLD}${unique_countries% }${RST}"
elif [[ "$country_count" -ge 2 ]]; then
  warn "数据源国家不一致：$unique_countries"
  echo "      → 大多数服务以 ipinfo (${IPINFO_COUNTRY:-?}) 为准；CF 路线判定用 CF (${CF_LOC:-?})"
fi

# ─────────────────────────────────────────────────────────────────
# 3. ASN / hosting 性质（IP 是不是被识别为机房 IP / VPN）
# ─────────────────────────────────────────────────────────────────

hdr "3. IP 性质（住宅 IP vs 机房 IP / VPN）"

# 简单规则：org / ASN 字段含已知 hosting 关键词 → 大概率被 AI 服务风控
HOSTING_KEYWORDS="hosting|hosthatch|hetzner|digitalocean|linode|vultr|ovh|leaseweb|amazon|aws|google.cloud|microsoft|azure|oracle.cloud|akamai|cloudflare|tencent|alibaba|m247|datacenter|dedicated|colocation|cdn|baremetal"
combined_org="${IPINFO_ORG} ${IPAPI_ORG}"
if echo "$combined_org" | grep -qiE "$HOSTING_KEYWORDS"; then
  kv "ASN 性质" "${RED}datacenter / hosting${RST}"
  warn "ASN 被识别成机房 IP —— Gemini / OpenAI / Anthropic 都对机房 IP 高度警惕"
  warn "全 datacenter IP 段被屏蔽，换同 VPS 的别的节点也没用"
  warn "解法：① 套 Cloudflare WARP（VPS 上装 wgcf）让出口变 CF residential"
  warn "      ② 换"住宅 IP" 中转（贵但管用）"
  warn "      ③ 临时绕：用别的能用的服务（Gemini 改 ChatGPT、Cursor 改 Claude Code）"
else
  kv "ASN 性质" "${GRN}非典型 hosting（可能是住宅 / 移动 / 中转）${RST}"
fi

# ─────────────────────────────────────────────────────────────────
# 4. 各 AI 服务实测
# ─────────────────────────────────────────────────────────────────

hdr "4. AI 服务可达性 + 国家屏蔽实测"

# 4.1 Gemini —— 最严的国家屏蔽
echo "${BOLD}Gemini (Google AI Studio)${RST}"
gem_status=$(curl "${CURL_OPTS[@]}" -o /tmp/gem.html -w "%{http_code}" "https://gemini.google.com/" 2>/dev/null || echo "000")
if [[ "$gem_status" == "200" ]]; then
  if grep -qiE "not.*supported.*country|isn't currently supported|不支持.*地区" /tmp/gem.html 2>/dev/null; then
    no "HTTP 200 但页面提示"not supported in your country" → ${BOLD}${RED}国家被屏蔽${RST}"
    warn "Google 看到的国家：${IPINFO_COUNTRY:-?}（不在 Gemini 支持列表里）"
    warn "支持列表参考：US / UK / 大部分 EU / JP / SG / TW（不含 HK / CN / RU）"
  elif grep -qi "Sign in" /tmp/gem.html 2>/dev/null; then
    ok "HTTP 200 + 登录页正常 → IP 国家通过 Gemini 检查"
  else
    warn "HTTP 200 但页面内容未识别（自己 cat /tmp/gem.html | head 看看）"
  fi
else
  no "HTTP $gem_status → 连不上（可能节点本身挂了）"
fi
rm -f /tmp/gem.html

# 4.2 Google search —— 最宽松，几乎只要能访问就 200
gs_status=$(curl "${CURL_OPTS[@]}" -o /dev/null -w "%{http_code}" "https://www.google.com/" 2>/dev/null || echo "000")
[[ "$gs_status" == "200" || "$gs_status" == "301" || "$gs_status" == "302" ]] \
  && ok "google.com → HTTP ${gs_status}（基础连通 OK）" \
  || no "google.com → HTTP ${gs_status}"

# 4.3 OpenAI / ChatGPT
echo
echo "${BOLD}OpenAI / ChatGPT / Cursor 后端${RST}"
# 用 ipcheck 接口（OpenAI 自己拿的国家）
oai_country=$(fetch -H "user-agent: Mozilla/5.0" "https://chat.openai.com/cdn-cgi/trace" | awk -F= '/^loc=/ {print $2}')
if [[ -n "$oai_country" ]]; then
  if echo "HK CN RU IR" | grep -qw "$oai_country"; then
    no "OpenAI CDN 看到的国家：${RED}$oai_country${RST} → ChatGPT / Cursor 都会拒"
  else
    ok "OpenAI CDN 看到的国家：${GRN}$oai_country${RST}（OpenAI 支持列表里）"
  fi
fi
oai_status=$(curl "${CURL_OPTS[@]}" -o /dev/null -w "%{http_code}" "https://api.openai.com/v1/models" 2>/dev/null || echo "000")
case "$oai_status" in
  401) ok "api.openai.com → 401（IP 通过国家检查；正常未带 token 是 401）" ;;
  403) no "api.openai.com → ${RED}403${RST}（IP 国家被拒；这就是 Cursor 报海外检测失败的原因）" ;;
  200) ok "api.openai.com → 200" ;;
  *)   warn "api.openai.com → HTTP ${oai_status}（异常）" ;;
esac

# 4.4 Anthropic / Claude
echo
echo "${BOLD}Anthropic / Claude / Claude Code${RST}"
anthropic_status=$(curl "${CURL_OPTS[@]}" -o /dev/null -w "%{http_code}" "https://api.anthropic.com/v1/messages" 2>/dev/null || echo "000")
case "$anthropic_status" in
  401|400) ok "api.anthropic.com → ${anthropic_status}（IP 通过；正常未带 token）" ;;
  403)     no "api.anthropic.com → ${RED}403${RST}（IP 国家被拒）" ;;
  200)     ok "api.anthropic.com → 200" ;;
  *)       warn "api.anthropic.com → HTTP $anthropic_status" ;;
esac

# 4.5 Cursor 自己的 license/health 接口
echo
cursor_status=$(curl "${CURL_OPTS[@]}" -o /dev/null -w "%{http_code}" "https://api2.cursor.sh/" 2>/dev/null || echo "000")
case "$cursor_status" in
  200|404|401|403) [[ "$cursor_status" == "403" ]] && no "api2.cursor.sh → ${RED}403${RST}" || ok "api2.cursor.sh → ${cursor_status}（基础连通 OK）" ;;
  *) warn "api2.cursor.sh → HTTP $cursor_status" ;;
esac

# ─────────────────────────────────────────────────────────────────
# 5. 综合判定
# ─────────────────────────────────────────────────────────────────

hdr "5. 综合判定 / 怎么办"

# Country 黑名单：被各大 AI 服务普遍排除的国家
BLACKLIST_COUNTRIES="HK CN RU IR KP CU SY"
PROBLEM_COUNTRY=""
for c in "$IPINFO_COUNTRY" "$CF_LOC"; do
  if echo "$BLACKLIST_COUNTRIES" | grep -qw "$c"; then
    PROBLEM_COUNTRY=$c; break
  fi
done

if [[ -n "$PROBLEM_COUNTRY" ]]; then
  echo "${BOLD}${RED}诊断：当前出口 IP 国家是 $PROBLEM_COUNTRY，被 Gemini / OpenAI / Anthropic 默认屏蔽。${RST}"
  echo
  echo "  ${BOLD}建议（按性价比）${RST}："
  echo "  1) ${GRN}立刻换节点${RST}：在 Mihomo Party / Clash Party 左侧 Proxies → ⚡ AUTO 或 🚀 PROXY"
  echo "     选一个明确标 US/JP/SG 的节点，再跑一次 bash scripts/test/ip-check.sh 验证"
  echo "  2) 如果你的 VPS 全是 HK 出口，去 hosthatch / racknerd 加一台 US/JP 小机器（\$2-5/月）"
  echo "  3) VPS 上装 Cloudflare WARP (wgcf) 把出口转给 CF，国家会变成 WARP 出口的国家"
elif echo "$combined_org" | grep -qiE "$HOSTING_KEYWORDS"; then
  echo "${BOLD}${YLW}诊断：国家 OK 但 ASN 是 datacenter，仍可能被风控。${RST}"
  echo
  echo "  Gemini / Cursor / ChatGPT 三家对 datacenter IP 的容忍度："
  echo "  - Gemini  : 最严，绝大多数 datacenter IP 都看到不支持地区页"
  echo "  - OpenAI  : 中等，大部分老 datacenter ASN 还能用"
  echo "  - Claude  : 最宽，几乎都能用"
  echo
  echo "  ${BOLD}建议${RST}："
  echo "  1) Gemini 替代：直接用 ChatGPT / Claude（这两家对 datacenter 友好得多）"
  echo "  2) Cursor 必须用：在 VPS 上套 WARP（wgcf）让出口变 residential"
  echo "  3) 终极方案：买一台 IP 信誉好的小 VPS（搜 'good ASN VPS for AI'）"
else
  echo "${BOLD}${GRN}诊断：国家 OK + ASN 性质 OK。${RST}"
  echo
  echo "  如果 Gemini 仍报错，可能是："
  echo "  1) 你的 Google 账号 IP 历史污染：换浏览器无痕窗口测、或 Google 账号设置里看 IP 历史"
  echo "  2) Gemini 在你这个国家的服务尚未开放（虽然支持但灰度未到）"
  echo "  3) 换一个 region 的节点再试，gemini.google.com 在不同 region 用不同入口"
fi

echo
echo "${DIM}（脚本本身只读不改任何配置；多次跑安全）${RST}"
