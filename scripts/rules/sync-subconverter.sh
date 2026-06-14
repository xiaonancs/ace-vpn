#!/usr/bin/env bash
# 把本地 scripts/server/sub-converter.py 同步到 VPS 并重启 ace-vpn-sub
#
# 对称于 sync-intranet.sh，但多一层防线：推前/推后都用 validate-config.py
# 做语义校验，一旦失败自动从最近一次备份回滚，保证"要么更新成功、要么保持
# 可用"。永远不会留下"改坏了但不可恢复"的 VPS。
#
# 前置：
#   1. source private/env.sh
#   2. scripts/server/sub-converter.py 存在（本地版本）
#
# 用法：
#   bash scripts/rules/sync-subconverter.sh                  # 推 VPS_IP_LIST 全部节点
#   bash scripts/rules/sync-subconverter.sh --vps name|ip    # 只推某一台
#   bash scripts/rules/sync-subconverter.sh --dry-run        # 只校验，不推
#   bash scripts/rules/sync-subconverter.sh --continue-on-error  # 多 VPS 单台失败继续
#   bash scripts/rules/sync-subconverter.sh --rollback            # 从最新备份回滚（不推新代码）
#   bash scripts/rules/sync-subconverter.sh --skip-output-check   # 跳过远端 /<SUB_PATH_PREFIX>/<tok> 语义校验
#
# 流程（每台 VPS 独立执行，任何一步失败立刻回滚）：
#   [本地，所有 VPS 共用一次]
#   1. python3 -m py_compile  sub-converter.py          # 语法
#   2. python3 -c 'import + build(dummy) + dump'         # 运行期导入
#   3. python3 validate-config.py  <生成的 yaml>          # 语义（respect-rules 等联动）
#   [远端，每台 VPS]
#   4. ssh 预检
#   5. cp REMOTE_FILE → backups/sub-converter-<ts>.py （保留最近 5 份）
#   6. scp local → REMOTE_FILE.new
#   7. mv -f REMOTE_FILE.new REMOTE_FILE                # 原子替换
#   8. systemctl restart ace-vpn-sub
#   9. systemctl is-active  + curl /healthz
#   10. curl /<SUB_PATH_PREFIX>/<token> → python3 validate-config.py --quiet
#   任一 8-10 失败：cp backups/最新 → REMOTE_FILE + systemctl restart
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
LOCAL_FILE=${LOCAL_SUBCONV_FILE:-"$ROOT_DIR/scripts/server/sub-converter.py"}
VALIDATOR="$ROOT_DIR/scripts/server/validate-config.py"
REMOTE_FILE=${REMOTE_SUBCONV_FILE:-"/opt/ace-vpn-sub/sub-converter.py"}
REMOTE_SVC=${REMOTE_SUBCONV_SVC:-"ace-vpn-sub"}
SUB_PORT=${SUB_PORT_CLASH:-25500}
SUB_PATH_PREFIX=${SUB_PATH_PREFIX:-clash}
BACKUP_KEEP=${SUBCONV_BACKUP_KEEP:-5}

# ────────── token 选择（与 sync-intranet.sh 对齐）──────────
sub_health_token() {
  if [[ -n "${SUB_HEALTH_TOKEN:-}" ]]; then echo "$SUB_HEALTH_TOKEN"; return; fi
  if [[ -n "${SUB_TOKEN:-}" ]]; then echo "$SUB_TOKEN"; return; fi
  if [[ -n "${SUB_TOKENS:-}" ]]; then echo "${SUB_TOKENS%%,*}"; return; fi
  echo "ace-main"
}

color_red=$'\033[31m'; color_grn=$'\033[32m'; color_ylw=$'\033[33m'; color_cyn=$'\033[36m'; color_off=$'\033[0m'
die()  { echo "${color_red}ERROR${color_off} $*" >&2; exit 1; }
info() { echo "${color_grn}→${color_off} $*"; }
warn() { echo "${color_ylw}!${color_off}  $*" >&2; }
hdr()  { echo; echo "${color_cyn}━━━ $* ━━━${color_off}"; }

