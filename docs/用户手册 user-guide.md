# ace-vpn · 用户手册（user-guide）

> 面向普通用户（家人、朋友、未来的你自己）。**不需要任何技术背景**，跟着做就能用。
>
> 如果你是开发者/维护者，请看 [`开发者日志.md`](开发者日志.md)。

---

## ✨ 亮点功能 / 索引

ace-vpn 不是普通 VPN，是一套"自己当运营商"的家庭网络分流系统。核心能力速览：

| 能力 | 一句话 | 详细 |
|------|--------|------|
| 🌐 **三网段智能分流** | 公司内网（IN）/ 国内（DIRECT）/ 海外（VPS）三种链路自动选 | [§7 三选一速查](#7-如何自定义新增-url-和规则) · [§9.3 规则优先级](#sub-converter-规则优先级) |
| 📱 **跨四端零差异** | Mac / Windows / iPhone / iPad / Android 同一份订阅 URL，规则全自动同步 | [§3](#3-mac-配置) / [§4](#4-iphone-与-ipad) / [§5](#5-windows-配置家人版) / [§6](#6-android-手机与平板) |
| ⚡ **一条命令加规则** | `bash scripts/rules/add-rule.sh <URL_OR_HOST> <IN\|DIRECT\|VPS> [HOST] [--note "..."]` 秒级生效 | [§7](#7-如何自定义新增-url-和规则) |
| 🔄 **本地优先 + 全设备同步** | Mac 本地池立即生效，攒一周一键 promote 到 VPS，全家人订阅自动刷新 | [§9.3 设计原则](#设计原则) |
| 🏢 **换公司一行命令** | profile 系统：换公司只需 `enabled: true/false`，旧公司规则保留不丢 | [§9.2 换公司内网](#92仅管理员换公司内网改一次-yaml全家生效) |
| 💻 **多 Mac git 同步本地池** | 公司 Mac / 家里 Mac 通过 private git 仓库自动同步未 promote 的规则 | [§9.3 多 Mac 同步](#多-mac-同步本地池) |
| 🔍 **一键诊断** | `bash scripts/test/test-route.sh <URL>` 输出规则命中 / DNS / TCP / TLS / TTFB 全链路 | [§9.1 换机同步](#91仅管理员换机同步拉两个仓库--symlink--pre-commit) |
| 🛡️ **公私分离 + pre-commit hook** | 真实公司域名 / VPS 凭据全在私有仓库，public 仓库 hook 拦截泄漏 | [`private/README.md`](../private/README.md) |
| 🚨 **三层安全网，永远不会"自己把自己网砍了"** | 加规则前 pre-flight 校验 + 自动备份 + 一键 `rollback-overrides.sh` 回退 | [§9.4](#94仅管理员安全网应急回退别让一条坏规则把自己的网砍了) |

> 家人只需要看 §3-§6 装 App 粘订阅 URL，剩下全自动。  
> 中级用户（自己想加规则）看 §7。  
> 管理员（你自己换机 / 换公司 / 维护规则池）看 §9。

---

## 目录

1. [这是什么？](#1-这是什么)
2. [我需要什么？](#2-我需要什么)
3. [Mac 配置](#3-mac-配置)
4. [iPhone 与 iPad](#4-iphone-与-ipad)
5. [Windows 配置（家人版）](#5-windows-配置家人版)
6. [Android 手机与平板](#6-android-手机与平板)
7. [如何自定义新增 URL 和规则](#7-如何自定义新增-url-和规则)
8. [新 Mac 30 分钟上手](#8-新-mac-30-分钟上手)
9. [管理员速查](#9-管理员速查)
10. [日常使用小贴士](#10-日常使用小贴士)
11. [常见问题 FAQ](#11-常见问题-faq)
12. [给家人的极简卡片](#12-给家人的极简卡片)
13. [仅管理员：HH / Vultr 连续 20 天测速对比](#13仅管理员hh--vultr-连续-20-天测速对比)

---

## 1. 这是什么？

一句话：**家用 VPN**。装好以后：

- 打开 Google、YouTube、ChatGPT、Claude、Discord → **可以**
- 打开 百度、淘宝、抖音、B 站 → **和平时一样快**（不会被代理拖慢）
- 公司 VPN / 打卡 App 不受影响

背后技术细节你不用关心，只需要知道两样东西：

1. **客户端 App**（Mac 用 Mihomo Party；Windows 用 Clash Verge；iPhone/iPad 用 Stash 或小火箭；**Android 用 FlClash 或 Clash Meta for Android**，见 §6）
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
| **Clash YAML**（推荐）| `http://<VPS_IP>:25500/clash/<SubId>` | Mac / Windows / Android（FlClash、CMFA）/ iPad Stash |
| **v2ray base64** | `https://<VPS_IP>:2096/<sub_path>/<SubId>` | iPhone / iPad 小火箭 |

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

## 4. iPhone 与 iPad

适用于 **iOS / iPadOS**。手机和平板**用同一套 App**（Stash / Shadowrocket），步骤几乎一样；差别主要在屏幕布局和「台前调度 / 分屏」时的操作习惯。

### 4.1 iPhone（手机）

#### 方案 A：Stash（推荐，¥15 一次性）

**优点**：和 Mac 同一份规则，零维护；iOS 上体验最接近 Mac。

##### 配置

1. App Store 搜 **Stash** → 购买下载
2. 右上 **+** → **Import from URL** → 粘贴订阅 URL
3. Name 填 `ace-vpn` → Save
4. 首页 **Configurations** 选 `ace-vpn` → 激活
5. 右上角**总开关** ON → 授权 VPN
6. **Settings → Enhanced Mode (TUN)** 打开（更稳）

##### 验证

- Safari 打开 YouTube / Google → 正常 ✅
- 抖音 App 刷视频流畅（走直连）✅
- Discord / Telegram App 能登 ✅

#### 方案 B：Shadowrocket（¥15，iOS 老牌）

**优点**：原生吃 base64 订阅，导入 30 秒。
**缺点**：规则要自己配（iOS 系统限制只能按域名/IP 分流）。

##### 配置

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

##### 维护规则的进阶方法

手写维护麻烦，可以改用**社区 ruleset**（自动更新）。在配置里加：

| 规则集 | URL | 策略 |
|-------|-----|------|
| Claude | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/Claude/Claude.list` | PROXY |
| OpenAI | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/OpenAI/OpenAI.list` | PROXY |
| Discord | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/Discord/Discord.list` | PROXY |
| 境外通用 | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/Global/Global.list` | PROXY |
| 境内大陆 | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/ChinaMax/ChinaMax.list` | DIRECT |

顺序：Claude → OpenAI → Discord → Global → ChinaMax → GEOIP CN → FINAL,PROXY。

### 4.2 iPad / iPad Pro（平板）

1. **App**：与 §4.1 完全相同 —— 在 App Store 安装 **Stash** 或 **Shadowrocket**（一次购买通常可在「同 Apple ID 的 iPhone + iPad」上共用，以 App Store 说明为准）。
2. **导入订阅**：Stash 用 **Import from URL** 粘贴 Clash 订阅；小火箭用 **Subscribe** 粘 base64 订阅（与手机一致）。
3. **建议打开**：Stash 里 **Settings → Enhanced Mode (TUN)**，平板上分屏办公时更不容易漏流量。
4. **横屏 / 键盘**：连妙控键盘时，Safari 与 App 走代理的逻辑与竖屏相同；若某 App 异常，先锁屏再解锁触发 VPN 重连，或开关一次总开关。
5. **家人只用平板**：没有 iPhone 也可以单独买 Stash / 小火箭，按上面 §4.1 同样配置即可。

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

## 6. Android 手机与平板

### 6.1 说明：为什么没有「Mihomo Party 安卓版」

**Mihomo Party（Clash Party）是桌面端（Electron）**，官方发布页只有 Windows / macOS / Linux，**没有**给手机用的 `.apk`。若在第三方站点看到所谓「Party 安卓版」，不要装，来源不可信。

安卓上要的是：**能导入 Clash YAML 订阅**、支持 **VPN 权限** 的客户端。下面两款是**官方 GitHub 带 APK** 的主流选择（手机、平板通用）。

### 6.2 首选：FlClash（推荐）

#### 下载 APK

1. 手机浏览器打开：**[FlClash Releases](https://github.com/chen08209/FlClash/releases)**
2. 下载最新带 `apk` 的包（常见文件名含 `android-arm64-v8a` 或 `universal`；不确定就选 **universal** / **arm64**）。
3. 系统设置里允许**安装未知应用**（各品牌菜单位置不同，搜「安装未知应用」）。

> 国区往往**没有** Google Play，不要死等应用商店；**直接从 GitHub 装 APK** 即可。

#### 导入订阅（与 Mac 同一条 URL）

1. 安装打开 → 允许 **VPN** 权限。
2. 找到 **配置 / Profiles / 订阅** 一类入口 → **从 URL 添加** → 粘贴管理员给的  
   `http://<VPS_IP>:25500/clash/<SubId>`。
3. **选中**该配置 → 打开主界面上的 **运行 / 系统代理 / VPN**（具体文案因版本略有不同，原则是：**让 App 接管 VPN**）。
4. 若有 **TUN / 虚拟网卡** 选项，打开后更贴近 Mac 上「全局按规则分流」的行为。

不同版本菜单名可能叫「配置」「订阅」「Profile」，认准 **URL 导入** 即可。

### 6.3 备选：Clash Meta for Android（CMFA）

1. 打开：**[Clash Meta for Android Releases](https://github.com/MetaCubeX/ClashMetaForAndroid/releases)**
2. 下载 `arm64-v8a`（绝大多数手机）或 `universal` APK。
3. App 内 **Profiles → Create Profile from URL**（或「新建配置 → URL」）→ 粘贴同一 Clash 订阅 URL → 启动 **VPN**。

与 FlClash 二选一即可，不必两个都装。

### 6.4 Android 平板

- **App**：与手机**完全相同**，安装 **FlClash 或 CMFA** 任一即可。
- **订阅**：同一条 Clash YAML URL；大屏上只是按钮位置不同。
- **分屏 / 小窗**：尽量保持代理 App 在后台未被系统「深度休眠」，否则部分机型会断 VPN；可在系统设置里给该 App **关闭电池优化**。
- **仅 Wi‑Fi 的平板**：步骤与手机一致，无需 SIM 卡。

---

## 7. 如何自定义新增 URL 和规则

> **谁该看本节**：自己已经装好客户端能科学上网（看完 §3-§6），现在想给某个特定 URL 指定走「内网 / 国内直连 / 海外代理」三种链路里的某一种。
>
> **背后原理 / 多机同步 / promote 到 VPS / sub-converter 优先级 / FAQ** 全部抽到 [§9.3 本地规则池](#93仅管理员本地规则池单机即时加规则积累后批量推-vps)，本节只给最常用的速查。

### 7.1 三个 target 怎么选

只要记住三个字母：**IN** / **DIRECT** / **VPS**。

| TARGET | 含义 | 何时用 |
|--------|------|-------|
| `IN` | 公司内网（直连 + 走公司内网 DNS） | 公司内网新发现的域名（GitLab / Jira / Confluence / OA…） |
| `DIRECT` | 普通直连（走系统/公网 DNS） | 国内站被 sub-converter 误判走代理（少见，多数已被 GEOIP CN 兜底） |
| `VPS` | 走 VPS 代理出去 | 新 AI 服务 / 新海外站点没被 sub-converter 默认覆盖 |

> 大小写无关：`in` / `In` / `IN` 都接受。也兼容老名 `intranet` / `cn` / `overseas`，自动归一。

### 7.2 一条命令加规则

```bash
cd ~/workspace/publish/ace-vpn
# 完整签名
bash scripts/rules/add-rule.sh <URL_OR_HOST> <TARGET> [HOST_OVERRIDE] [--note "备注"]
```

三种典型用法：

```bash
# 1) 最常见：扔一个 URL 进去，自动解析 host
bash scripts/rules/add-rule.sh https://gitlab.corp-a.example/  IN

# 2) 直接传裸 host（最干净；想加宽到 *.foo.com 段时推荐）
bash scripts/rules/add-rule.sh api.corp-a.example  IN  --note "公司 API（含所有 region）"

# 3) URL + 自定义 HOST：丢一长串 URL 但用第 3 个参数手动指定真正写入的 host
bash scripts/rules/add-rule.sh https://aaa.bbb.api.corp-a.example/x.dmg  IN  api.corp-a.example
#                          └─ 只用来读              └─ 真正落到 yaml 的 host
```

执行完毕规则**秒级生效**：脚本写入本地池 + 渲染 Mihomo Party override + 触发客户端 reload。打开 Mihomo Party GUI 在 Connections 里立刻能看到新规则。

> ⚠️ **HOST 匹配范围说明**
>
> 规则是 `DOMAIN-SUFFIX,host,...`，**只覆盖 `*.host` 这一精确后缀**。脚本不会替你猜"哪几段是站点边界"（没有 PSL 也猜不准 `api.foo.com` vs `foo.com`）。
>
> 当你**传完整 URL 且没传 HOST_OVERRIDE，且解析出的 host 段数 ≥ 3** 时，脚本会自动打印一段 hint，给两条可复制的"加宽匹配"命令（一条收敛到上一级、一条到 SLD）。要改已加的某条规则，直接编辑 `private/local-rules.yaml` 的 `host` 字段 → 跑 `bash scripts/rules/apply-local-overrides.sh`。
>
> `--note "..."` 可以放在任意位置，全部可选。

### 7.3 看 / 删 / 重渲染

```bash
bash scripts/rules/list-rules.sh                # 看本机积累了什么
bash scripts/rules/list-rules.sh IN             # 只看 IN 类
bash scripts/rules/list-rules.sh VPS            # 只看 VPS 类

# 想删一条：直接编辑 ace-vpn-private/local-rules.yaml 删掉那一行
$EDITOR ~/workspace/publish/ace-vpn-private/local-rules.yaml
bash scripts/rules/apply-local-overrides.sh     # 重新渲染，本机生效
```

### 7.4 攒一周之后批量推 VPS（让全家人都生效）

```bash
bash scripts/rules/promote-to-vps.sh --dry-run  # 先看计划：会推什么
bash scripts/rules/promote-to-vps.sh            # 真推（自动清空本地池）
```

推完之后家人的客户端下次刷新订阅（默认每隔几小时）就拿到新规则，不需要做任何事。

### 7.5 真实案例：长 URL 想加宽到 SLD 段

最常见的踩坑：浏览器复制下来一个超长 URL，里面 host 是带 region/服务节点
的精确长 host（例：`aaa.bbb.api.corp-a.example`），但你真正想加的是整个
`*.api.corp-a.example` 段。

❌ 老办法（一条窄规则 + 事后改 yaml）：

```bash
# 第 1 步：扔 URL 进去
bash scripts/rules/add-rule.sh https://aaa.bbb.api.corp-a.example/path/x.dmg IN
#   → 只匹配 *.aaa.bbb.api.corp-a.example 这一精确后缀，不覆盖其他 region 节点

# 第 2 步：发现匹配太窄，手动编辑 yaml 把 host 改宽
$EDITOR ~/workspace/publish/ace-vpn-private/local-rules.yaml
bash scripts/rules/apply-local-overrides.sh
```

✅ 新办法（HOST_OVERRIDE 一条搞定，不用事后手编辑 yaml）：

```bash
bash scripts/rules/add-rule.sh https://aaa.bbb.api.corp-a.example/path/x.dmg IN api.corp-a.example
#                          └─ 只用来读                                    └─ 真正落到 yaml 的 host
#   → 写入规则 host = api.corp-a.example，匹配整个 *.api.corp-a.example 段
```

更一般的速查（任何带 `://` 且 host 段数 ≥ 3 的 URL，脚本会自动给提示）：

```text
$ bash scripts/rules/add-rule.sh https://aaa.bbb.api.corp-a.example/path/x.dmg IN
  ✅ 新增：aaa.bbb.api.corp-a.example → IN

💡 当前规则按 DOMAIN-SUFFIX 只匹配 *.aaa.bbb.api.corp-a.example（精确这条后缀）
   想加宽？两种办法：
   A) 下次直接传裸 host：
        bash scripts/rules/add-rule.sh bbb.api.corp-a.example  IN   # 覆盖 *.bbb.api.corp-a.example
        bash scripts/rules/add-rule.sh corp-a.example          IN   # 覆盖整个 SLD
   B) 保留长 URL 不动，第 3 个参数手动指定要的 host：
        bash scripts/rules/add-rule.sh 'https://aaa.bbb.api.corp-a.example/path/x.dmg' IN bbb.api.corp-a.example
```

A、B 任选其一。已经踩坑加完窄规则的，照 A/B 重新加一条更宽的 + 删旧那条
（编辑 yaml 删一行）即可，不会冲突。

### 7.6 多机本地池同步（顺带说一下）

`ace-vpn/private/local-rules.yaml` 是 **symlink**，指向
`ace-vpn-private/local-rules.yaml`，由 git 跟踪。在公司 Mac 上加的规则，
回家那台只要 `git pull` 一下、再渲染一遍 override 就同步了：

```bash
# 在第二台 Mac 上偶尔同步本地池
cd ~/workspace/publish/ace-vpn-private && git pull
cd ~/workspace/publish/ace-vpn        && bash scripts/rules/apply-local-overrides.sh
```

> ⚠️ 如果你在 §9.1 之前装出来的环境 `ace-vpn/private/local-rules.yaml`
> 是独立文件而不是 symlink，跑下面这一条做 migration（一次性，做完就稳了）：
>
> ```bash
> # 假设两边都有 yaml：先合并到 private 仓库的版本，再做 symlink
> mv ~/workspace/publish/ace-vpn/private/local-rules.yaml \
>    ~/workspace/publish/ace-vpn-private/local-rules.yaml.merge && \
> $EDITOR ~/workspace/publish/ace-vpn-private/local-rules.yaml{.merge,}  # 手动合并
> ln -sf ../../ace-vpn-private/local-rules.yaml \
>    ~/workspace/publish/ace-vpn/private/local-rules.yaml
> ```

> 完整原理 / 优先级 / promote 后流程 / sub-converter 规则优先级 / FAQ
> → [§9.3](#93仅管理员本地规则池单机即时加规则积累后批量推-vps)

---

## 8. 新 Mac 30 分钟上手

> 办公电脑换新 Mac，或者给家人的 Mac 第一次配置 VPN，照这个跑。

### 8.1 开干前收集 2 样东西

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

### 8.2 Phase 1：装 Mihomo Party

```bash
brew install --cask mihomo-party
```

（没装 Homebrew 先装：https://brew.sh/index_zh-cn）

### 8.3 Phase 2：导入订阅 + 打开开关

1. Mihomo Party → Profiles → New Profile → Remote → 粘 URL → Save
2. 点这条 Profile 变成绿色 Current
3. Overview 顶部：System Proxy ON，Tun Mode ON（首次装 helper，输 Mac 密码）

### 8.4 Phase 3：验证

Safari 打开：
- https://ipinfo.io → 日本 IP
- https://baidu.com → 秒开
- https://youtube.com → 4K 播放
- https://claude.ai → 能登录

全 ✅ = 新 Mac 就绪。

### 8.5 Phase 4（可选）：终端代理

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

### 8.6 Phase 5（可选）：Cursor

Tun Mode 开着 Cursor 就能访问 Claude/OpenAI，不用额外配。如果个别插件报网络错误：

- Cursor → Settings → Network → HTTP Proxy: `http://127.0.0.1:7890`
- Restart Cursor

---

## 9. 管理员速查

> **谁该看本节**：你（管理员）自己。家人不需要看。这里把 ace-vpn 维护过程中三个最高频场景集中放在一处：换机、换公司、维护规则池。
>
> | 场景 | 跳转 |
> |------|------|
> | 拿到一台新 Mac，要装出完整开发环境（脚本 + 真实配置 + pre-commit） | [§9.1](#91仅管理员换机同步拉两个仓库--symlink--pre-commit) |
> | 换工作 / 兼职多家 / 离职保留旧公司配置 | [§9.2](#92仅管理员换公司内网改一次-yaml全家生效) |
> | 单机即时加规则、积累后批量推 VPS | [§9.3](#93仅管理员本地规则池单机即时加规则积累后批量推-vps) |
> | 加规则后突然全网炸了 / 想立即"回到上一个能上网的版本" | [§9.4](#94仅管理员安全网应急回退别让一条坏规则把自己的网砍了) |

---

### 9.1（仅管理员）换机同步：拉两个仓库 + symlink + pre-commit

> **家人可以跳过本节。** 这里是你（管理员）在另一台 Mac 上重新装出一套完整
> 开发环境（public 脚本 + private 真实配置 + pre-commit 防泄漏 hook）的速查。

仓库结构：
- `ace-vpn`（public，GitHub 公开）—— 脚本、文档、模板
- `ace-vpn-private`（private，GitHub 私有）—— 真实 `intranet.yaml` / `env.sh` / `credentials.txt` / `sensitive-words.txt`
- public 仓库的 `private/` 下文件是 **symlink** 指向 private 仓库

> **前置：private 仓库里要有 `env.sh`**
> 最早只有 `ace-vpn/private/env.sh.minimal.example` 这个公开模板，真实 env.sh
> 应当放到 private 仓库。如果 `ace-vpn-private/env.sh` 还不存在（第一次启用
> private 仓库），在任意一台已知 VPS_IP 的机器上做一次：
>
> ```bash
> cp ~/workspace/publish/ace-vpn/private/env.sh.minimal.example \
>    ~/workspace/publish/ace-vpn-private/env.sh
> chmod 600 ~/workspace/publish/ace-vpn-private/env.sh
> $EDITOR  ~/workspace/publish/ace-vpn-private/env.sh        # 填真实 VPS_IP
> cd       ~/workspace/publish/ace-vpn-private
> git add env.sh && git commit -m "env: init" && git push
> ```
>
> 之后所有 Mac 只要 `git pull` private 仓库就拿到了最新 env.sh，换 VPS 时也
> 只在一处修改 + push。

#### 一次性配好（新 Mac 执行）

```bash
# 1. 拉两个仓库
mkdir -p ~/workspace/publish && cd ~/workspace/publish
git clone https://github.com/xiaonancs/ace-vpn.git
git clone https://github.com/xiaonancs/ace-vpn-private.git

# 2. 建 symlink 把真实配置挂进 public 仓库的 private/ 下
cd ~/workspace/publish/ace-vpn
ln -sf ../../ace-vpn-private/intranet.yaml   private/intranet.yaml
ln -sf ../../ace-vpn-private/env.sh          private/env.sh           # 有才建
ln -sf ../../ace-vpn-private/credentials.txt private/credentials.txt  # 有才建

ls -la private/                              # 应看到 symlink 指向 ../../ace-vpn-private/...
# env.sh 如果存在就直接用；从这里开始后续脚本会自动 source
[ -L private/env.sh ] && source private/env.sh && echo "VPS_IP_LIST=$VPS_IP_LIST"

# 3. 装 pre-commit hook（不跟 git 走，每台新机都要装）
cat > .git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
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
chmod +x .git/hooks/pre-commit
bash .git/hooks/pre-commit && echo "hook OK"
```

#### 日常同步（之前已经配过）

```bash
cd ~/workspace/publish/ace-vpn         && git pull
cd ~/workspace/publish/ace-vpn-private && git pull
```

#### 冒烟测试（确认同步完成）

`test-route.sh` / `sync-intranet.sh` 在 `$VPS_IP_LIST` 没设时会**自动** `source private/env.sh`，所以不需要手动 source：

```bash
cd ~/workspace/publish/ace-vpn
bash scripts/test/test-route.sh https://www.google.com/         # 应命中 🚀 PROXY
bash scripts/test/test-route.sh https://www.baidu.com/          # 应命中 DIRECT
bash scripts/test/test-route.sh https://<你公司内网域名>/          # 应命中 DIRECT（intranet profile）
```

---

### 9.2（仅管理员）换公司内网：改一次 YAML，全家生效

> **家人可以跳过本节。** 换工作 / 同时兼职多家 / 离职保留配置 都在这里。

#### 路径 A — 单公司切换（换工作）

编辑 `ace-vpn-private/intranet.yaml`（= `ace-vpn/private/intranet.yaml`，symlink 同一文件）：

```yaml
# 旧公司：保留数据 + 关掉开关，将来返聘秒恢复
corp_a:
  enabled: false
  desc: "前东家 Corp A（已离职）"
  dns_servers: [10.x.x.1, 10.x.x.2]
  domains: [office.corp-a.example, portal.corp-a.example]

# 新公司：新增一段
corp_b:
  enabled: true
  desc: "新东家 Corp B"
  dns_servers:
    - 10.y.y.1                      # 新公司内网 DNS（IT 手册 / scutil --dns 抓）
    - 10.y.y.2
  domains:
    - office.corp-b.example         # 协作平台
    - portal.corp-b.example         # 内网门户
    - git.corp-b.example            # 内部 git
  cidrs:
    - 10.y.0.0/16                   # 保险起见加整段
```

两条命令推送：

```bash
cd ~/workspace/publish/ace-vpn
bash scripts/rules/sync-intranet.sh      # 脚本自己会 source private/env.sh
```

`sync-intranet.sh` 会做：① 本地 YAML 语法校验 ② `scp` 到 VPS `/etc/ace-vpn/intranet.yaml` ③ VPS 端 `sub-converter.py` 下次订阅请求**自动重读**（无 systemctl restart）。

最后任意客户端 **点一下"刷新订阅"** → 新规则下发。家人不用动，他们的客户端会自动轮询订阅。

#### 路径 B — 多公司并存（外包 / 咨询 / 临时返聘）

两个 profile 同时 `enabled: true`：

```yaml
corp_a: { enabled: true, dns_servers: [10.x.x.1, 10.x.x.2], domains: [portal.corp-a.example] }
corp_b: { enabled: true, dns_servers: [10.y.y.1, 10.y.y.2], domains: [git.corp-b.example] }
```

`sub-converter.py` 会合并生成规则，每个域名走自己 profile 声明的 `dns_servers`（`+.portal.corp-a.example: [10.x.x.1,10.x.x.2]`、`+.git.corp-b.example: [10.y.y.1,10.y.y.2]`），彼此不冲突。唯一约束：**两家内网 IP 段不能重叠**（域名维度天然隔离，不受影响）。

#### 备份到 private 仓库

改完真实数据一定要提交 private 仓库（**不是** public）：

```bash
cd ~/workspace/publish/ace-vpn-private
git add intranet.yaml
git commit -m "intranet: 切换到新公司 Corp B；Corp A 保留但 disabled"
git push
```

#### 新公司某个域名没通？一条命令定位

```bash
bash scripts/test/test-route.sh https://git.corp-b.example/
```

一次输出：规则命中 / DNS 解析 / TCP / TLS / TTFB 各阶段延时 / 出口 IP。95% 的接入问题能被这一条命令定位。剩下 5% 多半是本机**公司 VPN 客户端没连上**（Corplink / AnyConnect 等），内网 CIDR 路由没发布到 `utun`，`DIRECT` 命中后包无处可发。

---

### 9.3（仅管理员）本地规则池：单机即时加规则，积累后批量推 VPS

> **家人可以跳过本节。** 适用场景：日常发现某个域名要走代理 / 直连 / 内网，不想每条都立刻惊动 VPS 和家人客户端，先在自己 Mac 上即时生效，攒一周再批量推。

#### 设计原则

```
   ┌──────────────────┐
   │  优先级（从高到低）  │
   ├──────────────────┤
   │  1. 本地池规则     │  ← Mihomo Party override.yaml prepend
   │  2. VPS 订阅规则   │  ← sub-converter 生成
   │  3. MATCH/FINAL   │
   └──────────────────┘
```

天然就是 "**本地 > VPS**"。promote 到 VPS 后本地池清空，"VPS 新规则覆盖本地旧规则" 自动达成（本地为空，全是 VPS）。

#### 三个 target 落到什么规则

`IN`/`DIRECT`/`VPS` 三选一的**用户视角**和**速查命令**已经在 [§7](#7-如何自定义新增-url-和规则) 给过。这里补充每个 target 在底层落成什么：

| TARGET | 落到什么 |
|--------|----------|
| `IN` | `DOMAIN-SUFFIX,host,DIRECT` + 走当前 enabled profile 的内网 DNS（fake-ip-filter + nameserver-policy） |
| `DIRECT` | `DOMAIN-SUFFIX,host,DIRECT`（走系统/公网 DNS） |
| `VPS` | `DOMAIN-SUFFIX,host,🚀 PROXY` |

三种 target promote 到 VPS 后的去向：

| TARGET | 写入 `intranet.yaml` 的位置 | 是否随 profile 切换 |
|--------|------------------------------|---------------------|
| `IN` | `profiles[当前 enabled].domains` | ✅ 跟着公司走 |
| `VPS` | 顶层 `extra.overseas` | ❌ 跨公司共享 |
| `DIRECT` | 顶层 `extra.cn` | ❌ 跨公司共享 |

> intranet.yaml 顶层 `extra.overseas` / `extra.cn` 的字段名是历史 schema（sub-converter 在 VPS 上读它）。用户层只看 IN/DIRECT/VPS 即可，schema 命名是内部细节。

#### 4 个脚本（cheatsheet）

四件套：`add-rule.sh` / `list-rules.sh` / `apply-local-overrides.sh` / `promote-to-vps.sh`。常用命令在 [§7.2-§7.4](#7-如何自定义新增-url-和规则)，这里不再重复。

#### add-rule 之后发生了什么

1. 写入 `ace-vpn-private/local-rules.yaml`（git 跟踪，多 Mac 同步本地池）
2. 渲染 → `~/Library/Application Support/mihomo-party/override/ace-vpn-local.yaml`
3. 自动注册到 `~/Library/Application Support/mihomo-party/override.yaml`（item id = `ace-vpn-local`，global=true）
4. Mihomo Party GUI 监听 override 目录变化 → **秒级自动 reload**，本机生效
5. 从此这条规则的优先级最高，订阅刷新 / 配置切换都不会冲掉它

> **GUI 没启动？** 没关系，文件已经写好了，下次开 Mihomo Party 自动应用。

#### promote 之后发生了什么

1. 扫描本地池，按 target 分组合并到 `intranet.yaml`：
   - `IN` → 当前 enabled profile 的 `domains`（跟着公司走，换公司会一起 enable/disable）
   - `VPS` → 顶层 `extra.overseas`（跨 profile 共享，换公司不影响）
   - `DIRECT` → 顶层 `extra.cn`（跨 profile 共享）
2. 调 `sync-intranet.sh` scp 到 VPS，sub-converter 热加载（无需 systemctl restart）
3. 已 promote 的规则全部从本地池删除（避免重复）
4. 重新渲染本地 override（本地池空了那部分，规则 100% 来自 VPS 订阅）
5. 家人客户端：下次订阅刷新（默认每隔几小时，或手动点刷新）拿到新规则

#### sub-converter 规则优先级

```
1. profile.cidrs                              → DIRECT
2. profile.domains（IN 类落这里）              → DIRECT  + 走 profile.dns_servers
3. 私有网段（127/8、10/8、192.168/16…）        → DIRECT
4. extra.overseas（VPS 类落这里）              → 🚀 PROXY      ← 用户加的赢内置
5. extra.cn（DIRECT 类落这里）                 → DIRECT        ← 用户加的赢内置
6. AI 内置（OpenAI/Claude/Cursor…）            → 🤖 AI
7. 海外社交内置（Discord/X/Telegram…）         → 🚀 PROXY
8. 流媒体内置（YouTube/Netflix…）              → 📺 MEDIA
9. 国内常用内置（淘宝/B 站/抖音…）              → DIRECT
10. GEOIP CN                                  → DIRECT
11. MATCH                                     → 🐟 FINAL
```

`extra.*` 在内置 AI / SOCIAL_PROXY / CHINA_DIRECT 之前，所以你 promote 的规则**永远赢内置默认**——比如某个本来被 GEOIP CN 误判的国内站，加 `DIRECT` 后立刻直连；某个新 AI 服务加 `VPS` 后立刻代理。

#### 多 Mac 同步本地池

`local-rules.yaml` 在 private 仓库里，git 跟踪。在公司 Mac 上加的规则，回家那台只要 `git pull` 一下，再跑一次 `bash scripts/rules/apply-local-overrides.sh` 就同步了 override。

```bash
# 在第二台 Mac 上偶尔同步本地池
cd ~/workspace/publish/ace-vpn-private && git pull
cd ~/workspace/publish/ace-vpn        && bash scripts/rules/apply-local-overrides.sh
```

#### 常见疑问

- **Q：IN/DIRECT/VPS 这三个名字怎么记？** `IN`=内网（**In**tranet）、`DIRECT`=普通直连、`VPS`=经过 VPS 出去（=代理）。从用户视角讲，VPS 就是"那台中转服务器"。
- **Q：用老名 `intranet`/`cn`/`overseas` 还能用吗？** 能。脚本和 yaml 都自动归一到 IN/DIRECT/VPS，旧文档/旧池不会坏。新加的统一用大写三字母。
- **Q：本地池能放多久？** 没有上限。但建议每 1-2 周 promote 一次，避免家人那边规则缺失太多。
- **Q：promote 后我的 Mac 还有那条规则吗？** 有，只是从"本地池 prepend"变成"VPS 订阅里的 extra/profile.domains"，优先级降一档但效果不变。
- **Q：换公司后 VPS 类规则会丢吗？** 不会。VPS / DIRECT 类落在顶层 `extra`（`extra.overseas` / `extra.cn`），独立于 profiles，不受 enabled/disabled 影响。换公司只切 profile，新 AI / 海外站点继续生效。
- **Q：手编辑 `local-rules.yaml` 行不行？** 行。改完跑 `bash scripts/rules/apply-local-overrides.sh` 渲染一下。
- **Q：怎么删一条本地规则？** 直接编辑 `local-rules.yaml` 删行 → `apply-local-overrides.sh`。
- **Q：怎么删一条已经 promote 到 VPS 的规则？** 编辑 `private/intranet.yaml`（删掉 extra.overseas / extra.cn / profile.domains 里那行）→ `bash scripts/rules/sync-intranet.sh`。

---

### 9.4（仅管理员）安全网 & 应急回退：别让一条坏规则把自己的网砍了

> **背景故事**（真事）：某次给 `gemini.google.com` 加了条 `VPS` 规则，结果代码里硬编码的
> proxy group 名（`🚀 节点选择`）和 sub-converter 实际生成的 group 名（`🚀 PROXY`）对不上 →
> Mihomo Party 加载 profile 时报 `proxy [🚀 节点选择] not found` → **整个 profile 加载失败 →
> 直接没网 → 连 VPS 都改不了 → 也没法用 Cursor / Claude Code 修 → 砖**。
>
> 这一节就是把这种"自己把电话线砍了"的灾难永久挡住的安全网。

#### 三层安全网

| 层 | 触发时机 | 干什么 |
|----|---------|--------|
| **① pre-flight 校验** | `add-rule.sh` / `apply-local-overrides.sh` 写 override 之前 | 解析当前 active profile 拿到所有合法 proxy group 名集合，把本地池里所有 `VPS` 类规则的 target proxy 比对一遍。**任意一个不在集合里就拒绝写入**，旧 override 完整保留，网络不受影响 |
| **② 自动备份** | 每次成功写入 override 之前 | 当前 override 文件复制到 `~/Library/Application Support/mihomo-party/override/.bak/<file>.<timestamp>.bak`，自动保留最近 10 个 |
| **③ 一键回退** | 出问题后 | `bash scripts/rules/rollback-overrides.sh` 列备份选一个回退；或 `--last` 直接回退到最近一个；或 `--disable` 把整个本地 override 暂时关掉 |

#### 校验失败长什么样

故意加一条引用不存在 group 的规则后，apply 会拒绝写入并明确告诉你坏在哪：

```
pre-flight 校验失败，未写入 override（你的网络不受影响）：

  ✗ VPS 类规则 host=test.com 引用 proxy '🚀 不存在的群组'，但当前 profile 里没有这个 group

当前 profile 里可用的 proxy group：
    ace-vpn-reality-hxn-iwork, ⚡ AUTO, 🐟 FINAL, 📺 MEDIA, 🚀 PROXY, 🤖 AI

修法：编辑 ~/workspace/publish/ace-vpn-private/local-rules.yaml 修正/删除上面那些坏规则，
     再跑一次 bash scripts/rules/apply-local-overrides.sh
```

注意：**坏规则只是拒绝写入，旧 override 文件没动**——你的网络在这一刻是好的。

#### 应急救援命令速查

```bash
# 1) 列出所有备份（看历史，啥也不改）
bash scripts/rules/rollback-overrides.sh --list

# 2) 一键回退到最近一个备份（最常用）
bash scripts/rules/rollback-overrides.sh --last

# 3) 交互选：列出备份让你按编号选
bash scripts/rules/rollback-overrides.sh

# 4) 把整个本地 override 暂时禁用 —— 订阅原样加载，本地池"装作没装"
#    这是最强应急，连 override 文件都不读。备份还在，本地池源文件 local-rules.yaml 也不动。
bash scripts/rules/rollback-overrides.sh --disable
# 排查完后恢复：
bash scripts/rules/rollback-overrides.sh --enable

# 5) 清空 override 内容（保留注册）—— 比 --disable 温和，等于"本地池为空"
bash scripts/rules/rollback-overrides.sh --clear
```

#### 真没救了怎么办（手动应急）

如果上面命令都跑不动（比如 Python 也炸了），**直接在 Mihomo Party GUI 里**：

1. 顶部 **System Proxy** + **TUN Mode** 都关掉（先脱机但能上网）
2. 左侧 **Override（覆写）** → 把 `ace-vpn local rules` 那条 enabled 拨成 false
3. 切一下 profile 让它重新加载
4. 网通了，再回到终端慢慢排查 `local-rules.yaml`

或者命令行删 override 文件：

```bash
mv ~/Library/Application\ Support/mihomo-party/override/ace-vpn-local.yaml \
   ~/Library/Application\ Support/mihomo-party/override/ace-vpn-local.yaml.bad
```

Mihomo Party 监听到文件没了会重新只加载订阅，秒级恢复。

#### 为什么这套机制能彻底防"砖"

- **核心**：override 写入是"先校验后写"——**坏规则永远进不了 override 文件**，就不可能让 profile 加载失败
- **第二保险**：万一校验有盲区漏过去（比如 sub-converter 改了 group 名我们没及时同步），自动备份保证 30 秒内能恢复到上一个能上网的状态
- **第三保险**：`--disable` 直接绕开本地 override，等于"本地池不存在"，订阅原样工作

> ⚠ **VPS 那条线还没接入这套校验**：`promote-to-vps.sh` 把规则推到 VPS 后由 sub-converter 重生成订阅。如果想加同等强度的"VPS 端 pre-flight + 自动 rollback"，需要改 `sync-intranet.sh` 在 VPS 上备份 `intranet.yaml.bak` + 推送后调 `/healthz` 验证，失败就 ssh 回滚。这个还没做，目前 VPS 端依赖 promote 时本地 sub-converter 的 dry-run（如果本地能解析就大概率 VPS 也能）。短期建议：**promote 后立即在浏览器开 `http://VPS_IP:25500/healthz` 看一眼计数对不对**，然后再让家人刷订阅。

---

## 10. 日常使用小贴士

### 10.1 切换节点 / 测速

**Mihomo Party / Clash Verge**：
- 左侧 **Proxies**（代理）→ 找到节点组 **⚡AUTO** → 点 **测延迟**
- 手动选择：在节点组里点想用的那个节点

### 10.2 更新订阅（规则 / 新节点生效）

管理员改了服务端配置后，通知你"刷新订阅"。方法：

| 客户端 | 怎么刷 |
|-------|-------|
| Mihomo Party (Mac) | Profiles → 该条右侧圆箭头图标 🔄 |
| FlClash / CMFA (Android) | 配置 / 订阅页 → 选中配置 → 更新或下拉刷新（以当前版本界面为准） |
| Clash Verge Rev (Win) | 订阅 → 该条右上角刷新图标 |
| Stash (iPhone / iPad) | Profiles → 左滑该条 → Update |
| Shadowrocket | 订阅标签 → 下拉刷新 |

### 10.3 想临时关代理

| 客户端 | 怎么关 |
|-------|-------|
| Mihomo Party / Clash Verge | 顶部 **System Proxy** 关 + **TUN Mode** 关 |
| FlClash / CMFA | 主界面 **停止 / 断开 VPN**（或关闭「运行」开关） |
| Stash | 右上角总开关拨回去 |
| Shadowrocket | 主页顶部总开关 OFF |

### 10.4 想用公司 VPN

所有客户端都兼容：
- 正常连接公司 VPN（Cisco AnyConnect / 公司自研 App）
- 公司 VPN 会接管公司 CIDR 流量，其他照常走 ace-vpn
- 如果冲突（公司 VPN 全局代理），先关掉 TUN Mode，只开 System Proxy

### 10.5 什么时候该刷订阅

- 管理员通知"更新了规则"
- 某个网站突然打不开了（可能规则里新加了直连/代理）
- 换 VPS 后（URL 里 IP 变了）

---

## 11. 常见问题 FAQ

### Q1：所有网站都打不开

按顺序排查：

1. **如果是刚加完规则**（管理员场景）：八成是规则把 profile 加载坏了。立刻跑 `bash scripts/rules/rollback-overrides.sh --last`（30 秒内恢复），详见 [§9.4](#94仅管理员安全网应急回退别让一条坏规则把自己的网砍了)
2. 系统里其他 VPN 是否开着（Let's VPN、Shadowsocks、公司 VPN）？先全关
3. 客户端顶部 System Proxy / TUN 是不是都 ON
4. Proxies 页切另一个节点试试（可能当前节点挂了）
5. 刷新订阅
6. 还不行 → 微信找管理员

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

## 12. 给家人的极简卡片

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

## 13. 仅管理员：HH / Vultr 连续 20 天测速对比

这一节给管理员用，用来长期比较 **HostHatch（HH）** 和 **Vultr** 两台 VPS 到常用海外服务的稳定性。

它的工作方式是：

1. 本地 Mac 用 macOS `launchd` 每 30 分钟触发一次；
2. 脚本读取 `private/env.sh` 里的 `VPS_IP_LIST`，通常是 `hosthatch:<IP> vultr:<IP>`；
3. 本地 Mac 分别 SSH 到 HH / Vultr；
4. 在两台 VPS 上对同一批 URL 跑 `curl`；
5. 所有结果追加到本地日志 `~/Library/Logs/ace-vpn/vps-watch.log`；
6. 20 天后用 `scripts/test/vps-watch-summary.py` 汇总成功率、median、p95、平均耗时和每个 URL 的赢家。

注意：这测的是 **VPS → 目标网站** 的出站质量，用来比较 HH / Vultr 哪台到 AI、YouTube、X、Discord、Telegram、GitHub 等服务更稳。它不是完整的 `Mac → VPS → 目标网站` 代理链路测试。

### 13.1 前置条件

先确认本地有最新代码：

```bash
cd ~/workspace/cursor-base/ace-vpn
git pull
```

确认 `private/env.sh` 里至少有这些变量：

```bash
export VPS_IP_LIST="hosthatch:<HostHatch-IP> vultr:<Vultr-IP>"
export VPS_SSH_USER="root"
export VPS_SSH_KEY="$HOME/.ssh/id_ed25519_vps"
```

加载环境变量：

```bash
source private/env.sh
```

确认两台 VPS 都能免密 SSH：

```bash
ssh -i "$VPS_SSH_KEY" "$VPS_SSH_USER@<HostHatch-IP>" 'echo hosthatch-ok'
ssh -i "$VPS_SSH_KEY" "$VPS_SSH_USER@<Vultr-IP>" 'echo vultr-ok'
```

如果还要输密码，先给两台 VPS 装本机公钥：

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub "$VPS_SSH_USER@<HostHatch-IP>"
ssh-copy-id -i ~/.ssh/id_ed25519.pub "$VPS_SSH_USER@<Vultr-IP>"
```

如果你的公钥不是 `id_ed25519.pub`，换成实际文件名。

### 13.2 手动试跑一次

先手动跑一次，确认脚本能同时测 HH / Vultr：

```bash
cd ~/workspace/cursor-base/ace-vpn
source private/env.sh
bash scripts/test/vps-watch-urls.sh --log
```

结果会打印到终端，同时追加到：

```bash
~/Library/Logs/ace-vpn/vps-watch.log
```

日志每一行是 TSV 格式，字段含义：

```text
时间    节点名    VPS IP    HTTP状态码    总耗时    TCP耗时    TLS耗时    远端IP    URL
```

说明：

- `HTTP状态码=000`：超时 / 连接失败；
- `total`：从发起请求到拿到响应的总耗时；
- `tcp`：TCP 建连耗时；
- `ssl`：TLS 握手耗时；
- 403 / 404 / 421 不一定是坏事。很多 AI / API 站点没登录态或没 API Key 时会返回这些状态，这里主要比较“能不能快速度拿到响应”。

### 13.3 启动每 30 分钟自动测速

复制 LaunchAgent 模板：

```bash
cp scripts/launchd/ace-vpn.vps-watch-urls.example.plist \
  ~/Library/LaunchAgents/com.xiaonancs.ace-vpn.vps-watch-urls.plist
```

把模板里的 `__REPO_ROOT__` 替换成本机仓库路径：

```bash
sed -i '' "s#__REPO_ROOT__#$(pwd)#g" \
  ~/Library/LaunchAgents/com.xiaonancs.ace-vpn.vps-watch-urls.plist
```

加载定时任务：

```bash
launchctl load ~/Library/LaunchAgents/com.xiaonancs.ace-vpn.vps-watch-urls.plist
```

这个命令执行后会发生两件事：

- 因为 plist 里有 `RunAtLoad=true`，所以**会立刻跑一次**；
- 因为 plist 里有 `StartInterval=1800`，所以之后会**每 30 分钟自动跑一次**。

也可以手动触发一次：

```bash
launchctl start com.xiaonancs.ace-vpn.vps-watch-urls
```

### 13.4 查看是否在运行

查看任务是否已注册：

```bash
launchctl list | grep ace-vpn
```

有输出说明已加载；没有输出说明没加载或已经停掉。

查看实时日志：

```bash
tail -f ~/Library/Logs/ace-vpn/vps-watch.log
```

查看最近几次结果：

```bash
tail -80 ~/Library/Logs/ace-vpn/vps-watch.log
```

### 13.5 随时汇总结果

默认汇总最近 20 天：

```bash
cd ~/workspace/cursor-base/ace-vpn
python3 scripts/test/vps-watch-summary.py
```

输出会包含三块：

- `summary`：总体范围、节点、URL 数、记录数；
- 按 `node + url` 聚合的成功率、超时次数、median、p95、平均耗时；
- `comparison_by_url`：每个 URL 上 HH / Vultr 谁的 median 更低，以及谁成功率更高。

如果想把最近 20 天的**所有原始记录**也一起打印出来：

```bash
python3 scripts/test/vps-watch-summary.py --records
```

如果想汇总全部历史日志，不限 20 天：

```bash
python3 scripts/test/vps-watch-summary.py --all
```

如果日志在自定义路径：

```bash
python3 scripts/test/vps-watch-summary.py --log ~/Desktop/vps-watch.log
```

### 13.6 20 天后如何停止

停止定时任务：

```bash
launchctl unload ~/Library/LaunchAgents/com.xiaonancs.ace-vpn.vps-watch-urls.plist
```

确认已经停止：

```bash
launchctl list | grep ace-vpn
```

没有输出就说明已经停了。

如果以后不再用，可以删除 LaunchAgent 文件：

```bash
rm ~/Library/LaunchAgents/com.xiaonancs.ace-vpn.vps-watch-urls.plist
```

日志不会因为停止任务而自动删除。要保留结果就别删；要清掉日志：

```bash
rm ~/Library/Logs/ace-vpn/vps-watch.log
```

### 13.7 常见问题

**Q：启动后会一直跑吗？**

会。只要执行过 `launchctl load ...plist`，并且没有 `unload`，它就会每 30 分钟自动跑一次。

**Q：Mac 重启后还会跑吗？**

会。`~/Library/LaunchAgents/` 下的任务会在你登录该用户后自动加载。

**Q：结果在哪里？**

默认在：

```bash
~/Library/Logs/ace-vpn/vps-watch.log
```

**Q：会不会影响电脑上网？**

基本不会。它每 30 分钟 SSH 到两台 VPS，各自 curl 二三十个 URL。主要消耗 VPS 出站和少量本地 CPU / 网络。

**Q：会不会产生很多日志？**

20 天约为：`20 天 × 48 次/天 × 2 台 VPS × 约 25 个 URL ≈ 4.8 万行`。TSV 文本体积很小，通常只有几 MB。

**Q：某些 URL 状态码不是 200，是不是失败？**

不一定。AI / API 站点在未登录或无 API Key 时返回 403 / 404 / 421 很常见。这里更关注：

- 是否超时（`000`）；
- `total` 是否明显偏高；
- HH / Vultr 谁的 median / p95 更低；
- 哪台成功率更高。

---

## 开发者 / 维护者请看

- 服务端部署、VPS 迁移、踩坑排查 → [`开发者日志.md`](开发者日志.md)
- 本地真实凭据（IP / UUID / 订阅 URL）→ `private/env.sh` / `private/ace-vpn-credentials.txt`

**不要把你的订阅 URL 贴到 GitHub / 朋友圈 / 公开群。**
