# 🔐 private/ ——「真实凭据 & 内网配置」存放区

> public 仓库（本 repo）**绝对不能**出现任何真实公司名、内网 IP、内网 DNS、
> 内网域名、VPS 凭据。这些都放在这个 gitignore 守护的目录，或独立 private
> 仓库（见下）。

## 设计原则：公私分离

| | public 仓库（xiaonancs/ace-vpn） | private 仓库 / 本地 |
|---|---|---|
| **放什么** | 代码、脚本、文档、`*.example` 模板 | 真实 `intranet.yaml`、`env.sh`、`credentials.txt` |
| **谁能看** | 任何人（开源） | 仅自己（单机或私有 GitHub） |
| **Git 历史** | 公开 | 不发布 / 私有 |
| **示例数据** | `corp-a` / `10.x.x.x` / `app.corp-a.example` | 真实公司名 / 真实 DNS / 真实域名 |

`.gitignore` 里已经写了 `private/*` + whitelist 几个 `.example` 和本 README，
正常情况下**编辑 private/ 里的真实文件不会污染 public 仓库的 git 历史**。

## 文件约定

| 文件 | gitignored? | 说明 |
|------|:-:|------|
| `README.md` | ❌（本文件） | 目录说明 |
| `env.sh.example` | ❌ | 全量环境变量模板（含面板凭据） |
| `env.sh.minimal.example` | ❌ | 最小模板（只含 VPS_IP / SSH_KEY），新机快速拉起用 |
| `intranet.yaml.example` | ❌ | 内网分流模板，脱敏占位数据 |
| `credentials.txt.example` | ❌ | 凭据文件模板 |
| `env.sh` | ✅ | 真实环境变量。从 `.example` 复制后改 |
| `intranet.yaml` | ✅ | 真实内网分流（公司内网 DNS / 域名 / CIDR） |
| `credentials.txt` | ✅ | 从 VPS `/root/ace-vpn-credentials.txt` 下载的完整凭据 |
| `subscription-urls.md` | ✅ | 各设备订阅 URL |
| `vps-inventory.md` | ✅ | 当前/备用 VPS 登录信息、到期时间、备份文件位置 |
| `家人-设备清单.md` | ✅ | 谁用哪个 Client、Email、SubId |

## 三种 private 数据管理方式

### 方式 A：仅本地（零配置，默认）

对单机用户最简单，**什么都不做**，直接用 `private/` 下的真实文件。靠
`.gitignore` 隔离。

```bash
cp private/env.sh.example            private/env.sh
cp private/intranet.yaml.example     private/intranet.yaml
$EDITOR private/env.sh               # 填真实 VPS_IP / token
$EDITOR private/intranet.yaml        # 填真实公司 DNS / 域名
chmod 600 private/env.sh
```

缺点：**换机器 / 换系统就丢了**，需要手动拷贝或备份。

### 方式 B：独立 private 仓库 + symlink（推荐）⭐

在另一个（私有）Git 仓库维护真实数据，用 symlink 挂进 `private/`：

```bash
# 1. 另建一个 GitHub 私有仓库，比如 xiaonancs/ace-vpn-private，clone 到本地
git clone git@github.com:<YOUR>/ace-vpn-private.git ~/workspace/ace-vpn-private

# 2. 在 private 仓库里放真实文件
cd ~/workspace/ace-vpn-private
cp ~/workspace/publish/ace-vpn/private/env.sh.example            ./env.sh
cp ~/workspace/publish/ace-vpn/private/intranet.yaml.example     ./intranet.yaml
$EDITOR env.sh intranet.yaml   # 填真实数据
git add . && git commit -m "init real configs"
git push

# 3. 回 public 仓库，把 symlink 指过去
cd ~/workspace/publish/ace-vpn
ln -sf ~/workspace/ace-vpn-private/env.sh        private/env.sh
ln -sf ~/workspace/ace-vpn-private/intranet.yaml private/intranet.yaml

# 4. 验证（应看到 symlink 指向，而不是实体文件）
ls -la private/env.sh private/intranet.yaml
```

换机器时：只要 clone 两个仓库 + 跑 step 3 的 `ln -sf`，一切原样恢复。真实
数据只存在 private 仓库里，和 public 仓库完全物理分离。

