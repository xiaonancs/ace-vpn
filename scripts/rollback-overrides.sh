#!/usr/bin/env bash
# 应急回退本地 override —— 让 Mac 立即恢复网络。
#
# 用法：
#   bash scripts/rollback-overrides.sh                # 交互：列出备份让你选
#   bash scripts/rollback-overrides.sh --last         # 自动回退到最近一个备份
#   bash scripts/rollback-overrides.sh --list         # 只列备份不改动
#   bash scripts/rollback-overrides.sh --disable      # 应急核选项：禁用整个本地 override
#                                                       订阅原样加载，本地池"暂时不参与"
#   bash scripts/rollback-overrides.sh --enable       # 启用本地 override（与 --disable 配对）
#   bash scripts/rollback-overrides.sh --clear        # 清空 override 文件（写入空规则占位）
#
# 触发场景：
#   - 加完一条规则发现 Mihomo Party 报 "proxy not found" / 规则不合法 / 整个 profile 加载失败
#   - 想"先回到能上网的状态"，再慢慢排查 local-rules.yaml 哪里坏了
#
# 安全保证：
#   1. 每次 add-rule.sh / apply-local-overrides.sh 写 override 之前都会自动备份，
#      最近 10 个版本保留在 ~/Library/Application Support/mihomo-party/override/.bak/
#   2. 这个脚本只动 override 文件 / 注册表，不动 local-rules.yaml 源文件
#   3. --disable 是最强应急：让 Mihomo Party 直接忽略本地池，等于"装作没装本地规则"
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

color_red=$'\033[31m'; color_grn=$'\033[32m'; color_ylw=$'\033[33m'; color_off=$'\033[0m'
die()  { echo "${color_red}ERROR${color_off} $*" >&2; exit 1; }
info() { echo "${color_grn}→${color_off} $*"; }
warn() { echo "${color_ylw}!${color_off}  $*" >&2; }

MODE="interactive"
case "${1:-}" in
  ""|--help|-h)
    if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
      grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
      exit 0
    fi
    ;;
  --last|--list|--disable|--enable|--clear) MODE=${1#--} ;;
  *) die "未知参数：$1（用 --help 看用法）" ;;
esac

PYTHONPATH="$SCRIPT_DIR" python3 - "$MODE" <<'PY'
import sys
from pathlib import Path
from lib import local_rules as lr

mode = sys.argv[1]
baks = lr.list_override_backups()  # 新→旧

def _pretty(p: Path) -> str:
    # ace-vpn-local.yaml.20260423-121123.bak  →  20260423-121123
    return p.name.split(".", 2)[-1].rsplit(".bak", 1)[0]

if mode == "list":
    if not baks:
        print("没有备份。")
        sys.exit(0)
    print(f"备份目录：{lr.OVERRIDE_BAK_DIR}")
    print()
    for i, b in enumerate(baks, 1):
        size = b.stat().st_size
        print(f"  [{i:2d}] {_pretty(b)}    ({size} bytes)  {b.name}")
    sys.exit(0)

if mode == "disable":
    ok = lr.disable_override_in_registry()
    if ok:
        print("✅ 已把 ace-vpn-local 在 Mihomo Party 注册表里 enabled=false")
        print("   订阅会按原样加载，本地池所有规则暂时不参与。")
        print("   恢复：bash scripts/rollback-overrides.sh --enable")
    else:
        print("ℹ 注册表里没找到 ace-vpn-local（你可能还没 apply 过）。")
    sys.exit(0)

if mode == "enable":
    # 直接重新 apply，等价于"重新启用"
    try:
        stats = lr.render_and_install()
    except ValueError as e:
        print()
        print(str(e))
        print()
        sys.exit(2)
    print(f"✅ 已重新启用本地 override（规则 {stats['rules_total']} 条）")
    sys.exit(0)

if mode == "clear":
    # 写入"空池"内容（rules: []），override 仍然 enabled 但啥都不加
    content = lr.render_override_yaml([])
    lr._backup_override_file()
    lr.OVERRIDE_DIR.mkdir(parents=True, exist_ok=True)
    lr._atomic_write(lr.OVERRIDE_FILE, content)
    print(f"✅ 已清空 override 内容（保留注册）：{lr.OVERRIDE_FILE}")
    print(f"   想完全脱离 override：bash scripts/rollback-overrides.sh --disable")
    sys.exit(0)

if not baks:
    print("没有任何备份。可以用 --disable 临时禁用本地 override。")
    sys.exit(1)

if mode == "last":
    pick = baks[0]
elif mode == "interactive":
    print(f"备份目录：{lr.OVERRIDE_BAK_DIR}")
    print()
    for i, b in enumerate(baks, 1):
        size = b.stat().st_size
        print(f"  [{i:2d}] {_pretty(b)}    ({size} bytes)")
    print()
    try:
        ans = input(f"回退到哪个备份？[1-{len(baks)}]，回车=最近一个，q=取消: ").strip()
    except EOFError:
        ans = ""
    if ans.lower() in ("q", "quit", "exit"):
        print("取消。")
        sys.exit(0)
    if not ans:
        pick = baks[0]
    else:
        try:
            idx = int(ans)
            if not (1 <= idx <= len(baks)):
                raise ValueError
            pick = baks[idx - 1]
        except ValueError:
            print(f"无效输入：{ans}", file=sys.stderr)
            sys.exit(1)
else:
    print(f"未知模式：{mode}", file=sys.stderr)
    sys.exit(1)

# 回退前再备份一下当前（万一回退选错了还能再回退）
lr._backup_override_file()
lr.restore_override_backup(pick)
print(f"✅ 已回退到备份：{_pretty(pick)}")
print(f"   {pick}")
print()
print("Mihomo Party GUI 监听 override 目录，应该秒级自动应用。")
print("如果没生效：在 GUI 里切一下 profile 强制刷新。")
PY
