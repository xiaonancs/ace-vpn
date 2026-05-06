#!/usr/bin/env bash
# ace-vpn · AI service stability probe from each VPS in VPS_IP_LIST.
#
# Goal:
#   Decide which single VPS provider should be kept when cost requires HH/Vultr
#   to be a strict either-or choice. This is not a generic latency benchmark.
#   It focuses on AI product availability and stability signals:
#     - transport failures / timeouts
#     - slow requests
#     - expected vs unexpected HTTP status
#     - simple application-layer block / geo mismatch hints in response bodies
#     - consecutive bad events
#
# Defaults:
#   duration: 24 hours
#   interval: 300 seconds
#   method: endpoint-specific GET/HEAD
#   endpoints: Gemini/Google AI, Claude/Claude Code, OpenAI/ChatGPT/Codex, Cursor
#
# Optional authenticated probes:
#   By default, this script does not send account cookies or API keys. To test
#   API-key authentication from each VPS, export keys in private/env.sh and opt in:
#
#     export AI_PROBE_ENABLE_KEY_TESTS=1
#     export OPENAI_API_KEY="sk-..."
#     export ANTHROPIC_API_KEY="sk-ant-..."
#     export GEMINI_API_KEY="..."
#
#   To also test tiny real model calls and streaming/SSE, explicitly opt in:
#
#     export AI_PROBE_ENABLE_REAL_CALLS=1
#
#   Defaults use max token/output 1 to minimize cost:
#     AI_PROBE_OPENAI_MODEL=gpt-4o-mini
#     AI_PROBE_ANTHROPIC_MODEL=claude-3-5-haiku-latest
#     AI_PROBE_GEMINI_MODEL=gemini-1.5-flash
#
# Optional geo expectations:
#   For IP stability checks, set expected country globally or per node:
#     export AI_PROBE_EXPECTED_COUNTRY=JP
#     export AI_PROBE_EXPECTED_COUNTRY_HOSTHATCH=JP
#     export AI_PROBE_EXPECTED_COUNTRY_VULTR=JP
#
# Usage:
#   cd ~/workspace/publish/ace-vpn && source private/env.sh
#   bash scripts/test/ai-stability-probe.sh --rounds 1 --log     # smoke test
#   bash scripts/test/ai-stability-probe.sh --duration-hours 24 --interval-sec 300 --log
#
# Output columns:
#   ts node ip round service url method curl_exit http_code expected_ok slow block_hint total connect tls ttfb remote_ip size
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)

if [[ -f "$ROOT_DIR/private/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/private/env.sh"
fi

USE_LOG=0
DURATION_HOURS=${AI_PROBE_DURATION_HOURS:-24}
INTERVAL_SEC=${AI_PROBE_INTERVAL_SEC:-300}
ROUNDS=${AI_PROBE_ROUNDS:-}
SLOW_SEC=${AI_PROBE_SLOW_SEC:-5}
MAX_TIME=${AI_PROBE_MAX_TIME:-20}
CONNECT_TIMEOUT=${AI_PROBE_CONNECT_TIMEOUT:-8}
LOG_FILE="${AI_PROBE_LOG_FILE:-${AI_PROBE_LOG_DIR:-$HOME/Library/Logs/ace-vpn}/ai-stability-probe.log}"
RUN_FILE=$(mktemp /tmp/ace-vpn-ai-probe-run.XXXXXX)
ENDPOINT_FILE=$(mktemp /tmp/ace-vpn-ai-probe-endpoints.XXXXXX)
REMOTE_LIST=/tmp/ace-vpn-ai-probe-endpoints.tsv
VPS_SSH_USER=${VPS_SSH_USER:-root}
ENABLE_KEY_TESTS=${AI_PROBE_ENABLE_KEY_TESTS:-0}
ENABLE_REAL_CALLS=${AI_PROBE_ENABLE_REAL_CALLS:-0}
OPENAI_MODEL=${AI_PROBE_OPENAI_MODEL:-gpt-4o-mini}
ANTHROPIC_MODEL=${AI_PROBE_ANTHROPIC_MODEL:-claude-3-5-haiku-latest}
GEMINI_MODEL=${AI_PROBE_GEMINI_MODEL:-gemini-1.5-flash}

usage() {
  sed -n '1,/^set -euo pipefail/p' "$0" | grep '^#' | sed 's/^# \?//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log) USE_LOG=1; shift ;;
    --duration-hours) DURATION_HOURS=$2; shift 2 ;;
    --interval-sec) INTERVAL_SEC=$2; shift 2 ;;
    --rounds) ROUNDS=$2; shift 2 ;;
    --slow-sec) SLOW_SEC=$2; shift 2 ;;
    --max-time) MAX_TIME=$2; shift 2 ;;
    --connect-timeout) CONNECT_TIMEOUT=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

