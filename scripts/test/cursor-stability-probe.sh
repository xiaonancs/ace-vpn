#!/usr/bin/env bash
# ace-vpn · Cursor stability probe from each VPS in VPS_IP_LIST.
#
# Goal:
#   Detect intermittent Cursor connectivity problems without generating real
#   Cursor account/API traffic. This script only probes public endpoints with
#   unauthenticated curl requests at a low default rate.
#
# Defaults:
#   duration: 30 minutes
#   interval: 60 seconds
#   method: HEAD
#   endpoints: cursor.com, api2/api3/repo42.cursor.sh
#
# Usage:
#   cd ~/workspace/cursor-base/ace-vpn && source private/env.sh
#   bash scripts/test/cursor-stability-probe.sh --log
#   bash scripts/test/cursor-stability-probe.sh --rounds 1 --log  # smoke test
#   bash scripts/test/cursor-stability-probe.sh --duration-min 60 --interval-sec 90 --log
#
# Output columns:
#   ts node ip round url curl_exit http_code total connect tls ttfb remote_ip size_download
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)

if [[ -f "$ROOT_DIR/private/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/private/env.sh"
fi

USE_LOG=0
DURATION_MIN=${CURSOR_PROBE_DURATION_MIN:-30}
INTERVAL_SEC=${CURSOR_PROBE_INTERVAL_SEC:-60}
ROUNDS=${CURSOR_PROBE_ROUNDS:-}
SLOW_SEC=${CURSOR_PROBE_SLOW_SEC:-10}
MAX_TIME=${CURSOR_PROBE_MAX_TIME:-20}
CONNECT_TIMEOUT=${CURSOR_PROBE_CONNECT_TIMEOUT:-8}
METHOD=${CURSOR_PROBE_METHOD:-HEAD}
LOG_FILE="${CURSOR_PROBE_LOG_FILE:-${CURSOR_PROBE_LOG_DIR:-$HOME/Library/Logs/ace-vpn}/cursor-stability-probe.log}"
RUN_FILE=$(mktemp /tmp/ace-vpn-cursor-probe-run.XXXXXX)
URL_FILE=$(mktemp /tmp/ace-vpn-cursor-probe-urls.XXXXXX)
REMOTE_LIST=/tmp/ace-vpn-cursor-probe-urls.txt
VPS_SSH_USER=${VPS_SSH_USER:-root}

usage() {
  sed -n '1,/^set -euo pipefail/p' "$0" | grep '^#' | sed 's/^# \?//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log) USE_LOG=1; shift ;;
    --duration-min) DURATION_MIN=$2; shift 2 ;;
    --interval-sec) INTERVAL_SEC=$2; shift 2 ;;
    --rounds) ROUNDS=$2; shift 2 ;;
    --slow-sec) SLOW_SEC=$2; shift 2 ;;
    --max-time) MAX_TIME=$2; shift 2 ;;
    --connect-timeout) CONNECT_TIMEOUT=$2; shift 2 ;;
    --method) METHOD=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

trap 'rm -f "$RUN_FILE" "$URL_FILE"' EXIT

is_pos_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

is_nonneg_number() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

is_pos_int "$DURATION_MIN" || { echo "ERROR: --duration-min must be positive integer" >&2; exit 1; }
is_pos_int "$INTERVAL_SEC" || { echo "ERROR: --interval-sec must be positive integer" >&2; exit 1; }
is_nonneg_number "$SLOW_SEC" || { echo "ERROR: --slow-sec must be non-negative number" >&2; exit 1; }
is_pos_int "$MAX_TIME" || { echo "ERROR: --max-time must be positive integer" >&2; exit 1; }
is_pos_int "$CONNECT_TIMEOUT" || { echo "ERROR: --connect-timeout must be positive integer" >&2; exit 1; }
[[ "$METHOD" == "HEAD" || "$METHOD" == "GET" ]] || { echo "ERROR: --method must be HEAD or GET" >&2; exit 1; }
if [[ -n "$ROUNDS" ]]; then
  is_pos_int "$ROUNDS" || { echo "ERROR: --rounds must be positive integer" >&2; exit 1; }
else
  ROUNDS=$(( (DURATION_MIN * 60 + INTERVAL_SEC - 1) / INTERVAL_SEC ))
fi

