#!/usr/bin/env bash
# 把 scripts/git-hooks/pre-commit 装到 .git/hooks/pre-commit
#
# 用法：从 repo 根目录运行
#   bash scripts/git-hooks/install.sh
#
# 新机器 clone 后跑一次即可；之后每次改 hook 内容不需要重跑
# （因为 .git/hooks/pre-commit 是软链，跟着源文件走）。

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SRC="$REPO_ROOT/scripts/git-hooks/pre-commit"
DST="$REPO_ROOT/.git/hooks/pre-commit"

if [ ! -f "$SRC" ]; then
  echo "源文件不存在：$SRC" >&2
  exit 1
fi

chmod +x "$SRC"

# 备份已有 hook（如果不是我们装的）
if [ -e "$DST" ] && [ ! -L "$DST" ]; then
  backup="$DST.backup.$(date +%Y%m%d%H%M%S)"
  echo "检测到已有 pre-commit，备份为：$backup"
  mv "$DST" "$backup"
fi

ln -sf "$SRC" "$DST"
echo "pre-commit hook 安装完成："
echo "  $DST -> $SRC"
echo ""
echo "自检："
if "$DST" >/dev/null 2>&1; then
  echo "  hook 可执行，当前 user.email 通过检查"
else
  echo "  hook 可执行，但当前 user.email 没通过检查（先跑下面两行修正）："
  echo "    git config user.email xiaonan.cs@gmail.com"
  echo "    git config user.name  hexiaonan"
fi