trap 'rm -f "$RUN_FILE" "$ENDPOINT_FILE"' EXIT

is_pos_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

is_nonneg_number() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

is_pos_int "$DURATION_HOURS" || { echo "ERROR: --duration-hours must be positive integer" >&2; exit 1; }
is_pos_int "$INTERVAL_SEC" || { echo "ERROR: --interval-sec must be positive integer" >&2; exit 1; }
is_nonneg_number "$SLOW_SEC" || { echo "ERROR: --slow-sec must be non-negative number" >&2; exit 1; }
is_pos_int "$MAX_TIME" || { echo "ERROR: --max-time must be positive integer" >&2; exit 1; }
is_pos_int "$CONNECT_TIMEOUT" || { echo "ERROR: --connect-timeout must be positive integer" >&2; exit 1; }
if [[ -n "$ROUNDS" ]]; then
  is_pos_int "$ROUNDS" || { echo "ERROR: --rounds must be positive integer" >&2; exit 1; }
else
  ROUNDS=$(( (DURATION_HOURS * 3600 + INTERVAL_SEC - 1) / INTERVAL_SEC ))
fi

write_endpoints() {
  if [[ -n "${AI_PROBE_ENDPOINTS_FILE:-}" ]]; then
    cat "$AI_PROBE_ENDPOINTS_FILE"
    return
  fi

  # service<TAB>url<TAB>method<TAB>expected_http_codes
  # Notes:
  #   - 404/403/421 can be healthy for unauthenticated API roots.
  #   - We intentionally do not send account cookies or API keys.
  #   - These endpoints are chosen to exercise the same hostnames used by
  #     Gemini, Claude Code, OpenAI API/Codex, ChatGPT, and Cursor.
  cat <<'EOF'
# IP identity / geo database drift.
# GET6OPT means: use IPv6 when the VPS has it; do not penalize IPv4-only nodes.
ip_ipify	https://api.ipify.org/	GET	200
ip_ipify_v4	https://api.ipify.org/	GET4	200
ip_ipify_v6	https://api64.ipify.org/	GET6OPT	200,000
ip_sb	https://api.ip.sb/geoip	GET	200
ip_sb_v4	https://api.ip.sb/geoip	GET4	200
ip_sb_v6	https://api.ip.sb/geoip	GET6OPT	200,000
ipwho_is	https://ipwho.is/	GET	200
ipwho_is_v4	https://ipwho.is/	GET4	200
ipwho_is_v6	https://ipwho.is/	GET6OPT	200,000
ipapi_is	https://api.ipapi.is/	GET	200
ipapi_is_v4	https://api.ipapi.is/	GET4	200
ipapi_is_v6	https://api.ipapi.is/	GET6OPT	200,000
cloudflare_trace	https://www.cloudflare.com/cdn-cgi/trace	GET	200
cloudflare_trace_v4	https://www.cloudflare.com/cdn-cgi/trace	GET4	200
cloudflare_trace_v6	https://www.cloudflare.com/cdn-cgi/trace	GET6OPT	200,000

# Google AI / Gemini
gemini	https://gemini.google.com/	GET	200
gemini_app	https://gemini.google.com/app	GET	200
gemini_static	https://gemini.gstatic.com/	GET	404
aistudio	https://aistudio.google.com/	GET	200,302
gemini_api	https://generativelanguage.googleapis.com/	GET	404
google_ai_api_models	https://generativelanguage.googleapis.com/v1beta/models	GET	403,404
notebooklm	https://notebooklm.google.com/	GET	200
google_accounts	https://accounts.google.com/	GET	200
googleapis_root	https://www.googleapis.com/	GET	404

# Cursor
cursor_api2	https://api2.cursor.sh/	GET	200
cursor_api2direct	https://api2direct.cursor.sh/	GET	404
cursor_api3	https://api3.cursor.sh/	GET	404
cursor_repo	https://repo42.cursor.sh/	GET	404
cursor_agent	https://agentn.global.api5.cursor.sh/	GET	200

# Anthropic / Claude / Claude Code
claude	https://claude.ai/	GET	403
anthropic_www	https://www.anthropic.com/	GET	200
anthropic_api	https://api.anthropic.com/	GET	404
anthropic_api_v1_messages	https://api.anthropic.com/v1/messages	GET	401,405

# OpenAI / ChatGPT / Codex
chatgpt	https://chatgpt.com/	GET	403
chatgpt_backend_root	https://chatgpt.com/backend-api/	GET	403,404
openai_www	https://openai.com/	GET	200,403
openai_api	https://api.openai.com/	GET	421
openai_api_v1_models	https://api.openai.com/v1/models	GET	401
openai_auth	https://auth.openai.com/	GET	200,403
openai_auth0	https://auth0.openai.com/	GET	200,403
oaistatic	https://cdn.oaistatic.com/	GET	403,404
EOF
}

