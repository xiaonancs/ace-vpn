# 📱 四端客户端配置手册（Mac / iOS / Android / Windows）

> 本文是「**上手即用**」的客户端配置手册，对应服务端 [`03-server-setup.md`](03-server-setup.md) 已搭好的 3x-ui + sub-converter。  
> 请先在 `private/env.sh` 里填好真实值，下面示例用占位符（**不要**直接复制）。

---

## 0. 先准备这些值（一次性填到 `private/env.sh`）

```bash
# 复制示例
cp private/env.sh.example private/env.sh && chmod 600 private/env.sh
# 打开填真实值
$EDITOR private/env.sh

source private/env.sh
```

填好后，下面四种场景需要用到这些 URL：

| 给谁用 | URL 形式 |
|--------|---------|
| **Clash 系**（Mac / Stash / Android Mihomo Party / Win Clash Verge Rev） | `$URL_CLASH_HOME` → `http://<VPS_IP>:25500/clash/<SUB_TOKEN>` |
| **Shadowrocket**（iOS / iPadOS）| `$URL_XUI_SUB_HOME` → `https://<VPS_IP>:2096/<sub_path>/<subId>` |

**两条 URL 的区别**：见 [05-journey-and-skill.md §1.3](05-journey-and-skill.md#13-架构图一屏)。  
简答：前者是**节点+规则**的 Clash YAML；后者是**纯节点**的 v2ray base64。

---

## 1. Mac（Mihomo Party）⭐ 推荐

### 1.1 安装

```bash
brew install --cask mihomo-party
# 或手动下载：https://github.com/mihomo-party-org/mihomo-party/releases
```

### 1.2 配置

1. 打开 Mihomo Party
2. 左侧 **Profiles** → 右上 **New Profile** → 选 **Remote** → 粘贴 `$URL_CLASH_HOME`
3. Name 填 `ace-vpn`，保存
4. **点一下这条 Profile 使其变成 Current**（圆圈变绿）
5. 回 **Overview**，顶部两个开关：
   - **System Proxy** = ON（浏览器走代理）
   - **Tun Mode** = ON（给 Cursor / 终端 / Claude Code 用，**首次需输 Mac 密码安装 helper**）

### 1.3 验证

```bash
# 翻墙
curl -s https://ipinfo.io/ip        # → 日本 IP
# 国内直连
curl -s https://www.baidu.com -I    # → 200 OK，速度快
```

浏览器：Google / YouTube 4K / ChatGPT / Claude 都能开；Baidu / 淘宝 / B站秒开。

### 1.4 日常维护

- **服务端改规则后**：Profiles → 该条右侧 **Refresh/↻** → 新规则即刻生效
- **节点延迟不理想**：Proxies 页 → `⚡ AUTO` 组 → 测速

---

## 2. iOS / iPadOS

### 2.1 方案 A：Stash（推荐，$1.99 一次性）

**优点**：吃 Clash YAML，和 Mac 同一份规则，零维护。

**配置**：

1. App Store 搜 **Stash** → 购买下载
2. 右上 **+** → **Import from URL** → 粘贴 `$URL_CLASH_HOME`
3. Name `ace-vpn` → Save
4. 首页 **Configurations** 选 `ace-vpn` → 激活
5. 右上角总开关 ON → 授权 VPN
6. 开 **Settings → Enhanced Mode (TUN)** 更稳

**验证**：Safari 打开 YouTube / Google；抖音 App 刷视频流畅（确认走直连）；Discord App 能登录。

### 2.2 方案 B：Shadowrocket（$2.99）

**优点**：原生吃 3x-ui base64 订阅，导入 30 秒完。

**劣势**：规则要自己配（iOS 只能按域名/IP，iOS 系统限制）。

**配置**：

1. App Store 买 **Shadowrocket**
2. 右上 **+** → **Type: Subscribe** → URL 粘贴 `$URL_XUI_SUB_HOME`
3. Remark `ace-vpn` → Save → 列表里会自动拉出所有节点
4. 首页切换到 **配置（Config）** 标签 → 默认会有一个「config」配置
5. **全局路由** 选 **配置**（不是代理/直连/规则那种全局）
6. 点「config」进入编辑，**规则** 区域加以下条目（顺序从上到下）：

```
DOMAIN-SUFFIX,discord.com,PROXY
DOMAIN-SUFFIX,discordapp.com,PROXY
DOMAIN-SUFFIX,discordapp.net,PROXY
DOMAIN-SUFFIX,discord.gg,PROXY
DOMAIN-KEYWORD,discord,PROXY
DOMAIN-SUFFIX,cursor.sh,PROXY
DOMAIN-SUFFIX,cursor.com,PROXY
DOMAIN-SUFFIX,anthropic.com,PROXY
DOMAIN-SUFFIX,claude.ai,PROXY
DOMAIN-SUFFIX,openai.com,PROXY
DOMAIN-SUFFIX,chatgpt.com,PROXY
DOMAIN-SUFFIX,twitter.com,PROXY
DOMAIN-SUFFIX,x.com,PROXY
DOMAIN-SUFFIX,t.me,PROXY
DOMAIN-SUFFIX,telegram.org,PROXY
DOMAIN-SUFFIX,googlevideo.com,PROXY
DOMAIN-SUFFIX,youtube.com,PROXY
DOMAIN-SUFFIX,google.com,PROXY
DOMAIN-SUFFIX,googleapis.com,PROXY
DOMAIN-SUFFIX,gstatic.com,PROXY
DOMAIN-SUFFIX,github.com,PROXY
DOMAIN-SUFFIX,githubusercontent.com,PROXY
DOMAIN-SUFFIX,douyin.com,DIRECT
DOMAIN-SUFFIX,aweme.snssdk.com,DIRECT
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

### 2.3 （小火箭进阶）用 Rule-Set 代替手写规则

手写规则维护成本高，推荐用 **Loyalsoldier** 或 **BlackMatrix7** 的规则集：

首页 → 配置 → 进「config」→ 规则区 → 底部 **添加规则** → 类型选 **RULE-SET** → 填写：

| 分类 | URL | 策略 |
|------|-----|------|
| AI / Claude | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/Claude/Claude.list` | PROXY |
| OpenAI | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/OpenAI/OpenAI.list` | PROXY |
| Discord | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/Discord/Discord.list` | PROXY |
| 境外通用 | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/Global/Global.list` | PROXY |
| 境内大陆 | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/ChinaMax/ChinaMax.list` | DIRECT |

**顺序从上到下**：Claude → OpenAI → Discord → Global → ChinaMax → GEOIP CN → FINAL,PROXY。

> `https://raw.githubusercontent.com` 是 GitHub 的 raw 文件静态资源域名；这些规则文件由社区维护，常年更新，**你用 URL 引用，规则变化自动同步**，不用你自己改。
> 
> 推荐的两个来源：
> - **BlackMatrix7 / ios_rule_script**（最全，按应用分类，iOS 专用）：https://github.com/blackmatrix7/ios_rule_script
> - **Loyalsoldier / v2ray-rules-dat**（GFW + 中国直连的权威列表）：https://github.com/Loyalsoldier/v2ray-rules-dat

---

## 3. Android

### 3.1 Mihomo Party（Android 版）⭐ 推荐

**下载**：GitHub Release → https://github.com/mihomo-party-org/mihomo-party/releases  
选 `.apk` 安装包（需允许"安装未知来源"）。

**配置**：

1. 安装、打开 → 授予 VPN 权限
2. **Profiles → New Profile → Remote URL** → 粘贴 `$URL_CLASH_HOME`
3. 激活 → 主界面 **TUN Mode ON**

同一套 Clash YAML，规则和 Mac 完全一致。

### 3.2 备选：FlClash（开源、Google Play 可下）

<https://github.com/chen08209/FlClash/releases>，流程一致。

### 3.3 备选：Clash Meta for Android（老牌，稳定）

<https://github.com/MetaCubeX/ClashMetaForAndroid/releases>

---

## 4. Windows（家人用，零配置）

### 4.1 Clash Verge Rev ⭐ 推荐给家人

**理由**：图形界面最友好，**开机自启**，**TUN 模式一键**。

**安装**：
1. https://github.com/clash-verge-rev/clash-verge-rev/releases 下 `.exe`
2. 双击安装（UAC 同意）

**配置**：
1. 打开 → 左侧菜单 **订阅（Profiles）**
2. 右上 **新建** → **从 URL 导入** → 粘贴 `$URL_CLASH_HOME`
3. Name `ace-vpn` → 导入
4. 点订阅卡片，打勾激活
5. 左侧 **设置** → 勾 **系统代理**、**TUN 模式**、**开机自启**
6. 大功告成

**远程帮家人安装**：
- 国内：**向日葵远程控制**（对方点一次「接受」即可）
- 国外：**TeamViewer QuickSupport**

**给家人的一页纸「使用手册」**：

> 1. 双击桌面 Clash Verge 图标打开
> 2. 看到图标变绿 = 在用 VPN；变灰 = 在直连
> 3. 想开 = 打开 App 即可；想关 = **左侧"设置"→关闭"系统代理"和"TUN 模式"**
> 4. 网络有问题第一步：**左侧"订阅"→ 点右上的刷新按钮**
> 5. 解决不了就微信叫我

---

## 5. 分流规则：**为什么一改 VPS，全家同步？**

核心是 **「订阅」机制** + sub-converter：

```
sub-converter.py（VPS 上运行）
        │
        │  产出 Clash YAML（含 rules）
        ▼
http://<VPS_IP>:25500/clash/<SUB_TOKEN>
        │
        ├── Mac Mihomo Party    （点「刷新」）
        ├── iPad Stash         （自动 12 小时拉一次）
        ├── Android Mihomo      （点「刷新」）
        └── Win Clash Verge     （自动 24 小时拉一次）
```

**你在 Mac 上改 `scripts/sub-converter.py`，推到 VPS 重启服务 → 全家客户端下次刷新自动生效**。

```bash
# 本地改规则后一键分发
scp scripts/sub-converter.py root@$VPS_IP:/opt/ace-vpn-sub/sub-converter.py
ssh root@$VPS_IP "systemctl restart ace-vpn-sub"
# 通知家人：在客户端里点一下"更新订阅"
```

**例外：Shadowrocket**。它吃的是 **3x-ui 原 base64 订阅**（没有规则），**规则只能在 Shadowrocket 本机里改**。如果你只有自己一个 iPhone 用小火箭，这不是大问题；但若全家都用小火箭，规则多端同步就要手工。所以推荐 **iOS 升级到 Stash**。

---

## 6. 规则集速查表（可直接放到 `scripts/sub-converter.py` 或 Shadowrocket）

### 6.1 社区维护的规则集（Rule Set URL）

| 用途 | URL | 来源 |
|------|-----|------|
| **国内直连大全** | `https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt` | Loyalsoldier |
| **代理（需翻墙）域名** | `https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/proxy.txt` | Loyalsoldier |
| **广告屏蔽** | `https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt` | Loyalsoldier |
| **Apple 服务** | `https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/apple.txt` | Loyalsoldier |
| **Microsoft** | `https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/microsoft.txt` | Loyalsoldier |
| **OpenAI / ChatGPT** | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/OpenAI/OpenAI.yaml` | BlackMatrix7 |
| **Claude** | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Claude/Claude.yaml` | BlackMatrix7 |
| **Cursor** | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Cursor/Cursor.yaml` | BlackMatrix7 |
| **Discord** | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Discord/Discord.yaml` | BlackMatrix7 |

> `https://raw.githubusercontent.com` 是 GitHub 的 raw 资源直链，**你订阅 URL 粘贴进去，规则自动跟随社区更新**。  
> 代价：这些域名在国内有时会间歇不稳，可以用 jsDelivr 镜像代替：把 `raw.githubusercontent.com/xxx/yyy/branch/path` 改成 `cdn.jsdelivr.net/gh/xxx/yyy@branch/path`。

### 6.2 在 sub-converter.py 里内置的规则（不用拉远程，就在 VPS 上）

当前版本把规则硬编码在 `AI_DOMAINS`、`SOCIAL_PROXY`、`MEDIA_PROXY`、`CHINA_DIRECT` 四个 Python list 里。  
**好处**：离线可用、响应最快、完全可控。  
**扩展方式**：见 [05-journey-and-skill.md §4](05-journey-and-skill.md#4-分流规则写在-sub-converterpy-里集中维护)。

### 6.3 混合方案（推荐）：硬编码核心 + 远程 ruleset 兜底

在 sub-converter 输出的 YAML 里用 `rule-providers`：

```yaml
rule-providers:
  loyalsoldier-direct:
    type: http
    behavior: domain
    url: https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/direct.txt
    interval: 86400
    path: ./ruleset/direct.yaml
  loyalsoldier-proxy:
    type: http
    behavior: domain
    url: https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/proxy.txt
    interval: 86400
    path: ./ruleset/proxy.yaml

rules:
  - RULE-SET,loyalsoldier-direct,DIRECT
  - RULE-SET,loyalsoldier-proxy,🚀 PROXY
  - GEOIP,CN,DIRECT
  - MATCH,🐟 FINAL
```

**要启用**：往 `scripts/sub-converter.py` 的 `build_clash_yaml()` 里加 `rule-providers` 字段 + `rules:` 里前面插入 `RULE-SET,...` 两行。现阶段硬编码规则已够用，不急。

---

## 7. 面板「客户端」增删改（Add Client / Edit / Disable）

### 7.1 一设备一 Client，还是多设备共用？

| 方式 | 适合 |
|------|------|
| **一人一 Client**（4 个设备共用一个 UUID）| 最简单，订阅里节点数 = 1 |
| **一设备一 Client**（每设备独立 UUID）| 能单独统计流量、单独吊销 |

**家庭推荐**：**一人一 Client + 一家一 SubId**。即你 Mac/iPhone/iPad/Android 全用同一个 Client（同一 UUID），SubId=`sub-hxn`；爸爸一个 Client，SubId=`dad-home`；妈妈同理。

### 7.2 操作

**添加**：面板 → **Inbounds** → `ace-vpn-reality` 那行最右边 → 点绿色「客户端（+）」图标 → Add Client →  
- ID：点刷新 🔄 随机 UUID
- Email：**填有意义的**，如 `dad-win`、`xiaonan-home`
- Sub ID：填 `sub-hxn` / `dad-home`
- Save

**吊销**：找到对应 Client → Edit → **Enable = OFF** → Save（保留数据但断连）；或直接删除。

**查流量**：面板首页或 Inbounds 页每个 Client 有 Up / Down 统计。

---

## 8. 常见故障 & 10 秒排查

| 现象 | 排查顺序 |
|------|---------|
| 所有网站都打不开 | ❶ 关了 Let's VPN 再试 → ❷ System Proxy / TUN 是否打开 → ❸ Proxies 页测延迟有数字 → ❹ VPS 上 `systemctl status x-ui` |
| 国外能开，国内慢 | TUN 开着且 mode=global 了。改回 rule 模式 |
| 国内能开，国外不行 | 节点不通。检查 pbk/shortId / VPS 端 xray 是否启动 |
| YouTube 能开但不流畅 | Proxies 页切到延迟更低的节点；或开 `tcp-concurrent: true` |
| Cursor / Claude Code 说「海外 IP 检测失败」 | Mac 端开 TUN 模式（不是系统代理）；`curl ipinfo.io/ip` 要返回日本 IP |
| 面板 `https://<VPS>:<port>/<path>/` 打不开 | ❶ 改过端口/path？❷ `ufw status` 看端口是否放行 ❸ 证书过期（IP 证书 6 天续一次，`x-ui` 菜单 19） |
| 抖音加载慢 | 你订阅里可能没有 `CHINA_DIRECT` 规则，或它被 FINAL→代理 兜底。**刷新订阅** |

---

## 9. 给家人的极简说明（打印/发截图）

```
┌────────────────────────────────────────┐
│  家用梯子使用说明（爸妈版）                │
├────────────────────────────────────────┤
│  1. 桌面双击 Clash Verge 图标            │
│  2. 看到小猫图标 = 在翻墙                 │
│  3. 想关 → 右下角图标 → 退出              │
│  4. 上不了网 → 刷新订阅 → 等 3 秒         │
│  5. 还不行 → 发微信："梯子坏了，当前图标 xx"│
└────────────────────────────────────────┘
```

---

## 10. 相关文档

- 服务端部署：[03-server-setup.md](03-server-setup.md)
- 需求总结：[04-requirements-summary.md](04-requirements-summary.md)
- 经验 / skill：[05-journey-and-skill.md](05-journey-and-skill.md)
- 私有环境变量：[`../private/env.sh.example`](../private/env.sh.example)
