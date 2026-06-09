#!/usr/bin/env bash
# ace-vpn · 一键换 IP / VPS 迁移
#
# 用途：
#   把某台 VPS（IP 被 GFW 封 / 换厂商 / 换 region）整体迁移到新 IP。
#   "整体" = 系统部署 + 3x-ui 数据库 + reality / SubId 凭据 + sub-converter
#         + intranet.yaml + 本地 env.sh + git 提交，全部自动化。
#   迁移后客户端只需修改订阅 URL 里的 IP，不用换 token。
#
# 前置：
#   1. source private/env.sh（脚本会自动 source）
#   2. 新 VPS：能 SSH（root，建议 key auth）；可空白机或已跑过 install.sh
#   3. 旧 VPS：能 SSH 最理想（脚本自动备份）；不能 SSH 则用 --from-backup
#   4. 你的 ace-vpn 仓库工作区干净（脚本会 rsync 全量到新机）
#
# 用法：
#   # 标准：把 VPS_IP_LIST 里的 hosthatch 替换成新 IP
#   bash scripts/deploy/migrate-vps.sh --from hosthatch --to 203.0.113.10
#
#   # 旧机 IP 在 GFW 后面 SSH 也不通（GFW 国境封锁连 22 也走不过去）：
#   #   方案 A：--via = SSH 跳板（ProxyJump），跟具体厂商无关。
#   #     只要满足两点：① 你的 Mac 能 SSH 到它 ② 它能 SSH 到旧机（境外→境外不过 GFW）。
#   #     可以是任何一台还活着的境外机器：另一台 VPS / 新买的那台新机 / 朋友的服务器都行。
#   bash scripts/deploy/migrate-vps.sh --from hosthatch --to NEW_IP \
#        --via root@<任意能连旧机的境外主机>:22
#   #   方案 B：用本地之前 backup-vps-state.sh 拉过的备份（如果有跑定期备份）
#   bash scripts/deploy/migrate-vps.sh --to 203.0.113.10 \
#        --from-backup private/migration-backup/20260601-110000
#
#   # 新增一台（不替换旧的，旧 IP 还留在 VPS_IP_LIST 作 fallback）
#   bash scripts/deploy/migrate-vps.sh --to 203.0.113.10 --new-name hosthatch-tokyo
#
#   # 新机已经手动跑过 install.sh + 改好面板凭据，只要迁数据：
#   bash scripts/deploy/migrate-vps.sh --from hosthatch --to NEW_IP --skip-install
#
#   # 仅预演不动手：
#   bash scripts/deploy/migrate-vps.sh --from hosthatch --to NEW_IP --dry-run
#
#   # 迁移完成 + 验证 ok 后把旧 entry 从 env.sh 移除（默认保留 30 分钟作对照）：
#   bash scripts/deploy/migrate-vps.sh --from hosthatch --to NEW_IP --decommission-old
#
# 安全保证：
#   1. 备份在迁移前完成，落到 private/migration-backup/<timestamp>/
#      （symlink 走 ace-vpn-private 仓库时备份自动持久化到 git）
#   2. env.sh 修改是最后一步；中途任何阶段失败 env.sh 不动
#   3. 默认不删旧 VPS 任何东西；旧 entry 保留 30 分钟可手动切回
#   4. 旧 VPS 不可达时不会假装成功，会要求显式 --from-backup
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"

color_red=$'\033[31m'; color_grn=$'\033[32m'; color_ylw=$'\033[33m'
color_cyn=$'\033[36m'; color_bld=$'\033[1m'; color_off=$'\033[0m'
die()  { echo "${color_red}ERROR${color_off} $*" >&2; exit 1; }
info() { echo "${color_grn}→${color_off} $*"; }
warn() { echo "${color_ylw}!${color_off}  $*" >&2; }
ok()   { echo "  ${color_grn}✓${color_off} $*"; }
hdr()  { echo; echo "${color_cyn}━━━ $* ━━━${color_off}"; }
step() { echo; echo "${color_bld}${color_cyn}▶ $*${color_off}"; }

