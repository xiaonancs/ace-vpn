# 🔐 private/ ——「真实凭据 & 内网配置」入口

> public 仓库（本 repo）**绝对不能**出现任何真实公司名、内网 IP、内网 DNS、
> 内网域名、VPS 凭据。真实数据在独立的 **private 仓库** 维护，本目录下的真实
> 文件全部是 symlink 指过去。

## 设计原则：公私分离

| | public 仓库（xiaonancs/ace-vpn） | private 仓库（xiaonancs/ace-vpn-private） |
|---|---|---|
| 放什么 | 代码、脚本、文档、`*.example` 模板 | 真实 `intranet.yaml` / `env.sh` / `credentials.txt` / sensitive-words |
| 谁能看 | 任何人（开源） | 仅自己 |
| Git 历史 | 公开 | 私有 |
| 示例数据 | `corp-a` / `10.x.x.x` / `app.corp-a.example` | 真实公司名 / 真实 DNS / 真实域名 |

本目录 (`ace-vpn/private/`) 的实际文件分布：

```
private/
├── README.md                    本文件（公开，讲目录用法）
├── credentials.txt.example      公开模板
├── env.sh.example               公开模板（全量环境变量）
├── env.sh.minimal.example       公开模板（最小环境变量）
├── intranet.yaml.example        公开模板（脱敏占位）
│
├── intranet.yaml    → symlink → ../../ace-vpn-private/intranet.yaml      （VPS 共享规则）
├── local-rules.yaml → symlink → ../../ace-vpn-private/local-rules.yaml   （Mac 本地池）
├── env.sh           → symlink → ../../ace-vpn-private/env.sh            （可选）
└── credentials.txt  → symlink → ../../ace-vpn-private/credentials.txt   （可选）
```

所有 symlink 都被 `.gitignore` 里 `private/*` 规则挡住，不会进 public git。

## 换机 / 首次搭建

```bash
# 1. clone 两个仓库到同级目录
cd ~/workspace/publish
git clone git@github.com:xiaonancs/ace-vpn.git
git clone git@github.com:xiaonancs/ace-vpn-private.git

# 2. 建 symlink
cd ace-vpn
for f in intranet.yaml local-rules.yaml env.sh credentials.txt; do
  [ -f ../ace-vpn-private/$f ] && ln -sf ../../ace-vpn-private/$f private/$f
done

# 3. 验证
ls -la private/          # 应看到 symlink 指向 ../../ace-vpn-private/...
python3 -c "import yaml; print(len(yaml.safe_load(open('private/intranet.yaml'))['profiles']))"
```

## 日常工作流

### 长期 / 全设备共享规则（VPS 同步）

```bash
cd ~/workspace/publish/ace-vpn
$EDITOR private/intranet.yaml          # 实际编辑 private 仓库文件（透过 symlink）
bash scripts/sync-intranet.sh          # scp 推到 VPS 热加载，家人客户端刷新即生效

cd ~/workspace/publish/ace-vpn-private # 把真实改动提交到 private 仓库（备份）
git add intranet.yaml
git commit -m "update: corp-a 新 DNS"
git push
```

### 临时 / 仅本机即时生效（本地规则池）

```bash
cd ~/workspace/publish/ace-vpn
# TARGET = IN | DIRECT | VPS（大小写无关）
bash scripts/add-rule.sh https://gitlab.corp-a.example/ IN  --note "内网 GitLab"
bash scripts/add-rule.sh https://claude-foo.example     VPS --note "新 AI 走 VPS 出去"
# ↑ 写入 private/local-rules.yaml + 渲染 Mihomo override + GUI 秒级 reload
#   家人 / VPS 不动；攒一段时间后跑 promote-to-vps.sh 批量 sync
bash scripts/list-rules.sh             # 看本地池现状
bash scripts/promote-to-vps.sh         # 批量 promote → 推 VPS → 清空本地池
```

详细工作流见 [`docs/用户手册 user-guide.md` §7.9](../docs/用户手册%20user-guide.md#79仅管理员本地规则池单机即时加规则积累后批量推-vps)。

## pre-commit hook（强烈建议装）

防意外把隐私 commit 到 public 仓库。黑名单维护在 private 仓库里（`sensitive-words.txt`），
public 仓库的 hook 直接读：

```bash
cat > ~/workspace/publish/ace-vpn/.git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
# 扫 staged diff，命中 private 仓库黑名单就拒绝
#
# 关键：必须先过滤掉黑名单里的 # 注释和空行，
# 否则 grep -iEf 会把空行当作空 pattern，匹配一切，误报 100%（血泪教训）

BLACKLIST=~/workspace/publish/ace-vpn-private/sensitive-words.txt
[ -f "$BLACKLIST" ] || exit 0

PATTERNS=$(grep -vE '^\s*(#|$)' "$BLACKLIST")
[ -z "$PATTERNS" ] && exit 0
JOINED=$(echo "$PATTERNS" | paste -sd '|' -)

STAGED=$(git diff --cached --unified=0 | grep -E '^\+' | grep -vE '^\+\+\+')

if echo "$STAGED" | grep -iE "$JOINED" >/dev/null; then
    echo "⚠️  diff 命中 private 仓库维护的黑名单："
    echo "$STAGED" | grep -inE --color=always "$JOINED"
    echo ""
    echo "    复查后再提交；确为示例占位可 git commit --no-verify"
    exit 1
fi
EOF
chmod +x ~/workspace/publish/ace-vpn/.git/hooks/pre-commit
```

> 黑名单里允许写注释行（`#` 开头）和空行，方便分组。
> hook 自己会过滤，不会误报。

## 安全守则

- 所有 private 仓库下真实文件 `chmod 600`
- 不把 private 内容复制/粘贴到聊天；截图前马赛克 IP / 公司名
- 定期滚动 SubToken（见 `docs/dev-skill.md` §10.7）
- 怀疑泄露：3x-ui 面板禁用对应 Client → 重新生成 UUID → 家人重订阅
- private 仓库绝对不要 public 化、不要加 contributor

## 为什么不用"加密存在 public 仓库"（如 git-crypt / sops）

- 加密后 `git diff` 不可读，失去版本控制语义；
- 编辑流程 decrypt → edit → re-encrypt 太重；
- 密钥管理本身就是麻烦，不比维护一个私有 git remote 更简单；
- 公私分离是更干净的边界——public 仓库天然**零隐私**，任何 contributor fork
  / PR 都不会意外看到真实公司内网。
