#!/usr/bin/env bash
# 回家后运行这个脚本：在 ace-vpn 目录里执行
#   chmod +x push-to-github.sh && ./push-to-github.sh
#
# 作用：
#   1. 重新登录 gh CLI（web flow，30 秒）
#   2. 创建 GitHub 私有仓库
#   3. 推送 main 分支
#   4. 设置 upstream tracking

set -e

REPO_NAME="ace-vpn"
VISIBILITY="--private"  # 改成 --public 如果想公开（不推荐 VPN 项目公开）

echo "==> 1/4 检查 gh 登录状态..."
if ! gh auth status >/dev/null 2>&1; then
    echo "   gh 未登录或 token 过期，现在开始 web 登录流程..."
    echo "   浏览器会自动打开，输入显示的 8 位 code 即可"
    gh auth login --web --git-protocol https
fi

echo "==> 2/4 当前登录账号: $(gh api user --jq .login)"

echo "==> 3/4 创建远程仓库 $REPO_NAME..."
if gh repo view "$REPO_NAME" >/dev/null 2>&1; then
    echo "   仓库已存在，跳过创建"
    if ! git remote | grep -q origin; then
        git remote add origin "$(gh repo view $REPO_NAME --json sshUrl --jq .sshUrl)"
    fi
else
    gh repo create "$REPO_NAME" $VISIBILITY --source=. --remote=origin --description "自建 VPN 方案，基于 Oracle Cloud 免费 ARM 或 HostDare CN2 GIA"
fi

echo "==> 4/4 推送 main 分支..."
git push -u origin main

echo ""
echo "✅ 完成！仓库地址："
gh repo view "$REPO_NAME" --json url --jq .url
echo ""
echo "后续 commit 直接用 git push 即可。"