build_nodes() {
  NODES=()
  if [[ -z "${VPS_IP_LIST:-}" ]]; then
    echo "ERROR: 未设置 VPS_IP_LIST" >&2
    exit 1
  fi
  local e idx=1
  for e in $VPS_IP_LIST; do
    if [[ "$e" == *:* ]]; then
      NODES+=( "$e" )
    else
      NODES+=( "vps${idx}:${e}" )
    fi
    idx=$((idx + 1))
  done
}

first_probe_ip() {
  local entry
  for entry in ${VPS_IP_LIST:-}; do
    if [[ "$entry" == *:* ]]; then
      echo "${entry##*:}"
    else
      echo "$entry"
    fi
    return
  done
  echo ""
}

resolve_ssh_key() {
  SSH_OPTS=( -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new )
  local ip=$1 k cand

  if [[ -n "${VPS_SSH_KEY:-}" ]]; then
    k="${VPS_SSH_KEY/#~/$HOME}"
    [[ -f "$k" ]] || { echo "ERROR: VPS_SSH_KEY=${VPS_SSH_KEY} 文件不存在" >&2; exit 1; }
    ssh "${SSH_OPTS[@]}" -i "$k" "${VPS_SSH_USER}@${ip}" 'echo OK' >/dev/null 2>&1 || {
      echo "ERROR: 用 ${k} 无法免密登录 ${ip}" >&2
      exit 1
    }
    SSH_OPTS+=( -i "$k" )
    echo "→ 使用 VPS_SSH_KEY: ${k}" >&2
    return
  fi

  for cand in "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ecdsa"; do
    [[ -f "$cand" ]] || continue
    if ssh "${SSH_OPTS[@]}" -i "$cand" "${VPS_SSH_USER}@${ip}" 'echo OK' >/dev/null 2>&1; then
      SSH_OPTS+=( -i "$cand" )
      echo "→ 自动选用免密私钥: ${cand}" >&2
      return
    fi
  done

  echo "ERROR: 未配置可免密登录 ${ip} 的 SSH key" >&2
  exit 1
}

remote_probe_once() {
  local ip=$1 round=$2 node_name=$3 max_time=$4 connect_timeout=$5 slow_sec=$6
  local expected_var node_key openai_key_b64 anthropic_key_b64 gemini_key_b64
  node_key=$(printf '%s' "$node_name" | tr '[:lower:]-' '[:upper:]_')
  expected_var="AI_PROBE_EXPECTED_COUNTRY_${node_key}"
  node_expected_country="${!expected_var:-${AI_PROBE_EXPECTED_COUNTRY:-}}"
  openai_key_b64=""
  anthropic_key_b64=""
  gemini_key_b64=""
  if [[ "$ENABLE_KEY_TESTS" == "1" ]]; then
    [[ -n "${OPENAI_API_KEY:-}" ]] && openai_key_b64=$(printf '%s' "$OPENAI_API_KEY" | base64 | tr -d '\n')
    [[ -n "${ANTHROPIC_API_KEY:-}" ]] && anthropic_key_b64=$(printf '%s' "$ANTHROPIC_API_KEY" | base64 | tr -d '\n')
    [[ -n "${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}" ]] && gemini_key_b64=$(printf '%s' "${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}" | base64 | tr -d '\n')
  fi
  ssh "${SSH_OPTS[@]}" "${VPS_SSH_USER}@${ip}" \
    "ROUND='$round' NODE_NAME='$node_name' NODE_EXPECTED_COUNTRY='$node_expected_country' MAX_TIME='$max_time' CONNECT_TIMEOUT='$connect_timeout' SLOW_SEC='$slow_sec' ENABLE_KEY_TESTS='$ENABLE_KEY_TESTS' ENABLE_REAL_CALLS='$ENABLE_REAL_CALLS' OPENAI_MODEL='$OPENAI_MODEL' ANTHROPIC_MODEL='$ANTHROPIC_MODEL' GEMINI_MODEL='$GEMINI_MODEL' OPENAI_API_KEY_B64='$openai_key_b64' ANTHROPIC_API_KEY_B64='$anthropic_key_b64' GEMINI_API_KEY_B64='$gemini_key_b64' bash -s" <<'EOS'
set -euo pipefail
f=/tmp/ace-vpn-ai-probe-endpoints.tsv
[[ -f "$f" ]] || { echo "missing $f"; exit 1; }
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"

decode_b64() {
  [[ -n "${1:-}" ]] || return 0
  printf '%s' "$1" | base64 -d 2>/dev/null || true
}

OPENAI_API_KEY=$(decode_b64 "${OPENAI_API_KEY_B64:-}")
ANTHROPIC_API_KEY=$(decode_b64 "${ANTHROPIC_API_KEY_B64:-}")
GEMINI_API_KEY=$(decode_b64 "${GEMINI_API_KEY_B64:-}")

contains_code() {
  local list=$1 code=$2
  case ",${list}," in
    *",${code},"*) return 0 ;;
    *) return 1 ;;
  esac
}

