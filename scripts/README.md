# 🚀 ace-vpn · scripts 目录说明

> 所有脚本按用途分四类。先看分类表知道每个脚本干啥，再看具体使用。

---

## 📑 速查表

### A. 部署类（在 **VPS** 上跑，一次性）

新机部署或迁移时用。日常无需碰。

| 脚本 | 作用 | 何时跑 |
|------|------|--------|
| [`install.sh`](install.sh) | **入口**：依次调用 setup-system / setup-firewall / install-3xui | 新机第一次部署 |
| [`setup-system.sh`](setup-system.sh) | apt 更新 + 时区 + BBR + IP 转发 + 句柄上限 | install.sh 内部 |
| [`setup-firewall.sh`](setup-firewall.sh) | UFW 默认策略 + 放行必要端口 | install.sh 内部 |
| [`install-3xui.sh`](install-3xui.sh) | 安装 3x-ui 面板 | install.sh 内部 |
| [`configure-3xui.sh`](configure-3xui.sh) | 自动登录 3x-ui + 生成 Reality 密钥 / UUID + 建入站 + 输出分享链接 | 部署 3x-ui 后 |
| [`install-sub-converter.sh`](install-sub-converter.sh) | 部署 Clash 订阅转换器 + 初始化 `/etc/ace-vpn/intranet.yaml` | 部署 sub-converter 后 |
| [`sub-converter.py`](sub-converter.py) | **运行时**：订阅生成 / 热加载 intranet.yaml / `/match` 规则查询 / `/healthz` | 由 systemd 启动，不直接跑 |

### B. 日常运维（在 **Mac** 上跑，高频）

加规则 / 同步规则 / 应急回退 —— 最常用的就这一组。

| 脚本 | 作用 | 何时跑 |
|------|------|--------|
| [`add-rule.sh`](add-rule.sh) | 加一条规则到本地池 + 自动 reload mihomo | 发现某个站走错路了想纠正时 |
| [`list-rules.sh`](list-rules.sh) | 看本地池里积累了哪些规则 | 想知道还没 promote 的规则有啥 |
| [`apply-local-overrides.sh`](apply-local-overrides.sh) | 把 `local-rules.yaml` 渲染成 mihomo override + 触发 reload | 手动改了 local-rules.yaml 后；add-rule 内部也调它 |
| [`promote-to-vps.sh`](promote-to-vps.sh) | 把本地池合并进 `intranet.yaml`（**本地优先**，与已有 intranet 冲突则覆盖并打印前后对比）+ `sync-intranet` + 清池 | 积累几天后批量同步给家人/手机 |
| [`sync-intranet.sh`](sync-intranet.sh) | 把 `private/intranet.yaml` scp 到 VPS；**推送前远端自动备份** `backups/intranet-*.yaml`（保留最近 5 份） | 直接编辑了 intranet.yaml 想推上去时；promote-to-vps 内部也调它 |
| [`rollback-overrides.sh`](rollback-overrides.sh) | **应急**：回退 mihomo override 到上一个备份 / 禁用本地池 | 加了坏规则导致 mac 上不了网时 |

### C. 诊断 / 调试（**Mac** 或 **VPS**，按需）

出问题时用。

| 脚本 | 作用 | 何时跑 |
|------|------|--------|
| [`speed-test.sh`](speed-test.sh) | 测当前网络对 AI / cursor / youtube 等关键服务的延迟 + 带宽 | 怀疑网速慢、对比节点速度 |
| [`diagnose.sh`](diagnose.sh) | 一次性收集 mihomo 状态 + 出口 IP + cursor 后端可达性 + cursor IDE 日志 | cursor / gemini 突然不能用，要把诊断信息整包发出去看 |
| [`ip-check.sh`](ip-check.sh) | 测当前出口 IP 在 Google / OpenAI / Anthropic 眼里是哪国 + 哪些 AI 服务能用 | 怀疑出口 IP 被某 AI 服务封了 |
| [`check-xui-panel.sh`](check-xui-panel.sh) | 从本机 `curl -vk` 探测 3x-ui 面板 URL（TCP/TLS/HTTP 层） | 面板突然打不开，先区分是端口/路径/服务还是本地网络 |
| [`vps-watch-urls.sh`](vps-watch-urls.sh) | SSH 到各 VPS，默认合并 `speed-test-endpoints.txt` + 可选 `private/vps-watch-urls.txt`，curl 指标与 `speed-test.sh` 一致；`--log` 写入单文件 | 每 30 分钟对比两台 VPS 出站（LaunchAgent 模板见 `scripts/launchd/`） |
| [`test-route.sh`](test-route.sh) | 给一个 URL，输出命中哪条规则 + 命中哪个组 + 实测延时 + 出口 IP | 想知道某站到底走的什么路径 |