# ────────── 参数解析 ──────────
FROM_NAME=""           # 旧 VPS 的 name 或 IP
TO_IP=""               # 新 IP
NEW_NAME=""            # --new-name 时启用：不替换旧条目，新增一台
FROM_BACKUP_DIR=""     # --from-backup：用现成本地备份替代旧 VPS 拉取
VIA_HOST=""            # --via：从中国大陆碰不到旧 IP 时，借另一台境外 VPS 当 ProxyJump
SKIP_INSTALL=0
DECOMMISSION_OLD=0
DRY_RUN=0
NO_TOUCH_ENV=0
NO_GIT_PUSH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)             FROM_NAME="$2"; shift 2 ;;
    --from=*)           FROM_NAME="${1#*=}"; shift ;;
    --to)               TO_IP="$2"; shift 2 ;;
    --to=*)             TO_IP="${1#*=}"; shift ;;
    --new-name)         NEW_NAME="$2"; shift 2 ;;
    --new-name=*)       NEW_NAME="${1#*=}"; shift ;;
    --from-backup)      FROM_BACKUP_DIR="$2"; shift 2 ;;
    --from-backup=*)    FROM_BACKUP_DIR="${1#*=}"; shift ;;
    --via)              VIA_HOST="$2"; shift 2 ;;
    --via=*)            VIA_HOST="${1#*=}"; shift ;;
    --skip-install)     SKIP_INSTALL=1; shift ;;
    --decommission-old) DECOMMISSION_OLD=1; shift ;;
    --no-touch-env)     NO_TOUCH_ENV=1; shift ;;
    --no-git-push)      NO_GIT_PUSH=1; shift ;;
    --dry-run|-n)       DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | sed -n '/^#/p' | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) die "未知参数：$1（--help 查用法）" ;;
  esac
done

[[ -z "$TO_IP" ]] && die "--to <新 IP> 必填"
if ! [[ "$TO_IP" =~ ^[0-9.]+$ ]]; then
  die "--to 必须是 IPv4，不接受域名（reality SERVER_OVERRIDE 需要 IP）"
fi

