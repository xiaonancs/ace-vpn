#!/usr/bin/env bash
# 把本地 private/intranet.yaml 同步到 VPS（热加载，不用重启 systemd）
#
# 前置：
#   1. source private/env.sh       # 导出 $VPS_IP / $VPS_SSH_USER / $VPS_SSH_KEY
#   2. private/intranet.yaml 存在（从 intranet.yaml.example 复制并编辑）
#
# 用法：
#   bash scripts/rules/sync-intranet.sh                  # 默认推 $VPS_IP 那一台（向后兼容）
#   bash scripts/rules/sync-intranet.sh --all-vps        # 推 $VPS_NODES 列表里所有节点
#   bash scripts/rules/sync-intranet.sh --vps name|ip    # 只推某一台（按 name 或 ip 匹配）
#   bash scripts/rules/sync-intranet.sh --dry-run        # 校验 + 打印计划，不真推
#   bash scripts/rules/sync-intranet.sh --continue-on-error  # 多 VPS 时单台失败继续下一台
#
# 流程（每台 VPS 独立执行）：
#   - 本地用 python3 yaml.safe_load 校验一次（共用）
#   - 远端：若已有 intranet.yaml，先复制到 $(dirname REMOTE)/backups/intranet-时间戳.yaml，
#     并只保留最近 5 份 intranet-*.yaml 备份，再 scp 覆盖 REMOTE_FILE
#   - scp 覆盖 VPS 上的 /etc/ace-vpn/intranet.yaml
#   - 远端 curl /healthz（新版）或回退探测 /clash/<token>（旧版无 healthz 时）
#
# 设计原则：
#   - 多 VPS 时**只动 intranet.yaml**，不碰 xray outbounds/routing —— 各 VPS 的
#     warp / 自有出口配置原样保留，互不干扰。
#   - 任何一台失败默认 fail-fast；带 --continue-on-error 时跳到下一台，最后
#     汇总成败。
#   - --dry-run 只校验本地 + 解析节点列表，不发任何远端命令。
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
LOCAL_FILE=${LOCAL_INTRANET_FILE:-"$ROOT_DIR/private/intranet.yaml"}
REMOTE_FILE=${REMOTE_INTRANET_FILE:-"/etc/ace-vpn/intranet.yaml"}
SUB_PORT=${SUB_PORT_CLASH:-25500}

# 旧版 sub-converter 无 /healthz 时，用此 token 探测 /clash/<token> 是否 200
sub_health_token() {
  if [[ -n "${SUB_HEALTH_TOKEN:-}" ]]; then
    echo "$SUB_HEALTH_TOKEN"
    return
  fi
  if [[ -n "${SUB_TOKEN:-}" ]]; then
    echo "$SUB_TOKEN"
    return
  fi
  if [[ -n "${SUB_TOKENS:-}" ]]; then
    echo "${SUB_TOKENS%%,*}"
    return
  fi
  echo "sub-hxn"
}

color_red=$'\033[31m'; color_grn=$'\033[32m'; color_ylw=$'\033[33m'; color_cyn=$'\033[36m'; color_off=$'\033[0m'
die()  { echo "${color_red}ERROR${color_off} $*" >&2; exit 1; }
info() { echo "${color_grn}→${color_off} $*"; }
warn() { echo "${color_ylw}!${color_off}  $*" >&2; }
hdr()  { echo; echo "${color_cyn}━━━ $* ━━━${color_off}"; }

# ────────── 解析参数 ──────────
MODE="single"           # single | all | one
ONE_TARGET=""
DRY_RUN=0
CONTINUE_ON_ERROR=0
for arg in "$@"; do
  case "$arg" in
    --all-vps|--all)        MODE="all" ;;
    --vps=*)                MODE="one"; ONE_TARGET="${arg#*=}" ;;
    --vps)                  MODE="one"; ONE_TARGET="__NEXT__" ;;
    --dry-run|-n)           DRY_RUN=1 ;;
    --continue-on-error)    CONTINUE_ON_ERROR=1 ;;
    -h|--help)
      sed -n '1,/^set -euo/p' "$0" | sed -n '/^#/p'
      exit 0 ;;
    *)
      if [[ "$ONE_TARGET" == "__NEXT__" ]]; then
        ONE_TARGET="$arg"
      else
        die "未知参数：${arg}（看 --help）"
      fi ;;
  esac
done
[[ "$ONE_TARGET" == "__NEXT__" ]] && die "--vps 后面要跟节点 name 或 ip"

