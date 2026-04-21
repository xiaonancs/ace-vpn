#!/usr/bin/env bash
# 把本地规则池推到 VPS：
#   1. 按 target 合并到 private/intranet.yaml：
#       IN     → profiles[active].domains
#       VPS    → 顶层 extra.overseas
#       DIRECT → 顶层 extra.cn
#   2. 调 sync-intranet.sh 推 VPS（sub-converter 热加载，全设备订阅刷新即生效）
#   3. 已 promote 的规则从本地池删除
#   4. 重新渲染 Mihomo override（本地池清空了那部分，规则下沉到订阅）
#
# 用法：
#   bash scripts/promote-to-vps.sh             # 标准流程
#   bash scripts/promote-to-vps.sh --dry-run   # 只预览，不改文件
#   bash scripts/promote-to-vps.sh --keep      # 推 VPS 后不清空本地池（debug 用）
#   bash scripts/promote-to-vps.sh --no-sync   # 只改本地 intranet.yaml + 清池，不推 VPS
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

color_red=$'\033[31m'; color_grn=$'\033[32m'; color_ylw=$'\033[33m'; color_off=$'\033[0m'
die()  { echo "${color_red}ERROR${color_off} $*" >&2; exit 1; }
info() { echo "${color_grn}→${color_off} $*"; }
warn() { echo "${color_ylw}!${color_off}  $*" >&2; }

DRY_RUN=0
KEEP=0
NO_SYNC=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --keep) KEEP=1 ;;
    --no-sync) NO_SYNC=1 ;;
    -h|--help) sed -n '1,/^set/p' "$0" | grep '^#' ; exit 0 ;;
    *) die "未知参数：$arg" ;;
  esac
done

info "扫描本地池..."
PLAN=$(PYTHONPATH="$SCRIPT_DIR" python3 - <<'PY'
import json
from lib import local_rules as lr

try:
    plan = lr.promote_to_intranet()
except ValueError as e:
    print(json.dumps({"error": str(e)}))
    raise SystemExit(0)

print(json.dumps(plan, ensure_ascii=False))
PY
)

ERR=$(echo "$PLAN" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("error",""))')
[[ -n "$ERR" ]] && die "$ERR"

py_get() { echo "$PLAN" | python3 -c "import json,sys;d=json.load(sys.stdin);v=d['$1'];print('\n'.join(v) if isinstance(v,list) else v)"; }

ACTIVE=$(py_get active_profile)
IN_ADD=$(py_get in_to_add)
IN_DUP=$(py_get in_skipped_dup)
VPS_ADD=$(py_get vps_to_add)
VPS_DUP=$(py_get vps_skipped_dup)
DIR_ADD=$(py_get direct_to_add)
DIR_DUP=$(py_get direct_skipped_dup)

count() { echo -n "${1:-}" | grep -c . || true; }
IN_ADD_N=$(count "$IN_ADD");   IN_DUP_N=$(count "$IN_DUP")
VPS_ADD_N=$(count "$VPS_ADD"); VPS_DUP_N=$(count "$VPS_DUP")
DIR_ADD_N=$(count "$DIR_ADD"); DIR_DUP_N=$(count "$DIR_DUP")

TOTAL_ADD=$((IN_ADD_N + VPS_ADD_N + DIR_ADD_N))

echo
echo "📋 计划"
echo "   当前 enabled profile: $ACTIVE"
echo
print_section() {
  local icon=$1 label=$2 add_list=$3 add_n=$4 dup_list=$5 dup_n=$6 dest=$7
  if [[ $add_n -gt 0 ]]; then
    echo "   $icon $label：合并到 $dest（+$add_n 条）"
    echo "$add_list" | sed 's/^/        + /'
  fi
  if [[ $dup_n -gt 0 ]]; then
    echo "   ⏭  $label：已存在跳过（$dup_n 条）"
    echo "$dup_list" | sed 's/^/        · /'
  fi
}

print_section "🏢" "IN"      "$IN_ADD"  "$IN_ADD_N"  "$IN_DUP"  "$IN_DUP_N"  "profiles.$ACTIVE.domains"
print_section "🌍" "VPS"     "$VPS_ADD" "$VPS_ADD_N" "$VPS_DUP" "$VPS_DUP_N" "extra.overseas"
print_section "🇨🇳" "DIRECT"  "$DIR_ADD" "$DIR_ADD_N" "$DIR_DUP" "$DIR_DUP_N" "extra.cn"

if [[ $TOTAL_ADD -eq 0 ]]; then
  if [[ $((IN_DUP_N + VPS_DUP_N + DIR_DUP_N)) -gt 0 ]]; then
    info "本地池里全是 intranet.yaml 已有的规则，没有需要 promote 的。"
    info "可以手工清掉本地池：编辑 private/local-rules.yaml 删行 + 跑 apply-local-overrides.sh"
  else
    info "本地池为空，没什么可 promote 的。"
  fi
  exit 0
fi
echo

if [[ $DRY_RUN -eq 1 ]]; then
  warn "--dry-run，啥也没改。退出。"
  exit 0
fi

info "改 intranet.yaml..."
PYTHONPATH="$SCRIPT_DIR" python3 - <<'PY' || die "intranet.yaml 修改失败"
from lib import local_rules as lr
plan = lr.promote_to_intranet()
lr.apply_promote(plan)
total = len(plan['in_to_add']) + len(plan['vps_to_add']) + len(plan['direct_to_add'])
print(f"  ✅ {total} 条已写入 {lr.INTRANET_PATH}")
PY

if [[ $NO_SYNC -eq 0 ]]; then
  info "推 VPS（调 sync-intranet.sh）..."
  bash "$SCRIPT_DIR/sync-intranet.sh"
else
  warn "--no-sync，没推 VPS。手动跑：bash scripts/sync-intranet.sh"
fi

if [[ $KEEP -eq 0 ]]; then
  info "从本地池移除已 promote 的规则..."
  PYTHONPATH="$SCRIPT_DIR" python3 - <<PY
from lib import local_rules as lr
hosts = """$(printf '%s\n' "$IN_ADD" "$VPS_ADD" "$DIR_ADD" | grep -v '^$' || true)""".strip().splitlines()
removed = lr.remove_from_pool(hosts)
print(f"  ✅ 本地池删除 {removed} 条")
PY

  info "重新渲染 Mihomo override（本地池现在不含这些规则了）..."
  bash "$SCRIPT_DIR/apply-local-overrides.sh"
fi

echo
info "✅ promote 完成"
echo "   家人客户端：下次订阅刷新即获得新规则"
echo "   你这台 Mac：override 已清理，规则 100% 来自 VPS（避免本地/远端冲突）"
