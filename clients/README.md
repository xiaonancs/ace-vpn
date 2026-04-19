# 📱 客户端配置总览（Clients）

> 本目录是 **通用客户端模板**，按设备选用；**不包含** UUID / 订阅 URL / 公司真实域名等敏感信息。  
> 敏感信息放本地私密目录或 1Password，**不要 commit**（`.gitignore` 已排除 `clients/generated/` 和 `clients/*/personal/`）。

---

## 一、选哪个客户端

| 设备 | 推荐客户端 | 备注 |
|------|----------|------|
| **Mac ×2** | [Mihomo Party](https://mihomo.party/) / [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev) | Clash Meta 系，TUN 模式，日常主力 |
| **iPhone** | [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118)（付费 $2.99） | iOS 上兼容性最好 |
| **iPad** | Shadowrocket / [Stash](https://apps.apple.com/app/stash/id1596063349) | 同 iOS |
| **Android** | [Clash Meta for Android (Clash MT)](https://github.com/MetaCubeX/ClashMetaForAndroid) | 规则完全复用 Mac 的 |
| **Windows ×2（家人）** | Clash Verge Rev | 一键开启，零配置 |

---

## 二、文件索引

| 文件 | 用途 |
|------|------|
| [`mac-clash-meta.yaml`](mac-clash-meta.yaml) | Mac / Windows / Android 的 Clash Meta 配置模板 |
| [`iphone-shadowrocket.md`](iphone-shadowrocket.md) | iPhone Shadowrocket 配置步骤 + 规则集 |
| [`shell-proxy.sh`](shell-proxy.sh) | Mac 终端代理开关（Claude Code / Cursor 命令行） |
| [`cursor-proxy.md`](cursor-proxy.md) | Cursor / VS Code 专用代理配置 |

---

## 三、核心设计原则（所有客户端统一）

### 3.1 规则优先级（从上到下）

```
1. 公司域名 / 公司 CIDR       → DIRECT
2. AI 类（Claude/OpenAI/…）    → PROXY-AI（海外出口）
3. 国内规则集（ChinaMax）      → DIRECT
4. GEOIP, CN                  → DIRECT
5. 海外规则集（Global）        → PROXY
6. FINAL / MATCH              → DIRECT（兜底）
```

**为什么 FINAL 是 DIRECT？**  
新 App / 新公司域名默认直连，避免误伤；海外该代理的靠规则集精确命中。

### 3.2 出口组设计

```
【PROXY-AI】    ── 专门给 Claude/OpenAI/Cursor，可随时切不同 VPS
【PROXY-MAIN】  ── 主力海外代理，日常用
【PROXY-FALLBACK】── 故障时自动切（Reality → Hy2）
```

好处：将来 AI 出口被识别时，**只换 PROXY-AI 组**，不影响日常。

### 3.3 订阅管理

- 3x-ui 生成一个 URL，所有客户端导入
- 换 VPS 时：更新 3x-ui 里的出站 IP → 客户端"更新订阅"即可
- **不要**给每个客户端单独手抄 UUID

---

## 四、推荐规则集（社区成熟维护）

### 4.1 BlackMatrix7（iOS/Shadowrocket/Loon/Clash 通用）
- 仓库：https://github.com/blackmatrix7/ios_rule_script
- 分类 URL 模板（不写死具体分支，以仓库为准）：
  - **AI**：`rule/Clash/OpenAI/OpenAI.yaml`、`rule/Clash/Claude/Claude.yaml`、`rule/Clash/Gemini/Gemini.yaml`、`rule/Clash/Copilot/Copilot.yaml`
  - **Discord**：`rule/Clash/Discord/Discord.yaml`
  - **中国大陆**：`rule/Clash/ChinaMax/ChinaMax_Classical.yaml`
  - **全球加速**：`rule/Clash/Global/Global_Classical.yaml`

### 4.2 Loyalsoldier（GeoIP / GeoSite 数据）
- 仓库：https://github.com/Loyalsoldier/v2ray-rules-dat
- 用途：离线 geoip.dat / geosite.dat，Clash 可直接引用

---

## 五、敏感信息放哪

**绝对不要 commit：**

| 类型 | 建议存放 |
|------|---------|
| 订阅 URL | 1Password / macOS Keychain |
| VPS IP / UUID / Reality 私钥 | 同上 |
| 公司真实域名 / CIDR | 本地私有配置（`clients/personal/`，已 gitignore） |

**推荐做法：**
- 在本地建 `clients/personal/mac-clash-meta.local.yaml`（被 gitignore）
- 从本仓库的 `mac-clash-meta.yaml` 模板 `include:` 进去
- 或用 Clash Verge Rev 的"合并 profile"功能