# 自动 source private/env.sh（如果存在且未 source 过）
if [[ -z "${VPS_IP:-}" && -f "$ROOT_DIR/private/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/private/env.sh"
fi

VPS_SSH_USER=${VPS_SSH_USER:-root}

# SSH key 可选；带了就用，没带靠 ssh-agent / 默认 key
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o BatchMode=no -o ConnectTimeout=15)
if [[ -n "${VPS_SSH_KEY:-}" ]]; then
  expanded=${VPS_SSH_KEY/#~/$HOME}
  [[ -f "$expanded" ]] && SSH_OPTS+=(-i "$expanded") || warn "VPS_SSH_KEY=$VPS_SSH_KEY 不存在，尝试默认 key"
fi

[[ -f "$LOCAL_FILE" ]] || die "$LOCAL_FILE not found. 先：cp private/intranet.yaml.example private/intranet.yaml"

# ────────── 本地 YAML 校验（多 VPS 时只校验一次）──────────
hdr "校验本地 YAML：$LOCAL_FILE"
python3 - <<PY
import sys, yaml
try:
    data = yaml.safe_load(open("$LOCAL_FILE")) or {}
except Exception as e:
    print(f"YAML 解析失败：{e}", file=sys.stderr)
    sys.exit(1)
profs = data.get("profiles") or {}
if isinstance(profs, dict):
    enabled = [n for n, p in profs.items() if isinstance(p, dict) and p.get("enabled")]
    total_d = sum(len((p or {}).get("domains") or []) for p in profs.values() if isinstance(p, dict) and p.get("enabled"))
    total_c = sum(len((p or {}).get("cidrs") or []) for p in profs.values() if isinstance(p, dict) and p.get("enabled"))
    print(f"  Profiles: 总 {len(profs)} / 激活 {len(enabled)} → {enabled}")
    print(f"  合计 domains={total_d}, cidrs={total_c}")
else:
    print(f"  扁平格式: domains={len(data.get('domains') or [])}, cidrs={len(data.get('cidrs') or [])}")
PY

# ────────── 解析目标节点列表 ──────────
declare -a TARGETS  # 每项形如 "name|ip"

case "$MODE" in
  single)
    : "${VPS_IP:?VPS_IP not set; run 'source private/env.sh' first}"
    TARGETS=("primary|$VPS_IP")
    ;;
  all)
    [[ -n "${VPS_NODES:-}" ]] || die "--all-vps 但 \$VPS_NODES 没设。在 private/env.sh 加：export VPS_NODES=\"name1:ip1 name2:ip2\""
    for entry in $VPS_NODES; do
      name="${entry%%:*}"
      ip="${entry##*:}"
      [[ -z "$name" || -z "$ip" || "$name" == "$ip" ]] && die "VPS_NODES 格式错：${entry}（要 name:ip）"
      TARGETS+=("$name|$ip")
    done
    ;;
  one)
    # 在 VPS_NODES 里按 name 或 ip 匹配
    if [[ -n "${VPS_NODES:-}" ]]; then
      for entry in $VPS_NODES; do
        name="${entry%%:*}"
        ip="${entry##*:}"
        if [[ "$ONE_TARGET" == "$name" || "$ONE_TARGET" == "$ip" ]]; then
          TARGETS=("$name|$ip")
          break
        fi
      done
    fi
    if [[ ${#TARGETS[@]} -eq 0 ]]; then
      # 退化：直接当 ip 用
      TARGETS=("custom|$ONE_TARGET")
      warn "$ONE_TARGET 不在 \$VPS_NODES 里，按裸 IP 处理"
    fi
    ;;
esac

hdr "目标节点（${#TARGETS[@]} 个）"
for t in "${TARGETS[@]}"; do
  echo "  • ${t%|*}  →  ${t#*|}"
done

if [[ $DRY_RUN -eq 1 ]]; then
  echo
  warn "--dry-run，不实际推送，退出"
  exit 0
fi

# ────────── 推单台的函数（核心逻辑）──────────
push_one() {
  local name=$1 ip=$2
  hdr "[$name] $ip"

  info "ssh 连通性预检"
  if ! ssh "${SSH_OPTS[@]}" -o BatchMode=yes "$VPS_SSH_USER@$ip" 'echo OK' >/dev/null 2>&1; then
    # 不 BatchMode 再试一次（可能是密码）
    if ! ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip" 'echo OK' >/dev/null; then
      warn "[$name] SSH 不通，跳过"
      return 1
    fi
  fi

  info "确保远端目录：$(dirname "$REMOTE_FILE")"
  ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip" \
    "mkdir -p '$(dirname "$REMOTE_FILE")' && chmod 0755 '$(dirname "$REMOTE_FILE")'" \
    || { warn "[$name] mkdir 失败"; return 1; }

  info "远端备份当前规则（保留最近 5 份 intranet-*.yaml）"
  if ! ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip" bash <<EOF
set -euo pipefail
REMOTE_FILE='${REMOTE_FILE}'
BACKUP_DIR="\$(dirname "\$REMOTE_FILE")/backups"
mkdir -p "\$(dirname "\$REMOTE_FILE")"
mkdir -p "\$BACKUP_DIR"
if [[ -f "\$REMOTE_FILE" ]]; then
  cp "\$REMOTE_FILE" "\$BACKUP_DIR/intranet-\$(date +%Y%m%d-%H%M%S).yaml"
fi
# 按修改时间保留最新 5 个，其余删除
ls -1t "\$BACKUP_DIR"/intranet-*.yaml 2>/dev/null | tail -n +6 | xargs -r rm -f || true
EOF
  then
    warn "[$name] 远端备份失败（中止推送以免无回滚点）"
    return 1
  fi

  info "上传到 $VPS_SSH_USER@$ip:$REMOTE_FILE"
  scp "${SSH_OPTS[@]}" "$LOCAL_FILE" "$VPS_SSH_USER@$ip:$REMOTE_FILE" \
    || { warn "[$name] scp 失败"; return 1; }

  info "远端权限 & 自检"
  ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip" "chmod 0644 '$REMOTE_FILE' && ls -l '$REMOTE_FILE'" \
    || { warn "[$name] chmod 失败"; return 1; }

  info "验证 sub-converter（/healthz 或旧版 /clash/<token>）"
  local tok
  tok=$(sub_health_token)
  if curl -fsS --max-time 8 "http://${ip}:${SUB_PORT}/healthz" 2>/dev/null; then
    echo
  else
    local code
    code=$(curl -sS --max-time 15 -o /dev/null -w "%{http_code}" "http://${ip}:${SUB_PORT}/clash/${tok}" 2>/dev/null || echo 000)
    if [[ "$code" == "200" ]]; then
      warn "[$name] 无 /healthz（旧版 sub-converter），但 http://${ip}:${SUB_PORT}/clash/${tok} 返回 200，热加载仍可用"
      warn "  可选：scp scripts/server/sub-converter.py 到 VPS 后 systemctl restart ace-vpn-sub，即获得 /healthz"
    else
      warn "[$name] /healthz 失败且 /clash/${tok} 返回 ${code}（服务或端口 ${SUB_PORT} 异常）"
      warn "  文件已同步，需要时重启：ssh ${VPS_SSH_USER}@${ip} 'systemctl restart ace-vpn-sub'"
    fi
  fi
  echo "  ${color_grn}✓${color_off} [$name] 推送完成"
  return 0
}

# ────────── 逐台推送 ──────────
declare -a OK_LIST FAIL_LIST
for entry in "${TARGETS[@]}"; do
  name="${entry%|*}"
  ip="${entry#*|}"
  if push_one "$name" "$ip"; then
    OK_LIST+=("$name|$ip")
  else
    FAIL_LIST+=("$name|$ip")
    if [[ $CONTINUE_ON_ERROR -eq 0 && ${#TARGETS[@]} -gt 1 ]]; then
      warn "失败 fail-fast 退出（要继续：加 --continue-on-error）"
      break
    fi
  fi
done

# ────────── 汇总 ──────────
hdr "汇总"
for t in "${OK_LIST[@]-}"; do
  [[ -n "$t" ]] && echo "  ${color_grn}✓${color_off} ${t%|*}  ${t#*|}"
done
for t in "${FAIL_LIST[@]-}"; do
  [[ -n "$t" ]] && echo "  ${color_red}✗${color_off} ${t%|*}  ${t#*|}"
done

echo
FAIL_COUNT=0
if declare -p FAIL_LIST >/dev/null 2>&1; then
  FAIL_COUNT=$(printf '%s\n' "${FAIL_LIST[@]-}" | grep -c . || true)
fi
if [[ $FAIL_COUNT -eq 0 ]]; then
  info "✅ 全部同步完成。客户端刷新订阅即可生效（不用重启 VPS 服务）"
  echo "   Mihomo Party / Clash Verge：Profiles 里点该条的刷新按钮"
  echo "   Stash (iOS)：Profiles → 左滑 → Update"
  echo "   Shadowrocket：订阅页下拉刷新"
  exit 0
else
  warn "有 ${FAIL_COUNT} 台失败，见上方"
  exit 1
fi
