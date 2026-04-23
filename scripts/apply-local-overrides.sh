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

set +e
PYTHONPATH="$SCRIPT_DIR" python3 - <<'PY'
import sys
from lib import local_rules as lr

try:
    stats = lr.render_and_install()
except ValueError as e:
    # pre-flight 校验失败：旧 override 完整保留，用户网络不受影响
    print()
    print(str(e))
    print()
    sys.exit(2)
except Exception as e:
    print(f"❌ 渲染失败：{type(e).__name__}: {e}", file=sys.stderr)
    sys.exit(3)

print(f"  规则总数: {stats['rules_total']}")
print(f"  按 target: {stats['by_target']}")
print(f"  写入: {stats['override_file']}")
if stats["registered"]:
    print(f"  ✨ 首次注册到 Mihomo override.yaml")

ok, msg = lr.trigger_mihomo_reload()
prefix = "  ✅" if ok else "  ⚠"
print(f"{prefix} Mihomo reload: {msg}")

# Mihomo Party 监听 override 目录会自动重载；这里 reload 调用失败不阻塞流程。
sys.exit(0)
PY
rc=$?
set -e

case $rc in
  0) ;;
  2) die "本地池里有不合法的规则，旧 override 已保留，网络不受影响。按上面提示修复 local-rules.yaml 再跑一次。" ;;
  *) die "渲染 / 触发 reload 失败（rc=$rc）。旧 override 已保留。"
     ;;
esac

echo
info "完成。在 Mihomo Party 设置 → 覆写 里能看到 'ace-vpn local rules'"
echo "   验证生效：访问 https://your-test-host  或者用 curl 测延迟"
