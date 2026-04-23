#!/usr/bin/env bash
# 加一条规则到本地池 + 自动应用到 Mihomo Party。
#
# 用法：
#   bash scripts/add-rule.sh <URL_OR_HOST> <TARGET> [HOST_OVERRIDE] [--note "备注"]
#
# 三种典型用法：
#
#   1) 最常见：传 URL，自动解析 host
#        bash scripts/add-rule.sh https://gitlab.corp-a.example/  IN
#
#   2) 直接传裸 host（最干净；想加宽到 *.foo.com 段时推荐）
#        bash scripts/add-rule.sh api.corp-a.example  IN
#
#   3) 传 URL + 自定义 HOST：丢一长串 URL 进来，但用第 3 个参数手动指定
#      最终落到规则里的 host，覆盖自动解析结果。适合"懒得手敲域名但又想
#      加宽匹配范围"的场景。
#        bash scripts/add-rule.sh https://aaa.bbb.api.corp-a.example/x.dmg  IN  api.corp-a.example
#                                  └─ 只用来读，不写规则     └─ 真正写到 yaml 里的 host
#
# 备注用 --note 选填（可在任意位置）：
#   bash scripts/add-rule.sh https://gitlab.corp-a.example/ IN --note "内网 GitLab"
#   bash scripts/add-rule.sh https://aaa.api.corp-a.example/x IN api.corp-a.example --note "公司 API（含所有 region）"
#
# TARGET（大小写无关；老名 intranet/cn/overseas 也兼容）：
#   IN      → 公司内网 DIRECT + 走内网 DNS（fake-ip-filter + nameserver-policy）
#   DIRECT  → 普通直连（走系统/公网 DNS；用于修正国内站被误判）
#   VPS     → 走 VPS 代理出去（🚀 PROXY；用于新 AI / 新海外站）
#
# 行为：
#   1. 解析 URL 拿 host（去 protocol / port / path / 通配前缀）
#      如果传了 HOST_OVERRIDE，跳过自动解析，直接用它
#   2. 写入 private/local-rules.yaml（同 host 已存在则更新 target）
#   3. 自动调 apply-local-overrides.sh：渲染 override + 触发 Mihomo reload
#   4. 几秒内本机生效，VPS 不变（积累后用 promote-to-vps.sh 推 VPS）
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

color_red=$'\033[31m'; color_grn=$'\033[32m'; color_off=$'\033[0m'
die()  { echo "${color_red}ERROR${color_off} $*" >&2; exit 1; }
info() { echo "${color_grn}→${color_off} $*"; }

# 解析参数：支持 --note "..." 在任意位置，剩下按顺序为 URL TARGET [HOST_OVERRIDE]
NOTE=""
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --note)      NOTE=${2:-}; shift 2 ;;
    --note=*)    NOTE=${1#--note=}; shift ;;
    -h|--help)
      grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    --) shift; while [[ $# -gt 0 ]]; do POSITIONAL+=("$1"); shift; done ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

if [[ ${#POSITIONAL[@]} -lt 2 ]]; then
  die "用法: $0 <URL_OR_HOST> <IN|DIRECT|VPS> [HOST_OVERRIDE] [--note \"备注\"]"
fi

INPUT=${POSITIONAL[0]}
TARGET=${POSITIONAL[1]}
HOST_OVERRIDE=${POSITIONAL[2]:-}

PYTHONPATH="$SCRIPT_DIR" python3 - "$INPUT" "$TARGET" "$HOST_OVERRIDE" "$NOTE" <<'PY' || die "加规则失败"
import sys
import urllib.parse
from lib import local_rules as lr

raw, target, host_override, note = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
raw_was_url = "://" in raw
host_override = (host_override or "").strip()

if host_override:
    # 用户显式指定了 host：拿来当裸 host 处理（容许带 protocol，做一次清理）
    h = host_override
    if "://" in h:
        h = (urllib.parse.urlparse(h).hostname or "").lower()
    host = h.lstrip("*.").lstrip(".").lower()
    if not host:
        print(f"HOST_OVERRIDE 无法解析为合法 host：'{host_override}'", file=sys.stderr)
        sys.exit(1)
else:
    host = raw.strip()
    if "://" not in host:
        host = "scheme://" + host
    parsed = urllib.parse.urlparse(host)
    host = (parsed.hostname or "").lower()
    if not host:
        print(f"无法从 '{raw}' 解析出 host", file=sys.stderr)
        sys.exit(1)
    host = host.lstrip("*.").lstrip(".")

added, msg = lr.add_rule(host, target, note)
status = "✅" if added else "ℹ"
print(f"  {status} {msg}")
if host_override:
    print(f"     ↳ 自定义 host（覆盖了从 URL 解析的结果）")
if note:
    print(f"     备注: {note}")

# 仅当 (a) 输入的是完整 URL，(b) 没用 HOST_OVERRIDE，(c) host 段数 ≥ 3 时
# 提示一段加宽匹配的建议。用户已经主动指定 host_override 就别噪音了。
parts = host.split(".")
if raw_was_url and not host_override and len(parts) >= 3:
    suggested_n1 = ".".join(parts[1:])     # 去掉最左一段
    suggested_sld = ".".join(parts[-2:])   # 只保留最右两段
    print()
    print(f"💡 当前规则按 DOMAIN-SUFFIX 只匹配 *.{host}（精确这条后缀）")
    print(f"   想加宽？两种办法：")
    print(f"   A) 下次直接传裸 host：")
    print(f"        bash scripts/add-rule.sh {suggested_n1:<33} {target}   # 覆盖 *.{suggested_n1}")
    if suggested_sld != suggested_n1:
        print(f"        bash scripts/add-rule.sh {suggested_sld:<33} {target}   # 覆盖整个 SLD")
    print(f"   B) 保留长 URL 不动，第 3 个参数手动指定要的 host：")
    print(f"        bash scripts/add-rule.sh '{raw}' {target} {suggested_n1}")
PY

echo
info "本地池已更新，开始应用到 Mihomo Party..."
bash "$SCRIPT_DIR/apply-local-overrides.sh"
