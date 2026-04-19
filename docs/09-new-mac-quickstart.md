# 💻 新 Mac 快速配置（30 分钟上手）

> 新办公/家用 Mac 到手，怎么在半小时内把 ace-vpn + 常用工具全跑起来。
> 前置条件：你的家庭 VPS（HostHatch / Vultr 等）已经跑通 ace-vpn，新 Mac 只做**客户端配置**。

---

## 📋 开干前收集这 4 样东西

从**老 Mac** 的 `private/env.sh` 或 `private/ace-vpn-credentials.txt` 里拿（或者密码管理器）：

| 值 | 示例 | 从哪拿 |
|----|------|--------|
| `VPS_IP` | `xxx.xxx.xxx.xxx` | `private/env.sh` |
| `SUB_TOKEN_SELF`（你自己订阅）| `sub-hxn` | `private/env.sh` |
| Clash 订阅 URL | `http://<VPS_IP>:25500/clash/sub-hxn` | 由上面拼出 |
| SSH private key（管 VPS 用，可选）| `~/.ssh/id_ed25519` | 从老 Mac scp 过来 |

如果老 Mac 还在手边，**从老 Mac 跑这行把 SSH key 和 env 拷到新 Mac**：

```bash
# 老 Mac 上（<NEW_MAC_IP_OR_HOSTNAME> 替换为新 Mac 的 IP 或 Bonjour 名）
scp ~/.ssh/id_ed25519* <you>@<NEW_MAC>:~/.ssh/
scp ~/workspace/cursor-base/ace-vpn/private/env.sh \
    <you>@<NEW_MAC>:~/ace-vpn-env.sh
```

（或者：iCloud Drive 里放一个加密 zip 中转，用完删掉。**别走微信/邮件明文**。）

---

## Phase 1：装 Mihomo Party（VPN 客户端，5 分钟）

### 1.1 装

```bash
# 方法 A（推荐，Homebrew）
brew install --cask mihomo-party

# 方法 B（手动下载 .dmg）
# https://github.com/mihomo-party-org/mihomo-party/releases
```

首次启动会弹 macOS 权限，一路允许。

### 1.2 导入订阅

1. 打开 Mihomo Party
2. 左侧 **Profiles** → 右上 **New Profile** → 选 **Remote**
3. URL 填：
   ```
   http://<VPS_IP>:25500/clash/<SUB_TOKEN_SELF>
   ```
   例：`http://<VPS_IP>:25500/clash/<SUB_TOKEN_SELF>`
4. Name 填 `ace-vpn-<地点>`（如 `ace-vpn-tokyo`），保存
5. **点这条 Profile 使其变成 Current**（图标变绿）

### 1.3 打开开关

回到 **Overview**（主页），顶部 3 个开关：

| 开关 | 状态 | 说明 |
|------|------|------|
| **System Proxy** | ✅ ON | 浏览器、HTTP 客户端走代理 |
| **Tun Mode** | ✅ ON | 终端、Cursor、所有 App 走代理（**首次会弹权限提示装 helper，输 Mac 密码**）|
| **Unified Delay** | 随意 | 纯 UI 偏好 |

### 1.4 验证

打开 Safari：
- https://ipinfo.io → 应显示日本 IP (东京)
- https://www.baidu.com → 秒开（走直连）
- https://www.youtube.com → 播放任意视频 4K 不卡
- https://claude.ai → 能正常登录、对话

---

## Phase 2：终端 / Cursor 代理（5 分钟）

### 2.1 克隆仓库

```bash
# 新建工作目录
mkdir -p ~/workspace
cd ~/workspace

# clone 这个项目（私仓，用 SSH key 或 Personal Access Token）
git clone git@github.com:xiaonancs/ace-vpn.git
# 或 https + token:
# git clone https://github.com/xiaonancs/ace-vpn.git
```

如果还没配 GitHub SSH key：

```bash
ssh-keygen -t ed25519 -C "<your-email>"
cat ~/.ssh/id_ed25519.pub
# 复制内容贴到 https://github.com/settings/ssh/new
```

### 2.2 Shell 代理别名

```bash
cd ~/workspace/ace-vpn

# 把 shell-proxy.sh source 进 zshrc
echo "source $(pwd)/clients/shell-proxy.sh" >> ~/.zshrc
source ~/.zshrc
```

以后任何终端：

```bash
proxy_on       # 打开代理（HTTP_PROXY / HTTPS_PROXY 环境变量）
proxy_off      # 关闭
proxy_status   # 查当前状态 + 出口 IP
```

> **注**：Tun Mode 开着的话，`proxy_on` 其实不是必需（Tun 已经接管所有流量）。但一些工具（curl、git over HTTP）显式读 `HTTPS_PROXY`，有这个双保险更稳。

### 2.3 Cursor / VS Code 代理

大多数情况下 **Tun Mode 开着就不用做任何事**，Cursor 直接能访问 Claude / OpenAI。

如果 Cursor 报网络错误（个别插件不吃 Tun），按 [`clients/cursor-proxy.md`](../clients/cursor-proxy.md) 操作。

### 2.4 私钥还原（管 VPS 用）

