#!/usr/bin/env bash
# ace-vpn · VPS 关键状态定期备份（给 migrate-vps.sh --from-backup 用）
#
# 目的：
#   GFW 封 IP 时 SSH 连不上旧机 → 拉不到 x-ui.db / credentials → 客户端 SubId、reality 私钥
#   全部失联 → 只能新建 inbound 让全家换订阅。本脚本每天/每小时拉一份回本机，
#   被封那一刻随时有最近备份可用。
#
# 建议挂在 cron / launchd 每 1-6 小时跑一次。
#
# 用法：
#   bash scripts/test/backup-vps-state.sh                 # 全部 VPS
#   bash scripts/test/backup-vps-state.sh --vps name|ip   # 单台
#   bash scripts/test/backup-vps-state.sh --prune-days 30 # 删 30 天前的备份
#
# 输出：
#   private/migration-backup/<vps_name>/<timestamp>/
#     ├─ x-ui.db
#     ├─ ace-vpn-credentials.txt
#     ├─ ace-vpn-sub.service
#     └─ intranet.yaml  (可选)
#
#   private/ 是 symlink 到 ace-vpn-private/ → 备份自动持久化到 git。
#   建议在 ace-vpn-private 仓库定期 git add + commit，断网时还能恢复。
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)

color_red=$'\033[31m'; color_grn=$'\033[32m'; color_ylw=$'\033[33m'
color_cyn=$'\033[36m'; color_off=$'\033[0m'
die()  { echo "${color_red}ERROR${color_off} $*" >&2; exit 1; }
info() { echo "${color_grn}→${color_off} $*"; }
warn() { echo "${color_ylw}!${color_off}  $*" >&2; }
hdr()  { echo; echo "${color_cyn}━━━ $* ━━━${color_off}"; }

ONE_TARGET=""
PRUNE_DAYS=60
GIT_COMMIT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vps)             ONE_TARGET="$2"; shift 2 ;;
    --vps=*)           ONE_TARGET="${1#*=}"; shift ;;
    --prune-days)      PRUNE_DAYS="$2"; shift 2 ;;
    --prune-days=*)    PRUNE_DAYS="${1#*=}"; shift ;;
    --commit)          GIT_COMMIT=1; shift ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | sed -n '/^#/p' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
done

if [[ -z "${VPS_IP_LIST:-}" && -f "$ROOT_DIR/private/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/private/env.sh"
fi
VPS_SSH_USER=${VPS_SSH_USER:-root}
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes)
if [[ -n "${VPS_SSH_KEY:-}" ]]; then
  expanded=${VPS_SSH_KEY/#~/$HOME}
  [[ -f "$expanded" ]] && SSH_OPTS+=(-i "$expanded")
fi

declare -a TARGETS
if [[ -n "$ONE_TARGET" ]]; then
  for entry in $VPS_IP_LIST; do
    n="${entry%%:*}"; i="${entry##*:}"
    if [[ "$ONE_TARGET" == "$n" || "$ONE_TARGET" == "$i" ]]; then
      TARGETS=("$n|$i"); break
    fi
  done
  [[ ${#TARGETS[@]} -eq 0 ]] && die "$ONE_TARGET 不在 VPS_IP_LIST"
else
  idx=1
  for entry in $VPS_IP_LIST; do
    if [[ "$entry" == *:* ]]; then
      n="${entry%%:*}"; i="${entry##*:}"
    else
      n="vps${idx}"; i="$entry"
    fi
    TARGETS+=("$n|$i"); idx=$((idx + 1))
  done
fi

TS=$(date +%Y%m%d-%H%M%S)
ROOT_BAK="$ROOT_DIR/private/migration-backup"
mkdir -p "$ROOT_BAK"

backup_one() {
  local name=$1 ip=$2
  hdr "$name → $ip"
  local outdir="$ROOT_BAK/$name/$TS"

  if ! ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip" 'echo OK' >/dev/null 2>&1; then
    warn "SSH 不通，跳过 $name（要在还能连时就先备份起来）"
    return 1
  fi

  mkdir -p "$outdir"; chmod 700 "$outdir"

  info "[$name] /etc/x-ui/x-ui.db"
  scp -q "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip:/etc/x-ui/x-ui.db" "$outdir/x-ui.db" \
    || { warn "x-ui.db 拉失败"; return 1; }

  info "[$name] /root/ace-vpn-credentials.txt"
  scp -q "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip:/root/ace-vpn-credentials.txt" \
      "$outdir/ace-vpn-credentials.txt" 2>/dev/null || warn "credentials 拉失败（可能没装 sub）"

  info "[$name] /etc/systemd/system/ace-vpn-sub.service"
  scp -q "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip:/etc/systemd/system/ace-vpn-sub.service" \
      "$outdir/ace-vpn-sub.service" 2>/dev/null || warn "sub.service 拉失败"

  info "[$name] /etc/ace-vpn/intranet.yaml"
  scp -q "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip:/etc/ace-vpn/intranet.yaml" \
      "$outdir/intranet.yaml" 2>/dev/null || true

  echo "  ${color_grn}✓${color_off} $outdir"
  return 0
}

declare -a OK FAIL
for entry in "${TARGETS[@]}"; do
  if backup_one "${entry%|*}" "${entry#*|}"; then
    OK+=("$entry")
  else
    FAIL+=("$entry")
  fi
done

# 清理过期备份（按 mtime）
if [[ "$PRUNE_DAYS" =~ ^[0-9]+$ ]] && (( PRUNE_DAYS > 0 )); then
  info "清理 > ${PRUNE_DAYS} 天的旧备份"
  find "$ROOT_BAK" -mindepth 2 -maxdepth 2 -type d -mtime "+${PRUNE_DAYS}" \
    -exec rm -rf {} + 2>/dev/null || true
fi

# 可选 git commit
if [[ $GIT_COMMIT -eq 1 ]]; then
  PRIV_DIR=$(readlink -f "$ROOT_DIR/private" 2>/dev/null || echo "$ROOT_DIR/private")
  if (cd "$PRIV_DIR" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
    info "git commit + push 备份"
    (cd "$PRIV_DIR" && git add migration-backup/ \
      && git -c commit.gpgsign=false commit -m "chore(backup): vps state $TS" --allow-empty \
      && git push) || warn "git push 失败"
  fi
fi

hdr "汇总"
for t in "${OK[@]-}";   do [[ -n "$t" ]] && echo "  ${color_grn}✓${color_off} ${t%|*}"; done
for t in "${FAIL[@]-}"; do [[ -n "$t" ]] && echo "  ${color_red}✗${color_off} ${t%|*}"; done

if [[ ${#FAIL[@]} -gt 0 ]]; then
  exit 1
fi
