# ace-vpn 开发者日志（dev-skill）

> 项目从 2026-04-17 启动至今的开发记录。按 **新增功能 / 性能优化 / 踩坑与填坑** 三大主题组织，所有条目都标注日期，方便半年后翻看。
>
> 系统级文档（架构、部署、订阅、规则、客户端、同步）请看 [ACE 架构设计](./三网段分流架构.md)；本文只写"做了什么 / 学到什么"。
>
> 案例主线：**Vultr Tokyo → HostHatch Tokyo**（2026-04，数据库整库迁移，家人无感切换）。

---

## 目录

1. [项目目标 & 当前状态](#1-项目目标--当前状态)
2. [新增功能（按时间倒序）](#2-新增功能按时间倒序)
3. [性能优化](#3-性能优化)
4. [踩坑与填坑（按主题分类）](#4-踩坑与填坑按主题分类)
5. [WARP 备选方案（Cloudflare WARP outbound）](#5-warp-备选方案cloudflare-warp-outbound)
6. [VPS 迁移 Playbook](#6-vps-迁移-playbook)
7. [日常维护 Cheatsheet](#7-日常维护-cheatsheet)
8. [红线 & 安全](#8-红线--安全)
9. [附：相关文件](#9-附相关文件)

---

## 1. 项目目标 & 当前状态

### 1.1 目标画像

- **谁用**：2–5 人家庭（我 + 家人 Windows）；设备覆盖 Mac×2 / iPhone / iPad / Android / Win×2。
- **三个网段**：公司内网（公司 VPN 直连）/ 中国境内（直连）/ 海外（代理）。
- **硬要求**：
  - AI 工具（Claude / Cursor / ChatGPT）**永远海外 IP**
  - Discord / X / YouTube 4K 流畅
  - 抖音/淘宝/B 站**不被代理拖慢**
- **预算**：≤¥400/年（首版 Vultr 月付验证 → 转 HostHatch 年付）
- **迁移**：今天用 Vultr，明天可能换 HostHatch，**15 分钟无感迁移**，家人客户端只改 IP

### 1.2 当前状态（2026-04）

| | 主机 | 规格 | 价格 | 状态 |
|---|------|------|------|------|
| 🟢 生产 | **HostHatch Tokyo** | 1 AMD EPYC Milan / 2GB / 10GB NVMe / 1TB BW | $4/月 ≈ ¥345/年 | 2026-04-21 起运行中 |
| 🟡 冷备 | Vultr Tokyo | 1 vCPU / 1GB / 25GB / 2TB BW | $6/月 | 1 个月观察期，2026-05-20 destroy |
| 🔴 已放弃 | Oracle Free ARM (Osaka) | 4C/24G 免费 | 0 | 两次注册风控，改年付 |

---

## 2. 新增功能（按时间倒序）

### 2.1 [2026-04-24] sub-converter `extra.cn` 强制国内 DNS（`CN_PUBLIC_DNS`）

**背景**：本周最深的坑——`extra.cn` 里的零信任域名（公网 SaaS / 网关后挂业务）TUN + 海外 PROXY 同时开时，Mihomo 默认 DoH 经 PROXY 解析返回该网关的海外 CDN 节点 IP，DIRECT 直连后 TLS 握手卡死。详见 §4.A.7。

**变更**：`scripts/sub-converter.py` 引入 `CN_PUBLIC_DNS = ["119.29.29.29", "223.5.5.5"]` 常量，给 `extra.cn` 域名同时生成两份配置：
- `nameserver-policy: "+.<host>": [119.29.29.29, 223.5.5.5]` — 强制 UDP 53 国内公网 DNS
- `fake-ip-filter: +.<host>` — 跳过 fake-IP，确保规则反查路径不绕回 DoH

效果：`dig +short cas.<corp>.example` 从 `198.18.x.x` / 海外 CDN IP 变成稳定的国内入口 IP，`curl` 秒回 302。

### 2.2 [2026-04-24] `intranet.yaml` schema 三类域名分类

**背景**：把 SaaS / 零信任公网域名误塞进 `profiles.<>.domains`（强制走公司 10.x DNS），企业 VPN 没真注入 10/8 路由时一律 SERVFAIL。详见 §4.A.6。

**变更**：`intranet.yaml` 顶部新增 schema 注释，明确 A/B/C 三类：

| 类型 | 公网 DNS | 入口 | 应放在 |
|---|---|---|---|
| A. 真·内网 | 解不到 | 10/8 | `profiles.<>.domains` |
| B. SaaS | 公网真实 IP | 公网 | `extra.cn` |
| C. 零信任网关 | 公网网关 IP | 公网网关 | `extra.cn` |

`ace-vpn-private/notes-intranet-debugging.md` 记录占位符 ↔ 真实公司域名/IP 对照表（不进 public 仓库）。

### 2.3 [2026-04-24] `promote-to-vps.sh` 默认 local-wins + `sync-intranet.sh` 5 份滚动备份

**背景**：本地池规则 promote 到 VPS 时，本地视角才是新决策（用户刚改），但脚本默认让 VPS 旧规则赢，等于白改。

**变更**：
- `promote-to-vps.sh` **默认** 用本地 `local-rules.yaml` 覆盖 VPS `intranet.yaml` 中同名 host（不再需要 `--local-wins` flag），并打印冲突日志：哪些 host 是新增、哪些和 VPS 一致、哪些被改写（含 from → to 的位置 / target 变化）。
- `sync-intranet.sh` 每次 scp 覆盖前，远端在 `<dir>/backups/intranet-<时间戳>.yaml` 自动备份，**只保留最近 5 份**。回退：`scp <vps>:/etc/ace-vpn/backups/intranet-<时间戳>.yaml ./private/intranet.yaml && bash scripts/sync-intranet.sh`。

### 2.4 [2026-04-23] WARP 备选方案（实战跑通后弃用）

**背景**：当时怀疑 HostHatch JP 的 IP 被 Google 封，准备给 Gemini / NotebookLM 等域名走 Cloudflare WARP。完整调通后用 §5.2 的 SOP 复测，**当前 IP 没被封**（看到 `notSupported` 是 Google 账号绑定地区问题，跟 IP 无关）。

**沉淀**：完整流程留在 §5。判定 SOP / fscarmen Non-global 模式 / Xray 三铁律 / 3x-ui DB 覆盖坑全部成文，未来真被封时照做即可。

### 2.5 [2026-04-22] 多 VPS 同步 + `vps-watch-urls.sh`

**变更**：
- `sync-intranet.sh --all-vps` 一条命令同时刷 HostHatch 和 Vultr（`VPS_NODES="hosthatch:IP vultr:IP"` 解析），单台失败默认 fail-fast，加 `--continue-on-error` 跳到下一台。
- `sg-tunnel.sh` 新加坡 SSH 跳板（脱敏后 commit），用于 Oracle 注册等场景从干净 IP 出口。

### 2.6 [2026-04-21] 本地规则池：`add-rule` / `list-rules` / `promote` / `rollback` 三层安全网

**背景**：日常发现某个域名要走代理 / 直连 / 内网，但**还没想清楚是否值得让全家都同步**。需要"先在本机秒级生效，攒够再批量推 VPS"。

**变更**：四脚本闭环：
- `add-rule.sh <URL> <IN|DIRECT|VPS> [host] [--note ...]` — 写入 `private/local-rules.yaml`（git 跟踪在 `ace-vpn-private`）
- `list-rules.sh` — 看本地池
- `apply-local-overrides.sh` — 渲染成 Mihomo Party 的 `override/ace-vpn-local.yaml`（用 `+rules:` prepend、`dns.+fake-ip-filter:` prepend、`dns.nameserver-policy.<+.host>:` 强制覆盖深度合并语法），GUI 监听目录秒级 reload
- `promote-to-vps.sh` — 推 VPS + 清空本地池

**三层安全网**：
1. **pre-flight 校验**：本地池里所有 `VPS` 类规则的 proxy group 必须在当前 active profile 里存在，否则直接拒写
2. **自动备份**：每次写入前把旧 override 备份到 `override/.bak/`（保留最近 10 个）
3. **rollback-overrides.sh**：`--last` 回退到最近一个备份 / `--disable` 应急核选项彻底禁用本地 override / `--clear` 清空 / 交互选

### 2.7 [2026-04-21] target 命名归一：`IN` / `DIRECT` / `VPS`

**变更**：从 `intranet/cn/overseas` 改成更直观的 **IN（内网）/ DIRECT（直连）/ VPS（经过 VPS）**——用户视角而不是开发视角。大小写无关 + 老名兼容自动归一。`intranet.yaml` 顶层 `extra.{overseas,cn}` 字段名保持不变（避免破坏 sub-converter 已部署的 schema）。

### 2.8 [2026-04-21] 顶层 `extra.{overseas, cn}` 设计

**变更**：`intranet.yaml` 新增顶层 `extra: { overseas: [...], cn: [...] }`，跨 profile 共享（不属于任何具体公司）。`sub-converter.build_rules()` 把 `extra.overseas` / `extra.cn` 插在内置 `AI_DOMAINS` / `SOCIAL_PROXY` / `CHINA_DIRECT` **之前** prepend，**用户手加规则永远赢内置默认**（修正误判 / 接管新服务）。`/healthz` 暴露 `extra_overseas=N` `extra_cn=N` 计数便于验证。

### 2.9 [2026-04-21] 公私仓库分离 + symlink 工作流

**变更**：
- 真实配置（`intranet.yaml` / `env.sh` / `credentials.txt` / `local-rules.yaml`）迁入私有仓库 `ace-vpn-private`
- public 仓库 `ace-vpn` 通过 `private/intranet.yaml -> ../../ace-vpn-private/intranet.yaml` symlink 接入
- public `.gitignore` 把 `private/*` 全部忽略（symlink 也忽略），任何真实数据都进不了 public git 历史
- `ace-vpn-private` 维护 `sensitive-words.txt` 黑名单 + public 仓库装 pre-commit hook 扫 staged diff

### 2.10 [2026-04-19] 多 profile `intranet.yaml` + per-profile `dns_servers`

**变更**：
- 旧做法：`COMPANY_CIDRS` / `COMPANY_SFX` 环境变量 → `systemctl restart`（每改一次都要 ssh + 改 env + 重启）
- 新做法：一份 YAML（多 profile + `enabled` 开关）+ Mac 本地编辑 + `sync-intranet.sh` 一键 scp + VPS 端 per-request 热加载（零 systemctl）
- per-profile `dns_servers` 把"公司 A 用 10.234.x DNS / 公司 B 用 10.20.x DNS"分开维护，外包 / 双公司场景同时开多个 profile 直接共存
- 详见 [ACE 架构设计 §9 内网热加载机制](./三网段分流架构.md#9-内网热加载机制)

### 2.11 [2026-04-19] sub-converter `/match` 调试接口 + `test-route.sh`

**变更**：`sub-converter` 暴露 `/match?url=<URL>` 或 `?host=<HOST>`，返回该 URL 命中哪条规则（JSON：`{rule_index, rule, target, host, resolved_ip, active_profiles}`）。**和生成订阅走同一条代码路径**，所以服务端说命中哪条客户端就命中哪条（除非客户端缓存或 GUI override）。

Mac 端 `scripts/test-route.sh <URL>` 一次打三套诊断：
1. 服务端权威决策（`/match`）
2. 本机系统 DNS 解析（看是不是 `198.18.x.x` fake-IP）
3. 通过本机 Clash 代理实发 HTTPS 请求（拿 `time_*` 各阶段延时 + 出口 IP）

### 2.12 [2026-04-18] 多 token 单实例 sub-converter

**变更**：早期设计是"每家人一个 sub-converter 实例"，演进为：**一个实例 / 多 token 白名单 / token 对应 3x-ui 里的 SubId**。

```
SUB_TOKENS=sub-hxn,sub-hxn01     # 环境变量白名单
GET /clash/<token>:
  1. 校验 token 在白名单
  2. 拉 UPSTREAM_BASE/<token>（3x-ui base64 vless://）
  3. 解析 → 生成 Clash proxies
  4. SERVER_OVERRIDE 覆盖 server 字段
  5. 拼装 rule-providers + rules → 返回 YAML
```

| Token | 服务对象 |
|-------|---------|
| `sub-hxn` | 自己（Mac×2 / iPhone / iPad / Android）|
| `sub-hxn01` | 家人（Win×2 / ...） |

加人只需面板加 Client + 挂对应 SubId；加新 SubId 改 `SUB_TOKENS` 环境变量 + restart。详见 [ACE 架构设计 §5 sub-converter 多 token 架构](./三网段分流架构.md#5-sub-converter-多-token-架构)。

### 2.13 [2026-04-18] 整库迁移：3x-ui SQLite Vultr → HostHatch（家人无感）

**关键**：3x-ui 把 Client / SubToken / Inbound / xray 模板**全部存在 `/etc/x-ui/x-ui.db`** 一张 SQLite。整库 cp 到新机就是整站迁移，UUID / pbk / sid / SubId 全保留，**家人客户端只改订阅 URL 里的 IP**，不用换节点 / 不用换密钥。

完整 12 步 playbook 沉淀进 §6。

### 2.14 [2026-04-17] 一键部署：`install.sh` / `configure-3xui.sh`

**变更**：新机 5 行命令完成"系统 + 防火墙 + 3x-ui + 自动建 Reality 入站 + sub-converter"。`AUTO_CONFIGURE=1` 模式下 `configure-3xui.sh` 调 3x-ui HTTP API 自动建 VLESS+Reality 入站（SNI=cloudflare.com，flow=xtls-rprx-vision），凭据写到 `/root/ace-vpn-credentials.txt`。详见 [ACE 架构设计 §3 VPS 一键部署](./三网段分流架构.md#3-vps-一键部署)。

---

## 3. 性能优化

### 3.1 DNS 路径优化：DoH → 国内 UDP 53（`CN_PUBLIC_DNS`）

**问题**：默认 `nameserver: [doh.pub, dns.alidns.com]` 是 HTTPS DoH。TUN + 海外 PROXY 节点开启时，DoH HTTPS 请求经 PROXY 出去，**站在海外节点视角**解析国内 SaaS / 零信任域名 → 拿到对应 CDN 海外节点 IP → DIRECT 直连静默丢包。除性能损失外，正确性也错。

**优化**：sub-converter 给 `extra.cn` 域名强制 `nameserver-policy → [119.29.29.29, 223.5.5.5]` 国内 UDP 公网 DNS。Mihomo 看到裸 IP 直接构造 UDP 53 出去（不经 PROXY），永远拿国内视角的入口 IP。本周重大修复，详见 §2.1 / §4.A.7。

### 3.2 fake-IP filter 精细化

**问题**：`fake-ip-range` 默认对所有域名生成 `198.18.x.x` 假 IP。对内网 / SaaS 域名是灾难——`DIRECT` 时 Mihomo 把假 IP 扔给系统 socket，应用建 TCP 时操作系统对 `198.18.x.x` 没真路由 → RST。

**优化**：
- 内网域名（A 类）+ SaaS / 零信任（B/C 类）全部加进 `fake-ip-filter`，跳过 fake-IP 直接做真实 DNS 解析
- `fake-ip-filter` 写法是 **域名 / 后缀 list**，不是 mihomo 文档里写的 `*`（`*` 实际只匹配单段标签，等于没写）

### 3.3 配置热加载：per-request parse 替代 systemctl restart

**问题**：传统 Linux 服务用 SIGHUP / inotify 触发 reload，要么人工触发要么状态复杂。

**优化**：sub-converter 每次 HTTP 订阅请求都 `load_intranet_config()`（< 1ms 解析 4KB YAML）。换来"Mac 上改完 scp 就生效"的零状态简单度。订阅请求天然低频（每客户端一天几次），性能可忽略。

### 3.4 GeoIP mmdb 启动拉新

**问题**：mihomo 内置 `Country.mmdb` 长时间不更新，新分配给中国的 IP 段没收录，`GEOIP,CN,DIRECT` 误判走代理。

**优化**：订阅 YAML 里 hardcode：

```yaml
geodata-mode: true
geox-url:
  mmdb: "https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb"
```

客户端每次启动拉最新库，无需用户介入。

### 3.5 客户端订阅缓存：`Profile-Update-Interval: 24`

**优化**：sub-converter 给 Clash YAML response header 加 `Profile-Update-Interval: 24`，客户端被动 pull 一天一次，减小 VPS 端订阅请求压力。改规则秒级生效靠用户主动"刷新订阅"，不需要全家立即拉。

### 3.6 流量路径：Reality + EPYC + NVMe

| 优化点 | 效果 |
|---|---|
| **VLESS Reality flow=xtls-rprx-vision** | 比裸 vless 减少一层 mux；TLS 握手伪装第三方真实站 |
| **VPS 选 AMD EPYC Milan + NVMe** | 比 Vultr Intel + SSD 单核快 30-50%；NVMe 把 sqlite I/O 从瓶颈变零延时 |
| **Linux BBR + fq congestion** | `setup-system.sh` 默认开启；晚高峰下有效压平丢包 |
| **`net.ipv4.ip_forward=1` + 文件句柄上限** | xray 高并发握手必开 |

### 3.7 per-profile `dns_servers` 减少跨网 DNS 跳数

**优化**：每个 `intranet.yaml` profile 自带 `dns_servers: [10.x.x.1, 10.x.x.2]`，sub-converter 渲染时只把这条 profile 下的 `domains` 走对应 DNS。多公司并存场景：A 公司域名走 A 内网 DNS、B 公司域名走 B 内网 DNS、互不干扰。比"统一一套 fallback DNS"少一次错查。

---

## 4. 踩坑与填坑（按主题分类）

> 历史踩坑共 16 条，按主题归到 **A. DNS / B. 部署与 VPS / C. 客户端与工具链** 三类。日期标注的可以反查事件起源。

### 4.A DNS 类

#### 4.A.1 [2026-04-19] Mihomo Party 吞掉订阅的 DNS 段 ⚠️

**现象**：服务端 YAML 里 `fake-ip-filter` / `nameserver-policy` 都对、客户端 profile 文件里也对，**但** TUN 模式下 `dig portal.corp-a.example` 仍返回 `198.18.x.x`，`dig @<INTERNAL_DNS>` 也是。关 TUN 一切正常，开 TUN 就挂。

**根因**：Mihomo Party 在 `~/Library/Application Support/mihomo-party/config.yaml` 里默认 `controlDns: true` + `useNameserverPolicy: false`。开着 `controlDns` 时 GUI 把订阅的 `dns:` 段**整块替换**成 GUI 默认（`fake-ip-filter` 只含 `*` / `+.lan` / `+.local`）—— 我们精心塞的 `+.app.corp-a.example` 被直接丢弃。

**定位**：

```bash
grep -E "controlDns|useNameserverPolicy" \
  ~/Library/Application\ Support/mihomo-party/config.yaml
grep -A12 "fake-ip-filter" \
  ~/Library/Application\ Support/mihomo-party/work/config.yaml
```

如果 `work/config.yaml` 的 fake-ip-filter 和订阅 yaml 不一致，100% 是 GUI override。

**修复（一次性）**：

```bash
sed -i '' 's/^controlDns: true$/controlDns: false/' \
  ~/Library/Application\ Support/mihomo-party/config.yaml
sed -i '' 's/^useNameserverPolicy: false$/useNameserverPolicy: true/' \
  ~/Library/Application\ Support/mihomo-party/config.yaml
sudo pkill -9 -f mihomo
# Cmd+Q Mihomo Party 后重开
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```

GUI 等价：设置 → DNS → 关「控制 DNS」+ 开「使用 Nameserver Policy」。

**教训**：Clash Party / Mihomo Party / mihomo binary / runtime 四层都有脾气，要逐层 diff 验证（参见 §4.A 末尾「三层 diff」）。

#### 4.A.2 [2026-04-19] TUN 模式拦截所有 UDP 53

**现象**：§4.A.1 修完，关 TUN 正常，开 TUN 仍假 IP。

**根因**：TUN 是 L3 虚拟网卡，把**所有**进程的 UDP 53 流量都劫持给 mihomo 内置 DNS，哪怕你 `dig @10.x.x.1` 也不会走出物理网卡。

**修复**：接受现实，在 YAML `nameserver-policy` 里写**死 IP**（不是 `system`）。Mihomo 内部 DNS 组件会区分"自己发的"和"应用发的"，前者直接构造 UDP 包从物理网卡出去。

#### 4.A.3 [2026-04-19] fake-IP 缓存持久化

**现象**：修完 `fake-ip-filter` 重启 mihomo，某内网域名**还是**返回 fake-IP。

**根因**：fake-ip cache 落盘在 `~/Library/Application Support/mihomo-party/work/cache.db`，mihomo 启动时 reload。

**修复**：

```bash
rm ~/Library/Application\ Support/mihomo-party/work/cache.db
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
# Cmd+Q 重开 Mihomo
```

#### 4.A.4 [2026-04-19] GeoIP 数据库过期

**现象**：`GEOIP,CN,DIRECT` 把某些国内 IP 判成海外，走代理变慢。

**根因**：mihomo 内置 `Country.mmdb` 不更新，新分配给中国的 IP 段没收录。

**修复**：订阅 YAML 加 `geox-url.mmdb` 拉 Loyalsoldier 维护的最新库（详见 §3.4）。

#### 4.A.5 [2026-04-19] `hosts:` 写死导致规则失效

**现象**：为加速把 `claude.ai: 1.2.3.4` 写进 `hosts:`，结果 `claude.ai` 不再走代理。

**根因**：`hosts:` 在 DNS 之前生效，返回真实 IP 后，`DOMAIN-SUFFIX,claude.ai` 规则不再匹配（它匹配的是 host name，但应用拿到 IP 直接建连，Clash 只能靠反查，部分客户端反查会跳过）。

**修复**：不用 `hosts:` 加速，改用 `rule-providers` 或让代理节点选好 CDN。

#### 4.A.6 [2026-04-24] 把"零信任 / SaaS 公网域名"误当成"真·内网域名" ⚠️

**现象（本周最深的坑之一）**：把公司常用的 SaaS / 零信任网关后挂的服务域名（`<saas>.example` / `<sso>.<corp-office>.example` / `<biz-app>.<corp-app>.example`）加进 `intranet.yaml` 的 `profiles.<>.domains`。一开 ace-vpn TUN：`dig` SERVFAIL / 假 IP，`curl` 卡死。关掉 ace-vpn 反而能上。

**根因**：这些是**公网域名**——公网 DNS 能查到公司零信任网关的国内公网 IP，鉴权由网关侧的企业 VPN session 负责，**不需要也不该走 10.x 公司内网 DNS**。但 sub-converter 把 `profiles.<>.domains` 自动转成 `nameserver-policy → 10.x DNS`；你不在公司内网 + 企业 VPN 没真注入 10/8 路由（被 ace-vpn TUN 抢全表后是常态，见 4.A.8）→ DNS SERVFAIL。

**正确分类（已固化在 `intranet.yaml` 顶部注释）**：

| 类型 | 公网 DNS | 入口 | 应放在 |
|---|---|---|---|
| A. 真·内网（`<srv>.intranet`）| 解不到 | 10/8 | `profiles.<>.domains` |
| B. SaaS（`<saas-app>.example`）| 公网真实 IP | 公网 | `extra.cn` |
| C. 零信任网关（`<sso>.<corp-office>.example`）| 公网网关 IP | 公网网关 | `extra.cn` |

**判定方法**：彻底关 ace-vpn 和企业 VPN，跑 `dig +short <域名>`。返回 IP（哪怕是网关 IP）→ B/C，放 `extra.cn`；空/SERVFAIL → A，放 `profiles.<>.domains`。

#### 4.A.7 [2026-04-24] `extra.cn` 域名走默认 DoH 解析到海外 IP ⚠️

**现象（4.A.6 修完后才暴露的进阶坑）**：分类对了，但 TUN + 海外 PROXY 同时开时 `dig` 返回 fake-IP；`curl` Connected → TLS 握手卡死 10 秒；通过 Mihomo HTTP 代理 CONNECT 该域名时 Mihomo 内部解析到该零信任网关的**海外 CDN 节点 IP**。

**根因**：Mihomo 默认 `nameserver` 是 DoH（`doh.pub` / `dns.alidns.com`）。TUN + 海外 PROXY 开启时 DoH HTTPS 流量经 PROXY 出去 → **站在海外节点视角**解析 → 拿到该网关的海外 CDN IP → DIRECT 直连 → 海外节点对未鉴权请求静默丢包 → TLS 卡死。

**修复（已固化在 `sub-converter.py` 的 `CN_PUBLIC_DNS` 常量）**：给 `extra.cn` 强制 `nameserver-policy → [119.29.29.29, 223.5.5.5]` 国内 UDP 公网 DNS + 加进 `fake-ip-filter`。Mihomo 看到裸 IP 不预解析、直接 UDP 出去（不经 PROXY），永远拿国内视角 IP，秒回 302。

```yaml
# sub-converter 自动生成
nameserver-policy:
  +.<sso-domain>.example: [119.29.29.29, 223.5.5.5]
fake-ip-filter:
  - +.<sso-domain>.example
```

**验证**：客户端刷新订阅 + `rm cache.db` + 完全重启 mihomo（不只是重启 TUN）后：

```bash
dig +short <你的零信任域名>        # 期望国内 IP
curl -o /dev/null -w '%{http_code}\n' https://<你的零信任域名>/   # 期望 302
```

#### 4.A.8 [2026-04-24] 企业 VPN 客户端 + ace-vpn TUN 启动顺序

**现象**：企业 VPN 客户端打开后看似已连，但 `netstat -rn -f inet | grep "^10/"` **看不到 10.0.0.0/8 路由**，所有内网请求打不通。

**根因**：ace-vpn TUN 用 `auto-route: true` 把 `0.0.0.0/0` 拆成 `1/8` `2/7` `4/6` ... 占满全表。**后启动**的企业 VPN 发现冲突就静默放弃注入 10/8。

**修复**：调整启动顺序——**先连企业 VPN 客户端**，看到 `utun*: 10.x.x.x` + `10/8 → utun*` 后**再开 ace-vpn TUN**。基于"更具体路由优先"原则共存：10.x 走企业 VPN，其他走 ace-vpn TUN。

```bash
# 验证企业 VPN 真的接管了 10/8
ifconfig | awk '/^utun/{i=$1} /inet 10\./{print i": "$2}'
netstat -rn -f inet | grep "^10/"
```

#### 4.A.X 三层 diff（DNS 类问题通用排查）

怀疑客户端 GUI 吞订阅时：

```bash
# 订阅原文 vs mihomo runtime
diff <(curl -s http://$VPS_IP:25500/clash/$SUB_TOKEN | grep -A30 "^dns:") \
     <(grep -A30 "^dns:" ~/Library/Application\ Support/mihomo-party/work/config.yaml)
```

两份应完全一致；有差异就是客户端层吃掉了。

### 4.B 部署 / VPS 类

#### 4.B.1 [2026-04-17] Oracle 注册被风控

**现象**：「无法完成您的注册」，两次均挂。

**根因**：Oracle WAF + 反欺诈检查"国家 / 卡 BIN / IP / 主区域"一致性。频繁改字段、信用卡 BIN 与国家不匹配都会挂。

**结论**：放弃白嫖，改年付 HostHatch。详见 [Oracle Cloud 注册教程](./Oracle%20Cloud%20注册教程.md)。

#### 4.B.2 [2026-04-17] 3x-ui 安装器交互提示

**现象**：`install.sh` 跑到官方安装器时会问 panel port / admin / SSL 方式。

**修复**：手动响应 `y → 2053 → admin/admin/admin → 2`（IP 证书）。装完立刻到 Web 面板改掉 admin/admin 和 path。

#### 4.B.3 [2026-04-17] Hysteria2 在 Xray 26.x 里 "unknown config id"

```
ERROR - XRAY: Failed to start: ... infra/conf: unknown config id: hysteria2
```

**根因**：3x-ui 能保存 Hy2 入站到 db，但 Xray 主线代码把 Hy2 inbound 协议 ID 改掉，启动直接报错。一旦报错**整个 xray 进程挂，VLESS 一起废**。

**修复**：

```bash
sqlite3 /etc/x-ui/x-ui.db "DELETE FROM inbounds WHERE port=8443"
systemctl restart x-ui
```

暂时放弃 Hy2，Reality 完全够用。

#### 4.B.4 [2026-04-17] `configure-3xui.sh` 提示 pbk 为空 / 入站创建失败（多重合集）

| 子问题 | 根因 | 修复 |
|---|---|---|
| `pbk` 空 | 新版 `xray x25519` 输出 `Password:` 而不是 `PublicKey:` | `grep PublicKey` 匹配不到时 fallback 读 `Password:` |
| 入站创建失败 | 3x-ui v2 API 路径 `/panel/inbound/add` → 改成 `/panel/api/inbounds/add`；要 `X-Requested-With: XMLHttpRequest` | 脚本统一 |
| Hy2 `empty client ID` | 3x-ui 对非 trojan/ss 协议要求 `clients[].id` 非空 | Hy2 payload 给 `clients[0].id` 塞 UUID |
| `Port already exists: 443` | 3x-ui 端口校验**不分 TCP/UDP**，VLESS 443/TCP 已占，Hy2 443/UDP 被拒 | Hy2 默认改 UDP 8443 |
| `set -e` 提前退出 | `grep` 匹配不到退出码非 0，`pipefail` 触发 `set -e` | `( ... ) || true` 包裹 |

#### 4.B.5 [2026-04-18] sub-converter 所有节点 `server: 127.0.0.1`

**现象**：Clash YAML 里 `server: 127.0.0.1`，客户端全 timeout。

**根因**：3x-ui 根据 HTTP Host 头生成 vless 链接的 server 字段。`UPSTREAM_SUB` 写 `https://127.0.0.1:2096/...` → 返回的 vless 里 host 就是 127.0.0.1。

**修复**（双保险）：
- `UPSTREAM_BASE` 用**公网 IP** 而非 127.0.0.1（首选）
- `sub-converter.py` 的 `SERVER_OVERRIDE` 环境变量强制覆盖 `server:`（兜底）

#### 4.B.6 [2026-04-18] 社区 subconverter 不认 Reality

**现象**：`tindy2013/subconverter` / `stilleshan/subconverter` 喂 vless+reality base64 全部 `No nodes were found!`。

**根因**：这些 fork 的 vless 解析器不认 `pbk` / `sid` / `spx` Reality 参数。

**修复**：自己写 `sub-converter.py`，原生支持 Reality。

#### 4.B.7 [2026-04-21] HostHatch 下单被反欺诈 flag

**现象**：下单后页面提示 "Your order has been flagged ... ordering through a VPN"。

**根因**：下单时开着代理（出口 IP 在日本/新加坡），账单地址填中国，**IP 国家 vs 账单国家不一致** → 反欺诈 flag。

**修复**：
1. **关所有 VPN 代理**，`curl ipinfo.io` 确认是中国 IP
2. 清浏览器 HostHatch cookie
3. 账单地址和信用卡账单保持一致（真实中国地址）
4. 重新下单，秒过

#### 4.B.8 [2026-04-22] 小盘 NVMe VPS 磁盘被 journal / log 挤满

HostHatch 入门套餐只有 10 GB NVMe，journalctl 和 x-ui access.log 不清会撑爆。

**修复**：装 cron 日常清理（见 §7.3）。

### 4.C 客户端 / 工具链类

#### 4.C.1 [2026-04-18] Mihomo Party 同时有 Profile 和 Override 时规则被覆盖

**现象**：订阅 OK / 节点 OK，但打开 Google 不通。

**根因**：Override 里写 `rules:` 字段会**整体替换** Profile 的 300+ 条规则。

**修复**：**只用 Profile，别写 Override**（除非要本地加公司 CIDR 直连，且不想污染订阅；这种场景请用 §2.6 的本地规则池工作流）。

#### 4.C.2 [2026-04-18] 改了 sub-converter 环境变量但不生效 / 新 token 返回 0 节点

**现象**：改 `SUB_TOKENS` / `UPSTREAM_BASE` 后 `install-sub-converter.sh` 成功，`systemctl show -p Environment` 显示新值，但服务行为和没改一样。

**根因**：旧脚本只 `systemctl enable --now`，对已运行服务**不触发重启**。`daemon-reload` 只加载新 unit 文件，旧进程仍用老环境。

**修复**：每次重装后手动 `sudo systemctl restart ace-vpn-sub`；install 脚本已改成 `enable` + 显式 `restart`，并在最后自检每条 token 节点数。

#### 4.C.3 [2026-04-17] 颜色转义字符 `\033[...]` 原样打印

**根因**：`common.sh` 用单引号 `'\033[0;33m'` 只能在 `echo -e` 下生效，`cat <<EOF` 里直接原样输出。

**修复**：改成 ANSI-C 引号 `$'\033[0;33m'`，所有 `log_*` 用 `printf`。

#### 4.C.4 [2026-04-24] promote / sync 默认 local-wins + 自动备份

不是"坑"而是"填坑"：见 §2.3 描述的旧 flow（`promote` 默认让 VPS 旧规则赢、`sync` 没备份）的两个改进。

---

## 5. WARP 备选方案（Cloudflare WARP outbound）

> **2026-04-23 实战已跑通后弃用**——HostHatch JP 当前 IP 没被 Google 封，WARP 不必要。流程沉淀在此，未来真被封时照做。完整 step-by-step 历史版本可在 git history 查已删除的 `docs/warp-upgrade.md`（commit 前于 2026-04-24）。

### 5.1 什么时候真的需要

只有这两种情况才上 WARP：

| 场景 | 判定 |
|---|---|
| ① VPS IP 被 Google 标地区限制 | 浏览器无痕 + 干净账号访问 `https://gemini.google.com` 弹 "Gemini isn't currently supported in your country"，且 SSH 上 `curl` 拿首页关键词 `notSupported` / `country` 高频出现 |
| ② VPS 出口到 Google 物理路由完全不通 | `curl https://gemini.google.com/` 直接 timeout（不是慢，是连不上） |

**不需要 WARP 的两种伪信号**：
- 直出能拿 200 + 完整 HTML（哪怕慢）→ 是路由慢，WARP 救不了
- 浏览器弹 "isn't supported" 但 SSH 上 `curl` 能 200 → 是 **Google 账号绑定地区**问题，跟 IP 无关，WARP 也救不了

### 5.2 IP 是否被封的快速 SOP

```bash
ssh root@<VPS_IP> 'curl -sSL --max-time 15 -4 \
  -H "Accept-Language: en-US,en;q=0.9" \
  -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/130.0.0.0" \
  https://gemini.google.com/ -o /tmp/g.html \
  -w "http=%{http_code} size=%{size_download} time=%{time_total}s\n"
grep -oE "<title>[^<]+</title>" /tmp/g.html | head -1
for k in country notSupported isn\\'t Sign\\ in Bard Gemini; do
  printf "  %-15s: %s\n" "$k" "$(grep -ioE \"$k\" /tmp/g.html | wc -l)"
done'
```

**判定矩阵**：

| `<title>` | 关键词 | 结论 |
|---|---|---|
| `Google Gemini` | country=0, notSupported=0, Sign in≥3 | ✅ 未被封，是正常 SPA |
| `Sorry, Gemini isn't available...` | country / isn't 高频 | ❌ 被封 |
| HTTP 302 → `support.google.com/.../answer/13278668` | — | ❌ 被封（地区受限重定向） |

### 5.3 接入流程（fscarmen/warp，已实战跑通）

```bash
# VPS 上 root 跑（fscarmen 已迁 GitLab）
wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh
bash menu.sh 4   # 选 4 = Non-global IPv4 模式（关键，否则 SSH 自指环路）

# 验证
wg show
curl --interface warp -sS https://www.cloudflare.com/cdn-cgi/trace
# 应看到 ip=104.28.x.x  warp=on
```

**`Non-global` 模式必须**：只创建 `warp` 接口，**不**改默认路由。后续由 xray 自己决定哪些域名走 WARP。如果选了 global 模式，VPS 自身管理流量也被路由到 WARP 然后回环 → SSH 都连不上自己。

### 5.4 Xray outbounds + routing 模板（关键三条铁律）

- **`outbounds[0]` 必须是 `direct`**（默认出口；放成 `warp` 会让 VPS 自指环路）
- **第一条 routing 规则强制把 `<VPS_PUBLIC_IPV4>/32` 走 `direct`**（管理流量永远不进 WARP）
- **WireGuard `reserved` 字段必须从 `wgcf-account.toml` / `warp-account.conf` 读真值**——`[0,0,0]` 默认值会让 Cloudflare 静默丢包，TLS 握手永远完不成

```bash
# 提取真实 reserved
grep -oE 'reserved.*\[.*\]' /etc/wireguard/wgcf.conf 2>/dev/null \
  || grep -oE 'reserved.*\[.*\]' /etc/wireguard/warp-account.conf
```

### 5.5 改 xray config 必须改数据库（最深的坑）

**直接编辑 `/usr/local/x-ui/bin/config.json`，systemctl restart x-ui 后改动会被回滚**。原因：3x-ui 启动时从 `/etc/x-ui/x-ui.db` 的 `settings.xrayTemplateConfig` 读模板覆盖 config.json。

**正确改法**：

```bash
ssh root@<VPS_IP> 'python3 <<"PY"
import json, sqlite3
con = sqlite3.connect("/etc/x-ui/x-ui.db")
cur = con.cursor()
cur.execute("SELECT value FROM settings WHERE key=?", ("xrayTemplateConfig",))
tpl = json.loads(cur.fetchone()[0])

# 加 warp outbound + Google AI 域名走 warp 的 routing 规则
tpl["outbounds"].insert(1, {
  "tag": "warp", "protocol": "wireguard",
  "settings": {
    "secretKey": "<wgcf 生成的 PrivateKey>",
    "address":   ["172.16.0.2/32"],
    "peers":     [{"publicKey":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
                   "endpoint":"engage.cloudflareclient.com:2408",
                   "keepAlive":30,"allowedIPs":["0.0.0.0/0","::/0"]}],
    "reserved":  [<填真实 reserved>],
    "mtu": 1280
  }
})
tpl["routing"]["rules"].insert(0, {
  "type": "field", "ip": ["<VPS_PUBLIC_IPV4>/32"], "outboundTag": "direct"
})
tpl["routing"]["rules"].insert(1, {
  "type": "field", "outboundTag": "warp",
  "domain": ["domain:gemini.google.com",
             "domain:generativelanguage.googleapis.com",
             "domain:aistudio.google.com",
             "domain:bard.google.com",
             "domain:notebooklm.google.com"]
})
cur.execute("UPDATE settings SET value=? WHERE key=?",
            (json.dumps(tpl), "xrayTemplateConfig"))
con.commit()
PY
systemctl restart x-ui'
```

### 5.6 弃用 / 拆除

```bash
# 1) 同步删 db 里的 warp outbound + warp routing 规则（同 5.5 反向操作）
# 2) 拆 fscarmen
bash menu.sh u
systemctl disable --now wg-quick@warp.service 2>/dev/null
rm -rf /etc/wireguard/warp* /etc/wireguard/wgcf*
ip link delete warp 2>/dev/null
```

### 5.7 关键教训

- **不要把 Cursor / OpenAI / Claude / Anthropic 加进 WARP 路由**——这些站 IP 没被封，走 WARP 反而绕远 + Cloudflare WARP IP 段被它们风控会更慢。`AI_DOMAINS` 里只该留 Google AI 相关 7 个域名。
- **fscarmen Non-global 残留的系统级路由要清**：`systemctl disable --now wg-quick@warp.service` + `ip rule del table 51820`，否则 SSH 自指。
- **看到 "isn't supported in your country" 不要直接判 IP 被封**——先用 §5.2 SOP 验证。

---

## 6. VPS 迁移 Playbook

> 通用 playbook。本次案例 **Vultr → HostHatch**，未来再换家把 `<OLD_VPS_IP>` / `<NEW_VPS_IP>` / `<你的 SubId>` / `<OLD_SUB_PATH>` 替换即可。

### 6.1 迁移架构图

```
[Day 0]                  [Day 1-14]                [Day 15+]
 旧机（生产）        →    旧机（冷备）         →    旧机 destroy
                          新机（测试）→全员      新机（生产）
                         （跑通后切生产）
```

### 6.2 Phase 1：买新 VPS

下单时注意：
- 关代理、用真实中国 IP、账单地址填真实中国地址（见 §4.B.7）
- SSH key 订单页贴，省略临时密码流程
- Hostname 中性
- 月付/年付按能接受的退款窗口决定

### 6.3 Phase 2：新机服务器初始化

```bash
ssh root@<NEW_VPS_IP>

# 改密码（若下单没用 key）
passwd

# 禁用密码登录
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl restart sshd

# 新开终端测试还能登
ssh root@<NEW_VPS_IP> "uptime"

apt update && apt upgrade -y
# needrestart 弹窗选默认 OK 即可
timedatectl set-timezone UTC
```

### 6.4 Phase 3：部署基础设施（不建 inbound）

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

### 6.5 Phase 4：3x-ui 数据库整库迁移（⭐ 核心）

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

### 6.6 Phase 4.5：验证

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

### 6.7 Phase 5：装 sub-converter（新机 IP 关键）

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

**关键**：`SERVER_OVERRIDE` 必须是**新机** IP，否则订阅 YAML 里 server 还是旧机，等于没迁。

### 6.8 Phase 6：自己先试 3-5 天（不通知家人）

**Mac (Mihomo Party)**：新建 Profile `ace-vpn-<新机代号>`，URL = `http://<NEW_VPS_IP>:25500/clash/<你的 SubId>`，切换测试。**iPhone / iPad / Android**：同理。

**观察指标**（每天 3 时段，工作日 10/20/23 点）：

```bash
curl -o /dev/null https://speed.cloudflare.com/__down?bytes=104857600 \
     -w "速度: %{speed_download} bytes/s\n"
# 期望：白天 10+ MB/s，晚高峰 5+ MB/s
```

任一晚低于 3 MB/s 或 YouTube 4K 频繁 buffer，记下来。

### 6.9 Phase 7：通知家人切换

判断标准：
- ✅ 晚高峰 4K 不卡 + 白天流畅 → 通知家人
- ⚠️ 偶尔卡顿（一周 1-2 次）→ 继续观察
- ❌ 频繁卡/断流 → 在退款窗口内开 ticket 退款

**强烈建议**：用 TeamViewer / 向日葵 **远程帮每个家人操作一遍**，比让他们自己搞效率高 5 倍。

### 6.10 Phase 8：旧机冷备 1 个月

- 旧机不动任何配置
- 家人客户端里保留旧机订阅作为 fallback Profile
- 每周 `ssh root@<OLD_VPS_IP> "systemctl status x-ui | head; df -h /"` 检查
- 成本：冷备 1 月 ≈ ¥44

第 5 周决定：新机无问题 → Destroy 旧机。Destroy 前：(1) 降级 DNS 记录 (2) 删 cloud console SSH key (3) 看是否有按天退费。

### 6.11 紧急回滚

```
场景 1: 你一个人在测 → 客户端切回旧机 Profile
场景 2: 已通知家人但没全换 → 微信群撤销通知，全员切回旧机
场景 3: 全员已切新机、新机挂了 → 家人切 fallback Profile 到旧机
```

**核心心法**：冷备期内**旧机永远不要手动碰它**，它是你的红色按钮。

### 6.12 迁移验收清单

- [ ] 新机买到，Ubuntu 22.04 跑起来
- [ ] SSH key 配好，密码登录禁用
- [ ] `install.sh` 跑完，UFW 放行 22/443/2096/25500 + 旧机 panel port
- [ ] 数据库整库迁移，面板能登，clients/inbounds 可见
- [ ] Reality pbk/sid 两边一致
- [ ] sub-converter 每条 token 返回节点，server 字段 = 新机 IP
- [ ] Mac/iPhone/iPad/Android 切到新机，测 3 天稳定
- [ ] 家人订阅 URL 更新到新机，全家能用
- [ ] 旧机保留冷备 1 月
- [ ] 第 5 周 Destroy 旧机

---

## 7. 日常维护 Cheatsheet

### 7.1 加一个家人

```
1. 面板 → Inbounds → ace-vpn-reality → Add Client
2. Email: family-xxx   UUID: 点刷新   Sub ID: sub-hxn01   Flow: xtls-rprx-vision
3. Save ×2
4. 发订阅 URL: http://<VPS_IP>:25500/clash/sub-hxn01
```

### 7.2 改分流规则（全家同步）

两条路径，按"是否值得让全家立刻同步"二选一：

```bash
# A. 直接改 sub-converter.py 硬编码规则（影响全家、不可回滚）
scp scripts/sub-converter.py root@$VPS_IP:/opt/ace-vpn-sub/sub-converter.py
ssh root@$VPS_IP "systemctl restart ace-vpn-sub"
# 家人客户端点"更新订阅"，10 秒生效

# B. 经本地池：先 Mac 单机生效，攒后批量 promote 到 VPS
bash scripts/add-rule.sh https://gitlab.corp-a.example/  IN   --note "内网 GitLab"
bash scripts/add-rule.sh https://claude-foo.example      VPS  --note "新 AI"
bash scripts/list-rules.sh                  # 看本地池
bash scripts/promote-to-vps.sh --dry-run    # 预览 promote 计划
bash scripts/promote-to-vps.sh              # 推 VPS + 清空本地池
```

详细机制见 [ACE 架构设计 §7 规则系统](./三网段分流架构.md#7-规则系统更新--同步--冲突)。

### 7.3 日志自动清理（小盘 NVMe 必装）

```bash
cat > /etc/cron.daily/ace-vpn-logclean <<'EOF'
#!/bin/bash
journalctl --vacuum-time=7d
find /usr/local/x-ui/bin/ -name '*.log' -mtime +7 -delete 2>/dev/null
find /var/log -name '*.log' -size +100M -exec truncate -s 50M {} \; 2>/dev/null
EOF
chmod +x /etc/cron.daily/ace-vpn-logclean
```

### 7.4 自动备份数据库

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

### 7.5 健康检查 + 自恢复

```bash
cat > /etc/cron.hourly/ace-vpn-healthcheck <<'EOF'
#!/bin/bash
for svc in x-ui ace-vpn-sub; do
  systemctl is-active --quiet $svc || systemctl restart $svc
done
EOF
chmod +x /etc/cron.hourly/ace-vpn-healthcheck
```

### 7.6 证书续期（IP 证书 6 天）

面板用 Let's Encrypt for IP 临时证书，6 天续一次：

```bash
ssh root@$VPS_IP x-ui
# 菜单 19 -> 续 IP SSL
```

### 7.7 SUB_TOKEN / UUID 定期轮换（半年一次）

1. 3x-ui 面板里 SubId 重命名（如 `sub-hxn` → `sub-hxn-2026q4`）
2. 更新 `SUB_TOKENS` 环境变量：`systemctl edit ace-vpn-sub`
3. `systemctl restart ace-vpn-sub`
4. 通知家人刷新订阅 URL

---

## 8. 红线 & 安全

1. **不提交任何 UUID / pbk / 面板 URL / 订阅 URL / 真实 VPS IP** 到 public Git（`ace-vpn-private/sensitive-words.txt` + pre-commit hook 双重保险）
2. **面板端口/路径/账号绝不用默认值**（2053/admin/admin = 裸奔）
3. **订阅端口**（2096 / 25500）永远走内部 path + 随机 token，路径不可枚举
4. **每半年**滚动一次 SubToken 和 UUID
5. **迁移后**旧 VPS 的 3x-ui 至少**卸载 + 销毁磁盘**
6. **下单新 VPS 时**：关代理、真实中国 IP、真实中国账单地址（HostHatch 反欺诈必过）
7. **公司内部域名 / 真实国内入口 IP / 零信任网关产品名**不能进 public 仓库——public 文档里全用 `<gw>.corp-a.example` 等占位，对照表存 `ace-vpn-private/notes-intranet-debugging.md`

---

## 9. 附：相关文件

| 路径 | 作用 |
|------|------|
| `scripts/install.sh` | 新机入口：系统 + 防火墙 + 3x-ui + （可选）自动建 Reality |
| `scripts/setup-system.sh` | 系统初始化 + BBR |
| `scripts/setup-firewall.sh` | UFW |
| `scripts/install-3xui.sh` | 3x-ui 安装器包装 |
| `scripts/configure-3xui.sh` | 调 3x-ui API 建 VLESS+Reality 入站 |
| `scripts/install-sub-converter.sh` | sub-converter systemd 部署（多 token）|
| `scripts/sub-converter.py` | Python Clash YAML 转换器（原生 Reality + `CN_PUBLIC_DNS`）|
| `scripts/sync-intranet.sh` | `intranet.yaml` 一键 scp + 多 VPS（`--all-vps`）+ 5 份滚动备份 |
| `scripts/add-rule.sh` / `list-rules.sh` / `apply-local-overrides.sh` / `promote-to-vps.sh` / `rollback-overrides.sh` | 本地规则池四脚本闭环 + 三层安全网 |
| `scripts/test-route.sh` | 一行命令拿"URL → 走哪条规则 → 出口 IP / 各阶段延时" |
| `scripts/lib/common.sh` | 共享工具（log / apt / root check）|
| `private/env.sh` | 本地真实凭据（⚠️ 不入 git）|
| `private/intranet.yaml` → `ace-vpn-private/intranet.yaml` symlink | 内网真实分流配置 |
| [`docs/三网段分流架构.md`](./三网段分流架构.md) | ACE 架构设计 — 系统全景 + VPS 部署 + sub-converter + DNS + 规则系统 + 多设备同步 |
| `docs/用户手册 user-guide.md` | 给普通用户（家人）的手机 / 平板 / 电脑客户端手册 |
| `docs/Oracle Cloud 注册教程.md` | 免费 ARM VPS 申请教程（备选） |