### 方式 C：独立 private 仓库 + 周期性同步（无 symlink）

不喜欢 symlink 可以用 rsync：

```bash
# 随手写一条 alias
alias ace-pull='rsync -av ~/workspace/ace-vpn-private/ ~/workspace/publish/ace-vpn/private/ --exclude=".git/"'
alias ace-push='rsync -av ~/workspace/publish/ace-vpn/private/ ~/workspace/ace-vpn-private/ --exclude="*.example" --exclude="README.md" --exclude=".git/"'
```

改完跑 `ace-push` 再 `cd ~/workspace/ace-vpn-private && git commit -am ... && git push`。

## 日常工作流（方式 B 之后）

```bash
# 改内网规则
$EDITOR private/intranet.yaml        # 实际编辑的是 ace-vpn-private/intranet.yaml
bash scripts/sync-intranet.sh        # scp 到 VPS 热加载

# 提交真实改动（私有仓库）
cd ~/workspace/ace-vpn-private
git add intranet.yaml
git commit -m "update corp-a DNS"
git push

# 回到 public 仓库改代码/文档
cd ~/workspace/publish/ace-vpn
# 正常写代码，绝不在 docs/ / README.md / scripts/ 里出现真实公司名
```

## 从 VPS 拉凭据

```bash
scp root@${VPS_IP}:/root/ace-vpn-credentials.txt private/credentials.txt
chmod 600 private/credentials.txt
```

## 换 VPS 后

1. 更新 `env.sh` 里的 `VPS_IP` / `SUB_TOKENS` / `PANEL_*`
2. 如果是方式 B/C，在 private 仓库里 commit 这次更新
3. 其他脚本、客户端订阅 URL 都是参数化的 `$VPS_IP:${SUB_PORT}/clash/${SUB_TOKEN}`，
   刷新订阅即可

## 安全守则（通用）

- **绝对**不要把 private 内容复制到公开聊天；截图前马赛克 IP / 公司名
- 所有 `private/` 下真实文件 `chmod 600`
- 定期滚动 SubToken（见 `docs/skill.md §10.7`）
- 如怀疑泄露：3x-ui 面板禁用对应 Client → 重新生成 UUID → 家人重订阅
- public 仓库 commit 前，**强制自检**。建议在 private 仓库维护一份关键词
  黑名单 `sensitive-words.txt`（含自家公司名、真实内网域名/DNS 片段），然
  后在 public 仓库写一个本地 pre-commit hook：
  ```bash
  # .git/hooks/pre-commit （本地，不提交）
  #!/usr/bin/env bash
  BLACKLIST=~/workspace/ace-vpn-private/sensitive-words.txt
  [ -f "$BLACKLIST" ] || exit 0
  if git diff --cached | grep -iEf "$BLACKLIST"; then
      echo "⚠️  发现黑名单关键词，复查后再提交；若确为示例占位可 --no-verify"
      exit 1
  fi
  # 同时做一个 10.x 段粗筛，未脱敏常忘记
  if git diff --cached --unified=0 | grep -E "^\+" | \
     grep -E "(10|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.[0-9]+\.[0-9]+"; then
      echo "⚠️  新增行里出现内网 IP 段，请确认是否为示例占位 (10.x.x.x / 10.0.0.0/8)"
      exit 1
  fi
  ```

## 备份建议

```bash
# 方式 A：加密压缩后丢云盘
tar czf - private/ | gpg -c > private-$(date +%Y%m%d).tar.gz.gpg

# 方式 B/C：private 仓库已经是 git，push 到私有 remote 就是备份
```

## 为什么不干脆把 intranet.yaml 加密存在 public 仓库？

考虑过，放弃原因：

1. 加密后 `git diff` 不可读，失去版本控制语义；
2. 每次编辑都要 decrypt → edit → re-encrypt，工作流割裂；
3. `git-crypt` / `sops` / `age` 密钥管理本身就是麻烦，不比维护一个私有
   git remote 更简单；
4. 公私分离是更干净的边界——public 仓库天然**零隐私**，任何 contributor
   fork / PR 都不会意外看到真实公司内网。