block_hint_for_body() {
  local body=$1 code=$2
  local text
  text=$(tr '\n' ' ' < "$body" | head -c 200000 | tr '[:upper:]' '[:lower:]')
  case "$code" in
    429) echo "rate_limited"; return ;;
    451) echo "legal_unavailable"; return ;;
  esac
  if printf '%s' "$text" | grep -Eq 'not available in your country|not available in your region|unsupported country|unusual traffic|verify you are human|captcha|access denied|blocked|rate limit|too many requests'; then
    echo "block_hint"
  else
    echo "-"
  fi
}

json_field() {
  local key=$1 body=$2
  python3 - "$key" "$body" <<'PY' 2>/dev/null || true
import json
import sys

key, path = sys.argv[1], sys.argv[2]
try:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        data = json.load(f)
    value = data
    for part in key.split("."):
        if isinstance(value, dict):
            value = value.get(part)
        else:
            value = None
        if value is None:
            break
    print(value or "")
except Exception:
    print("")
PY
}

geo_country_for_body() {
  local service=$1 body=$2 country=""
  case "$service" in
    ip_sb|ip_sb_v4|ip_sb_v6)
      country=$(json_field country_code "$body")
      ;;
    ipwho_is|ipwho_is_v4|ipwho_is_v6)
      country=$(json_field country_code "$body")
      ;;
    ipapi_is|ipapi_is_v4|ipapi_is_v6)
      country=$(json_field location.country_code "$body")
      [[ -n "$country" ]] || country=$(json_field country_code "$body")
      ;;
    cloudflare_trace|cloudflare_trace_v4|cloudflare_trace_v6)
      country=$(awk -F= '/^loc=/ {print $2; exit}' "$body" 2>/dev/null || true)
      ;;
  esac
  printf '%s' "$country" | tr '[:lower:]' '[:upper:]'
}

geo_hint_for_body() {
  local service=$1 body=$2
  local country expected
  country=$(geo_country_for_body "$service" "$body")
  expected=$(printf '%s' "${NODE_EXPECTED_COUNTRY:-}" | tr '[:lower:]' '[:upper:]')
  if [[ -n "$country" && -n "$expected" && "$country" != "$expected" ]]; then
    echo "geo_${country}_expected_${expected}"
    return
  fi
  if [[ -n "$country" ]] && printf '%s\n' CN HK RU IR KP SY CU | grep -qx "$country"; then
    echo "geo_risky_${country}"
    return
  fi
  echo "-"
}

