# ace-vpn · 开发者技术文档（Skill）

> 面向半年后的自己或接手维护的开发者。读完这一篇就能在一台全新的 VPS 上把 ace-vpn 从 0 建起来、稳定运营、整库迁移到下一家 VPS。
>
> 案例主线：**Vultr Tokyo → HostHatch Tokyo**（2026-04 实战，数据库整库迁移，家人无感）。

---

## 目录

1. [项目目标 & 当前状态](#1-项目目标--当前状态)
2. [架构 & 技术栈](#2-架构--技术栈)
3. [VPS 选型：Vultr vs HostHatch](#3-vps-选型vultr-vs-hosthatch)
4. [一键部署（新 VPS 到手 5 分钟）](#4-一键部署新-vps-到手-5-分钟)
5. [sub-converter 多 token 架构](#5-sub-converter-多-token-架构)
6. [分流规则](#6-分流规则)
7. [客户端分发策略](#7-客户端分发策略)
8. [踩过的坑 & 根因](#8-踩过的坑--根因)
9. [VPS 迁移 Playbook](#9-vps-迁移-playbook)
10. [日常维护 Cheatsheet](#10-日常维护-cheatsheet)
11. [红线 & 安全](#11-红线--安全)

---

## 1. 项目目标 & 当前状态

### 1.1 目标画像

- **谁用**：2–5 人家庭（我 + 家人 Windows）；设备覆盖 Mac×2 / iPhone / iPad / Android / Win×2。
- **三个网段**：公司内网（公司 VPN 直连）/ 中国境内（直连）/ 海外（代理）。
- **硬要求**：
  - AI 工具（Claude / Cursor / ChatGPT）**永远海外 IP**
  - Discord / X / YouTube 4K 流畅
  - 抖音/淘宝/B站**不被代理拖慢**
- **预算**：≤¥400/年（放宽后的上限，首版 Vultr 月付验证）
- **迁移**：今天用 Vultr，明天可能换 HostHatch，**15 分钟无感迁移**，家人客户端只改 IP。

### 1.2 当前状态（2026-04）

| | 主机 | 规格 | 价格 | 状态 |
|---|------|------|------|------|
| 🟢 生产 | **HostHatch Tokyo** | 1 AMD EPYC Milan / 2GB / 10GB NVMe / 1TB BW | $4/月 ≈ ¥345/年 | 2026-04-21 起运行中 |
| 🟡 冷备 | Vultr Tokyo | 1 vCPU / 1GB / 25GB / 2TB BW | $6/月 | 1 个月观察期，2026-05-20 destroy |
| 🔴 已放弃 | Oracle Free ARM (Osaka) | 4C/24G 免费 | 0 | 两次注册风控，改年付 |

---

## 2. 架构 & 技术栈

### 2.1 软件选型

| 层级 | 选择 | 为什么不是别的 |
|------|------|---------------|
| 主协议 | **VLESS + Reality (Xray-core)** | Reality 抗封锁靠偷别家的 TLS 握手，无需自己备案域名，GFW 目前无法区分 |
| 备用协议 | Hysteria2（UDP）| 弱网/丢包强；**本次未启用**——新版 Xray 26.x 的 Hy2 支持有坑（见 §8.3）|
| 服务端面板 | **3x-ui** | Web 管理 + Client + 订阅 + 统计都在一张 sqlite（`/etc/x-ui/x-ui.db`），**整表迁移就是整站迁移** |
| 订阅转换 | 自研 Python **sub-converter.py** | 原生支持 Reality（社区 fork 的 subconverter 都不认 pbk/sid）；输出带规则的 Clash YAML |
| 桌面客户端 | Mihomo Party / Clash Verge Rev | 原生 Clash Meta；支持 TUN 模式（让 Cursor / 终端 / Claude Code 全自动走代理）|
| Android 客户端 | FlClash / Clash Meta for Android | **均有官方 GitHub APK**；吃 Clash YAML，与订阅规则一致（Mihomo Party 为桌面 Electron，无安卓版）|
| iOS / iPadOS 客户端 | Stash（首选）/ Shadowrocket | Stash 原生吃 Clash YAML，和 Mac 同一份规则；小火箭原生吃 v2ray 订阅，规则需自己堆 |

### 2.2 架构图

```
┌────────────────────────────────────────────────────────────┐
│  VPS（生产：HostHatch Tokyo，冷备：Vultr Tokyo 1 月）       │
│                                                            │
│   TCP 443       Xray VLESS+Reality   ← 主干翻墙流量         │
│   TCP <panel>   3x-ui Web 面板       ← 管理                 │
│   TCP 2096      3x-ui 订阅端口       ← 原生 base64 vless:// │
│   TCP 25500     ace-vpn-sub (Python) ← Clash YAML 转换器    │
│   UDP 8443      Hysteria2（已禁用）                         │
└────────────────────────────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
  [订阅 URL: base64]      [订阅 URL: Clash YAML]
  Shadowrocket（iOS）      Mihomo Party / Stash / Clash Verge / FlClash / CMFA
  - 节点列表              - 节点 + 代理组 + 分流规则
  - 规则自己写            - 规则已在 VPS 端统一生成
```

### 2.3 端口约定

| 端口 | 协议 | 服务 | 是否公网可达 |
|------|------|------|-------------|
| 22 | TCP | SSH | 是（仅 key） |
| 443 | TCP | VLESS Reality | 是 |
| 2096 | TCP | 3x-ui 订阅 | 是（HTTPS） |
| 25500 | TCP | sub-converter | 是（HTTP，内容为脱敏 YAML） |
| `<random>` | TCP | 3x-ui 面板 | 是（随机端口 + 随机 path + HTTPS） |
| 8443 | UDP | Hy2（预留） | 否（未启用） |

---

## 3. VPS 选型：Vultr vs HostHatch

### 3.1 为什么只留这两家

经过完整对比后（RackNerd/BandwagonHost/HostDare/Oracle Free 都评估过），最后留下这两家，分别扮演不同角色：

- **Vultr**：按月付、5 分钟开通、有全球 30 个节点 —— 适合**先拿来验证方案可行**，月付随时停。
- **HostHatch**：AMD EPYC + NVMe、Tokyo 节点、$4/月 —— 适合**方案跑通后的年付生产**。

### 3.2 横向对比（2026-04）

| 维度 | Vultr Tokyo | HostHatch Tokyo | 结论 |
|------|-------------|-----------------|------|
| 价格 | $6/月 ≈ ¥520/年 | $4/月 ≈ ¥345/年 | HostHatch 便宜 ¥175/年 |
| CPU | 1 vCPU（shared）| 1 AMD EPYC Milan core（fair share）| HostHatch 快 30-50% |
| RAM | 1 GB | 2 GB | HostHatch 胜 |
| 磁盘 | 25 GB SSD | 10 GB **NVMe** | Vultr 大，HostHatch 快 |
| 带宽 | 2 TB/月 | 1 TB/月 | Vultr 大，但家用单人 1TB 够 |
| 月付 | ✅ | ✅（也有年付） | 一致 |
| 退款 | ❌ | 3-7 天 | HostHatch 胜 |
| 注册风控 | 几乎无 | **下单时不能挂代理**（IP 国家 vs 账单地址不一致会被 flag） | Vultr 更省事 |
| 付款 | 信用卡/PayPal/Alipay | 信用卡/PayPal | 一致 |
| 延时（北京）| ~80ms | ~50ms | HostHatch 胜 |
| 晚高峰稳定性 | 中（普通 BGP）| 中（普通 BGP）| 打平；如需 peak 稳定选 Bandwagon CN2 GIA |

### 3.3 决策

**首选 HostHatch，Vultr 做短期验证 + 冷备**。

- 需求排序：**低延时（AI / 日常）> 晚高峰稳定（家人 4K）> 价格**；
- Bandwagon CN2 GIA 稳但延时 ~180ms，日常 AI 打字体验差；
- HostHatch 延时 ~50ms、NVMe、AMD EPYC，单人 4K 够用；
- Vultr 保留 1 个月冷备（额外 ¥44），确认稳定后 destroy。

### 3.4 下单坑

#### Vultr

- 账号 email 最好用正规域名（gmail/outlook）。
- 月付即可，随时停。

#### HostHatch

- **下单时必须关所有代理**，用真实中国 IP 直连网站填表。IP 国家 vs 账单国家不一致会被反欺诈系统 flag（本次迁移踩过）。
- 账单地址填**真实中国地址**，Country 选 China。不要伪装海外身份。
- SSH Key 字段订单页就有位置，直接贴 `cat ~/.ssh/id_ed25519.pub`，省掉临时密码再 `ssh-copy-id` 的过程。
- IPv6 免费就勾上，**不要加钱**的 Additional IPv4。
- Hostname 填中性的（例 `vpn-tyo`），不要 `xray` / `vpn-proxy` 这类关键词。

---

## 4. 一键部署（新 VPS 到手 5 分钟）

### 4.1 完整 5 行命令

```bash
# 1. SSH 登录新 VPS
ssh root@<VPS_IP>

# 2. 克隆仓库
git clone https://github.com/<you>/ace-vpn.git && cd ace-vpn

# 3. 一键：系统 + 防火墙 + 3x-ui + 自动建 Reality 入站
sudo AUTO_CONFIGURE=1 bash scripts/install.sh

# 4. 浏览器登面板改密码 + 改 path + 改端口
#    https://<VPS_IP>:2053/<random-path>/
#    → Panel Settings → Port/Path/User/Pass 全改

# 5. 装 Clash 订阅转换器（多 token 单实例）
sudo UPSTREAM_BASE='https://<VPS_IP>:2096/<sub_path>' \
     SUB_TOKENS='sub-hxn,sub-hxn01' \
     SERVER_OVERRIDE='<VPS_IP>' \
     LISTEN_PORT=25500 \
     bash scripts/install-sub-converter.sh
```

### 4.2 install.sh 干了啥

| 阶段 | 脚本 | 动作 |
|------|------|------|
| 系统初始化 | `setup-system.sh` | apt update、BBR+fq、IP forward、文件句柄上限 |
| 防火墙 | `setup-firewall.sh` | UFW 放行 22/80/443/2096/25500/面板端口 |
| 3x-ui | `install-3xui.sh` | 官方安装器；交互点：端口 2053、admin/admin、SSL 选 2（IP 证书）|
| 自动配 Reality | `configure-3xui.sh`（AUTO_CONFIGURE=1）| 调 3x-ui HTTP API 建 VLESS+Reality 入站，SNI=www.cloudflare.com，flow=xtls-rprx-vision |

### 4.3 交互点（3x-ui 安装器）

```
Q: Continue? → y
Q: Customize Panel Port? y → 2053
Q: Username? → admin
Q: Password? → admin
Q: Confirm Password? → admin
Q: SSL for IP? → 2（Let's Encrypt for IP，6 天续）
```

装完**立即**到 Web 面板改 admin/admin 和 path（见下一步）。

### 4.4 面板加固（必做）

浏览器打开 `https://<VPS_IP>:2053/<生成的随机 path>/` → 登录 → **Panel Settings**：

- 端口：2053 → 随机 5 位（如 41785）
- Path：改成随机 16 位（前后带 /）
- 用户名/密码：admin/admin → 强随机

改完立刻：

```bash
sudo ufw allow 41785/tcp
sudo ufw delete allow 2053/tcp
sudo ufw reload
```

**Subscription Settings**：

- Enable = ON
- Port = 2096
- Path = `/sub_<随机>/`、JSON Path = `/json_<随机>/`
- Domain 留空（用 IP）

### 4.5 一次性输出凭据

`configure-3xui.sh` 会在 `/root/ace-vpn-credentials.txt` 生成所有凭据（Panel URL / UUID / pbk / sid / 订阅 URL）。**跑完立刻 scp 到本地 `private/`，然后 VPS 上 `shred -u` 删掉**。

---

## 5. sub-converter 多 token 架构

### 5.1 为什么不直接用 3x-ui 的原生订阅

- 3x-ui 输出 `vless://` base64 列表，**没有分流规则**。
- Shadowrocket 能吃但得自己写规则；Mihomo / Clash 需要 YAML 格式。
- 社区的 `tindy2013/subconverter` 等 fork 不认 Reality 的 `pbk` / `sid` / `spx`（踩过的 §8.6）。

→ 自研 `scripts/sub-converter.py`（~200 行 Python），原生支持 Reality + 规则硬编码。

### 5.2 多 token 单实例

早期设计是"每家人一个 sub-converter 实例"，后来演进为：**一个实例、多 token 白名单、token 对应 3x-ui 里的 SubId**。

```
┌──────────────────────────────────────────────────┐
│ ace-vpn-sub systemd service                     │
│                                                  │
│ Environment:                                     │
│   UPSTREAM_BASE=https://127.0.0.1:2096/<path>    │
│   SUB_TOKENS=sub-hxn,sub-hxn01                   │
│   SERVER_OVERRIDE=<VPS_IP>                       │
│   LISTEN_PORT=25500                              │
│                                                  │
│ do_GET(/clash/<token>):                          │
│   1. 校验 token 在 SUB_TOKENS 白名单             │
│   2. 拉 UPSTREAM_BASE/<token>（3x-ui base64）   │
│   3. 解析 vless://... 生成 Clash proxies         │
│   4. 覆盖 server 字段为 SERVER_OVERRIDE          │
│   5. 拼装 rule-providers + rules → 返回 YAML     │
└──────────────────────────────────────────────────┘
```

| Token | 对应 3x-ui SubId | 服务对象 |
|-------|-----------------|----------|
| `sub-hxn` | `sub-hxn` | 你自己的所有设备（Mac×2 / iPhone / iPad / Android）|
| `sub-hxn01` | `sub-hxn01` | 家人所有设备（Windows×2 / ...） |

加人只需：
1. 面板里加 Client，挂到对应 SubId；
2. 如需新 SubId，加到 `SUB_TOKENS` 环境变量；
3. `systemctl restart ace-vpn-sub`。

### 5.3 关键环境变量

| 变量 | 作用 | 典型值 |
|------|------|--------|
| `UPSTREAM_BASE` | 3x-ui 订阅 URL 前缀 | `https://127.0.0.1:2096/sub_xxxxx` |
| `SUB_TOKENS` | 白名单，逗号分隔 | `sub-hxn,sub-hxn01` |
| `SERVER_OVERRIDE` | 覆盖 YAML 里 `server:` 字段 | `<VPS_IP>` |
| `LISTEN_PORT` | 监听端口 | `25500` |
| `COMPANY_CIDRS` | 公司内网 CIDR（走 DIRECT）| `10.128.0.0/16` |
| `COMPANY_SFX` | 公司域名后缀（走 DIRECT）| `corp.example.com` |

### 5.4 改了环境变量后必须显式 restart

旧版 install 脚本只做 `systemctl enable --now`，对已运行的服务**不触发重启**。daemon-reload 只加载新 unit 文件，旧进程仍在用老环境。

现在 `install-sub-converter.sh` 最后会显式 `systemctl restart ace-vpn-sub`，并自检每条 token 的节点数 —— 如果某条返回 0，脚本会直接报错。

---

## 6. 分流规则

### 6.1 规则顺序（硬编码在 sub-converter.py）

```
1. 公司内网 CIDR / 公司域名后缀                    → DIRECT
2. 私有网段（127/192.168/10.0/172.16）             → DIRECT
3. AI（OpenAI/Claude/Gemini/Cursor/Copilot）       → 🤖 AI 组（代理）
4. 社交/工具（Discord/X/Telegram/Google/GitHub）    → 🚀 PROXY
5. 流媒体（YouTube/Netflix/Disney+/Spotify）        → 📺 MEDIA
6. 国内（抖音/淘宝/B站/微博/QQ/百度）                → DIRECT
7. GEOIP CN / PRIVATE                               → DIRECT
8. MATCH                                            → 🐟 FINAL（默认代理）
```

### 6.2 改规则的正确流程（家人自动同步）

```bash
# 1. 本地改 scripts/sub-converter.py
# 2. 推到 VPS
scp scripts/sub-converter.py root@$VPS_IP:/opt/ace-vpn-sub/sub-converter.py
ssh root@$VPS_IP "systemctl restart ace-vpn-sub"
# 3. 家人客户端「更新订阅」，10 秒全家生效
```

### 6.3 公司内网分流（多 profile 热加载，2026-04-27 重构）

**旧做法**（依然兼容但不推荐）：`systemctl edit` 改 `COMPANY_CIDRS` / `COMPANY_SFX` 环境变量 → `systemctl restart`。缺点：每次改都要 ssh、换公司得改环境变量、无法多公司并存。

**新做法**：一份 YAML + Mac 本地编辑 + 一键 scp 热加载。

#### 设计

| 组件 | 位置 | 作用 |
|------|------|------|
| `private/intranet.yaml.example` | 仓库内（公开）| 模板，含多 profile 示例 |
| `private/intranet.yaml` | Mac 本地（gitignored）| **真实源**，你改这个 |
| `/etc/ace-vpn/intranet.yaml` | VPS 上 | 服务读的副本；`scripts/sync-intranet.sh` 覆盖它 |
| `scripts/sync-intranet.sh` | Mac 本地工具 | 校验 YAML → scp → curl `/healthz` 自检 |
| `sub-converter.py::load_intranet_config()` | VPS 服务 | **每次 HTTP 请求都 re-parse YAML**，零重启 |

#### YAML 格式（两种）

**推荐：profiles 格式**（支持切公司 / 多公司并存）：

```yaml
profiles:
  corp-a:
    enabled: true
    desc: "公司 A"
    dns_servers: [10.x.x.1, 10.x.x.2]   # 公司内网 DNS（公司 VPN 下发）
    domains: [app.corp-a.example, office.corp-a.example, corp-a.srv]
    cidrs:   [10.0.0.0/8]

  corp-b:
    enabled: false
    desc: "公司 B（不激活）"
    dns_servers: [10.y.y.1]
    domains: [portal.corp-b.example, corp-b.net]
    cidrs:   [172.20.0.0/16]
```

**fallback：扁平格式**（单公司，不支持切换）：

```yaml
domains: [app.corp-a.example]
cidrs:   [10.0.0.0/8]
```

#### 工作流

```bash
# 首次
cp private/intranet.yaml.example private/intranet.yaml
$EDITOR private/intranet.yaml

# 改 / 换公司 / 加新公司
$EDITOR private/intranet.yaml
bash scripts/sync-intranet.sh      # 脚本内部会自动 source private/env.sh

# 家人端刷新订阅即生效（不需要 ssh，不需要 systemctl restart）
```

#### 合并顺序（多来源时）

1. 环境变量 `COMPANY_SFX` / `COMPANY_CIDRS`（向后兼容旧部署）
2. `intranet.yaml` 里 `enabled: true` 的各 profile 依次合并
3. 结果去重（保留首次出现顺序）

#### /healthz 自检

```bash
curl -s http://$VPS_IP:25500/healthz
# 输出：
# ok
# active_profiles=corp-a,corp-b
# domains=7
# cidrs=2
```

#### 为什么是热加载而不是 SIGHUP

每次 HTTP 请求调一次 `load_intranet_config()`，开销 < 1ms（小 YAML），换来：
- **零操作成本**：scp 完就生效，没有「忘了 restart」的问题
- **订阅请求天然低频**（每家人客户端一天几次到几十次），性能可忽略
- 客户端 `Profile-Update-Interval: 24` 头会告诉它一天拉一次 YAML，被动 pull 模型

### 6.4 诊断：URL 走哪条规则？

`sub-converter` 暴露两个调试接口：

| Endpoint | 用途 | 返回 |
|----------|------|------|
| `GET /healthz` | 探活 + 当前激活 profile 数量 | `ok\nactive_profiles=corp-a\ndomains=4\ncidrs=1\n` |
| `GET /match?url=<URL>` 或 `?host=<HOST>` | **权威规则匹配**（JSON） | `{rule_index, rule, target, host, resolved_ip, active_profiles}` |

`/match` 用 `build_rules()` 本身跑一遍，和生成订阅走同一条代码路径，所以返回的规则就是客户端会命中的规则（除非客户端订阅缓存过期）。

Mac 端直接用 `scripts/test-route.sh`：

```bash
bash scripts/test-route.sh https://portal.corp-a.example/
```

脚本做三件事：
1. curl VPS 的 `/match?url=...` 拿服务端权威决策
2. 本机 `dig` 看系统 DNS 结果（如果是 `198.18.x.x` 说明 Clash TUN 的 fake-ip 拦下了）
3. 走 `http://127.0.0.1:7890` 发 HTTPS，打印 `time_namelookup` / `time_connect` / `time_appconnect` / `time_starttransfer` / `time_total` + 出口 IP

**典型排查场景**：
- 用户说 "某某网站打不开" → `bash scripts/test-route.sh <URL>` 看规则命中，确认是 DIRECT/PROXY 哪一边问题
- 加了新 intranet profile 后 → `sync-intranet.sh` 完立刻 `test-route.sh` 验证规则生效
- 订阅缓存漂移 → `/match` 返回的 rule 和客户端 Connections 面板显示的 rule 不一致 → 刷订阅

### 6.5 进阶：混用社区 ruleset

sub-converter.py 输出的 YAML 里可以加 `rule-providers`，引用社区维护的 ruleset（Loyalsoldier、BlackMatrix7）。当前硬编码规则已够用，不急。

---

## 7. 客户端分发策略

### 7.1 Client × SubId 分层

| 维度 | 做法 | 理由 |
|------|------|------|
| **Client（UUID）粒度** | **一设备一个** | 吊销某台设备时只影响它自己 |
| **SubId（订阅）粒度** | **一组人一个** | 自己 `sub-hxn`，家人 `sub-hxn01`，SubId 泄露只吊销那一组 |

### 7.2 Client Email 命名规范

Email 字段填**人类可读的设备名**，订阅生成的 Clash YAML 里每条节点 name 就是这个 Email，一眼看出哪台设备在用哪条。

```
sub-hxn 下（你自己）:
  hxn-macbook       # 公司笔记本
  hxn-iphone
  hxn-ipad
  hxn-ihome         # 家里 Mac
  hxn-android

sub-hxn01 下（家人）:
  family-dad-phone
  family-dad-pc
  family-mom-phone
  family-home-tv
```

### 7.3 添加 Client

面板 → Inbounds → `ace-vpn-reality` 那行最右 → 绿色「客户端（+）」→ Add Client：

- ID：点刷新 🔄 随机 UUID
- Email：按命名规范填
- Sub ID：填 `sub-hxn` 或 `sub-hxn01`
- Flow：**选 `xtls-rprx-vision`**（Reality 性能更好 + 更抗检测）
- Save → 再点 Inbound 行最外层的 Save（**保存两次才真正生效**）

### 7.4 吊销 Client

Edit → **Enable = OFF** → Save（保留数据但断连）；或直接删除。

### 7.5 清理历史测试 Client 的安全流程

`configure-3xui.sh` 重跑过多次可能留一堆重复 Client。**千万别一步到位直接删**：

```
1. 面板里先把要保留的 Client 改 Email（按命名规范改名，不影响 UUID 不断网）
2. 本机客户端刷新订阅 → 节点名变了但网还通 = 确认没删错
3. 回面板删掉「Email 乱 + 0 流量」的残留 Client
4. 客户端再刷一次订阅 → 节点数变成你期望的数字
```

先改名观察，再动删除 —— 否则删到 Mac 正在用的那个 UUID，立刻断网，Mac 上又没法登面板（因为你靠 VPN 访问），就尴尬了。

---

## 8. 踩过的坑 & 根因

### 8.1 Oracle 注册被风控

**现象**：「无法完成您的注册」，两次均挂。

**根因**：Oracle WAF + 反欺诈检查「国家 / 卡 BIN / IP / 主区域」一致性。频繁改字段、信用卡 BIN 与国家不匹配都会挂。

**结论**：放弃白嫖，改年付 HostHatch。

### 8.2 3x-ui 安装器交互提示

install.sh 跑到官方安装器时会问 panel port、admin 账号、SSL 方式。

**修复**：直接手动响应 `y → 2053 → admin/admin/admin → 2`（IP 证书）。装完立刻到 Web 面板改掉 admin / admin 和 path。

### 8.3 Hysteria2 在 Xray 26.x 里 "unknown config id"

```
ERROR - XRAY: Failed to start: ... infra/conf: unknown config id: hysteria2
```

**根因**：3x-ui 能保存 Hy2 入站到 db，但 Xray 主线代码把 Hy2 的 inbound 协议 ID 改掉 / 或该版本未合进 commit，启动时 xray 直接报错。一旦报错，**整个 xray 进程挂，VLESS 也一起废**。

**修复**：
```bash
# 方法 1：面板里删 Hy2 入站
# 方法 2：直接改数据库
sqlite3 /etc/x-ui/x-ui.db "DELETE FROM inbounds WHERE port=8443"
systemctl restart x-ui
```

暂时放弃 Hy2，Reality 完全够用。

### 8.4 configure-3xui.sh 提示 pbk 为空 / 入站创建失败（多重合集）

| 子问题 | 根因 | 修复 |
|-------|------|------|
| `pbk` 空 | `xray x25519` 新版输出 `Password:` 而不是 `PublicKey:` | `grep PublicKey` 匹配不到时 fallback 读 `Password:` |
| 入站创建失败 | 3x-ui v2 的 API 路径 `/panel/inbound/add` → 改成 `/panel/api/inbounds/add`；需要 `X-Requested-With: XMLHttpRequest` | 脚本已统一 |
| Hy2 `empty client ID` | 3x-ui 对非 trojan/ss 协议要求 `clients[].id` 非空 | Hy2 payload 里给 `clients[0].id` 塞 UUID（Hy2 实际用 password 认证，塞 UUID 无害） |
| `Port already exists: 443` | 3x-ui 的端口校验**不分 TCP/UDP**，VLESS 443/TCP 已占，Hy2 443/UDP 被拒 | Hy2 默认改成 UDP 8443 |
| `set -e` 导致脚本提前退出 | `grep` 匹配不到时退出码非 0，`pipefail` 触发 `set -e` | `( ... ) || true` 包裹 |

### 8.5 sub-converter 所有节点 `server: 127.0.0.1`

**现象**：Clash YAML 里 `server: 127.0.0.1`，客户端全 timeout。

**根因**：3x-ui 根据 HTTP Host 头生成 vless 链接的 server 字段。`UPSTREAM_SUB` 写 `https://127.0.0.1:2096/...` → 返回的 vless 里 host 就是 127.0.0.1。

**修复**（双保险）：
- `UPSTREAM_BASE` 用**公网 IP** 而非 127.0.0.1（首选）
- `sub-converter.py` 加 `SERVER_OVERRIDE` 环境变量强制覆盖 `server:`（兜底）

### 8.6 社区 subconverter 不认 Reality

**现象**：`tindy2013/subconverter` / `stilleshan/subconverter` 喂 vless+reality base64 全部 `No nodes were found!`。

**根因**：这些 fork 的 vless 解析器不认 `pbk`、`sid`、`spx` 这些 Reality 参数。

**修复**：自己写 `sub-converter.py`，原生支持 Reality，规则可自定义。

### 8.7 颜色转义字符 `\033[...]` 原样打印

`common.sh` 用单引号 `'\033[0;33m'` 只能在 `echo -e` 下生效，`cat <<EOF` 里直接原样输出。

**修复**：改成 ANSI-C 引号 `$'\033[0;33m'`，所有 `log_*` 用 `printf`。

### 8.8 Mihomo Party 同时有 Profile 和 Override 时规则被覆盖

**现象**：订阅 OK，节点 OK，但打开 Google 不通。

**根因**：Override 里写了 `rules:` 字段会**整体替换** Profile 的 300+ 条规则。

**修复**：**只用 Profile，别写 Override**（除非你真要在客户端本地加公司 CIDR 直连，且不想污染订阅）。

### 8.9 改了 sub-converter 环境变量但不生效 / 新 token 返回 0 节点

**现象**：改 `SUB_TOKENS`、`UPSTREAM_BASE` 后 `install-sub-converter.sh` 成功，`systemctl show -p Environment` 显示新值，但服务行为和没改一样。

**根因**：旧脚本只做 `systemctl enable --now`，对已运行服务**不触发重启**。daemon-reload 只加载新 unit 文件，旧进程仍在用老环境。

**修复**：每次重装后手动 `sudo systemctl restart ace-vpn-sub`；install 脚本已改成 `enable` + 显式 `restart`，并在最后自检每条 token 节点数。

### 8.10 HostHatch 下单被反欺诈 flag

**现象**：下单后页面提示 "Your order has been flagged ... ordering through a VPN"。

**根因**：下单时开着代理（出口 IP 在日本/新加坡），账单地址填中国，**IP 国家 vs 账单国家不一致** → 反欺诈系统 flag。

**修复**：
1. **关所有 VPN 代理**，`curl ipinfo.io` 确认是中国 IP；
2. 清浏览器 HostHatch 的 cookie；
3. 账单地址和信用卡账单保持一致（真实中国地址）；
4. 重新下单，秒过。

### 8.11 小盘 NVMe VPS 磁盘被 journal / log 挤满

HostHatch 入门套餐只有 10 GB NVMe，journalctl 和 x-ui access.log 不清会把盘挤满。

**修复**：装 cron 日常清理（见 §10.3）。

### 8.12 Clash Party / Mihomo Party 吞掉订阅的 DNS 配置 ⚠️

**现象（2026-04，极深的坑）**：

- 订阅里 `dns.fake-ip-filter` 写了 `+.app.corp-a.example` 等内网域名
- 订阅里 `dns.nameserver-policy` 写了内网 DNS（如 `10.x.x.x`）
- 客户端确实拉到了订阅、`profiles/xxx.yaml` 里内容正确
- **但** TUN 模式下 `dig portal.corp-a.example +short` 仍返回 `198.18.x.x` 假 IP
- `dig @<INTERNAL_DNS>` 也返回假 IP（TUN 拦截所有 UDP 53）
- 关掉 TUN 一切正常，开 TUN 就挂

**根因**：Clash Party（以及 Mihomo Party）在 `~/Library/Application Support/mihomo-party/config.yaml` 里默认：

```yaml
controlDns: true            # ← GUI 接管 DNS 段
useNameserverPolicy: false  # ← 忽略订阅的 nameserver-policy
```

开着 `controlDns` 时，GUI 会把订阅的 `dns:` 段**整块替换**，换成 GUI 设置 → DNS 页里的默认配置，其中 `fake-ip-filter` 只含 `"*"`, `+.lan`, `+.local` 等默认项——**订阅里塞进去的 `+.app.corp-a.example` 被直接丢弃**。

结果：内网域名拿不到真 DNS，统统变 fake-ip，命中 DIRECT 规则也连不上（Mihomo"直连"时用假 IP，必 RST）。

**定位步骤**：

```bash
# 1. 看 GUI 层设置
grep -E "controlDns|useNameserverPolicy" \
  ~/Library/Application\ Support/mihomo-party/config.yaml

# 2. 看 mihomo 真正加载的 runtime 配置
grep -A12 "fake-ip-filter" \
  ~/Library/Application\ Support/mihomo-party/work/config.yaml
```

如果 `work/config.yaml` 的 fake-ip-filter 和订阅 yaml 不一致，100% 是 GUI override。

**修复（一次性，之后全家自动）**：

```bash
# 改 GUI 设置：关掉 DNS 接管
sed -i '' 's/^controlDns: true$/controlDns: false/' \
  ~/Library/Application\ Support/mihomo-party/config.yaml
sed -i '' 's/^useNameserverPolicy: false$/useNameserverPolicy: true/' \
  ~/Library/Application\ Support/mihomo-party/config.yaml

# 彻底重启 Mihomo（清 fake-ip 缓存）
sudo pkill -9 -f mihomo 2>/dev/null
# Cmd+Q Clash Party 后重开

# 验证
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
dig portal.corp-a.example +short       # 应返回真实 10.x.x.x，不再是 198.18.x.x
```

或 GUI 里：**Clash Party → 设置 → DNS → 关掉「控制 DNS」**，同步打开「使用 Nameserver Policy」。

**教训**：

- 不只 Clash Party 有这毛病，新版 Mihomo Party 也一样。默认开 `controlDns` 是为"机场用户"准备的安全兜底，但对自建 + 精细分流是灾难。
- fake-ip-filter 里 `"*"` 不是"匹配所有"，而是"只匹配一段标签（如 `com`）"。Clash Party 默认写 `"*"` 实际等于没写，所以用户看到全域名都被 fake-ip 了。
- TUN 模式下 Mihomo 会拦截所有 UDP 53，不论目标 IP——所以 `dig @公网DNS` 也骗不过它，只能靠正确的 fake-ip-filter + nameserver-policy 让它自己去查真 DNS。

---

## 9. VPS 迁移 Playbook

> 通用 playbook。本次案例 **Vultr → HostHatch**，未来再换家把 `<OLD_VPS_IP>` / `<NEW_VPS_IP>` / `<你的 SubId>` / `<OLD_SUB_PATH>` 替换即可。

### 9.1 迁移架构图

```
[Day 0]                  [Day 1-14]                [Day 15+]
 旧机（生产）        →    旧机（冷备）         →    旧机 destroy
                          新机（测试）→全员      新机（生产）
                         （跑通后切生产）
```

### 9.2 Phase 1：买新 VPS

下单时注意：
- 关代理、用真实中国 IP、账单地址填真实中国地址（见 §3.4）
- SSH key 订单页贴，省略临时密码流程
- Hostname 中性
- 月付/年付按能接受的退款窗口决定

### 9.3 Phase 2：新机服务器初始化

```bash
# 本地 Mac
ssh root@<NEW_VPS_IP>

# 改密码（若下单没用 key）
passwd

# 禁用密码登录
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl restart sshd

# 新开终端测试还能登
ssh root@<NEW_VPS_IP> "uptime"

# 更新包
apt update && apt upgrade -y
# needrestart 弹窗选默认 OK 即可

# 时区
timedatectl set-timezone UTC
```

### 9.4 Phase 3：部署基础设施（不建 inbound）

```bash
# 本地 Mac: 推代码
cd ~/workspace
scp -r ace-vpn root@<NEW_VPS_IP>:/root/

# 新机: 跑 install.sh（不用 AUTO_CONFIGURE）
ssh root@<NEW_VPS_IP>
cd /root/ace-vpn
sudo bash scripts/install.sh
```

**关键**：**不要**在新机面板上手动改 panel port / admin / path，**不要**创建任何 inbound。所有值 Phase 4 会被旧机数据库覆盖。

### 9.5 Phase 4：3x-ui 数据库整库迁移（⭐ 核心）

```bash
# 旧机：备份
ssh root@<OLD_VPS_IP>
systemctl stop x-ui
cp /etc/x-ui/x-ui.db /root/x-ui-backup-$(date +%F).db
systemctl start x-ui

# 本地 Mac：中转
scp root@<OLD_VPS_IP>:/root/x-ui-backup-*.db /tmp/
scp /tmp/x-ui-backup-*.db root@<NEW_VPS_IP>:/root/

# 新机：恢复
ssh root@<NEW_VPS_IP>
systemctl stop x-ui
cp /etc/x-ui/x-ui.db /etc/x-ui/x-ui.db.fresh   # 空库回滚用
cp /root/x-ui-backup-*.db /etc/x-ui/x-ui.db
chown root:root /etc/x-ui/x-ui.db
chmod 644 /etc/x-ui/x-ui.db
systemctl start x-ui

# ⚠️ 数据库覆盖后，面板端口/账号/路径全部变成旧机的
# UFW 要放行旧机的面板端口
OLD_PANEL_PORT=<旧机的 panel port>
ufw allow $OLD_PANEL_PORT/tcp comment 'x-ui panel'
```

### 9.6 Phase 4.5：验证

```bash
ss -tlnp | grep x-ui
# 期望:
#   tcp *:<OLD_PANEL_PORT>   x-ui   ← 面板
#   tcp *:2096              x-ui   ← 订阅

# 登面板（用旧机的账号密码）
# http://<NEW_VPS_IP>:<OLD_PANEL_PORT><OLD_PANEL_PATH>/

# 对比 pbk/sid 两边一致
curl -sk "https://127.0.0.1:2096/<OLD_SUB_PATH>/<你的 SubId>" | base64 -d | head -1 | tr '&' '\n'
ssh root@<OLD_VPS_IP> "curl -sk https://127.0.0.1:2096/<OLD_SUB_PATH>/<你的 SubId> | base64 -d | head -1"
```

**一致** → 迁移成功。不一致（概率低）→ xray 重新生成了 key，手动到面板 Edit Inbound 粘贴旧机的 pbk/sid/spx。

### 9.7 Phase 5：装 sub-converter（新机 IP 关键）

```bash
cd /root/ace-vpn/scripts
sudo UPSTREAM_BASE='https://127.0.0.1:2096/<OLD_SUB_PATH>' \
     SUB_TOKENS='<SubId1>,<SubId2>' \
     SERVER_OVERRIDE='<NEW_VPS_IP>' \
     LISTEN_PORT=25500 \
     bash install-sub-converter.sh

ufw allow 25500/tcp comment 'ace-vpn sub converter'

# 验证每条 token 都有节点，且 server 字段是新机 IP
curl -s http://127.0.0.1:25500/clash/<SubId1> | grep -c '^- name:'
curl -s http://127.0.0.1:25500/clash/<SubId1> | grep 'server:' | head -3
```

**关键**：`SERVER_OVERRIDE` 必须是**新机**的 IP，否则订阅 YAML 里 server 还是旧机，等于没迁。

### 9.8 Phase 6：自己先试 3-5 天（不通知家人）

**Mac (Mihomo Party)**：新建 Profile `ace-vpn-<新机代号>`，URL = `http://<NEW_VPS_IP>:25500/clash/<你的 SubId>`，切换测试。

**iPhone / iPad / Android**：同理。

**观察指标**（每天 3 时段，工作日 10/20/23 点）：

```bash
# 本地 Mac 跑（已切到新机节点）
curl -o /dev/null https://speed.cloudflare.com/__down?bytes=104857600 \
     -w "速度: %{speed_download} bytes/s\n"
# 期望：白天 10+ MB/s，晚高峰 5+ MB/s
```

任一晚低于 3 MB/s 或 YouTube 4K 频繁 buffer，记下来。

### 9.9 Phase 7：通知家人切换

判断标准：
- ✅ 晚高峰 4K 不卡 + 白天流畅 → 通知家人
- ⚠️ 偶尔卡顿（一周 1-2 次）→ 继续观察，考虑加买 CN2 GIA 备线
- ❌ 频繁卡/断流 → 在退款窗口内开 ticket 退款

**强烈建议**：用 TeamViewer / 向日葵 **远程帮每个家人操作一遍**，比让他们自己搞效率高 5 倍。

### 9.10 Phase 8：旧机冷备 1 个月

- 旧机不动任何配置
- 家人客户端里保留旧机订阅作为 fallback Profile
- 每周 `ssh root@<OLD_VPS_IP> "systemctl status x-ui | head; df -h /"` 检查
- 成本：冷备 1 月 ≈ ¥44；冷备 2 月 ≈ ¥88

第 5 周决定：新机无问题 → Destroy 旧机。

```
Vultr:     https://my.vultr.com  → Instances → ⋮ → Destroy
HostHatch: https://my.hosthatch.com → Services → Cancel/Refund
```

Destroy 前：
1. 降级 DNS 记录（如有域名解析到旧机）
2. 删掉 API key / cloud console 里和旧机绑的 SSH key
3. Billing 页看是否有按天退费（prorated refund）

### 9.11 紧急回滚

任何阶段出问题：

```
场景 1: 你一个人在测 → 客户端切回旧机 Profile
场景 2: 已通知家人但没全换 → 微信群撤销通知，全员切回旧机
场景 3: 全员已切新机、新机挂了 → 家人切 fallback Profile 到旧机
```

**核心心法**：冷备期内**旧机永远不要手动碰它**，它是你的红色按钮。

### 9.12 迁移验收清单

- [ ] 新机买到，Ubuntu 22.04 跑起来
- [ ] SSH key 配好，密码登录禁用
- [ ] `install.sh` 跑完，UFW 放行 22/443/2096/25500 + 旧机 panel port
- [ ] 数据库整库迁移，面板能登，clients/inbounds 可见
- [ ] Reality pbk/sid 两边一致
- [ ] sub-converter 每条 token 返回节点，server 字段 = 新机 IP
- [ ] 你自己 Mac/iPhone/iPad/Android 切到新机，测 3 天稳定
- [ ] 家人订阅 URL 更新到新机，全家能用
- [ ] 旧机保留冷备 1 月
- [ ] 第 5 周 Destroy 旧机

---

## 10. 日常维护 Cheatsheet

### 10.1 加一个家人

```
1. 面板 → Inbounds → ace-vpn-reality → Add Client
2. Email: family-xxx   UUID: 点刷新   Sub ID: sub-hxn01   Flow: xtls-rprx-vision
3. Save ×2
4. 发订阅 URL: http://<VPS_IP>:25500/clash/sub-hxn01
```

### 10.2 改分流规则（全家同步）

```bash
# 本地改 scripts/sub-converter.py
scp scripts/sub-converter.py root@$VPS_IP:/opt/ace-vpn-sub/sub-converter.py
ssh root@$VPS_IP "systemctl restart ace-vpn-sub"
# 家人客户端点"更新订阅"，10 秒生效
```

### 10.3 日志自动清理（小盘 NVMe 必装）

```bash
cat > /etc/cron.daily/ace-vpn-logclean <<'EOF'
#!/bin/bash
journalctl --vacuum-time=7d
find /usr/local/x-ui/bin/ -name '*.log' -mtime +7 -delete 2>/dev/null
find /var/log -name '*.log' -size +100M -exec truncate -s 50M {} \; 2>/dev/null
EOF
chmod +x /etc/cron.daily/ace-vpn-logclean
```

### 10.4 自动备份数据库

```bash
cat > /etc/cron.daily/ace-vpn-backup <<'EOF'
#!/bin/bash
BACKUP_DIR=/root/backup
mkdir -p "$BACKUP_DIR"
cp /etc/x-ui/x-ui.db "$BACKUP_DIR/x-ui-$(date +%F).db"
find "$BACKUP_DIR" -name "x-ui-*.db" -mtime +14 -delete
EOF
chmod +x /etc/cron.daily/ace-vpn-backup
```

### 10.5 健康检查 + 自恢复

```bash
cat > /etc/cron.hourly/ace-vpn-healthcheck <<'EOF'
#!/bin/bash
for svc in x-ui ace-vpn-sub; do
  systemctl is-active --quiet $svc || systemctl restart $svc
done
EOF
chmod +x /etc/cron.hourly/ace-vpn-healthcheck
```

### 10.6 证书续期（IP 证书 6 天）

面板用的是 Let's Encrypt for IP 临时证书，6 天续一次：

```bash
ssh root@$VPS_IP x-ui
# 菜单 19 -> 续 IP SSL
```

或写成 cron（需先确认 `x-ui` CLI 支持非交互参数）。

### 10.7 SUB_TOKEN / UUID 定期轮换（半年一次）

1. 3x-ui 面板里 SubId 重命名（如 `sub-hxn` → `sub-hxn-2026q4`）
2. 更新 `SUB_TOKENS` 环境变量：`systemctl edit ace-vpn-sub`
3. `systemctl restart ace-vpn-sub`
4. 通知家人刷新订阅 URL

---

## 11. 红线 & 安全

1. **不提交任何 UUID / pbk / 面板 URL / 订阅 URL / 真实 VPS IP** 到 Git（见 `.gitignore`）
2. **面板端口/路径/账号绝不用默认值**（2053/admin/admin 的面板等于裸奔）
3. **订阅端口**（2096 / 25500）永远走内部 path + 随机 token，别让路径可枚举
4. **每半年**滚动一次 SubToken 和 UUID
5. **迁移后**旧 VPS 的 3x-ui 至少**卸载 + 销毁磁盘**，不能留着
6. **下单新 VPS 时**：关代理、真实中国 IP、真实中国账单地址（HostHatch 反欺诈必过）

---

## 附：相关文件

| 路径 | 作用 |
|------|------|
| `scripts/install.sh` | 新机入口：系统 + 防火墙 + 3x-ui + （可选）自动建 Reality |
| `scripts/setup-system.sh` | 系统初始化 + BBR |
| `scripts/setup-firewall.sh` | UFW |
| `scripts/install-3xui.sh` | 3x-ui 安装器包装 |
| `scripts/configure-3xui.sh` | 调 3x-ui API 建 VLESS+Reality 入站 |
| `scripts/install-sub-converter.sh` | sub-converter systemd 部署（多 token）|
| `scripts/sub-converter.py` | Python Clash YAML 转换器（原生 Reality）|
| `scripts/lib/common.sh` | 共享工具（log / apt / root check）|
| `private/env.sh` | 本地真实凭据（⚠️ 不入 git）|
| `private/ace-vpn-credentials.txt` | 凭据备份（⚠️ 不入 git）|
| `docs/用户手册 user-guide.md` | 给普通用户（家人）的手机 / 平板 / 电脑客户端手册 |
