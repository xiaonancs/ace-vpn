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
raw_was_url = "://" in raw

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

# 当输入是完整 URL 且 host 段数 >= 3 时，提示一下"想加宽匹配可以这样"
parts = host.split(".")
if raw_was_url and len(parts) >= 3:
    suggested_n1 = ".".join(parts[1:])     # 去掉最左一段
    suggested_sld = ".".join(parts[-2:])   # 只保留最右两段
    print()
    print(f"💡 当前规则按 DOMAIN-SUFFIX 只匹配 *.{host}（精确这条后缀）")
    print(f"   如果想覆盖更宽的范围，下次直接传裸 host：")
    print(f"     bash scripts/add-rule.sh {suggested_n1:<35} {target}   # 覆盖 *.{suggested_n1}")
    if suggested_sld != suggested_n1:
        print(f"     bash scripts/add-rule.sh {suggested_sld:<35} {target}   # 覆盖整个 SLD（更宽）")
    print(f"   想改这次的：编辑 private/local-rules.yaml 的 host 字段 → bash scripts/apply-local-overrides.sh")
PY

echo
info "本地池已更新，开始应用到 Mihomo Party..."
bash "$SCRIPT_DIR/apply-local-overrides.sh"