run_curl_probe() {
  local service=$1 display_url=$2 method=$3 expected_codes=$4 actual_url=$5
  shift 5
  local body header out exit_code code total _connect _tls _ttfb _remote_ip _size
  local expected_ok slow block_hint
  local method_args=() force_args=() optional_ipv6=0
  body=$(mktemp /tmp/ace-vpn-ai-probe-body.XXXXXX)
  header=$(mktemp /tmp/ace-vpn-ai-probe-header.XXXXXX)
  case "$method" in
    GET4) force_args=(-4); method="GET" ;;
    GET6) force_args=(-6); method="GET" ;;
    GET6OPT) force_args=(-6); method="GET6"; optional_ipv6=1 ;;
  esac
  if [[ "$method" == "HEAD" ]]; then
    method_args=(-I)
  elif [[ "$method" != "GET" && "$method" != "GET6" ]]; then
    method_args=(-X "$method")
  fi

  if out=$(curl -gLsS --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
    "${force_args[@]}" "${method_args[@]}" "$@" -o "$body" -D "$header" -A "$UA" \
    -w '%{http_code}\t%{time_total}\t%{time_connect}\t%{time_appconnect}\t%{time_starttransfer}\t%{remote_ip}\t%{size_download}' \
    "$actual_url" 2>/dev/null); then
    exit_code=0
  else
    exit_code=$?
    out="000	na	na	na	na	-	0"
  fi

  IFS=$'\t' read -r code total _connect _tls _ttfb _remote_ip _size <<< "$out"
  if [[ "$optional_ipv6" == "1" && "$exit_code" != "0" ]]; then
    exit_code=0
  fi
  expected_ok=0
  if [[ "$exit_code" == "0" ]] && contains_code "$expected_codes" "$code"; then
    expected_ok=1
  fi
  slow=0
  if [[ "$total" != "na" ]]; then
    slow=$(awk -v total="$total" -v slow="$SLOW_SEC" 'BEGIN { print (total >= slow) ? 1 : 0 }')
  fi
  block_hint="-"
  if [[ "$exit_code" == "0" ]]; then
    case "$service" in
      ip_sb|ip_sb_v4|ip_sb_v6|ipwho_is|ipwho_is_v4|ipwho_is_v6|ipapi_is|ipapi_is_v4|ipapi_is_v6|cloudflare_trace|cloudflare_trace_v4|cloudflare_trace_v6)
        block_hint=$(geo_hint_for_body "$service" "$body")
        ;;
      *)
        block_hint=$(block_hint_for_body "$body" "$code")
        ;;
    esac
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$ROUND" "$service" "$display_url" "$method" "$exit_code" "$expected_ok" "$slow" "$block_hint" "$out"

  rm -f "$body" "$header"
}

while IFS=$'\t' read -r service url method expected_codes || [[ -n "${service:-}" ]]; do
  [[ -z "${service:-}" || "${service:0:1}" == "#" ]] && continue
  run_curl_probe "$service" "$url" "$method" "$expected_codes" "$url"
  sleep 1
done < "$f"

if [[ "${ENABLE_KEY_TESTS:-0}" == "1" ]]; then
  if [[ -n "$OPENAI_API_KEY" ]]; then
    run_curl_probe openai_key_models "https://api.openai.com/v1/models" GET 200 "https://api.openai.com/v1/models" \
      -H "Authorization: Bearer ${OPENAI_API_KEY}"
    sleep 1
  fi
  if [[ -n "$ANTHROPIC_API_KEY" ]]; then
    run_curl_probe anthropic_key_models "https://api.anthropic.com/v1/models" GET 200 "https://api.anthropic.com/v1/models" \
      -H "x-api-key: ${ANTHROPIC_API_KEY}" -H "anthropic-version: 2023-06-01"
    sleep 1
  fi
  if [[ -n "$GEMINI_API_KEY" ]]; then
    run_curl_probe gemini_key_models "https://generativelanguage.googleapis.com/v1beta/models?key=<redacted>" GET 200 "https://generativelanguage.googleapis.com/v1beta/models?key=${GEMINI_API_KEY}"
    sleep 1
  fi
fi