### D. 仓库辅助

| 脚本 / 目录 | 作用 |
|-------------|------|
| [`lib/common.sh`](lib/common.sh) | shell 共享工具（日志、apt 锁等待、root 检查） |
| [`lib/local_rules.py`](lib/local_rules.py) | python 库：本地规则池的读 / 写 / 渲染 / promote / mihomo reload。被 add-rule / list-rules / apply-local-overrides / promote-to-vps / rollback-overrides 共用 |
| [`git-hooks/`](git-hooks/) | pre-commit hook，防止 private/ 下敏感文件误推到 GitHub |

---

## 🧹 可以删除的 / 重复的

**目前没有真正"没用"的脚本**，每个都有明确用途。但有几个"功能有重叠"的，按使用频率取舍：

| 脚本 | 状态 | 说明 |
|------|------|------|
| `speed-test.sh` | ✅ 保留 | 重写过的纯 curl 版，不依赖 mihomo API，最稳 |
| `diagnose.sh` | ✅ 保留 | 一次性收集"全景"，适合发给别人帮看 |
| `ip-check.sh` | ✅ 保留 | 专门判定 IP 是否被某 AI 服务封 |
| `test-route.sh` | ✅ 保留 | 唯一能查"某 URL 命中哪条规则"的工具 |

**重叠点**（不删，但知道何时用谁）：
- 都有"测延迟" → `speed-test` 适合**对比节点**；`diagnose` 适合**把状态发给别人看**；`ip-check` 适合**专测 AI 服务**
- 都涉及"出口 IP" → `speed-test` 顺便看；`ip-check` 详细查国家归属

**真要瘦身**也只能删 `__pycache__/`（python 自动生成，可加 .gitignore）。

```bash
echo "scripts/__pycache__/" >> .gitignore
echo "scripts/lib/__pycache__/" >> .gitignore
rm -rf scripts/__pycache__ scripts/lib/__pycache__
```

---

## 🛠 三种最常用工作流

### 工作流 1：发现新站需要走 VPS（或被误判走 VPS）

```bash
# 1. 测一下当前走哪
bash scripts/test-route.sh https://some-site.com/

# 2. 加规则（VPS = 走 VPS 代理 / DIRECT = 直连 / IN = 公司内网）
bash scripts/add-rule.sh https://some-site.com/  VPS  --note "GPT-5 工具"

# 3. 几秒内本机生效。攒够几条后批量推 VPS（家人也获益）
bash scripts/promote-to-vps.sh
```

### 工作流 2：cursor / gemini 突然连不上

```bash
# 1. 收集"灾难现场"全景
bash scripts/diagnose.sh
# 输出 /tmp/ace-vpn-diag-*.txt，把内容贴给会看的人

# 2. 怀疑 IP 被某服务封了？专项测
bash scripts/ip-check.sh

# 3. 怀疑加的规则把自己卡死了？立刻回退
bash scripts/rollback-overrides.sh --last
# 或者更狠
bash scripts/rollback-overrides.sh --disable
```

### 工作流 3：怀疑节点速度慢

```bash
# 测当前节点
bash scripts/speed-test.sh --quick

# 在 Clash Party GUI 里手动切到另一个节点

# 再测一次对比
bash scripts/speed-test.sh --quick

# 如果想看路由质量（哪一段丢包）
brew install mtr   # 一次性
sudo mtr -rwzbc 30 <VPS_IP>        # 换成你当前节点的公网 IP
```

---

## 多 VPS（`VPS_NODES`）

在 `private/env.sh` 里配置 `VPS_NODES="name1:ip1 name2:ip2"` 后：

- `bash scripts/sync-intranet.sh --all-vps`：把 `intranet.yaml` 推到列表里每一台。
- `bash scripts/promote-to-vps.sh --all-vps`：promote 后同样推多台（与上共用 SSH 配置）。
- `bash scripts/preflight-multi-vps.sh`：只读体检各节点 SSH / sub-converter / xray 摘要。
- `bash scripts/vps-watch-urls.sh`：对各节点上的 `private/vps-watch-urls.txt` 跑出站延迟（需 **`export VPS_SSH_KEY=...` + `ssh-copy-id`** 才能免密定时跑）。

