#!/usr/bin/env bash
# 把本地规则池推到 VPS：
#   1. 按 target **本地优先**合并到 private/intranet.yaml（与 intranet 已有位置冲突时
#      **覆盖**为本地池语义，并打印冲突说明）
#       IN     → profiles[active].domains
#       VPS    → 顶层 extra.overseas
#       DIRECT → 顶层 extra.cn
#   2. 调 sync-intranet.sh 推 VPS（远端先备份再覆盖；sub-converter 热加载）
#   3. 已 promote 的规则从本地池删除
#   4. 重新渲染 Mihomo override（本地池清空了那部分，规则下沉到订阅）
#
# 用法：
#   bash scripts/rules/promote-to-vps.sh             # 标准流程（推 VPS_IP_LIST 所有节点）
#   bash scripts/rules/promote-to-vps.sh --vps NAME  # 只推某一台（按 name 或 ip）
#   bash scripts/rules/promote-to-vps.sh --dry-run   # 只预览，不改文件
#   bash scripts/rules/promote-to-vps.sh --keep      # 推 VPS 后不清空本地池（debug 用）
#   bash scripts/rules/promote-to-vps.sh --no-sync   # 只改本地 intranet.yaml + 清池，不推 VPS
#   bash scripts/rules/promote-to-vps.sh --continue-on-error  # 多 VPS 时单台失败继续
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)

color_red=$'\033[31m'; color_grn=$'\033[32m'; color_ylw=$'\033[33m'; color_off=$'\033[0m'
die()  { echo "${color_red}ERROR${color_off} $*" >&2; exit 1; }
info() { echo "${color_grn}→${color_off} $*"; }
warn() { echo "${color_ylw}!${color_off}  $*" >&2; }

DRY_RUN=0
KEEP=0
NO_SYNC=0
SYNC_PASSTHROUGH=()      # 透传给 sync-intranet.sh 的参数（如 --vps X）
EXPECT_VPS_VALUE=0
for arg in "$@"; do
  if [[ $EXPECT_VPS_VALUE -eq 1 ]]; then
    SYNC_PASSTHROUGH+=(--vps "$arg")
    EXPECT_VPS_VALUE=0
    continue
  fi
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --keep) KEEP=1 ;;
    --no-sync) NO_SYNC=1 ;;
    --all-vps|--all) ;;  # 兼容旧命令；现在默认就是推 VPS_IP_LIST 全部节点
    --vps=*) SYNC_PASSTHROUGH+=("$arg") ;;
    --vps) EXPECT_VPS_VALUE=1 ;;
    --continue-on-error) SYNC_PASSTHROUGH+=(--continue-on-error) ;;
    -h|--help) sed -n '1,/^set/p' "$0" | grep '^#' ; exit 0 ;;
    *) die "未知参数：${arg}（看 --help）" ;;
  esac
done
[[ $EXPECT_VPS_VALUE -eq 1 ]] && die "--vps 后面要跟节点 name 或 ip"

info "扫描本地池（合并策略：本地优先，intranet 冲突则覆盖）..."
PLAN=$(PYTHONPATH="$ROOT_DIR/scripts" python3 - <<'PY'
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

ACTIVE=$(echo "$PLAN" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("active_profile",""))')
TOTAL=$(echo "$PLAN" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(len(d.get("hosts_processed") or []))')

echo
echo "📋 计划（enabled profile: ${ACTIVE}）"
echo
echo "$PLAN" | PYTHONPATH="$ROOT_DIR/scripts" python3 -c '
import json, sys
d = json.load(sys.stdin)
for line in d.get("conflict_log") or []:
    print("   " + line)
unk = d.get("unknown") or []
if unk:
    print()
    print("   ⚠ 以下条目 target 无法识别，已跳过（请用 IN / DIRECT / VPS）：")
    for host, tgt in unk:
        print("      · %s ← %r" % (host, tgt))
'

if [[ "$TOTAL" -eq 0 ]]; then
  echo
  info "本地池为空或没有可识别的规则，退出。"
  exit 0
fi
echo

if [[ $DRY_RUN -eq 1 ]]; then
  warn "--dry-run，未修改 intranet.yaml / 未推 VPS。退出。"
  exit 0
fi

info "写入 intranet.yaml（本地优先合并）..."
PYTHONPATH="$ROOT_DIR/scripts" python3 - <<'PY' || die "intranet.yaml 修改失败"
from lib import local_rules as lr
plan = lr.promote_to_intranet()
lr.apply_promote(plan)
n = len(plan.get("hosts_processed") or [])
print(f"  ✅ {n} 条已合并写入 {lr.INTRANET_PATH}")
PY

if [[ $NO_SYNC -eq 0 ]]; then
  if [[ ${#SYNC_PASSTHROUGH[@]} -gt 0 ]]; then
    info "推 VPS（调 sync-intranet.sh ${SYNC_PASSTHROUGH[*]}）..."
    bash "$SCRIPT_DIR/sync-intranet.sh" "${SYNC_PASSTHROUGH[@]}"
  else
    info "推 VPS（调 sync-intranet.sh，默认推 VPS_IP_LIST 全部节点）..."
    bash "$SCRIPT_DIR/sync-intranet.sh"
  fi
else
  warn "--no-sync，没推 VPS。手动跑：bash scripts/rules/sync-intranet.sh${SYNC_PASSTHROUGH[*]:+ }${SYNC_PASSTHROUGH[*]:-}"
fi

if [[ $KEEP -eq 0 ]]; then
  info "从本地池移除已 promote 的规则..."
  echo "$PLAN" | PYTHONPATH="$ROOT_DIR/scripts" python3 -c '
import json, sys
from lib import local_rules as lr
plan = json.load(sys.stdin)
hosts = plan.get("hosts_processed") or []
removed = lr.remove_from_pool(hosts)
print("  ✅ 本地池删除 %d 条" % removed)
'

  info "重新渲染 Mihomo override（本地池现在不含这些规则了）..."
  bash "$SCRIPT_DIR/apply-local-overrides.sh"
fi

echo
info "✅ promote 完成"
echo "   家人客户端：下次订阅刷新即获得新规则"
echo "   你这台 Mac：override 已清理，规则 100% 来自 VPS（避免本地/远端冲突）"