if [[ "${ENABLE_KEY_TESTS:-0}" == "1" && "${ENABLE_REAL_CALLS:-0}" == "1" ]]; then
  if [[ -n "$OPENAI_API_KEY" ]]; then
    run_curl_probe openai_responses_call "https://api.openai.com/v1/responses" POST 200 "https://api.openai.com/v1/responses" \
      -H "Authorization: Bearer ${OPENAI_API_KEY}" -H "Content-Type: application/json" \
      --data "{\"model\":\"${OPENAI_MODEL}\",\"input\":\"ping\",\"max_output_tokens\":1}"
    sleep 1
    run_curl_probe openai_responses_stream "https://api.openai.com/v1/responses (stream)" POST 200 "https://api.openai.com/v1/responses" \
      -H "Authorization: Bearer ${OPENAI_API_KEY}" -H "Content-Type: application/json" \
      --no-buffer --data "{\"model\":\"${OPENAI_MODEL}\",\"input\":\"ping\",\"max_output_tokens\":1,\"stream\":true}"
    sleep 1
  fi
  if [[ -n "$ANTHROPIC_API_KEY" ]]; then
    run_curl_probe anthropic_messages_call "https://api.anthropic.com/v1/messages" POST 200 "https://api.anthropic.com/v1/messages" \
      -H "x-api-key: ${ANTHROPIC_API_KEY}" -H "anthropic-version: 2023-06-01" -H "Content-Type: application/json" \
      --data "{\"model\":\"${ANTHROPIC_MODEL}\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}"
    sleep 1
    run_curl_probe anthropic_messages_stream "https://api.anthropic.com/v1/messages (stream)" POST 200 "https://api.anthropic.com/v1/messages" \
      -H "x-api-key: ${ANTHROPIC_API_KEY}" -H "anthropic-version: 2023-06-01" -H "Content-Type: application/json" \
      --no-buffer --data "{\"model\":\"${ANTHROPIC_MODEL}\",\"max_tokens\":1,\"stream\":true,\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}"
    sleep 1
  fi
  if [[ -n "$GEMINI_API_KEY" ]]; then
    run_curl_probe gemini_generate_call "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=<redacted>" POST 200 "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}" \
      -H "Content-Type: application/json" --data '{"contents":[{"parts":[{"text":"ping"}]}],"generationConfig":{"maxOutputTokens":1}}'
    sleep 1
    run_curl_probe gemini_generate_stream "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:streamGenerateContent?key=<redacted>&alt=sse" POST 200 "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:streamGenerateContent?key=${GEMINI_API_KEY}&alt=sse" \
      -H "Content-Type: application/json" --no-buffer --data '{"contents":[{"parts":[{"text":"ping"}]}],"generationConfig":{"maxOutputTokens":1}}'
    sleep 1
  fi
fi
true
EOS
}

build_nodes
probe_ip=$(first_probe_ip)
[[ -n "$probe_ip" ]] || { echo "ERROR: 需要 VPS_IP_LIST" >&2; exit 1; }
resolve_ssh_key "$probe_ip"

write_endpoints | awk -F '\t' 'NF >= 4 && $2 ~ /^https?:\/\// { key=$1 FS $2; if (!seen[key]++) print }' > "$ENDPOINT_FILE"
[[ -s "$ENDPOINT_FILE" ]] || { echo "ERROR: no AI probe endpoints" >&2; exit 1; }

if [[ $USE_LOG -eq 1 ]]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

echo "======== $(date '+%Y-%m-%d %H:%M:%S %z') ai stability probe ========"
echo "nodes: ${NODES[*]}"
echo "endpoints: $(wc -l < "$ENDPOINT_FILE" | xargs)"
echo "rounds: ${ROUNDS}"
echo "interval_sec: ${INTERVAL_SEC}"
echo "max_time_sec: ${MAX_TIME}"
echo "slow_threshold_sec: ${SLOW_SEC}"
echo "log_file: ${LOG_FILE}"
echo "说明: 只探测公开页面/API root，不带账号、Cookie 或 API Key；用于 VPS 二选一稳定性判断。"

for entry in "${NODES[@]}"; do
  ip="${entry##*:}"
  scp "${SSH_OPTS[@]}" "$ENDPOINT_FILE" "${VPS_SSH_USER}@${ip}:${REMOTE_LIST}" >/dev/null
done

for ((round=1; round<=ROUNDS; round++)); do
  echo ""
  echo "---- round ${round}/${ROUNDS} $(date '+%Y-%m-%d %H:%M:%S') ----"
  for entry in "${NODES[@]}"; do
    name="${entry%%:*}"
    ip="${entry##*:}"
    remote_probe_once "$ip" "$round" "$name" "$MAX_TIME" "$CONNECT_TIMEOUT" "$SLOW_SEC" | while IFS=$'\t' read -r r service url method curl_exit expected_ok slow block_hint code total connect tls ttfb remote_ip size; do
      row="$(date '+%Y-%m-%d %H:%M:%S')	${name}	${ip}	${r}	${service}	${url}	${method}	${curl_exit}	${code}	${expected_ok}	${slow}	${block_hint}	${total}	${connect}	${tls}	${ttfb}	${remote_ip}	${size}"
      echo "$row"
      printf '%s\n' "$row" >> "$RUN_FILE"
    done
  done

  if [[ "$round" -lt "$ROUNDS" ]]; then
    sleep_for=$((INTERVAL_SEC + (round % 11)))
    sleep "$sleep_for"
  fi
done

python3 "$SCRIPT_DIR/ai-stability-summary.py" --log "$RUN_FILE" --slow-sec "$SLOW_SEC"
echo ""
echo "完成。"