**定时每 30 分钟（macOS）**：复制并按注释编辑  
`scripts/launchd/ace-vpn.vps-watch-urls.example.plist` →  
`~/Library/LaunchAgents/com.xiaonancs.ace-vpn.vps-watch-urls.plist`，  
把 `__REPO_ROOT__` 换成本机 `ace-vpn` 路径后 `launchctl load`。

---

## 🔧 install.sh 环境变量

仅 VPS 部署用。

| 变量 | 默认 | 说明 |
|------|------|------|
| `TCP_PORT` | `443` | VLESS+Reality 监听端口 |
| `UDP_PORT` | `443` | Hysteria2 监听端口 |
| `PANEL_PORT` | `2053` | 3x-ui 面板端口 |
| `SUB_PORT` | `2096` | 订阅端口 |
| `SSH_PORT` | `22` | SSH 端口 |
| `TZ` | `Asia/Shanghai` | 时区 |
| `SKIP_3XUI` | `0` | `=1` 跳过 3x-ui 安装 |
| `AUTO_CONFIGURE` | `0` | `=1` 装完 3x-ui 后自动建 Reality + Hy2 入站 |
| `XUI_USER` / `XUI_PASS` | `admin` / `admin` | configure-3xui.sh 用的面板账号 |
| `XUI_PANEL_PATH` | 空 | 改过面板路径时填 |
| `REALITY_DEST` | `www.cloudflare.com:443` | Reality 伪装的真实站 |
| `REALITY_SNI` | `www.cloudflare.com` | Reality serverName |

---

## 🚨 常见踩坑

### 脚本报 "apt 被占用"
新装 VPS cloud-init 还在跑，等 2-3 分钟，或：
```bash
sudo systemctl stop unattended-upgrades && sudo bash scripts/install.sh
```

### `add-rule.sh` 加完后 mihomo 报 "proxy not found"
local-rules.yaml 写错了。立刻：
```bash
bash scripts/rollback-overrides.sh --last
```

### `promote-to-vps.sh` SCP 超时
检查 `private/env.sh` 里的 `VPS_IP` 是不是当前能访问的节点 IP。VPS 自己出问题（比如本次 hosthatch JP 链路抖动）时 SCP 会卡。

### `sync-intranet.sh` 报 `/healthz` 失败
sub-converter 服务挂了。SSH 到 VPS：
```bash
systemctl status ace-vpn-sub
systemctl restart ace-vpn-sub
journalctl -u ace-vpn-sub -n 50
```

### 改完 xray config 重启回滚
3x-ui 启动时从 `/etc/x-ui/x-ui.db` 的 `xrayTemplateConfig` 反向覆盖 `config.json`。看 [docs/dev-skill.md §5.5](../docs/dev-skill.md#55-改-xray-config-必须改数据库最深的坑)。

---

## 📚 配套文档

| 文档 | 内容 |
|------|------|
| [`../docs/三网段分流架构.md`](../docs/三网段分流架构.md) | ACE 架构设计 — 系统全景 / 部署 / DNS / 规则系统 / 多设备同步 |
| [`../docs/dev-skill.md`](../docs/dev-skill.md) | 开发者日志 — 新增功能 / 性能优化 / 踩坑分类 / VPS 迁移 playbook |
| [`../docs/用户手册 user-guide.md`](../docs/用户手册%20user-guide.md) | 终端用户使用指南 |
| [`../docs/Oracle Cloud 注册教程.md`](../docs/Oracle%20Cloud%20注册教程.md) | 免费 VPS 来源 |

> WARP 备选方案（IP 被 Google 封时启用）已收敛进 [`../docs/dev-skill.md` §5](../docs/dev-skill.md#5-warp-备选方案cloudflare-warp-outbound)，原 `warp-upgrade.md` 已删除。

---

## 🔄 迁移 VPS（换机）

```
旧机：
  systemctl stop x-ui
  cp /etc/x-ui/x-ui.db /root/x-ui-backup.db
  scp /root/x-ui-backup.db local:/safe/place/

新机：
  sudo bash scripts/install.sh
  systemctl stop x-ui
  scp local:/safe/place/x-ui-backup.db /etc/x-ui/x-ui.db
  systemctl start x-ui
  登录面板 → 入站列表改对外 IP（或用域名，免改）
  客户端点"更新订阅"
```

详见 [`docs/dev-skill.md`](../docs/dev-skill.md) 的"整库迁移"章节。
