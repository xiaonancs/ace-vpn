#!/usr/bin/env bash
# 看本地规则池里都有啥（按 target 分组）。
#
# 用法：
#   bash scripts/list-rules.sh
#   bash scripts/list-rules.sh IN          # 只看 IN 类
#   bash scripts/list-rules.sh DIRECT      # 只看 DIRECT 类
#   bash scripts/list-rules.sh VPS         # 只看 VPS 类
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FILTER=${1:-}

PYTHONPATH="$SCRIPT_DIR" python3 - "$FILTER" <<'PY'
import sys
from collections import defaultdict
from lib import local_rules as lr

raw_filter = sys.argv[1] if len(sys.argv) > 1 else ""
filter_target = lr.normalize_target(raw_filter) if raw_filter else None

pool = lr.load_pool()

if not pool:
    print("本地池为空。用 `bash scripts/add-rule.sh <URL> <IN|DIRECT|VPS>` 加规则。")
    sys.exit(0)

groups = defaultdict(list)
for r in pool:
    groups[r.get("target", "?")].append(r)

ICONS = {lr.TARGET_IN: "🏢", lr.TARGET_DIRECT: "🇨🇳", lr.TARGET_VPS: "🌍"}
LABELS = {
    lr.TARGET_IN:     "IN     (公司内网)",
    lr.TARGET_DIRECT: "DIRECT (普通直连)",
    lr.TARGET_VPS:    "VPS    (走 VPS 代理)",
}
ORDER = [lr.TARGET_IN, lr.TARGET_DIRECT, lr.TARGET_VPS]

print(f"📋 本地规则池（{lr.LOCAL_RULES_PATH}）")
print(f"   共 {len(pool)} 条 · {dict((k, len(v)) for k, v in groups.items())}")
print()

for tgt in ORDER + [t for t in groups if t not in ORDER]:
    if tgt not in groups:
        continue
    if filter_target and filter_target != tgt:
        continue
    icon = ICONS.get(tgt, "•")
    label = LABELS.get(tgt, tgt)
    print(f"{icon} {label}  ({len(groups[tgt])})")
    print("─" * 60)
    for r in groups[tgt]:
        host = r.get("host", "?")
        added = r.get("added", "")
        note = r.get("note", "")
        line = f"  {host:<40s}"
        if added:
            line += f"  [{added}]"
        print(line)
        if note:
            print(f"      └─ {note}")
    print()

print("提示：")
print("  · 这些规则当前已在本机 Mihomo Party 生效（本地优先级最高）")
print("  · VPS 上还没同步；要全设备生效跑 `bash scripts/promote-to-vps.sh`")
PY