# ────────── 参数解析 ──────────
MODE="all"              # all | one
ONE_TARGET=""
DRY_RUN=0
CONTINUE_ON_ERROR=0
ROLLBACK_ONLY=0
SKIP_OUTPUT_CHECK=0
for arg in "$@"; do
  case "$arg" in
    --all-vps|--all)        MODE="all" ;;
    --vps=*)                MODE="one"; ONE_TARGET="${arg#*=}" ;;
    --vps)                  MODE="one"; ONE_TARGET="__NEXT__" ;;
    --dry-run|-n)           DRY_RUN=1 ;;
    --continue-on-error)    CONTINUE_ON_ERROR=1 ;;
    --rollback)             ROLLBACK_ONLY=1 ;;
    --skip-output-check)    SKIP_OUTPUT_CHECK=1 ;;
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

# 自动 source private/env.sh
if [[ -z "${VPS_IP_LIST:-}" && -f "$ROOT_DIR/private/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/private/env.sh"
fi

VPS_SSH_USER=${VPS_SSH_USER:-root}
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o BatchMode=no -o ConnectTimeout=15)
if [[ -n "${VPS_SSH_KEY:-}" ]]; then
  expanded=${VPS_SSH_KEY/#~/$HOME}
  [[ -f "$expanded" ]] && SSH_OPTS+=(-i "$expanded") || warn "VPS_SSH_KEY=$VPS_SSH_KEY 不存在，尝试默认 key"
fi

# ────────── 本地预校验（推前，所有 VPS 共用一次）──────────
local_precheck() {
  hdr "本地预校验：$LOCAL_FILE"
  [[ -f "$LOCAL_FILE" ]] || die "$LOCAL_FILE 不存在"

  info "1/3 py_compile（语法）"
  python3 -m py_compile "$LOCAL_FILE" || die "python 语法错误"

  info "2/3 运行期导入 + build_clash_yaml(dummy)"
  local tmp_yaml
  tmp_yaml=$(mktemp -t ace-vpn-sub.XXXXXX.yaml)
  # shellcheck disable=SC2064
  trap "rm -f $tmp_yaml" EXIT
  if ! python3 - "$LOCAL_FILE" "$tmp_yaml" <<'PY'
import sys, os, importlib.util
src, dst = sys.argv[1], sys.argv[2]
os.environ.setdefault("UPSTREAM_SUB", "http://dummy/sub")
os.environ.setdefault("SUB_TOKEN", "dummy")
spec = importlib.util.spec_from_file_location("_sc_dryrun", src)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
# 用最小内网结构，避免依赖线上 intranet.yaml
intranet = {
    "cidrs": ["10.0.0.0/8"],
    "domains": ["example.com"],
    "domain_dns": {},
    "extra_overseas": ["cursor.sh"],
    "extra_cn": ["zoom.us"],
}
proxies = [{"name": "n1", "type": "vless", "server": "1.2.3.4", "port": 443, "uuid": "u1"}]
yaml_str = m.build_clash_yaml(proxies, intranet)
open(dst, "w").write(yaml_str)
print(f"  ✓ 生成 {len(yaml_str)} 字节 YAML", flush=True)
PY
  then
    die "运行期导入/生成失败"
  fi

  info "3/3 validate-config.py（语义联动校验）"
  if ! python3 "$VALIDATOR" "$tmp_yaml"; then
    die "语义校验失败（看上方）；本地修好再推"
  fi

  # 扫一下 local YAML 里的关键字段，显式告诉用户当前版本的 DNS 设置
  python3 -c "
import yaml
cfg = yaml.safe_load(open('$tmp_yaml'))
dns = cfg.get('dns') or {}
print(f'  respect-rules={dns.get(\"respect-rules\")}', end='')
print(f' · proxy-server-nameserver={len(dns.get(\"proxy-server-nameserver\") or [])} entries', end='')
print(f' · sniffer={bool((cfg.get(\"sniffer\") or {}).get(\"enable\"))}')
"
}

# ────────── 解析目标节点列表（和 sync-intranet.sh 一致）──────────
declare -a TARGETS
parse_targets() {
  case "$MODE" in
    all)
      local idx=1
      for entry in $VPS_IP_LIST; do
        if [[ "$entry" == *:* ]]; then name="${entry%%:*}"; ip="${entry##*:}"
        else name="vps${idx}"; ip="$entry"; fi
        [[ -z "$name" || -z "$ip" ]] && die "VPS_IP_LIST 格式错：${entry}"
        TARGETS+=("$name|$ip")
        idx=$((idx + 1))
      done
      ;;
    one)
      if [[ -n "${VPS_IP_LIST:-}" ]]; then
        local idx=1
        for entry in $VPS_IP_LIST; do
          if [[ "$entry" == *:* ]]; then name="${entry%%:*}"; ip="${entry##*:}"
          else name="vps${idx}"; ip="$entry"; fi
          if [[ "$ONE_TARGET" == "$name" || "$ONE_TARGET" == "$ip" ]]; then
            TARGETS=("$name|$ip"); break
          fi
          idx=$((idx + 1))
        done
      fi
      if [[ ${#TARGETS[@]} -eq 0 ]]; then
        TARGETS=("custom|$ONE_TARGET")
        warn "$ONE_TARGET 不在 VPS_IP_LIST 里，当裸 IP 处理"
      fi
      ;;
  esac
}

# ────────── 推单台的函数 ──────────
push_one() {
  local name=$1 ip=$2
  hdr "[$name] $ip"

  info "ssh 连通性预检"
  if ! ssh "${SSH_OPTS[@]}" -o BatchMode=yes "$VPS_SSH_USER@$ip" 'echo OK' >/dev/null 2>&1; then
    if ! ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip" 'echo OK' >/dev/null; then
      warn "[$name] SSH 不通，跳过"
      return 1
    fi
  fi

  # 1. 备份
  info "远端备份当前 sub-converter.py（保留最近 ${BACKUP_KEEP} 份）"
  local backup_ts
  backup_ts=$(date +%Y%m%d-%H%M%S)
  if ! ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip" bash <<EOF
set -euo pipefail
REMOTE_FILE='${REMOTE_FILE}'
BACKUP_DIR="\$(dirname "\$REMOTE_FILE")/backups"
mkdir -p "\$BACKUP_DIR"
if [[ -f "\$REMOTE_FILE" ]]; then
  cp "\$REMOTE_FILE" "\$BACKUP_DIR/sub-converter-${backup_ts}.py"
  echo "  ✓ 备份 → \$BACKUP_DIR/sub-converter-${backup_ts}.py (\$(wc -c < "\$REMOTE_FILE") bytes)"
else
  echo "  ! 远端当前没有 \$REMOTE_FILE，首次部署"
fi
ls -1t "\$BACKUP_DIR"/sub-converter-*.py 2>/dev/null | tail -n +$((BACKUP_KEEP + 1)) | xargs -r rm -f || true
echo "  当前备份数：\$(ls -1 "\$BACKUP_DIR"/sub-converter-*.py 2>/dev/null | wc -l)"
EOF
  then
    warn "[$name] 远端备份失败（中止推送以免无回滚点）"
    return 1
  fi

  # 2. 原子上传
  info "scp 到 ${REMOTE_FILE}.new"
  if ! scp "${SSH_OPTS[@]}" "$LOCAL_FILE" "$VPS_SSH_USER@$ip:${REMOTE_FILE}.new"; then
    warn "[$name] scp 失败"
    return 1
  fi

  info "原子替换 + chmod"
  if ! ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip" \
      "mv -f '${REMOTE_FILE}.new' '${REMOTE_FILE}' && chmod 0755 '${REMOTE_FILE}' && ls -l '${REMOTE_FILE}'"; then
    warn "[$name] mv / chmod 失败"
    ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip" "rm -f '${REMOTE_FILE}.new'" 2>/dev/null || true
    return 1
  fi

  # 3. 重启 + 健康检查
  info "systemctl restart ${REMOTE_SVC}"
  local restart_ok=1
  if ! ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip" \
      "systemctl restart ${REMOTE_SVC} && sleep 2 && systemctl is-active ${REMOTE_SVC}"; then
    warn "[$name] 重启失败（将回滚）"
    restart_ok=0
  fi

  # 4. /healthz（走远端 localhost；公网 /healthz 可保持关闭）
  local health_ok=1
  if [[ $restart_ok -eq 1 ]]; then
    info "curl /healthz"
    local admin_header=""
    [[ -n "${SUB_ADMIN_TOKEN:-}" ]] && admin_header="-H X-Admin-Token:${SUB_ADMIN_TOKEN}"
    if ! ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip" \
        "curl -fsS --max-time 8 ${admin_header} 'http://127.0.0.1:${SUB_PORT}/healthz'" >/dev/null; then
      warn "[$name] /healthz 失败（将回滚）"
      health_ok=0
    fi
  fi

  # 5. 远端生成 YAML 语义校验
  local output_ok=1
  if [[ $restart_ok -eq 1 && $health_ok -eq 1 && $SKIP_OUTPUT_CHECK -eq 0 ]]; then
    local tok
    tok=$(sub_health_token)
    info "curl /${SUB_PATH_PREFIX}/${tok} → 本地 validate-config.py"
    local tmp_out
    tmp_out=$(mktemp -t ace-vpn-sub-out.XXXXXX.yaml)
    if ! curl -fsS --max-time 30 "http://${ip}:${SUB_PORT}/${SUB_PATH_PREFIX}/${tok}" > "$tmp_out"; then
      warn "[$name] 拉取订阅失败"
      output_ok=0
    elif ! python3 "$VALIDATOR" --quiet "$tmp_out"; then
      warn "[$name] 远端生成的 YAML 语义校验失败（将回滚）"
      output_ok=0
    fi
    rm -f "$tmp_out"
  fi

  # 6. rollback（失败才做）
  if [[ $restart_ok -eq 0 || $health_ok -eq 0 || $output_ok -eq 0 ]]; then
    warn "[$name] 触发自动回滚"
    if ! ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip" bash <<EOF
set -euo pipefail
REMOTE_FILE='${REMOTE_FILE}'
BACKUP_DIR="\$(dirname "\$REMOTE_FILE")/backups"
LAST=\$(ls -1t "\$BACKUP_DIR"/sub-converter-*.py 2>/dev/null | head -n1)
if [[ -z "\$LAST" ]]; then
  echo "  ✗ 无备份可回滚（首次部署）"
  exit 1
fi
cp "\$LAST" "\$REMOTE_FILE"
chmod 0755 "\$REMOTE_FILE"
systemctl restart ${REMOTE_SVC}
sleep 2
systemctl is-active ${REMOTE_SVC} || exit 2
echo "  ✓ 从 \$LAST 回滚完成"
EOF
    then
      warn "[$name] ${color_red}回滚也失败！人工介入：ssh ${VPS_SSH_USER}@${ip}${color_off}"
    else
      info "[$name] 已回滚到上一版"
    fi
    return 1
  fi

  echo "  ${color_grn}✓${color_off} [$name] 推送完成"
  return 0
}

# ────────── 单台 rollback（--rollback 模式）──────────
rollback_one() {
  local name=$1 ip=$2
  hdr "[$name] $ip (rollback 模式)"
  if ! ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip" bash <<EOF
set -euo pipefail
REMOTE_FILE='${REMOTE_FILE}'
BACKUP_DIR="\$(dirname "\$REMOTE_FILE")/backups"
echo "  备份列表（新 → 旧，保留 ${BACKUP_KEEP} 份）："
ls -1t "\$BACKUP_DIR"/sub-converter-*.py 2>/dev/null | sed 's|^|    |'
LAST=\$(ls -1t "\$BACKUP_DIR"/sub-converter-*.py 2>/dev/null | head -n1)
if [[ -z "\$LAST" ]]; then
  echo "  ✗ 无备份可回滚"
  exit 1
fi
# 把当前在用的也备份一下，方便以后再回滚
cp "\$REMOTE_FILE" "\$BACKUP_DIR/sub-converter-\$(date +%Y%m%d-%H%M%S).py"
ls -1t "\$BACKUP_DIR"/sub-converter-*.py 2>/dev/null | tail -n +$((BACKUP_KEEP + 1)) | xargs -r rm -f || true
cp "\$LAST" "\$REMOTE_FILE"
chmod 0755 "\$REMOTE_FILE"
systemctl restart ${REMOTE_SVC}
sleep 2
systemctl is-active ${REMOTE_SVC} >/dev/null
echo "  ✓ 从 \$LAST 回滚完成"
EOF
  then
    warn "[$name] 回滚失败"
    return 1
  fi
  info "验证：curl /healthz"
  local admin_header=""
  [[ -n "${SUB_ADMIN_TOKEN:-}" ]] && admin_header="-H X-Admin-Token:${SUB_ADMIN_TOKEN}"
  ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip" \
    "curl -fsS --max-time 8 ${admin_header} 'http://127.0.0.1:${SUB_PORT}/healthz'" | head -5 \
    || warn "[$name] /healthz 异常"
  echo "  ${color_grn}✓${color_off} [$name] 回滚完成"
  return 0
}

# ────────── 主流程 ──────────
parse_targets
hdr "目标节点（${#TARGETS[@]} 个）"
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  warn "VPS_IP_LIST 为空，没有远端 VPS 需要推送。"
  warn "请在 private/env.sh 设置：export VPS_IP_LIST=\"name1:ip1 name2:ip2\""
  exit 0
fi
for t in "${TARGETS[@]}"; do
  echo "  • ${t%|*}  →  ${t#*|}"
done

if [[ $ROLLBACK_ONLY -eq 1 ]]; then
  hdr "rollback-only 模式（不推新代码，从远端最新备份恢复）"
  if [[ $DRY_RUN -eq 1 ]]; then
    warn "--dry-run 下只列出目标，不真做"
    exit 0
  fi
  declare -a OK_LIST FAIL_LIST
  for entry in "${TARGETS[@]}"; do
    if rollback_one "${entry%|*}" "${entry#*|}"; then
      OK_LIST+=("$entry")
    else
      FAIL_LIST+=("$entry")
      [[ $CONTINUE_ON_ERROR -eq 0 && ${#TARGETS[@]} -gt 1 ]] && { warn "fail-fast 退出"; break; }
    fi
  done
else
  local_precheck
  if [[ $DRY_RUN -eq 1 ]]; then
    echo
    warn "--dry-run，本地预校验通过，未推远端"
    exit 0
  fi
  declare -a OK_LIST FAIL_LIST
  for entry in "${TARGETS[@]}"; do
    if push_one "${entry%|*}" "${entry#*|}"; then
      OK_LIST+=("$entry")
    else
      FAIL_LIST+=("$entry")
      [[ $CONTINUE_ON_ERROR -eq 0 && ${#TARGETS[@]} -gt 1 ]] && { warn "fail-fast 退出"; break; }
    fi
  done
fi

# ────────── 汇总 ──────────
hdr "汇总"
for t in "${OK_LIST[@]-}"; do
  [[ -n "$t" ]] && echo "  ${color_grn}✓${color_off} ${t%|*}  ${t#*|}"
done
for t in "${FAIL_LIST[@]-}"; do
  [[ -n "$t" ]] && echo "  ${color_red}✗${color_off} ${t%|*}  ${t#*|}"
done

FAIL_COUNT=0
if declare -p FAIL_LIST >/dev/null 2>&1; then
  FAIL_COUNT=$(printf '%s\n' "${FAIL_LIST[@]-}" | grep -c . || true)
fi
echo
if [[ $FAIL_COUNT -eq 0 ]]; then
  if [[ $ROLLBACK_ONLY -eq 1 ]]; then
    info "✅ 全部回滚完成。客户端刷新订阅即可恢复到上一个可用版本。"
  else
    info "✅ 全部同步完成。客户端刷新订阅即可生效（备份已更新，下次失败可自动回滚）。"
  fi
  exit 0
else
  warn "有 ${FAIL_COUNT} 台失败，见上方（通常已自动回滚，服务仍可用）"
  exit 1
fi