write_urls() {
  if [[ -n "${CURSOR_PROBE_URLS:-}" ]]; then
    printf '%s\n' $CURSOR_PROBE_URLS
    return
  fi
  cat <<'EOF'
https://cursor.com/
https://api2.cursor.sh/
https://api3.cursor.sh/
https://repo42.cursor.sh/
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
  local ip=$1 round=$2 max_time=$3 connect_timeout=$4 method=$5
  ssh "${SSH_OPTS[@]}" "${VPS_SSH_USER}@${ip}" \
    "ROUND='$round' MAX_TIME='$max_time' CONNECT_TIMEOUT='$connect_timeout' METHOD='$method' bash -s" <<'EOS'
set -euo pipefail
f=/tmp/ace-vpn-cursor-probe-urls.txt
[[ -f "$f" ]] || { echo "missing $f"; exit 1; }
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
method_args=()
if [[ "$METHOD" == "HEAD" ]]; then
  method_args=(-I)
fi
while IFS= read -r url || [[ -n "$url" ]]; do
  url="${url%%#*}"
  url=$(echo "$url" | xargs)
  [[ -z "$url" ]] && continue
  start=$(date +%s)
  if out=$(curl -gLsS --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
    "${method_args[@]}" -o /dev/null -A "$UA" \
    -w '%{http_code}\t%{time_total}\t%{time_connect}\t%{time_appconnect}\t%{time_starttransfer}\t%{remote_ip}\t%{size_download}' \
    "$url" 2>/dev/null); then
    exit_code=0
  else
    exit_code=$?
    out="000	na	na	na	na	-	0"
  fi
  printf '%s\t%s\t%s\t%s\n' "$ROUND" "$url" "$exit_code" "$out"
  elapsed=$(( $(date +%s) - start ))
  # Avoid creating a burst against Cursor endpoints even within one round.
  if [[ "$elapsed" -lt 1 ]]; then
    sleep 1
  fi
done < "$f"
true
EOS
}

print_run_summary() {
  python3 - "$RUN_FILE" "$SLOW_SEC" <<'PY'
from __future__ import annotations

import statistics
import sys
from collections import defaultdict
from pathlib import Path

path = Path(sys.argv[1])
slow_sec = float(sys.argv[2])

def parse_float(value: str) -> float | None:
    if value in {"", "na", "-"}:
        return None
    try:
        return float(value)
    except ValueError:
        return None

def percentile(values: list[float], pct: float) -> float | None:
    if not values:
        return None
    values = sorted(values)
    if len(values) == 1:
        return values[0]
    idx = (len(values) - 1) * pct
    low = int(idx)
    high = min(low + 1, len(values) - 1)
    weight = idx - low
    return values[low] * (1 - weight) + values[high] * weight

def fmt_sec(value: float | None) -> str:
    if value is None:
        return "-"
    return f"{value * 1000:.0f}ms" if value < 1 else f"{value:.2f}s"

def fmt_pct(value: float) -> str:
    return f"{value * 100:.1f}%"

rows = []
for line in path.read_text().splitlines():
    if not line or line.startswith("#") or "\t" not in line:
        continue
    parts = line.split("\t")
    if len(parts) != 13:
        continue
    ts, node, ip, round_s, url, curl_exit, code, total, connect, tls, ttfb, remote_ip, size = parts
    rows.append(
        {
            "ts": ts,
            "node": node,
            "ip": ip,
            "round": int(round_s),
            "url": url,
            "curl_exit": int(curl_exit),
            "code": code,
            "total": parse_float(total),
            "connect": parse_float(connect),
            "tls": parse_float(tls),
            "ttfb": parse_float(ttfb),
            "remote_ip": remote_ip,
            "size": size,
        }
    )

print()
print("# cursor_probe_summary")
if not rows:
    print("no records")
    raise SystemExit(0)

print(f"records: {len(rows)}")
print(f"nodes: {', '.join(sorted({r['node'] for r in rows}))}")
print(f"urls: {len({r['url'] for r in rows})}")
print(f"rounds: {len({r['round'] for r in rows})}")
print()

print("# node_stability")
print("node\trecords\tfail_rate\tslow_rate\tavg\tmedian\tp95\tp99\tworst\tmax_consecutive_failures\texit_codes")

by_node: dict[str, list[dict[str, object]]] = defaultdict(list)
for row in rows:
    by_node[str(row["node"])].append(row)

for node, items in sorted(by_node.items()):
    totals = [r["total"] for r in items if isinstance(r["total"], float) and r["curl_exit"] == 0]
    failures = [r for r in items if r["curl_exit"] != 0]
    slow = [r for r in items if isinstance(r["total"], float) and r["total"] >= slow_sec]
    exit_counts: dict[int, int] = defaultdict(int)
    for r in items:
        exit_counts[int(r["curl_exit"])] += 1

    max_consecutive = 0
    current = 0
    for r in sorted(items, key=lambda x: (int(x["round"]), str(x["url"]))):
        if r["curl_exit"] != 0:
            current += 1
            max_consecutive = max(max_consecutive, current)
        else:
            current = 0

    print(
        "\t".join(
            [
                node,
                str(len(items)),
                fmt_pct(len(failures) / len(items)),
                fmt_pct(len(slow) / len(items)),
                fmt_sec(statistics.mean(totals) if totals else None),
                fmt_sec(statistics.median(totals) if totals else None),
                fmt_sec(percentile(totals, 0.95)),
                fmt_sec(percentile(totals, 0.99)),
                fmt_sec(max(totals) if totals else None),
                str(max_consecutive),
                ",".join(f"{k}:{v}" for k, v in sorted(exit_counts.items())),
            ]
        )
    )

print()
print("# cursor_endpoint_detail")
print("node\turl\trecords\tfailures\tslow_ge_threshold\tmedian\tp95\tworst\texit_codes")

by_pair: dict[tuple[str, str], list[dict[str, object]]] = defaultdict(list)
for row in rows:
    by_pair[(str(row["node"]), str(row["url"]))].append(row)

for (node, url), items in sorted(by_pair.items()):
    totals = [r["total"] for r in items if isinstance(r["total"], float) and r["curl_exit"] == 0]
    failures = [r for r in items if r["curl_exit"] != 0]
    slow = [r for r in items if isinstance(r["total"], float) and r["total"] >= slow_sec]
    exit_counts: dict[int, int] = defaultdict(int)
    for r in items:
        exit_counts[int(r["curl_exit"])] += 1
    print(
        "\t".join(
            [
                node,
                url,
                str(len(items)),
                str(len(failures)),
                str(len(slow)),
                fmt_sec(statistics.median(totals) if totals else None),
                fmt_sec(percentile(totals, 0.95)),
                fmt_sec(max(totals) if totals else None),
                ",".join(f"{k}:{v}" for k, v in sorted(exit_counts.items())),
            ]
        )
    )
PY
}