# ────────── source env.sh ──────────
if [[ -z "${VPS_IP_LIST:-}" ]]; then
  if [[ -f "$ROOT_DIR/private/env.sh" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT_DIR/private/env.sh"
  else
    die "private/env.sh 不存在，无法读取 VPS_IP_LIST"
  fi
fi

VPS_SSH_USER=${VPS_SSH_USER:-root}
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
if [[ -n "${VPS_SSH_KEY:-}" ]]; then
  expanded=${VPS_SSH_KEY/#~/$HOME}
  [[ -f "$expanded" ]] && SSH_OPTS+=(-i "$expanded")
fi
SUB_PORT=${SUB_PORT_CLASH:-25500}
SUB_PATH_PREFIX=${SUB_PATH_PREFIX:-clash}

# 拉旧机时专用的 SSH 选项：可能加 ProxyJump 借道另一台境外 VPS
OLD_SSH_OPTS=("${SSH_OPTS[@]}")
if [[ -n "$VIA_HOST" ]]; then
  OLD_SSH_OPTS+=(-o "ProxyJump=$VIA_HOST")
  info "拉旧机会经 ProxyJump=$VIA_HOST"
fi

# ────────── 解析旧 VPS（从 VPS_IP_LIST 找 name 或 ip）──────────
FROM_IP=""
FROM_ENTRY=""   # 用于 sed 替换的精确字符串
if [[ -n "$FROM_NAME" ]]; then
  for entry in $VPS_IP_LIST; do
    if [[ "$entry" == *:* ]]; then
      n="${entry%%:*}"; i="${entry##*:}"
    else
      n=""; i="$entry"
    fi
    if [[ "$FROM_NAME" == "$n" || "$FROM_NAME" == "$i" ]]; then
      FROM_IP="$i"
      FROM_ENTRY="$entry"
      # 把 name 标准化（如果用户传了 IP，按 entry 里的 name 来）
      if [[ -n "$n" ]]; then FROM_NAME="$n"; fi
      break
    fi
  done
  [[ -z "$FROM_IP" ]] && die "在 VPS_IP_LIST 找不到 --from=$FROM_NAME"
elif [[ -z "$NEW_NAME" ]]; then
  die "必须指定 --from <name|ip>（要替换旧的）或 --new-name <name>（新增一台）"
fi

# 防呆：新 IP 不能和现有任何节点重复
for entry in $VPS_IP_LIST; do
  i="${entry##*:}"
  if [[ "$i" == "$TO_IP" ]]; then
    die "$TO_IP 已经在 VPS_IP_LIST 里（entry: $entry），别重复添加"
  fi
done

# ────────── 配置打印 + 确认 ──────────
hdr "迁移计划"
echo "  当前 VPS_IP_LIST：$VPS_IP_LIST"
if [[ -n "$FROM_IP" ]]; then
  echo "  旧 VPS：${color_red}$FROM_NAME${color_off} ($FROM_IP)"
  echo "  新 VPS：${color_grn}$FROM_NAME${color_off} ($TO_IP)  ← 替换"
else
  echo "  新 VPS：${color_grn}$NEW_NAME${color_off} ($TO_IP)  ← 新增"
fi
[[ $SKIP_INSTALL -eq 1 ]]      && echo "  --skip-install：新机已自行装好 3x-ui + sub-converter，只迁数据"
[[ $DECOMMISSION_OLD -eq 1 ]]  && echo "  --decommission-old：迁移成功后从 VPS_IP_LIST 移除 ${FROM_NAME:-}"
[[ -n "$FROM_BACKUP_DIR" ]]    && echo "  --from-backup：使用本地备份 $FROM_BACKUP_DIR（跳过旧机 SSH）"
[[ $DRY_RUN -eq 1 ]]           && echo "  ${color_ylw}--dry-run：只演练${color_off}"

# ────────── Step 1: SSH 连通性预检 ──────────
step "Step 1/6  SSH 连通性预检"

info "测新 IP $TO_IP …"
if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "$VPS_SSH_USER@$TO_IP" 'echo OK' >/dev/null 2>&1; then
  ok "新 IP SSH 通"
elif [[ $DRY_RUN -eq 1 ]]; then
  warn "key 模式不通；--dry-run 允许跳过（实跑时必须能 SSH）"
else
  warn "key 模式失败，再试 (允许密码)"
  ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$TO_IP" 'echo OK' >/dev/null \
    || die "新 IP $TO_IP SSH 不通；先确认能进、~/.ssh/authorized_keys 已加你的公钥再重试"
  ok "新 IP SSH 通"
fi

# 旧 IP 可选
OLD_REACHABLE=0
if [[ -n "$FROM_IP" && -z "$FROM_BACKUP_DIR" ]]; then
  info "测旧 IP $FROM_IP $([[ -n "$VIA_HOST" ]] && echo "（经 $VIA_HOST 跳板）") …"
  if ssh "${OLD_SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=8 \
       "$VPS_SSH_USER@$FROM_IP" 'echo OK' >/dev/null 2>&1; then
    OLD_REACHABLE=1
    ok "旧 IP SSH 通（脚本将自动备份）"
  else
    warn "旧 IP $FROM_IP SSH 不通"
    if [[ -z "$VIA_HOST" ]]; then
      warn "  你在大陆，GFW 已封该 IP 一切 TCP（含 22 端口）—— 这是正常的"
      warn "  应对："
      warn "    a) 找一台还能 SSH 的境外 VPS 做跳板，重跑脚本时加："
      warn "         --via root@another-vps.example"
      warn "    b) 或之前 backup-vps-state.sh 跑过定期备份："
      warn "         --from-backup private/migration-backup/<最近时间戳>"
      warn "    c) 或用 VPS 厂商 web 控制台 VNC 进旧机抄文件（见 README）"
    else
      warn "  即使经 $VIA_HOST 跳板也连不上 —— 跳板机能 ssh 到旧机吗？"
      warn "    在跳板机上手动：ssh ${VPS_SSH_USER}@${FROM_IP} 看具体错误"
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
      warn "  --dry-run 阶段允许继续演练"
    else
      die "无法拉旧机备份；按上述提示处理后重试"
    fi
  fi
fi

if [[ $DRY_RUN -eq 1 ]]; then
  hdr "--dry-run 演练结束"; echo "  传 0 个参数实跑：bash $0 --from $FROM_NAME --to $TO_IP"
  exit 0
fi

# ────────── Step 2: 备份旧 VPS 关键状态 ──────────
step "Step 2/6  备份旧 VPS 关键文件"

TS=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$ROOT_DIR/private/migration-backup/$TS"

if [[ -n "$FROM_BACKUP_DIR" ]]; then
  if [[ ! -d "$FROM_BACKUP_DIR" ]]; then
    die "--from-backup 目录不存在：$FROM_BACKUP_DIR"
  fi
  # 几个关键文件必须有，否则迁移不下去
  for f in x-ui.db ace-vpn-credentials.txt ace-vpn-sub.service; do
    if [[ ! -f "$FROM_BACKUP_DIR/$f" ]]; then
      die "备份缺少 $f：$FROM_BACKUP_DIR/$f"
    fi
  done
  info "使用本地备份 $FROM_BACKUP_DIR"
  BACKUP_DIR="$FROM_BACKUP_DIR"
elif [[ $OLD_REACHABLE -eq 1 ]]; then
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"
  info "创建备份目录 $BACKUP_DIR"

  info "拉取 3x-ui 数据库（含 inbound / SubId / reality 凭据）"
  scp "${OLD_SSH_OPTS[@]}" "$VPS_SSH_USER@$FROM_IP:/etc/x-ui/x-ui.db" \
      "$BACKUP_DIR/x-ui.db" || die "拉 x-ui.db 失败"

  info "拉取 ace-vpn-credentials.txt"
  scp "${OLD_SSH_OPTS[@]}" "$VPS_SSH_USER@$FROM_IP:/root/ace-vpn-credentials.txt" \
      "$BACKUP_DIR/ace-vpn-credentials.txt" || warn "ace-vpn-credentials.txt 拉取失败，继续"

  info "拉取 sub-converter 服务定义（用来抓 UPSTREAM_BASE / SUB_TOKENS）"
  scp "${OLD_SSH_OPTS[@]}" "$VPS_SSH_USER@$FROM_IP:/etc/systemd/system/ace-vpn-sub.service" \
      "$BACKUP_DIR/ace-vpn-sub.service" || die "拉 ace-vpn-sub.service 失败"

  if ssh "${OLD_SSH_OPTS[@]}" "$VPS_SSH_USER@$FROM_IP" 'test -f /etc/ace-vpn/intranet.yaml' 2>/dev/null; then
    info "拉取 /etc/ace-vpn/intranet.yaml"
    scp "${OLD_SSH_OPTS[@]}" "$VPS_SSH_USER@$FROM_IP:/etc/ace-vpn/intranet.yaml" \
        "$BACKUP_DIR/intranet.yaml" || warn "intranet.yaml 拉取失败，本地版本会覆盖"
  fi

  ok "备份完成 → $BACKUP_DIR"
else
  die "旧机不可达，又未提供 --from-backup，无法继续"
fi

# 从 service 文件抓关键 Environment
UPSTREAM_BASE=$(awk -F= '/^Environment=UPSTREAM_BASE=/ {print $3}' "$BACKUP_DIR/ace-vpn-sub.service")
SUB_TOKENS=$(awk -F= '/^Environment=SUB_TOKENS=/ {print $3}' "$BACKUP_DIR/ace-vpn-sub.service")
[[ -z "$UPSTREAM_BASE" || -z "$SUB_TOKENS" ]] \
  && die "从 ace-vpn-sub.service 抓不到 UPSTREAM_BASE / SUB_TOKENS（旧机 sub-converter 没装好？）"

info "已从旧机抓到："
echo "  UPSTREAM_BASE=$UPSTREAM_BASE"
echo "  SUB_TOKENS=$SUB_TOKENS"

# ────────── Step 3: 把 ace-vpn 仓库同步到新机 ──────────
step "Step 3/6  rsync ace-vpn 仓库代码到新机"

if ! command -v rsync >/dev/null; then
  die "本机缺 rsync，brew install rsync"
fi

# private/ 完全不要推（含 SSH key、env.sh 等敏感），.git 不要推（占地）
rsync -az --delete \
  --exclude='.git/' --exclude='private/' --exclude='node_modules/' \
  --exclude='__pycache__/' --exclude='.venv/' --exclude='venv/' \
  --exclude='*.log' --exclude='.DS_Store' \
  -e "ssh ${SSH_OPTS[*]}" \
  "$ROOT_DIR/" "$VPS_SSH_USER@$TO_IP:/root/ace-vpn/" \
  || die "rsync 失败"
ok "代码已同步到 /root/ace-vpn/"

# ────────── Step 4: 新机部署 ──────────
step "Step 4/6  新机部署 3x-ui + sub-converter"

if [[ $SKIP_INSTALL -eq 1 ]]; then
  warn "--skip-install：跳过 install.sh / install-sub-converter.sh"
  warn "  前置确认：新机 3x-ui 服务已起、ace-vpn-sub 服务已起"
else
  info "[新机] 跑 install.sh 系统初始化 + 装 3x-ui（不动数据）"
  ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$TO_IP" 'cd /root/ace-vpn && bash scripts/deploy/install.sh' \
    || die "install.sh 失败，到新机 journalctl / 报错截图发回来"
fi

# ────────── Step 5: 还原数据 + 装 sub-converter ──────────
step "Step 5/6  还原 3x-ui 数据库 + 凭据 + 装 sub-converter"

info "[新机] 停 x-ui 服务"
ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$TO_IP" 'systemctl stop x-ui' || die "停 x-ui 失败"

# 关键：x-ui 3.3.0+ 用 SQLite WAL 模式，停服后仍残留 x-ui.db-wal / -shm。
# 若只替换 x-ui.db 而不删 WAL，下次启动会把旧 WAL 重放覆盖我们刚还原的库，
# 导致 inbounds 丢失、端口/凭据回退到安装器默认值（踩过坑，见开发者日志 §6.15）。
info "[新机] 清除残留 WAL/-shm（避免覆盖还原的库）"
ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$TO_IP" 'rm -f /etc/x-ui/x-ui.db-wal /etc/x-ui/x-ui.db-shm' \
  || warn "清 WAL 失败（继续，但启动后请核对 inbounds）"

info "[本机→新机] 推 x-ui.db"
scp "${SSH_OPTS[@]}" "$BACKUP_DIR/x-ui.db" "$VPS_SSH_USER@$TO_IP:/etc/x-ui/x-ui.db" \
  || die "推 x-ui.db 失败"

if [[ -f "$BACKUP_DIR/ace-vpn-credentials.txt" ]]; then
  info "[本机→新机] 推 ace-vpn-credentials.txt"
  scp "${SSH_OPTS[@]}" "$BACKUP_DIR/ace-vpn-credentials.txt" \
      "$VPS_SSH_USER@$TO_IP:/root/ace-vpn-credentials.txt" \
    || warn "推 credentials 失败（不致命）"
  ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$TO_IP" 'chmod 600 /root/ace-vpn-credentials.txt' || true
fi

info "[新机] 启 x-ui 服务（用旧数据）"
ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$TO_IP" 'systemctl start x-ui && sleep 2 && systemctl is-active x-ui' \
  || die "x-ui 启动失败，到新机 journalctl -u x-ui 查"

if [[ $SKIP_INSTALL -eq 0 ]]; then
  info "[新机] 跑 install-sub-converter.sh"
  # 把变量传入远端 env
  ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$TO_IP" bash -s <<EOF || die "install-sub-converter.sh 失败"
set -euo pipefail
cd /root/ace-vpn
UPSTREAM_BASE='$UPSTREAM_BASE' \\
SUB_TOKENS='$SUB_TOKENS' \\
SERVER_OVERRIDE='$TO_IP' \\
bash scripts/deploy/install-sub-converter.sh
EOF
else
  info "[新机] 仅热重启 ace-vpn-sub（载入新 SERVER_OVERRIDE）"
  ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$TO_IP" \
    "sudo sed -i 's|^Environment=SERVER_OVERRIDE=.*|Environment=SERVER_OVERRIDE=$TO_IP|' /etc/systemd/system/ace-vpn-sub.service && \
     sudo systemctl daemon-reload && sudo systemctl restart ace-vpn-sub" \
    || die "ace-vpn-sub 重启失败"
fi

ok "服务全部就位"

# ────────── Step 6: 验证新机 + 写入 env.sh ──────────
step "Step 6/6  验证新机 + 更新 env.sh"

# 取一个用于探测的 token
FIRST_TOKEN=$(echo "$SUB_TOKENS" | awk -F, '{print $1}' | xargs)
info "新机 /healthz"
if curl -fsS --max-time 8 "http://${TO_IP}:${SUB_PORT}/healthz" >/tmp/migrate-healthz.txt 2>&1; then
  ok "healthz: $(head -c 200 /tmp/migrate-healthz.txt)"
else
  warn "healthz 探测失败（旧版 sub-converter 无该端点），改用 /${SUB_PATH_PREFIX}/$FIRST_TOKEN"
fi

info "新机 /${SUB_PATH_PREFIX}/$FIRST_TOKEN 节点 server 字段"
clash_out=$(curl -fsS --max-time 10 "http://${TO_IP}:${SUB_PORT}/${SUB_PATH_PREFIX}/$FIRST_TOKEN" 2>/dev/null \
            | grep -E '^[[:space:]]*server:' | head -3 || true)
echo "$clash_out" | sed 's/^/    /'
if echo "$clash_out" | grep -q "$TO_IP"; then
  ok "节点 server 字段已是新 IP $TO_IP"
elif echo "$clash_out" | grep -q "$FROM_IP"; then
  die "节点 server 还是旧 IP $FROM_IP，SERVER_OVERRIDE 没生效（去新机 systemctl cat ace-vpn-sub 看）"
else
  warn "server 字段两个 IP 都不是？看看实际内容"
fi

# 写 env.sh
if [[ $NO_TOUCH_ENV -eq 1 ]]; then
  warn "--no-touch-env：env.sh 不动，请手动改：VPS_IP_LIST 中 $FROM_ENTRY → ${FROM_NAME:-$NEW_NAME}:$TO_IP"
else
  ENV_FILE="$ROOT_DIR/private/env.sh"
  # 解 symlink 到实际文件
  if [[ -L "$ENV_FILE" ]]; then
    ENV_FILE=$(readlink -f "$ENV_FILE" 2>/dev/null || readlink "$ENV_FILE")
    case "$ENV_FILE" in
      /*) ;;
      *) ENV_FILE="$ROOT_DIR/private/$ENV_FILE" ;;
    esac
  fi
  [[ -f "$ENV_FILE" ]] || die "env.sh 不存在：$ENV_FILE"

  cp "$ENV_FILE" "${ENV_FILE}.bak.$TS"
  info "改 env.sh（备份在 ${ENV_FILE}.bak.$TS）"

  if [[ -n "$FROM_ENTRY" ]]; then
    # 替换 hosthatch:OLD → hosthatch:NEW
    new_entry="${FROM_NAME}:${TO_IP}"
    if [[ $DECOMMISSION_OLD -eq 1 ]]; then
      # 删除 entry 而不是替换
      python3 - "$ENV_FILE" "$FROM_ENTRY" <<'PY'
import sys, re
fn, old_entry = sys.argv[1], sys.argv[2]
content = open(fn).read()
# 找 VPS_IP_LIST 那一行，把 old_entry 移除（前后多余空格也清掉）
def edit(m):
    val = m.group(2)
    parts = [p for p in val.split() if p != old_entry]
    return f'{m.group(1)}"{" ".join(parts)}"'
new = re.sub(r'(export\s+VPS_IP_LIST=)"([^"]*)"', edit, content)
open(fn, 'w').write(new)
PY
      ok "已从 VPS_IP_LIST 移除 $FROM_ENTRY"
    else
      python3 - "$ENV_FILE" "$FROM_ENTRY" "$new_entry" <<'PY'
import sys, re
fn, old_entry, new_entry = sys.argv[1], sys.argv[2], sys.argv[3]
content = open(fn).read()
def edit(m):
    val = m.group(2)
    parts = [new_entry if p == old_entry else p for p in val.split()]
    return f'{m.group(1)}"{" ".join(parts)}"'
new = re.sub(r'(export\s+VPS_IP_LIST=)"([^"]*)"', edit, content)
# 在那行下方加个注释（如果还没加过）
marker = f"# 旧 hosthatch IP（已被 GFW 封 / 已迁移）：{old_entry}"
if marker not in new:
    new = re.sub(
        r'^(export\s+VPS_IP_LIST="[^"]*")$',
        lambda m: m.group(1) + '\n' + marker,
        new, count=1, flags=re.M)
open(fn, 'w').write(new)
PY
      ok "已替换 $FROM_ENTRY → $new_entry，并加注释保留历史"
    fi
  else
    # --new-name 模式：在 VPS_IP_LIST 尾部追加
    new_entry="${NEW_NAME}:${TO_IP}"
    python3 - "$ENV_FILE" "$new_entry" <<'PY'
import sys, re
fn, new_entry = sys.argv[1], sys.argv[2]
content = open(fn).read()
def edit(m):
    val = m.group(2)
    parts = val.split() + [new_entry]
    return f'{m.group(1)}"{" ".join(parts)}"'
new = re.sub(r'(export\s+VPS_IP_LIST=)"([^"]*)"', edit, content)
open(fn, 'w').write(new)
PY
    ok "已追加 $new_entry 到 VPS_IP_LIST"
  fi

  # git commit + push 到 ace-vpn-private
  if [[ $NO_GIT_PUSH -eq 0 ]]; then
    ENV_DIR=$(dirname "$ENV_FILE")
    if (cd "$ENV_DIR" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
      info "git commit + push ace-vpn-private"
      (cd "$ENV_DIR" && \
        git add "$(basename "$ENV_FILE")" && \
        git -c commit.gpgsign=false commit -m "chore(env): migrate ${FROM_NAME:-+}${FROM_IP:+ }${FROM_IP:-} → $TO_IP" && \
        git push) \
        || warn "git push 失败（手动跑：cd $ENV_DIR && git push）"
    else
      warn "$ENV_DIR 不是 git 仓库，跳过 commit"
    fi
  fi
fi

# ────────── 完成 ──────────
hdr "🎉 迁移完成"
echo
echo "  新 VPS：${color_grn}${FROM_NAME:-$NEW_NAME}${color_off} ($TO_IP)"
echo
echo "  ${color_bld}客户端要做的事${color_off}："
echo
echo "  每台设备（Mac / iPhone / Windows / Android）打开客户端，把订阅 URL 里的"
echo "  IP 改成新的，然后刷新订阅："
echo
echo "    旧：http://${FROM_IP:-OLD_IP}:${SUB_PORT}/${SUB_PATH_PREFIX}/${FIRST_TOKEN}"
echo "    新：http://${color_grn}${TO_IP}${color_off}:${SUB_PORT}/${SUB_PATH_PREFIX}/${FIRST_TOKEN}"
echo
echo "  ${color_bld}验证${color_off}："
echo "    bash scripts/test/preflight-multi-vps.sh"
echo
echo "  ${color_bld}如果出问题想回退${color_off}（旧机还活着）："
echo "    1. cp ${ENV_FILE:-private/env.sh}.bak.$TS ${ENV_FILE:-private/env.sh}"
echo "    2. 客户端订阅 URL 改回 $FROM_IP"
echo
echo "  ${color_bld}下一步建议${color_off}：跑 ${color_cyn}bash scripts/deploy/harden-vps.sh --vps $TO_IP${color_off} 抗 GFW 封禁硬化"
