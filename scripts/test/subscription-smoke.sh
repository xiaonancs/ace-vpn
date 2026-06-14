#!/usr/bin/env bash
# Verify that a Clash/Mihomo subscription can be refreshed directly, without a proxy.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
VALIDATOR="$ROOT_DIR/scripts/server/validate-config.py"

die() { echo "ERROR $*" >&2; exit 1; }
info() { echo "→ $*"; }

if [[ -z "${VPS_IP_LIST:-}" && -f "$ROOT_DIR/private/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/private/env.sh"
fi

MODE="direct"
ONE_TARGET=""
TOKEN="${SUB_HEALTH_TOKEN:-}"
QUERY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vps)
      shift
      ONE_TARGET="${1:-}"
      [[ -n "$ONE_TARGET" ]] || die "--vps requires name or ip"
      ;;
    --vps=*)
      ONE_TARGET="${1#*=}"
      ;;
    --token)
      shift
      TOKEN="${1:-}"
      [[ -n "$TOKEN" ]] || die "--token requires value"
      ;;
    --token=*)
      TOKEN="${1#*=}"
      ;;
    --with-proxy)
      MODE="proxy"
      ;;
    --direct)
      MODE="direct"
      ;;
    --query)
      shift
      QUERY="${1:-}"
      [[ -n "$QUERY" ]] || die "--query requires value, e.g. process=1"
      ;;
    --query=*)
      QUERY="${1#*=}"
      ;;
    -h|--help)
      sed -n '1,80p' "$0"
      exit 0
      ;;
    *)
      die "unknown arg: $1"
      ;;
  esac
  shift
done

first_vps_ip() {
  local entry
  for entry in ${VPS_IP_LIST:-}; do
    if [[ "$entry" == *:* ]]; then
      echo "${entry##*:}"
    else
      echo "$entry"
    fi
    return
  done
}

find_vps_ip() {
  local target="$1" entry name ip idx=1
  if [[ -z "$target" ]]; then
    first_vps_ip
    return
  fi
  for entry in ${VPS_IP_LIST:-}; do
    if [[ "$entry" == *:* ]]; then
      name="${entry%%:*}"
      ip="${entry##*:}"
    else
      name="vps${idx}"
      ip="$entry"
    fi
    if [[ "$target" == "$name" || "$target" == "$ip" ]]; then
      echo "$ip"
      return
    fi
    idx=$((idx + 1))
  done
  echo "$target"
}

if [[ -z "$TOKEN" ]]; then
  if [[ -n "${SUB_TOKEN:-}" ]]; then
    TOKEN="$SUB_TOKEN"
  elif [[ -n "${SUB_TOKENS:-}" ]]; then
    TOKEN="${SUB_TOKENS%%,*}"
  else
    TOKEN="ace-main"
  fi
fi

VPS_IP=$(find_vps_ip "$ONE_TARGET")
[[ -n "$VPS_IP" ]] || die "VPS_IP_LIST empty; source private/env.sh or pass --vps <ip>"

SUB_PORT=${SUB_PORT_CLASH:-25500}
SUB_PATH_PREFIX=${SUB_PATH_PREFIX:-clash}
LOCAL_PROXY=${LOCAL_PROXY:-http://127.0.0.1:7890}
URL="http://${VPS_IP}:${SUB_PORT}/${SUB_PATH_PREFIX}/${TOKEN}"
REDACTED="http://${VPS_IP}:${SUB_PORT}/${SUB_PATH_PREFIX}/<token>"
if [[ -n "$QUERY" ]]; then
  URL="${URL}?${QUERY}"
  REDACTED="${REDACTED}?${QUERY}"
fi
TMP_YAML=$(mktemp -t ace-vpn-sub-smoke.XXXXXX.yaml)
trap 'rm -f "$TMP_YAML"' EXIT

info "subscription: $REDACTED"
if [[ "$MODE" == "direct" ]]; then
  info "fetch mode: direct (--noproxy '*')"
  curl -fsS --noproxy '*' --connect-timeout 5 --max-time 20 "$URL" -o "$TMP_YAML"
else
  info "fetch mode: local proxy $LOCAL_PROXY"
  curl -fsS -x "$LOCAL_PROXY" --connect-timeout 5 --max-time 20 "$URL" -o "$TMP_YAML"
fi

info "validate mihomo YAML"
python3 "$VALIDATOR" --quiet "$TMP_YAML"

info "extract key routing fields"
python3 - "$TMP_YAML" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
rules = cfg.get("rules") or []
dns = cfg.get("dns") or {}
groups = [g.get("name") for g in cfg.get("proxy-groups") or [] if isinstance(g, dict)]
print(f"rules={len(rules)} groups={','.join(groups)}")
print(f"tun.enable={(cfg.get('tun') or {}).get('enable')} process={cfg.get('find-process-mode')}")
print(f"dns.respect-rules={dns.get('respect-rules')} sniffer={(cfg.get('sniffer') or {}).get('enable')}")
PY

info "subscription smoke passed"
