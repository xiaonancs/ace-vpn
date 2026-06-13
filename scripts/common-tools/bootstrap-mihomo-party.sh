#!/usr/bin/env bash
# ace-vpn · Mihomo Party cold-start bootstrap for macOS.
#
# Purpose:
#   First install / first import / after VPS IP rotation, the local proxy may not
#   work yet, so Mihomo Party cannot update its remote profile through Clash.
#   This script uses SSH as the out-of-band channel:
#     Mac -> SSH VPS -> curl 127.0.0.1:<sub-converter> -> local profile file
#
# Usage:
#   bash scripts/common-tools/bootstrap-mihomo-party.sh
#   bash scripts/common-tools/bootstrap-mihomo-party.sh --vps vultr --token ace-main
#   bash scripts/common-tools/bootstrap-mihomo-party.sh --replace-current
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"

PARTY_DIR="${MIHOMO_PARTY_DIR:-$HOME/Library/Application Support/mihomo-party}"
PROFILE_NAME="${ACE_BOOTSTRAP_PROFILE_NAME:-ace-vpn}"
ONE_TARGET="${ACE_BOOTSTRAP_VPS:-}"
TOKEN="${ACE_BOOTSTRAP_TOKEN:-}"
PUBLIC_HOST="${ACE_BOOTSTRAP_PUBLIC_HOST:-}"
MAKE_CURRENT=1
REPLACE_CURRENT=0
INSTALL_APP=1
OPEN_APP=1
BATCH_SSH=0
DRY_RUN=0
INSTALL_SSH_KEY=0

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed -n '/^#/p' | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Options:
  --vps name|ip          VPS from private/env.sh VPS_IP_LIST. Default: first entry.
  --token token          SubId / sub-converter token. Default: SUB_ID_SELF, first
                         SUB_TOKENS, or SUB_TOKEN from private/env.sh.
  --name name            Mihomo Party profile name. Default: ace-vpn.
  --replace-current      Reuse the current remote profile id instead of creating
                         or updating by --name.
  --public-host host     Public host written into future Party update URL.
                         Default: SERVER_OVERRIDE from VPS service, else VPS IP.
  --party-dir path       Mihomo Party config dir.
  --no-current           Import but do not switch current profile.
  --no-install-app       Do not try brew install --cask mihomo-party.
  --no-open              Do not open Mihomo Party after import.
  --batch                SSH BatchMode=yes; fail instead of prompting password.
  --dry-run              Fetch and validate YAML, but do not write Party files.
  --install-ssh-key      Run ssh-copy-id first, then retry bootstrap. Requires
                         password login to be temporarily available on the VPS.
  -h, --help             Show this help.
EOF
}

die() {
  log_error "$*"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vps) ONE_TARGET="$2"; shift 2 ;;
    --vps=*) ONE_TARGET="${1#*=}"; shift ;;
    --token) TOKEN="$2"; shift 2 ;;
    --token=*) TOKEN="${1#*=}"; shift ;;
    --name) PROFILE_NAME="$2"; shift 2 ;;
    --name=*) PROFILE_NAME="${1#*=}"; shift ;;
    --replace-current) REPLACE_CURRENT=1; shift ;;
    --public-host) PUBLIC_HOST="$2"; shift 2 ;;
    --public-host=*) PUBLIC_HOST="${1#*=}"; shift ;;
    --party-dir) PARTY_DIR="$2"; shift 2 ;;
    --party-dir=*) PARTY_DIR="${1#*=}"; shift ;;
    --no-current) MAKE_CURRENT=0; shift ;;
    --no-install-app) INSTALL_APP=0; shift ;;
    --no-open) OPEN_APP=0; shift ;;
    --batch) BATCH_SSH=1; shift ;;
    --dry-run) DRY_RUN=1; INSTALL_APP=0; OPEN_APP=0; shift ;;
    --install-ssh-key) INSTALL_SSH_KEY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1（--help 查用法）" ;;
  esac
done

