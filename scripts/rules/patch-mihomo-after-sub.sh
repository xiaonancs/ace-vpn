#!/usr/bin/env bash
# 订阅刷新后修补 Mihomo Party 的 work/config.yaml
#
# 问题：remote 订阅 YAML 常带 tun.enable: false 或缺 dns-hijack，
#       Party 合并后 TUN 被关 → 系统流量直连（出口变国内/香港 IP，非东京 VPS）。
#
# 用法：
#   bash scripts/rules/patch-mihomo-after-sub.sh
#   bash scripts/rules/patch-mihomo-after-sub.sh --reload-only
set -euo pipefail

RELOAD_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reload-only) RELOAD_ONLY=1; shift ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | sed -n '/^#/p' | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

PARTY_DIR="${MIHOMO_PARTY_DIR:-$HOME/Library/Application Support/mihomo-party}"
WORK_CFG="$PARTY_DIR/work/config.yaml"
MIHOMO_CFG="$PARTY_DIR/mihomo.yaml"

[[ -f "$WORK_CFG" ]] || { echo "找不到 $WORK_CFG" >&2; exit 1; }

if [[ $RELOAD_ONLY -eq 0 ]]; then
  python3 - "$WORK_CFG" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
text = p.read_text()

text = re.sub(r'^ipv6:\s*true\s*$', 'ipv6: false', text, flags=re.M)

if re.search(r'^dns:\n', text, re.M):
    dns_block = text.split('dns:', 1)[1].split('\nproxies:', 1)[0]
    if 'ipv6: false' not in dns_block:
        text = text.replace(
            'dns:\n  enable: true\n  listen:',
            'dns:\n  enable: true\n  ipv6: false\n  listen:',
            1,
        )

# 强制 TUN 开启 + DNS 劫持（订阅模板常关 tun）
tun_pat = re.compile(
    r'tun:\n(?:  .+\n)+?(?=proxies:|\Z)',
    re.M,
)
replacement = """tun:
  enable: true
  stack: mixed
  auto-route: true
  auto-detect-interface: true
  dns-hijack:
    - any:53
  device: utun1500
  auto-redirect: false
  route-exclude-address: []
  mtu: 1500
"""
if tun_pat.search(text):
    text = tun_pat.sub(replacement, text, count=1)
else:
    text = text.replace('proxies:\n', replacement + 'proxies:\n', 1)

p.write_text(text)
print(f"已修补: {p}")
PY
fi

SECRET=""
if [[ -f "$MIHOMO_CFG" ]]; then
  SECRET=$(grep -E '^secret:' "$MIHOMO_CFG" | awk '{print $2}' | tr -d '"' || true)
fi

HDR=()
[[ -n "$SECRET" ]] && HDR=(-H "Authorization: Bearer $SECRET")

# 先确保 TUN 打开（API reload 有时不会重建 utun）
curl -fsS -X PATCH "http://127.0.0.1:9090/configs" \
  "${HDR[@]}" -H "Content-Type: application/json" \
  -d '{"tun":{"enable":true,"stack":"mixed","auto-route":true,"dns-hijack":["any:53"]}}' \
  >/dev/null 2>&1 || true

curl -fsS -X PUT "http://127.0.0.1:9090/configs?force=true" \
  "${HDR[@]}" -H "Content-Type: application/json" \
  -d "{\"path\":\"$WORK_CFG\"}" >/dev/null

curl -fsS -X PATCH "http://127.0.0.1:9090/configs" \
  "${HDR[@]}" -H "Content-Type: application/json" \
  -d '{"tun":{"enable":true,"stack":"mixed","auto-route":true,"dns-hijack":["any:53"]}}' \
  >/dev/null 2>&1 || true

echo "Mihomo 已重载；TUN 应已开启（订阅后请跑此脚本）"
