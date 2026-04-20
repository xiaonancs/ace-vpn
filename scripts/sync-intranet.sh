#!/usr/bin/env bash
# 把本地 private/intranet.yaml 同步到 VPS（热加载，不用重启 systemd）
#
# 前置：
#   1. source private/env.sh       # 导出 $VPS_IP / $VPS_SSH_USER / $VPS_SSH_KEY
#   2. private/intranet.yaml 存在（从 intranet.yaml.example 复制并编辑）
#
# 流程：
#   - 本地用 python3 yaml.safe_load 校验语法
#   - scp 覆盖 VPS 上的 /etc/ace-vpn/intranet.yaml
#   - 远端 curl /healthz 打印当前生效的 profile
#
# 客户端（Mac/iPhone/Windows/Android）只要下次订阅刷新即生效。
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
LOCAL_FILE=${LOCAL_INTRANET_FILE:-"$ROOT_DIR/private/intranet.yaml"}
REMOTE_FILE=${REMOTE_INTRANET_FILE:-"/etc/ace-vpn/intranet.yaml"}
SUB_PORT=${SUB_PORT_CLASH:-25500}

color_red=$'\033[31m'; color_grn=$'\033[32m'; color_ylw=$'\033[33m'; color_off=$'\033[0m'
die()  { echo "${color_red}ERROR${color_off} $*" >&2; exit 1; }
info() { echo "${color_grn}→${color_off} $*"; }
warn() { echo "${color_ylw}!${color_off}  $*" >&2; }

# 自动 source private/env.sh（如果存在且未 source 过）
if [[ -z "${VPS_IP:-}" && -f "$ROOT_DIR/private/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/private/env.sh"
fi

: "${VPS_IP:?VPS_IP not set; run 'source private/env.sh' first}"
VPS_SSH_USER=${VPS_SSH_USER:-root}

# SSH key 可选；带了就用，没带靠 ssh-agent / 默认 key
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o BatchMode=no)
if [[ -n "${VPS_SSH_KEY:-}" ]]; then
  expanded=${VPS_SSH_KEY/#~/$HOME}
  [[ -f "$expanded" ]] && SSH_OPTS+=(-i "$expanded") || warn "VPS_SSH_KEY=$VPS_SSH_KEY 不存在，尝试默认 key"
fi

[[ -f "$LOCAL_FILE" ]] || die "$LOCAL_FILE not found. 先：cp private/intranet.yaml.example private/intranet.yaml"

info "校验本地 YAML 语法：$LOCAL_FILE"
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

info "上传到 $VPS_SSH_USER@$VPS_IP:$REMOTE_FILE"
scp "${SSH_OPTS[@]}" "$LOCAL_FILE" "$VPS_SSH_USER@$VPS_IP:$REMOTE_FILE"

info "远端权限 & 自检"
ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$VPS_IP" "chmod 0644 '$REMOTE_FILE' && ls -l '$REMOTE_FILE'"

info "调 /healthz 验证热加载"
if curl -fsS "http://$VPS_IP:$SUB_PORT/healthz" 2>/dev/null; then
  :
else
  warn "/healthz 调用失败（服务未跑或端口未开）；但文件已同步，重启服务即可：ssh $VPS_SSH_USER@$VPS_IP 'systemctl restart ace-vpn-sub'"
fi

echo
info "✅ 同步完成。客户端刷新订阅即可生效（不用重启 VPS 服务）"
echo "   Mihomo Party / Clash Verge：Profiles 里点该条的刷新按钮"
echo "   Stash (iOS)：Profiles → 左滑 → Update"
echo "   Shadowrocket：订阅页下拉刷新"