if [[ -f "$ROOT_DIR/private/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/private/env.sh"
fi

VPS_SSH_USER=${VPS_SSH_USER:-root}
SUB_PORT_CLASH=${SUB_PORT_CLASH:-25500}
SUB_PATH_PREFIX=${SUB_PATH_PREFIX:-clash}

pick_first_token() {
  if [[ -n "${SUB_ID_SELF:-}" ]]; then
    printf '%s\n' "$SUB_ID_SELF"
    return 0
  fi
  if [[ -n "${SUB_TOKENS:-}" ]]; then
    printf '%s\n' "${SUB_TOKENS%%,*}" | xargs
    return 0
  fi
  if [[ -n "${SUB_TOKEN:-}" ]]; then
    printf '%s\n' "$SUB_TOKEN"
    return 0
  fi
  return 1
}

pick_target() {
  local entry name ip
  if [[ -z "${VPS_IP_LIST:-}" ]]; then
    [[ -n "$ONE_TARGET" ]] || die "VPS_IP_LIST 为空；请先配置 private/env.sh，或用 --vps <ip>"
    printf 'custom|%s\n' "$ONE_TARGET"
    return 0
  fi

  if [[ -z "$ONE_TARGET" ]]; then
    entry=${VPS_IP_LIST%% *}
    if [[ "$entry" == *:* ]]; then
      name="${entry%%:*}"
      ip="${entry##*:}"
    else
      name="vps"
      ip="$entry"
    fi
    printf '%s|%s\n' "$name" "$ip"
    return 0
  fi

  for entry in $VPS_IP_LIST; do
    if [[ "$entry" == *:* ]]; then
      name="${entry%%:*}"
      ip="${entry##*:}"
    else
      name="vps"
      ip="$entry"
    fi
    if [[ "$ONE_TARGET" == "$name" || "$ONE_TARGET" == "$ip" ]]; then
      printf '%s|%s\n' "$name" "$ip"
      return 0
    fi
  done

  printf 'custom|%s\n' "$ONE_TARGET"
}

if [[ -z "$TOKEN" ]]; then
  TOKEN=$(pick_first_token || true)
fi
[[ -n "$TOKEN" ]] || die "找不到 token；请在 private/env.sh 设置 SUB_ID_SELF/SUB_TOKENS，或传 --token"

TARGET=$(pick_target)
TARGET_NAME="${TARGET%%|*}"
TARGET_IP="${TARGET##*|}"
[[ -n "$TARGET_IP" ]] || die "无法解析 VPS IP"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
if [[ "$BATCH_SSH" -eq 1 ]]; then
  SSH_OPTS+=(-o BatchMode=yes)
fi
if [[ -n "${VPS_SSH_KEY:-}" ]]; then
  expanded=${VPS_SSH_KEY/#~/$HOME}
  if [[ -f "$expanded" ]]; then
    SSH_OPTS+=(-i "$expanded")
  else
    log_warn "VPS_SSH_KEY=$VPS_SSH_KEY 不存在，改用 ssh 默认 key / agent / 密码"
  fi
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}
require_cmd ssh
require_cmd python3
require_cmd curl

python3 - <<'PY' >/dev/null 2>&1 || die "python3 缺少 PyYAML；本仓库脚本需要 import yaml"
import yaml  # noqa: F401
PY

if [[ "$INSTALL_SSH_KEY" -eq 1 ]]; then
  require_cmd ssh-copy-id
  [[ "$BATCH_SSH" -eq 0 ]] || die "--install-ssh-key 需要交互输入密码，不能和 --batch 一起用"
  pub_key=""
  if [[ -n "${VPS_SSH_KEY:-}" ]]; then
    expanded_key=${VPS_SSH_KEY/#~/$HOME}
    [[ -f "${expanded_key}.pub" ]] && pub_key="${expanded_key}.pub"
  fi
  if [[ -z "$pub_key" ]]; then
    for cand in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub" "$HOME/.ssh/id_ecdsa.pub"; do
      [[ -f "$cand" ]] && { pub_key="$cand"; break; }
    done
  fi
  [[ -n "$pub_key" ]] || die "找不到本机公钥；先运行 ssh-keygen -t ed25519 -C ace-vpn"

  log_step "安装本机 SSH 公钥到 VPS"
  ssh-copy-id -o StrictHostKeyChecking=accept-new -i "$pub_key" "${VPS_SSH_USER}@${TARGET_IP}"
fi

if [[ "$INSTALL_APP" -eq 1 && ! -d "/Applications/Mihomo Party.app" ]]; then
  if command -v brew >/dev/null 2>&1; then
    log_step "安装 Mihomo Party（如 Homebrew/GitHub 被墙，失败后仍会继续导入配置）"
    if ! brew install --cask mihomo-party; then
      log_warn "Mihomo Party 自动安装失败；可稍后手动安装，已继续写入配置文件"
    fi
  else
    log_warn "未检测到 Homebrew；跳过 App 安装，仅写入 Mihomo Party 配置目录"
  fi
fi

log_step "通过 SSH 读取 VPS sub-converter 运行参数"
SSH_CHECK_OUTPUT=$(ssh "${SSH_OPTS[@]}" "${VPS_SSH_USER}@${TARGET_IP}" 'echo OK' 2>&1 || true)
if ! grep -q '^OK$' <<<"$SSH_CHECK_OUTPUT"; then
  if grep -q 'REMOTE HOST IDENTIFICATION HAS CHANGED' <<<"$SSH_CHECK_OUTPUT"; then
    die "SSH host key 冲突：请先确认 ${TARGET_IP} 确实是你的 VPS，再运行 ssh-keygen -R ${TARGET_IP} 后重试"
  fi
  if grep -qiE 'Permission denied|publickey|password' <<<"$SSH_CHECK_OUTPUT"; then
    pub_hint="${VPS_SSH_KEY:-$HOME/.ssh/id_ed25519}"
    pub_hint="${pub_hint/#~/$HOME}"
    die "SSH 登录被拒：当前公钥未被 ${TARGET_IP} 授权。若你有 root 密码，运行：ssh-copy-id -i ${pub_hint}.pub ${VPS_SSH_USER}@${TARGET_IP}；或直接重跑本脚本加 --install-ssh-key"
  fi
  echo "$SSH_CHECK_OUTPUT" | tail -5 >&2
  die "SSH 到 ${VPS_SSH_USER}@${TARGET_IP} 失败；这条冷启动链路只依赖 SSH，请先确认公司 VPN/防火墙没有拦 SSH"
fi

REMOTE_ENV=$(ssh "${SSH_OPTS[@]}" "${VPS_SSH_USER}@${TARGET_IP}" \
  "systemctl show -p Environment --value ace-vpn-sub.service 2>/dev/null || true")

env_get() {
  local key=$1
  printf '%s\n' "$REMOTE_ENV" | tr ' ' '\n' | awk -F= -v k="$key" '$1 == k {sub(/^[^=]*=/, ""); print}' | tail -1
}

REMOTE_PORT=$(env_get LISTEN_PORT)
REMOTE_PREFIX=$(env_get SUB_PATH_PREFIX)
REMOTE_TOKENS=$(env_get SUB_TOKENS)
REMOTE_SERVER=$(env_get SERVER_OVERRIDE)
REMOTE_PORT=${REMOTE_PORT:-$SUB_PORT_CLASH}
REMOTE_PREFIX=${REMOTE_PREFIX:-$SUB_PATH_PREFIX}
REMOTE_PREFIX=${REMOTE_PREFIX#/}
REMOTE_PREFIX=${REMOTE_PREFIX%/}
[[ -n "$REMOTE_PREFIX" ]] || REMOTE_PREFIX="clash"
PUBLIC_HOST=${PUBLIC_HOST:-${REMOTE_SERVER:-$TARGET_IP}}

if [[ -n "$REMOTE_TOKENS" ]]; then
  if ! printf ',%s,' "$REMOTE_TOKENS" | grep -Fq ",$TOKEN,"; then
    log_warn "当前 token 不在远端 SUB_TOKENS 白名单里；仍会尝试拉取，失败就换 --token"
  fi
fi

TMP_YAML=$(mktemp "${TMPDIR:-/tmp}/ace-vpn-bootstrap.XXXXXX.yaml")
trap 'rm -f "$TMP_YAML"' EXIT

REMOTE_LOCAL_URL="http://127.0.0.1:${REMOTE_PORT}/${REMOTE_PREFIX}/${TOKEN}?tun=1"
PUBLIC_URL="http://${PUBLIC_HOST}:${REMOTE_PORT}/${REMOTE_PREFIX}/${TOKEN}"

log_step "通过 SSH 从 VPS localhost 拉取 Clash YAML"
ssh "${SSH_OPTS[@]}" "${VPS_SSH_USER}@${TARGET_IP}" \
  "curl -fsS --max-time 20 '$REMOTE_LOCAL_URL'" >"$TMP_YAML"

if ! grep -q '^proxies:' "$TMP_YAML" || ! grep -q '^- name:' "$TMP_YAML"; then
  die "拉到的内容不像 Clash YAML；请检查 token / sub-converter / 3x-ui SubId"
fi

if [[ -x "$ROOT_DIR/scripts/server/validate-config.py" ]]; then
  log_step "校验 Clash YAML"
  python3 "$ROOT_DIR/scripts/server/validate-config.py" "$TMP_YAML" >/dev/null
  log_ok "YAML 语义校验通过"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  log_ok "dry-run 完成：已通过 SSH 拉取并校验配置，未写入 Mihomo Party"
  echo "  将写入的 Party 更新 URL: ${PUBLIC_URL}"
  exit 0
fi

log_step "写入 Mihomo Party profile"
IMPORT_RESULT=$(python3 - "$PARTY_DIR" "$PROFILE_NAME" "$PUBLIC_URL" "$TMP_YAML" "$MAKE_CURRENT" "$REPLACE_CURRENT" <<'PY'
import secrets
import shutil
import sys
import time
from pathlib import Path

import yaml

party_dir = Path(sys.argv[1]).expanduser()
profile_name = sys.argv[2]
profile_url = sys.argv[3]
yaml_file = Path(sys.argv[4])
make_current = sys.argv[5] == "1"
replace_current = sys.argv[6] == "1"

profile_dir = party_dir / "profiles"
profile_file = party_dir / "profile.yaml"
profile_dir.mkdir(parents=True, exist_ok=True)

backup_dir = profile_dir / (".ace-vpn-bootstrap-backup-" + time.strftime("%Y%m%d-%H%M%S"))
backup_dir.mkdir(parents=True, exist_ok=True)
if profile_file.exists():
    shutil.copy2(profile_file, backup_dir / "profile.yaml")

if profile_file.exists():
    data = yaml.safe_load(profile_file.read_text()) or {}
else:
    data = {}
items = data.get("items")
if not isinstance(items, list):
    items = []
    data["items"] = items

current_id = data.get("current")
item = None

if replace_current and current_id:
    for cand in items:
        if cand.get("id") == current_id and cand.get("type") == "remote":
            item = cand
            break

if item is None:
    for cand in items:
        if cand.get("name") == profile_name and cand.get("type") == "remote":
            item = cand
            break

created = False
if item is None:
    existing_ids = {str(cand.get("id")) for cand in items}
    profile_id = secrets.token_hex(6)[:11]
    while profile_id in existing_ids:
        profile_id = secrets.token_hex(6)[:11]
    item = {"id": profile_id, "name": profile_name, "type": "remote"}
    items.append(item)
    created = True

profile_id = str(item["id"])
old_profile = profile_dir / f"{profile_id}.yaml"
if old_profile.exists():
    shutil.copy2(old_profile, backup_dir / old_profile.name)

item["type"] = "remote"
item["name"] = item.get("name") or profile_name
if not replace_current:
    item["name"] = profile_name
item["url"] = profile_url
item["interval"] = int(item.get("interval") or 1440)
item["useProxy"] = False
item["updated"] = int(time.time() * 1000)
if make_current:
    data["current"] = profile_id

shutil.copy2(yaml_file, old_profile)
profile_file.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=True))

print(f"profile_id={profile_id}")
print(f"profile_name={item['name']}")
print(f"created={str(created).lower()}")
print(f"backup_dir={backup_dir}")
PY
)

printf '%s\n' "$IMPORT_RESULT" | sed 's/^/  /'

CONFIG_FILE="$PARTY_DIR/config.yaml"
if [[ -f "$CONFIG_FILE" ]]; then
  python3 - "$CONFIG_FILE" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
text = p.read_text()
orig = text

def set_bool(src: str, key: str, value: str) -> str:
    pat = rf"^{re.escape(key)}:\s*(true|false)\s*$"
    repl = f"{key}: {value}"
    if re.search(pat, src, flags=re.M):
        return re.sub(pat, repl, src, count=1, flags=re.M)
    return src + ("\n" if not src.endswith("\n") else "") + repl + "\n"

text = set_bool(text, "controlDns", "false")
text = set_bool(text, "useNameserverPolicy", "true")
if text != orig:
    p.write_text(text)
    print(f"  patched {p}")
PY
fi

if [[ "$OPEN_APP" -eq 1 ]]; then
  open -a "Mihomo Party" >/dev/null 2>&1 || log_warn "无法自动打开 Mihomo Party；手动打开即可"
fi

log_ok "冷启动导入完成"
echo "  未来 Party 更新 URL: ${PUBLIC_URL}"
echo "  如果 Mihomo Party 已经在运行，请 Cmd+Q 完全退出后重开一次，让它读取新的 current profile。"
