# git-hooks

本地 pre-commit 保护。**只为 public 仓库 `ace-vpn` 准备**，防止把公司邮箱 / 内网关键字泄露到公网。

## 安装（新机器 clone 后跑一次）

```bash
bash scripts/git-hooks/install.sh
```

## 它会拦截什么

1. `user.email` 不是 `xiaonan.cs@gmail.com` → 拒绝提交
2. staged diff 里出现 `xiaomi.com` / `@xiaomi` / `ihome.local` / `emailhxn` → 拒绝提交

## 紧急绕过

```bash
git commit --no-verify
```

## 改规则

直接编辑 `scripts/git-hooks/pre-commit`。因为 `.git/hooks/pre-commit` 是软链到这里的，改完立刻生效，不需要重装。
