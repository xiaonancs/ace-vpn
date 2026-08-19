#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
HOST_FILE=${1:-"$ROOT_DIR/scripts/test/mobile-direct-hosts.txt"}

if [[ -z "${MATCH_BASE:-}" && -f "$ROOT_DIR/private/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/private/env.sh"
fi

VPS_SSH_USER=${VPS_SSH_USER:-root}
VPS_ENTRY=${MOBILE_DIRECT_VPS:-${VPS_IP_LIST%% *}}
if [[ "$VPS_ENTRY" == *:* ]]; then
  VPS_IP=${VPS_ENTRY##*:}
else
  VPS_IP=${VPS_ENTRY:-207.148.102.103}
fi
SUB_PORT=${SUB_PORT_CLASH:-25500}
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=15)

collect_hosts() {
  while IFS= read -r line; do
    host=${line%%#*}
    host=$(printf '%s' "$host" | xargs)
    [[ -z "$host" ]] && continue
    printf '%s\n' "$host"
  done < "$HOST_FILE"
}

if [[ -n "${MATCH_BASE:-}" ]]; then
  failed=0
  while IFS= read -r host; do
    json=$(curl -fsS --max-time 8 "${MATCH_BASE}${host}" || true)
    target=$(python3 -c 'import json,sys; print((json.load(sys.stdin) or {}).get("target",""))' <<<"$json" 2>/dev/null || true)
    rule=$(python3 -c 'import json,sys; print((json.load(sys.stdin) or {}).get("rule",""))' <<<"$json" 2>/dev/null || true)
    if [[ "$target" != "DIRECT" ]]; then
      printf 'FAIL %-42s target=%s rule=%s\n' "$host" "${target:-"(empty)"}" "${rule:-"(empty)"}"
      failed=$((failed + 1))
    else
      printf 'OK   %-42s target=%s rule=%s\n' "$host" "$target" "$rule"
    fi
  done < <(collect_hosts)
  if [[ $failed -gt 0 ]]; then
    echo "$failed mobile direct host(s) failed" >&2
    exit 1
  fi
  exit 0
fi

HOSTS=$(collect_hosts)
ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$VPS_IP" \
  "HOSTS=$(printf '%q' "$HOSTS") SUB_PORT='$SUB_PORT' bash -s" <<'REMOTE'
set -euo pipefail
failed=0
while IFS= read -r host; do
  [[ -z "$host" ]] && continue
  json=$(curl -fsS --max-time 8 "http://127.0.0.1:${SUB_PORT}/match?host=${host}" || true)
  target=$(python3 -c 'import json,sys; print((json.load(sys.stdin) or {}).get("target",""))' <<<"$json" 2>/dev/null || true)
  rule=$(python3 -c 'import json,sys; print((json.load(sys.stdin) or {}).get("rule",""))' <<<"$json" 2>/dev/null || true)
  if [[ "$target" != "DIRECT" ]]; then
    printf 'FAIL %-42s target=%s rule=%s\n' "$host" "${target:-"(empty)"}" "${rule:-"(empty)"}"
    failed=$((failed + 1))
  else
    printf 'OK   %-42s target=%s rule=%s\n' "$host" "$target" "$rule"
  fi
done <<<"$HOSTS"
if [[ $failed -gt 0 ]]; then
  echo "$failed mobile direct host(s) failed" >&2
  exit 1
fi
REMOTE

exit 0