build_nodes
probe_ip=$(first_probe_ip)
[[ -n "$probe_ip" ]] || { echo "ERROR: 需要 VPS_IP_LIST" >&2; exit 1; }
resolve_ssh_key "$probe_ip"

write_urls | awk 'NF && $0 ~ /^https?:\/\// { if (!seen[$0]++) print }' > "$URL_FILE"
[[ -s "$URL_FILE" ]] || { echo "ERROR: no Cursor probe URLs" >&2; exit 1; }

if [[ $USE_LOG -eq 1 ]]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

echo "======== $(date '+%Y-%m-%d %H:%M:%S %z') cursor stability probe ========"
echo "nodes: ${NODES[*]}"
echo "urls: $(wc -l < "$URL_FILE" | xargs)"
echo "rounds: ${ROUNDS}"
echo "interval_sec: ${INTERVAL_SEC}"
echo "method: ${METHOD}"
echo "max_time_sec: ${MAX_TIME}"
echo "slow_threshold_sec: ${SLOW_SEC}"
echo "log_file: ${LOG_FILE}"
echo "说明: 只探测公开 Cursor 端点，不带账号、Cookie 或 API Key；默认低频，避免给 Cursor 造成压力。"

for entry in "${NODES[@]}"; do
  ip="${entry##*:}"
  scp "${SSH_OPTS[@]}" "$URL_FILE" "${VPS_SSH_USER}@${ip}:${REMOTE_LIST}" >/dev/null
done

for ((round=1; round<=ROUNDS; round++)); do
  echo ""
  echo "---- round ${round}/${ROUNDS} $(date '+%Y-%m-%d %H:%M:%S') ----"
  for entry in "${NODES[@]}"; do
    name="${entry%%:*}"
    ip="${entry##*:}"
    remote_probe_once "$ip" "$round" "$MAX_TIME" "$CONNECT_TIMEOUT" "$METHOD" | while IFS=$'\t' read -r r url curl_exit code total connect tls ttfb remote_ip size; do
      row="$(date '+%Y-%m-%d %H:%M:%S')	${name}	${ip}	${r}	${url}	${curl_exit}	${code}	${total}	${connect}	${tls}	${ttfb}	${remote_ip}	${size}"
      echo "$row"
      printf '%s\n' "$row" >> "$RUN_FILE"
    done
  done

  if [[ "$round" -lt "$ROUNDS" ]]; then
    # Small deterministic jitter avoids hitting endpoints at exactly fixed wall-clock seconds.
    sleep_for=$((INTERVAL_SEC + (round % 7)))
    sleep "$sleep_for"
  fi
done

print_run_summary
echo ""
echo "完成。"
