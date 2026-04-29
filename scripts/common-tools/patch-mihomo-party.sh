#!/usr/bin/env bash
# ace-vpn · patch Mihomo Party generated config after profile reloads.
#
# Why this exists:
#   Clash/Mihomo Party regenerates work/config.yaml from the active profile plus
#   its own base template. On some versions it forces:
#     tcp-concurrent: false
#     find-process-mode: strict
#   even when the subscription profile says otherwise. Rule+TUN then becomes
#   very slow for GitHub/Cursor style multi-IP endpoints, while Global+TUN looks
#   fast because it bypasses much of the rule path.
#
# This script patches both:
#   ~/Library/Application Support/mihomo-party/mihomo.yaml       (base template)
#   ~/Library/Application Support/mihomo-party/work/config.yaml  (runtime config)
# and reloads the running mihomo core through Mihomo Party's Unix socket.
set -euo pipefail

PARTY_DIR="${MIHOMO_PARTY_DIR:-$HOME/Library/Application Support/mihomo-party}"
BASE_CFG="${MIHOMO_PARTY_BASE_CFG:-$PARTY_DIR/mihomo.yaml}"
WORK_CFG="${MIHOMO_PARTY_WORK_CFG:-$PARTY_DIR/work/config.yaml}"
LOG_FILE="${MIHOMO_PARTY_PATCH_LOG:-$HOME/Library/Logs/ace-vpn/mihomo-party-patch.log}"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$*" | tee -a "$LOG_FILE"
}

patch_one() {
  local file=$1
  [[ -f "$file" ]] || return 0

  python3 - "$file" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
orig = text

def replace_or_insert(src: str, key: str, value: str, after_key=None) -> str:
    pattern = rf"^{re.escape(key)}:\s*.*$"
    repl = f"{key}: {value}"
    if re.search(pattern, src, flags=re.MULTILINE):
        return re.sub(pattern, repl, src, count=1, flags=re.MULTILINE)
    if after_key:
        after_pattern = rf"^({re.escape(after_key)}:\s*.*)$"
        if re.search(after_pattern, src, flags=re.MULTILINE):
            return re.sub(after_pattern, rf"\1\n{repl}", src, count=1, flags=re.MULTILINE)
    return repl + "\n" + src

text = replace_or_insert(text, "tcp-concurrent", "true", "unified-delay")
text = replace_or_insert(text, "find-process-mode", "off", "external-controller")

if text != orig:
    path.write_text(text)
    print("changed")
else:
    print("unchanged")
PY
}

reload_mihomo() {
  local sock=${MIHOMO_PARTY_SOCKET:-}

  if [[ -z "$sock" ]]; then
    sock=$(ps aux | awk '/sidecar\/mihomo/ && /mihomo-party/ {for (i=1; i<=NF; i++) if ($i=="-ext-ctl-unix") print $(i+1)}' | head -1)
  fi

  if [[ -z "$sock" || ! -S "$sock" ]]; then
    log "mihomo core socket not found; patched files will take effect on next core restart"
    return 0
  fi

  if curl -fsS --unix-socket "$sock" -X PUT "http://unix/configs?force=true" \
    -H 'Content-Type: application/json' \
    -d "{\"path\":\"$WORK_CFG\"}" >/dev/null; then
    log "mihomo core reloaded via $sock"
  else
    log "WARN: failed to reload mihomo core via $sock"
  fi
}

main() {
  local changed=0 out

  out=$(patch_one "$BASE_CFG")
  [[ "$out" == "changed" ]] && { changed=1; log "patched base config: $BASE_CFG"; }

  out=$(patch_one "$WORK_CFG")
  [[ "$out" == "changed" ]] && { changed=1; log "patched runtime config: $WORK_CFG"; }

  if [[ $changed -eq 1 ]]; then
    reload_mihomo
  else
    log "already patched"
  fi
}

main "$@"