```bash
# 如果从老 Mac scp 了 id_ed25519 过来
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub

# 测试能登 VPS
ssh root@<VPS_IP> "uptime"
```

没有老 Mac 的 key？从**家里老 Mac** 或**密码管理器**恢复，或者登 HostHatch 控制台 reset password 重新推公钥。

---

## Phase 3：本地环境变量 private/env.sh（5 分钟）

这一步**可选**，方便后续在终端里直接用 `$VPS_IP` / `$URL_CLASH_SELF` 等变量。

### 3.1 如果从老 Mac 拷了 env.sh

```bash
cp ~/ace-vpn-env.sh ~/workspace/ace-vpn/private/env.sh
chmod 600 ~/workspace/ace-vpn/private/env.sh
rm ~/ace-vpn-env.sh   # 中转文件删掉
```

### 3.2 如果没拷，手动创建

```bash
cd ~/workspace/ace-vpn
cp private/env.sh.example private/env.sh
chmod 600 private/env.sh
$EDITOR private/env.sh
# 把 VPS_IP / PANEL_PORT / PANEL_PATH / SUB_ID_* 填进去
# 这些值都在你的密码管理器或老 Mac 里
```

### 3.3 每次新 shell 可选自动 source

```bash
echo "[ -f ~/workspace/ace-vpn/private/env.sh ] && source ~/workspace/ace-vpn/private/env.sh" >> ~/.zshrc
source ~/.zshrc

# 验证
echo $VPS_IP                 # 应输出 VPS IP
echo $URL_CLASH_SELF         # 应输出你的订阅 URL
```

---

## Phase 4：常用开发工具（看需求，各 1-5 分钟）

### 4.1 必装

```bash
# Xcode Command Line Tools
xcode-select --install

# Homebrew（如还没装）
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 常用 CLI
brew install git node python@3.12 rg fd bat jq httpie
```

### 4.2 Cursor

```bash
brew install --cask cursor
# 或下载: https://cursor.sh

# 首次启动登录账号，同步设置
# Settings → Extensions → 恢复插件（GitHub Copilot、GitLens 等）
```

### 4.3 Claude Desktop / Claude Code

```bash
# Claude Desktop
# 下载: https://claude.ai/download

# Claude Code CLI
npm install -g @anthropic-ai/claude-code
# 登录（Tun Mode 开着，可直接登）
claude
```

### 4.4 1Password / Bitwarden（密码管理器）

从 App Store 或官网装，登录同步所有密码（VPS 面板、Github token、各种 API key 都在这里）。

---

## ✅ 30 分钟验收清单

| 能力 | 测试方法 | 标准 |
|------|---------|------|
| VPN 翻墙 | Safari 打开 youtube.com | 秒开，4K 不卡 |
| 国内直连 | Safari 打开 baidu.com | 秒开 |
| AI 工具 | Safari 打开 claude.ai、chat.openai.com | 都能登 |
| 终端代理 | `proxy_status` | 显示 IP 为 VPS 位置 |
| SSH to VPS | `ssh root@<VPS_IP> "uptime"` | 返回 uptime |
| Cursor | 任意代码用 Claude 补全 | 1-2 秒返回 |
| GitHub | `git clone git@github.com:...` | 成功 |

全部 ✅ → 新 Mac 就绪。

---

## 🆘 常见问题

### Q1：订阅导入后 Proxies 里没节点

检查：
```bash
curl -s http://<VPS_IP>:25500/clash/<SUB_TOKEN_SELF> | head -30
```

- 能看到 YAML → Mihomo Party 的问题，重新导入 profile
- 404 或空 → VPS 上 `ace-vpn-sub` 服务挂了，SSH 过去 `systemctl restart ace-vpn-sub`
- 连接超时 → VPS 防火墙没开 25500 端口，`ufw allow 25500/tcp`

### Q2：Tun Mode 开不了 / 装 helper 失败

```
系统设置 → 隐私与安全性 → 看"允许开发者运行"
把 Mihomo Party / helper 放行
重启 Mihomo Party，再开 Tun
```

### Q3：浏览器打不开 Google，但能开 Baidu

说明代理没生效：
- 检查 Mihomo Party → Current Profile 是绿色
- 顶部 System Proxy 是 ON
- 底部 Proxy Group 手动选一个节点（不是 DIRECT）

### Q4：Cursor 报 "Network Error"

Tun Mode 应该能解决。如果还不行：
- Cursor → Settings → Network → HTTP Proxy: `http://127.0.0.1:7890`
- Restart Cursor

---

## 🔗 相关文档

- [`06-client-setup.md`](06-client-setup.md) — 完整四端客户端配置（iOS/Windows/Android 也在这）
- [`05-journey-and-skill.md`](05-journey-and-skill.md) — 整个项目的踩坑和原理
- [`clients/cursor-proxy.md`](../clients/cursor-proxy.md) — Cursor 专项代理配置
- [`clients/shell-proxy.sh`](../clients/shell-proxy.sh) — 终端代理开关脚本

---

**走完这一页，新 Mac 和老 Mac 等价，家人能用的你都能用。**
