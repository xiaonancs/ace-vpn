#!/usr/bin/env bash
# 加一条规则到本地池 + 自动应用到 Mihomo Party。
#
# 用法：
#   bash scripts/add-rule.sh <URL_OR_HOST> <TARGET> [NOTE]
#
# 示例：
#   bash scripts/add-rule.sh https://gitlab.corp-a.example/  IN      "内网 GitLab"
#   bash scripts/add-rule.sh some-cn-tool.com               DIRECT  "国内站被误判走代理"
#   bash scripts/add-rule.sh https://claude-foo.example     VPS     "新 AI（走 VPS 出去）"
#
# TARGET（大小写无关；老名 intranet/cn/overseas 也兼容）：
#   IN      → 公司内网 DIRECT + 走内网 DNS（fake-ip-filter + nameserver-policy）
#   DIRECT  → 普通直连（走系统/公网 DNS；用于修正国内站被误判）
#   VPS     → 走 VPS 代理出去（🚀 节点选择；用于新 AI / 新海外站）
#
# 行为：
#   1. 解析 URL 拿 host（去 protocol / port / path / 通配前缀）
#   2. 写入 private/local-rules.yaml（同 host 已存在则更新 target）
#   3. 自动调 apply-local-overrides.sh：渲染 override + 触发 Mihomo reload
#   4. 几秒内本机生效，VPS 不变（积累后用 promote-to-vps.sh 推 VPS）
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

color_red=$'\033[31m'; color_grn=$'\033[32m'; color_off=$'\033[0m'
die()  { echo "${color_red}ERROR${color_off} $*" >&2; exit 1; }
info() { echo "${color_grn}→${color_off} $*"; }

if [[ $# -lt 2 ]]; then
  die "用法: $0 <URL_OR_HOST> <IN|DIRECT|VPS> [NOTE]"
fi

INPUT=$1
TARGET=$2
NOTE=${3:-}

# 这里只做大小写归一；老名 intranet/cn/overseas 由 Python 层 normalize 接住
TARGET_UC=$(echo "$TARGET" | tr '[:lower:]' '[:upper:]')

PYTHONPATH="$SCRIPT_DIR" python3 - "$INPUT" "$TARGET" "$NOTE" <<'PY' || die "加规则失败"
import sys
import urllib.parse
from lib import local_rules as lr

raw, target, note = sys.argv[1], sys.argv[2], sys.argv[3]

# 解析 host：支持完整 URL（https://foo.com/path）/ 裸域 / 带通配 (*.foo.com)
host = raw.strip()
if "://" not in host:
    host = "scheme://" + host
parsed = urllib.parse.urlparse(host)
host = (parsed.hostname or "").lower()
if not host:
    print(f"无法从 '{raw}' 解析出 host", file=sys.stderr)
    sys.exit(1)

# 去通配前缀（*.foo.com → foo.com，因为 DOMAIN-SUFFIX 自动覆盖所有子域）
host = host.lstrip("*.").lstrip(".")

added, msg = lr.add_rule(host, target, note)
status = "✅" if added else "ℹ"
print(f"  {status} {msg}")
if note:
    print(f"     备注: {note}")
PY

echo
info "本地池已更新，开始应用到 Mihomo Party..."
bash "$SCRIPT_DIR/apply-local-overrides.sh"
