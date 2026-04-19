# ace-vpn · 使用手册（Mac / iOS / Windows / Android）

> 面向普通用户（家人、朋友、未来的你自己）。**不需要任何技术背景**，跟着做就能用。
>
> 如果你是开发者/维护者，请看 [`skill.md`](skill.md)。

---

## 目录

1. [这是什么？](#1-这是什么)
2. [我需要什么？](#2-我需要什么)
3. [Mac 配置](#3-mac-配置)
4. [iPhone / iPad 配置](#4-iphone--ipad-配置)
5. [Windows 配置（家人版）](#5-windows-配置家人版)
6. [Android 配置](#6-android-配置)
7. [新 Mac 30 分钟上手](#7-新-mac-30-分钟上手)
8. [日常使用小贴士](#8-日常使用小贴士)
9. [常见问题 FAQ](#9-常见问题-faq)
10. [给家人的极简卡片](#10-给家人的极简卡片)

---

## 1. 这是什么？

一句话：**家用 VPN**。装好以后：

- 打开 Google、YouTube、ChatGPT、Claude、Discord → **可以**
- 打开 百度、淘宝、抖音、B 站 → **和平时一样快**（不会被代理拖慢）
- 公司 VPN / 打卡 App 不受影响

背后技术细节你不用关心，只需要知道两样东西：

1. **客户端 App**（Clash / Mihomo / Stash / Shadowrocket 之一，按你的设备选）
2. **订阅 URL**（管理员发给你的一条 `http://...` 链接）

把订阅 URL 粘到 App 里，打开总开关 → 完事。

---

## 2. 我需要什么？

跟**管理员**（ace-vpn 的人）要 **1 条订阅 URL**，格式大概是：

```
http://<VPS_IP>:25500/clash/<你的 SubId>
```

例如：
- 你自己的设备：`http://<VPS_IP>:25500/clash/sub-hxn`
- 家人设备：`http://<VPS_IP>:25500/clash/sub-hxn01`

把这条 URL 保存好（密码管理器/备忘录），下面所有设备配置都要用它。

### 2.1 两种订阅格式（管理员帮你选）

| 格式 | URL 形式 | 适用 |
|------|---------|------|
| **Clash YAML**（推荐）| `http://<VPS_IP>:25500/clash/<SubId>` | Mac / Windows / Android / iPad Stash |
| **v2ray base64** | `https://<VPS_IP>:2096/<sub_path>/<SubId>` | iPhone Shadowrocket |

Clash YAML 里自带**分流规则**（国内直连、国外代理、AI 走代理、抖音直连）全部自动。base64 版是纯节点，需要自己写规则。能用 Clash YAML 就用 Clash YAML。

---

## 3. Mac 配置

### 3.1 推荐：Mihomo Party（免费）

#### 安装

打开终端（⌘+Space 搜 "Terminal"），粘贴：

```bash
brew install --cask mihomo-party
```

没装 Homebrew？手动下载：https://github.com/mihomo-party-org/mihomo-party/releases 选最新的 `.dmg` 双击装。

#### 导入订阅

1. 打开 **Mihomo Party**（应用程序里）
2. 左侧菜单 **Profiles** → 右上 **New Profile** → 选 **Remote**
3. **URL** 粘贴管理员给的订阅 URL
4. **Name** 填 `ace-vpn`，点 Save
5. **点一下这条 Profile，让它变成 Current**（前面出现绿色圆圈）

#### 打开开关

回到顶部 **Overview**，顶部 3 个开关：

| 开关 | 状态 | 作用 |
|------|------|------|
| **System Proxy** | ✅ ON | Safari / Chrome 等浏览器走代理 |
| **Tun Mode** | ✅ ON | Cursor / 终端 / 所有 App 走代理 |
| **Unified Delay** | 随意 | 仅 UI 显示，不影响使用 |

**第一次开 Tun Mode 会弹权限提示，输 Mac 开机密码安装 helper**。

#### 验证（Safari 打开以下网址）

- https://ipinfo.io → 显示日本 IP ✅
- https://www.baidu.com → 秒开 ✅
- https://www.youtube.com → 4K 播放不卡 ✅
- https://claude.ai → 能正常登录 ✅

---

## 4. iPhone / iPad 配置

### 4.1 方案 A：Stash（推荐，¥15 一次性）

**优点**：和 Mac 同一份规则，零维护；iOS 上体验最接近 Mac。

#### 配置

1. App Store 搜 **Stash** → 购买下载
2. 右上 **+** → **Import from URL** → 粘贴订阅 URL
3. Name 填 `ace-vpn` → Save
4. 首页 **Configurations** 选 `ace-vpn` → 激活
5. 右上角**总开关** ON → 授权 VPN
6. **Settings → Enhanced Mode (TUN)** 打开（更稳）

#### 验证

- Safari 打开 YouTube / Google → 正常 ✅
- 抖音 App 刷视频流畅（走直连）✅
- Discord / Telegram App 能登 ✅

### 4.2 方案 B：Shadowrocket（¥15，iOS 老牌）

**优点**：原生吃 base64 订阅，导入 30 秒。
**缺点**：规则要自己配（iOS 系统限制只能按域名/IP 分流）。

#### 配置

1. App Store 买 **Shadowrocket**
2. 右上 **+** → **Type: Subscribe** → URL 粘贴 base64 订阅 URL（`https://<VPS_IP>:2096/...` 那种）
3. Remark `ace-vpn` → Save
4. 首页切到 **配置（Config）** 标签 → 默认有一个「config」
5. **全局路由** 选 **配置**
6. 点「config」进入编辑，**规则**区域按顺序加：

```
DOMAIN-SUFFIX,claude.ai,PROXY
DOMAIN-SUFFIX,anthropic.com,PROXY
DOMAIN-SUFFIX,openai.com,PROXY
DOMAIN-SUFFIX,chatgpt.com,PROXY
DOMAIN-SUFFIX,cursor.sh,PROXY
DOMAIN-SUFFIX,discord.com,PROXY
DOMAIN-SUFFIX,discordapp.com,PROXY
DOMAIN-KEYWORD,discord,PROXY
DOMAIN-SUFFIX,youtube.com,PROXY
DOMAIN-SUFFIX,googlevideo.com,PROXY
DOMAIN-SUFFIX,google.com,PROXY
DOMAIN-SUFFIX,googleapis.com,PROXY
DOMAIN-SUFFIX,gstatic.com,PROXY
DOMAIN-SUFFIX,twitter.com,PROXY
DOMAIN-SUFFIX,x.com,PROXY
DOMAIN-SUFFIX,t.me,PROXY
DOMAIN-SUFFIX,telegram.org,PROXY
DOMAIN-SUFFIX,github.com,PROXY
DOMAIN-SUFFIX,githubusercontent.com,PROXY
DOMAIN-SUFFIX,douyin.com,DIRECT
DOMAIN-SUFFIX,snssdk.com,DIRECT
DOMAIN-SUFFIX,taobao.com,DIRECT
DOMAIN-SUFFIX,tmall.com,DIRECT
DOMAIN-SUFFIX,alicdn.com,DIRECT
DOMAIN-SUFFIX,qq.com,DIRECT
DOMAIN-SUFFIX,bilibili.com,DIRECT
DOMAIN-SUFFIX,weibo.com,DIRECT
DOMAIN-SUFFIX,baidu.com,DIRECT
GEOIP,CN,DIRECT
FINAL,PROXY
```

保存。

#### 维护规则的进阶方法

手写维护麻烦，可以改用**社区 ruleset**（自动更新）。在配置里加：

| 规则集 | URL | 策略 |
|-------|-----|------|
| Claude | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/Claude/Claude.list` | PROXY |
| OpenAI | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/OpenAI/OpenAI.list` | PROXY |
| Discord | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/Discord/Discord.list` | PROXY |
| 境外通用 | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/Global/Global.list` | PROXY |
| 境内大陆 | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/ChinaMax/ChinaMax.list` | DIRECT |

顺序：Claude → OpenAI → Discord → Global → ChinaMax → GEOIP CN → FINAL,PROXY。

---

## 5. Windows 配置（家人版）

### 5.1 Clash Verge Rev（推荐给家人，最友好）

#### 安装

1. 打开 https://github.com/clash-verge-rev/clash-verge-rev/releases
2. 下载最新 `*.exe`（Windows 安装包）
3. 双击安装（UAC 弹出点"是"）

#### 配置

1. 打开 Clash Verge Rev
2. 左侧 **订阅（Profiles）** → 右上 **新建** → **从 URL 导入**
3. 粘贴订阅 URL
4. Name 填 `家用VPN` → 导入
5. 点订阅卡片，打勾激活（卡片右上角变勾）
6. 左侧 **设置** → 勾上：
   - ☑ **系统代理**
   - ☑ **TUN 模式**
   - ☑ **开机自启**
7. 完成

#### 远程帮家人安装（推荐）

- 国内：**向日葵远程控制**（家人点一次"接受"即可）
- 国外：**TeamViewer QuickSupport**

让他们自己搞大概率搞不定，远程帮一次之后他们就只要会"打开/关闭"。

---

## 6. Android 配置

### 6.1 Mihomo Party（Android 版）⭐ 推荐

#### 下载

浏览器打开：https://github.com/mihomo-party-org/mihomo-party/releases
下载最新 `.apk`（需先在系统设置里允许"安装未知来源"应用）。

#### 配置

1. 安装、打开 → 授予 VPN 权限
2. **Profiles → New Profile → Remote URL** → 粘贴订阅 URL
3. 点该 Profile 激活
4. 主界面 **TUN Mode ON**

和 Mac 完全一致，规则同一份。

### 6.2 备选：FlClash / Clash Meta for Android

- FlClash（Google Play 可下）：https://github.com/chen08209/FlClash/releases
- Clash Meta for Android（老牌稳定）：https://github.com/MetaCubeX/ClashMetaForAndroid/releases

流程一致。

---

## 7. 新 Mac 30 分钟上手

> 办公电脑换新 Mac，或者给家人的 Mac 第一次配置 VPN，照这个跑。

### 7.1 开干前收集 2 样东西

| 值 | 在哪找 |
|----|--------|
| 订阅 URL | 找管理员要，或从**老 Mac 的密码管理器/备忘录** |
| （可选）SSH private key | 从老 Mac `~/.ssh/id_ed25519` scp 过来 |

从老 Mac 一键拷 SSH key（新 Mac 已联网的情况下）：

```bash
# 在老 Mac 终端跑，<NEW_MAC> 替换为新 Mac 的 IP 或 Bonjour 名
scp ~/.ssh/id_ed25519* <you>@<NEW_MAC>.local:~/.ssh/
```

没有老 Mac？也能用，跳过这一步即可（翻墙不需要 SSH key）。

### 7.2 Phase 1：装 Mihomo Party

```bash
brew install --cask mihomo-party
```

（没装 Homebrew 先装：https://brew.sh/index_zh-cn）

### 7.3 Phase 2：导入订阅 + 打开开关

1. Mihomo Party → Profiles → New Profile → Remote → 粘 URL → Save
2. 点这条 Profile 变成绿色 Current
3. Overview 顶部：System Proxy ON，Tun Mode ON（首次装 helper，输 Mac 密码）

### 7.4 Phase 3：验证

Safari 打开：
- https://ipinfo.io → 日本 IP
- https://baidu.com → 秒开
- https://youtube.com → 4K 播放
- https://claude.ai → 能登录

全 ✅ = 新 Mac 就绪。

### 7.5 Phase 4（可选）：终端代理

给开发者用。大部分 App 开了 Tun 就走代理，但 curl/git/npm 有时候显式读 `HTTPS_PROXY` 环境变量。

如果你是 ace-vpn 管理员，clone 仓库后：

```bash
cd ~/workspace
git clone git@github.com:xiaonancs/ace-vpn.git
cd ace-vpn
echo "source $(pwd)/clients/shell-proxy.sh" >> ~/.zshrc
source ~/.zshrc
```

以后终端里：

```bash
proxy_on       # 打开代理
proxy_off      # 关闭
proxy_status   # 查当前状态
```

### 7.6 Phase 5（可选）：Cursor

Tun Mode 开着 Cursor 就能访问 Claude/OpenAI，不用额外配。如果个别插件报网络错误：

- Cursor → Settings → Network → HTTP Proxy: `http://127.0.0.1:7890`
- Restart Cursor

---

## 8. 日常使用小贴士

### 8.1 切换节点 / 测速

**Mihomo Party / Clash Verge**：
- 左侧 **Proxies**（代理）→ 找到节点组 **⚡AUTO** → 点 **测延迟**
- 手动选择：在节点组里点想用的那个节点

### 8.2 更新订阅（规则 / 新节点生效）

管理员改了服务端配置后，通知你"刷新订阅"。方法：

| 客户端 | 怎么刷 |
|-------|-------|
| Mihomo Party (Mac/Android) | Profiles → 该条右侧圆箭头图标 🔄 |
| Clash Verge Rev (Win) | 订阅 → 该条右上角刷新图标 |
| Stash (iOS) | Profiles → 左滑该条 → Update |
| Shadowrocket | 订阅标签 → 下拉刷新 |

### 8.3 想临时关代理

| 客户端 | 怎么关 |
|-------|-------|
| Mihomo Party / Clash Verge | 顶部 **System Proxy** 关 + **TUN Mode** 关 |
| Stash | 右上角总开关拨回去 |
| Shadowrocket | 主页顶部总开关 OFF |

### 8.4 想用公司 VPN

所有客户端都兼容：
- 正常连接公司 VPN（Cisco AnyConnect / 公司自研 App）
- 公司 VPN 会接管公司 CIDR 流量，其他照常走 ace-vpn
- 如果冲突（公司 VPN 全局代理），先关掉 TUN Mode，只开 System Proxy

### 8.5 什么时候该刷订阅

- 管理员通知"更新了规则"
- 某个网站突然打不开了（可能规则里新加了直连/代理）
- 换 VPS 后（URL 里 IP 变了）

---

## 9. 常见问题 FAQ

### Q1：所有网站都打不开

按顺序排查：

1. 系统里其他 VPN 是否开着（Let's VPN、Shadowsocks、公司 VPN）？先全关
2. 客户端顶部 System Proxy / TUN 是不是都 ON
3. Proxies 页切另一个节点试试（可能当前节点挂了）
4. 刷新订阅
5. 还不行 → 微信找管理员

### Q2：国外能开，国内很慢

TUN 模式误开成"全局"了。

- Mihomo Party → Mode 选 **Rule**（不是 Global）
- Clash Verge → 规则模式（不是全局）

### Q3：国内能开，国外不行

节点不通。排查：
- Proxies 页测延迟，看当前节点是不是超时
- 换到 ⚡AUTO 组的最低延迟节点
- 还不行 → 微信找管理员（服务端可能挂了）

### Q4：YouTube 能开但不流畅

- Proxies 页切延迟更低的节点
- 画质调到 1080p 试试（晚高峰偶尔不稳）

### Q5：Cursor / Claude Code 报 "海外 IP 检测失败"

Mac 端必须开 **TUN 模式**（不是系统代理）。`curl ipinfo.io/ip` 在终端里应该返回日本 IP。

### Q6：抖音加载慢

你的订阅里可能没有 CHINA_DIRECT 规则。**刷新订阅**（规则是服务端统一下发的）。

### Q7：家人 Windows 图标变红了 / 灰了

- 红 = 服务端连不上。刷新订阅，还不行微信找管理员
- 灰 = 没开总开关。打开 Clash Verge → 左侧图标变绿即可

### Q8：某天突然"无法连接到服务器"

大概率是：
1. VPS 当天重启了（等 2 分钟自动起来）
2. 服务端挂了（微信管理员）
3. 你的订阅 URL 过期 / 换 VPS 了（去密码管理器取最新 URL）

### Q9：订阅 URL 可以分享吗？

**不可以**。每个人的 URL 里有你专属的 SubId，分享给别人等于让他蹭流量 + 流量统计混乱。让他们找管理员单独要一条。

---

## 10. 给家人的极简卡片

可以打印 / 发截图给爸妈：

```
┌──────────────────────────────────────────┐
│   家用梯子使用说明（爸妈版）               │
├──────────────────────────────────────────┤
│  1. 桌面双击 Clash Verge 图标              │
│  2. 图标变绿 = 在翻墙                     │
│  3. 想关 → 右下角图标 → 退出              │
│  4. 上不了网 → 左侧"订阅"→ 点刷新 → 等 3 秒│
│  5. 还不行 → 发微信："梯子坏了"           │
└──────────────────────────────────────────┘
```

---

## 开发者 / 维护者请看

- 服务端部署、VPS 迁移、踩坑排查 → [`skill.md`](skill.md)
- 本地真实凭据（IP / UUID / 订阅 URL）→ `private/env.sh` / `private/ace-vpn-credentials.txt`

**不要把你的订阅 URL 贴到 GitHub / 朋友圈 / 公开群。**
