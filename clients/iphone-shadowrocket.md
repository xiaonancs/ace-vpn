# 📱 iPhone / iPad - Shadowrocket 配置指南

> **前置**：在 App Store 购买并安装 [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118)（$2.99，美区账号）。  
> **目标**：抖音直连、Discord / Claude / Cursor / YouTube 自动走代理、公司内网可切换。

---

## 一、导入订阅（最关键一步）

1. 在 3x-ui 面板 → 订阅设置 → 复制某个用户的 Subscription URL
2. Shadowrocket → 右下角 **配置** → 左上角 **+**（添加订阅）
3. 粘贴 URL → **下载**
4. 回到"首页"，选中该配置，点击"开启"

**换 VPS 后**：回到配置列表点击"更新"按钮即可，不用重新手抄。

---

## 二、全局路由模式

Shadowrocket 首页 → **全局路由**，选择：

```
✅ 配置      ← 关键！这个模式才会按下面的规则分流
```

不要选"代理"（全局代理）或"直连"。

---

## 三、规则配置（按优先级从上到下）

Shadowrocket → 配置 → 当前配置 → **规则**。

### 3.1 添加规则集（Rule Set）

点"添加规则集"，依次添加以下 URL（**类型：规则集**，**策略**按下表选）：

| 规则集名 | URL | 策略 |
|---------|-----|------|
| 🏢 公司直连 | 自己维护（见下） | DIRECT |
| 🤖 Claude | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/Claude/Claude.list` | PROXY |
| 🤖 OpenAI | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/OpenAI/OpenAI.list` | PROXY |
| 🤖 Gemini | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/Gemini/Gemini.list` | PROXY |
| 🤖 Copilot | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/Copilot/Copilot.list` | PROXY |
| 💬 Discord | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/Discord/Discord.list` | PROXY |
| 🇨🇳 ChinaMax | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/ChinaMax/ChinaMax.list` | DIRECT |
| 🌍 Global | `https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/Global/Global.list` | PROXY |

### 3.2 排序（必须按这个顺序）

```
1. 🏢 公司直连       → DIRECT
2. 🤖 Claude         → PROXY
3. 🤖 OpenAI         → PROXY
4. 🤖 Gemini         → PROXY
5. 🤖 Copilot        → PROXY
6. 💬 Discord        → PROXY
7. 🇨🇳 ChinaMax      → DIRECT
8. 🌍 Global         → PROXY
9. GEOIP CN          → DIRECT
10. FINAL            → DIRECT   ⚠️ 兜底必须是 DIRECT
```

### 3.3 Cursor 补充规则

Shadowrocket → 配置 → 规则 → **添加规则**：

| 类型 | 值 | 策略 |
|------|----|------|
| DOMAIN-SUFFIX | cursor.sh | PROXY |
| DOMAIN-SUFFIX | cursor.com | PROXY |
| DOMAIN-KEYWORD | cursor | PROXY |
| DOMAIN-SUFFIX | anthropic.com | PROXY |

放在 AI 规则集附近（第 2~6 行之间都行）。

---

## 四、自维护的"公司直连"规则集

### 4.1 创建本地规则集

在 iCloud Drive / 1Password 里建一个文件 `corp-direct.list`，内容示例：

```
# 公司域名
DOMAIN-SUFFIX,corp.example.com
DOMAIN-SUFFIX,internal.example
DOMAIN-SUFFIX,oa.example.com
DOMAIN-SUFFIX,wiki.example.com

# 公司 CIDR
IP-CIDR,10.0.0.0/8,no-resolve
IP-CIDR,172.16.0.0/12,no-resolve
```

### 4.2 挂上去

把这个文件放一个私密 URL（GitHub 私有 Gist / 自己的 VPS 静态文件）后，在 Shadowrocket 作为规则集订阅，**策略 DIRECT**。

**简单做法**：少量条目直接在 Shadowrocket 里手动加 `DOMAIN-SUFFIX,xxx → DIRECT` 也可以。

---

## 五、公司 VPN 共存方案

**iOS 限制**：系统级 VPN **一次只能开一个**。

| 场景 | 操作 |
|------|------|
| 日常（抖音 + Claude + Discord） | 开 Shadowrocket |
| 临时看公司内网文档 / 用 OA | 关 Shadowrocket → 开公司 VPN → 用完切回 |
| 刷抖音同时用 AI | 保持 Shadowrocket 开启即可 |

---

## 六、验证

连接后，在手机浏览器里打开：

- https://ip.sb → 应显示 **VPS 的境外 IP**（AI / Discord 命中时）
- https://chat.openai.com → 应该能打开、不提示 unavailable
- 打开抖音 → 视频能加载（证明走了直连）

如果某个 App 不通：Shadowrocket → 配置 → **最近匹配（Recent Logs）** 看它的请求命中了哪条规则。

---

## 七、常见问题

### Q1：Claude 能打开但提示 "unavailable in your country"
- 说明某个 API 请求没走代理。检查"最近匹配"，把对应域名加进 PROXY 规则。

### Q2：Discord 语音断断续续
- Discord 语音走 UDP。检查 3x-ui 里的 Hysteria2 是否正常，或者在出口组里切到 Hysteria2。

### Q3：抖音刷不出来
- 检查 ChinaMax 规则集是否排在 Global 之前。
- 如果 ChinaMax 里没覆盖某个抖音域名，手动加 `DOMAIN-SUFFIX,douyin.com → DIRECT`。

### Q4：家人 iPhone 也想用
- 把同一个订阅 URL 发给他们，重复 Step 1 导入即可。
- 3x-ui 里可以给他们单独建一个用户，避免共用 UUID。
