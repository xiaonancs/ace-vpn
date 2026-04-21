#!/usr/bin/env bash
# 把 private/local-rules.yaml 渲染成 Mihomo Party 的覆写文件，并触发 reload。
#
# 用法：
#   bash scripts/apply-local-overrides.sh
#
# 副作用：
#   - 写 ~/Library/Application Support/mihomo-party/override/ace-vpn-local.yaml
#   - 在 ~/Library/Application Support/mihomo-party/override.yaml 注册该 item
#   - PUT http://127.0.0.1:9097/configs?force=true 让 Mihomo 重新加载
#
# 这个脚本被 add-rule.sh 自动调用；你也可以手动跑（比如直接编辑了 local-rules.yaml）。
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

color_red=$'\033[31m'; color_grn=$'\033[32m'; color_ylw=$'\033[33m'; color_off=$'\033[0m'
die()  { echo "${color_red}ERROR${color_off} $*" >&2; exit 1; }
info() { echo "${color_grn}→${color_off} $*"; }
warn() { echo "${color_ylw}!${color_off}  $*" >&2; }

PYTHONPATH="$SCRIPT_DIR" python3 - <<'PY' || die "渲染 / 触发 reload 失败"
import sys
from lib import local_rules as lr

stats = lr.render_and_install()
print(f"  规则总数: {stats['rules_total']}")
print(f"  按 target: {stats['by_target']}")
print(f"  写入: {stats['override_file']}")
if stats["registered"]:
    print(f"  ✨ 首次注册到 Mihomo override.yaml")

ok, msg = lr.trigger_mihomo_reload()
prefix = "  ✅" if ok else "  ⚠"
print(f"{prefix} Mihomo reload: {msg}")

# Mihomo Party 有个特性：override 文件改了它会自动 watch 重载，
# 但在某些情况（比如用户没启动 GUI）curl reload 会失败也无妨——
# 下次 GUI 一启动会自动应用。
sys.exit(0 if ok else 0)  # 不让 reload 失败阻塞，只警告
PY

echo
info "完成。在 Mihomo Party 设置 → 覆写 里能看到 'ace-vpn local rules'"
echo "   验证生效：访问 https://your-test-host  或者用 curl 测延迟"
