# 📋 需求与方案总结（Requirements & Plan）

> **更新时间**：2026-04-18  
> **目的**：把多轮讨论沉淀成一份"回家/换设备/换 VPS 都能继续"的总纲。  
> 对应项目：`ace-vpn`

---

## 一、使用场景 & 设备清单

### 使用者
- **本人**：北京常驻，重度互联网 + 技术使用
- **家人**：北京，轻度使用（网页、视频）

### 需要访问的三个网段

| 网段 | 代表站点 / 工具 | 期望走法 |
|------|----------------|---------|
| **公司内网** | 内部 OA、内部文档、内部 Git | 走公司 VPN / 直连（不经个人 VPS） |
| **中国境内** | 抖音、B 站、国内银行、国内 SaaS | **直连**（不走代理） |
| **海外网站** | YouTube、Google、GitHub、Discord、Claude、ChatGPT、Cursor | **走个人 VPS（代理）** |

### 设备清单

| 设备 | 数量 | 用户 | 客户端 |
|------|------|------|--------|
| iPhone | 1 | 本人 | Shadowrocket |
| Android | 1 | 本人 | Clash Meta for Android |
| iPad | 1 | 本人 | Shadowrocket / Stash |
| Mac | 2 | 本人 | Clash Meta 系（Mihomo Party / Clash Verge Rev） |
| Windows | 2 | 家人 | Clash Verge Rev |

---

## 二、硬性需求（Must-have）

1. **三个网段正确分流**：公司 / 国内 / 海外，自动判断，**不需要手动切换全局**。
2. **AI 类工具必须走海外 IP**：包括 **Claude / Claude Code**、**ChatGPT**、**Gemini**、**Cursor**、**GitHub Copilot**。
3. **家人 Windows 零配置**：扫码 / 一键导入订阅，后续完全无感。
4. **可迁移**：今天用 Vultr，明天可能换 Oracle / HostDare / RackNerd，**15 分钟内完成迁移**，客户端不用重配。
5. **4K YouTube 流畅**（北京晚高峰，家庭共享 2–5 人）。
6. **抗 GFW**：协议层伪装，不要用易被识别特征的老协议（OpenVPN / WireGuard / Shadowsocks 裸奔）。
7. **预算**：
   - **验证阶段**：≤ ¥50 / 月
   - **长线**：≤ ¥300 / 年（Oracle 免费最佳，付费备选）

---

## 三、关键痛点与解决方向

### 痛点 1：Mac 上公司 VPN + 海外代理互相打架
- **现象**：开了海外 VPN，公司部分内网访问不通。
- **根因**：Clash TUN 模式抢走默认路由 + DNS。
- **解决**：
  - 规则里**公司 CIDR / 域名 → DIRECT**（放在 `MATCH` 之前）
  - **`dns.nameserver-policy`** 让公司域名走公司 DNS
  - TUN 模式**排除公司 VPN 虚拟网卡**

### 痛点 2：iPhone 无法按 App 分流（系统限制）
- **现象**：抖音要直连、Discord 要代理，只能手动切全局。
- **根因**：**iOS 第三方代理只能按域名/IP/端口分**（Per-App VPN 仅企业 MDM 开放）。
- **解决**：
  - Discord 等有明确域名指纹：用成熟规则集覆盖（**BlackMatrix7**）
  - `FINAL = DIRECT`（未命中默认直连）
  - 公司 VPN 临时用时单独开系统 VPN

### 痛点 3：Cursor / Claude Code 等终端/Electron 不走系统代理
- **现象**：开了代理 GUI，AI 工具仍然用本地 IP 访问。
- **根因**：
  - Node.js / Electron 默认**不读 macOS 系统代理**
  - Cursor 的部分请求走 Electron 内部，不受外部 GUI 代理影响
- **解决**：
  - **优先用 Clash TUN 模式**（系统层接管，所有程序生效）
  - 终端额外设 `HTTPS_PROXY` / `HTTP_PROXY` / `NO_PROXY`（见 `clients/shell-proxy.sh`）
  - Cursor 可以在 Settings 里手动配置 `http.proxy`

### 痛点 4：Oracle 注册失败
- **现象**：国家先选日本、后改新加坡，账号卡在"无法完成注册"。
- **根因**：**注册轨迹矛盾** → 风控打标。
- **解决**：Oracle 作为长线方案；先用 Vultr 月付 $6 机器**短期验证栈**，待 Oracle 风控冷却后再开新邮箱重试。

---

## 四、最终架构

### 4.1 服务端

```
┌──────────────────────────────────────┐
│  VPS（当前 Vultr Tokyo $6/月）        │
│  ┌────────────────────────────────┐  │
│  │ 3x-ui Web Panel                │  │
│  │  ├── VLESS + Reality (TCP 443) │  │  主力：抗封锁
│  │  └── Hysteria2      (UDP 443)  │  │  备用：弱网 UDP 加速
│  └────────────────────────────────┘  │
│         │                             │
│         ▼ 生成 Subscription URL       │
└─────────┼─────────────────────────────┘
          │
          ▼
┌──────────────────────────────────────┐
│  所有客户端（订阅制，统一规则）        │
│  ┌────────────────────────────────┐  │
│  │ Mac:     Clash Meta / Mihomo   │  │
│  │ iOS:     Shadowrocket          │  │
│  │ Android: Clash Meta            │  │
│  │ Windows: Clash Verge Rev       │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

### 4.2 客户端规则顺序（所有设备一致）

```
1. 公司域名 / 公司 CIDR       → DIRECT
2. AI 类（Anthropic/OpenAI/…） → PROXY（海外出口）
3. 国内规则集（ChinaMax）      → DIRECT
4. GEOIP, CN                  → DIRECT
5. 海外规则集（Global）        → PROXY
6. MATCH / FINAL              → DIRECT（兜底保守直连）
```

> **为什么 FINAL 用 DIRECT 而不是 PROXY？**  
> 未知域名默认直连，可以避免误伤国内新 App / 公司新域名；海外该走代理的靠规则集命中即可，社区维护成熟。

### 4.3 迁移机制

| 换什么 | 做什么 |
|--------|--------|
| 换 VPS（Vultr → Oracle） | 新机跑 `scripts/install.sh` → 3x-ui 恢复备份 → 改对外 IP |
| 换客户端 App | 重新导入订阅 URL + 规则集 URL |
| 规则更新 | 客户端点"更新订阅/规则集"，家人无感 |

---

## 五、分阶段计划

### 🟢 阶段 1：Vultr 验证栈（本周）
- [x] 买 Vultr $6/月 Tokyo 实例（已完成）
- [ ] 运行 `scripts/install.sh` 部署 3x-ui + 协议
- [ ] 导入 Mac / iPhone 订阅，跑通分流
- [ ] 验证 Claude Code / Cursor / Discord / 抖音 / 公司内网
- [ ] 给家人 Windows 配好

### 🟡 阶段 2：Oracle 白嫖（冷却后）
- [ ] 等 24–72 小时，用**新邮箱**重试注册
- [ ] Country 和 Home Region 保持稳定（推荐 Singapore + Osaka）
- [ ] 抢 ARM 4C/24G 实例
- [ ] 部署同一套 `scripts/install.sh`
- [ ] 3x-ui 恢复备份 → 客户端刷新订阅

### 🔵 阶段 3：正式切换
- [ ] Vultr 作备用或销毁
- [ ] Oracle 作主力
- [ ] 评估是否需要第二台（HostDare CN2 GIA 作容灾）

---

## 六、开放问题 / TODO

- [ ] 是否需要 Cloudflare WARP / 住宅 IP 出口（AI 厂商对数据中心 IP 风控时再考虑）
- [ ] 家人端是否需要更傻瓜化方案（快捷方式一键启停）
- [ ] 备份策略：3x-ui DB 加密后放哪里（1Password / 本地 keyring）
- [ ] 监控：是否要挂个轻量可用性监控（UptimeRobot）

---

## 七、关联文档

- [`README.md`](../README.md) - 项目总览
- [`docs/00-handover.md`](00-handover.md) - 会话交接
- [`docs/01-vps-decision.md`](01-vps-decision.md) - VPS 选型
- [`docs/02-oracle-setup.md`](02-oracle-setup.md) - Oracle 注册手册
- [`docs/03-server-setup.md`](03-server-setup.md) - 服务端部署（3x-ui）
- [`clients/README.md`](../clients/README.md) - 客户端配置总览
- [`scripts/install.sh`](../scripts/install.sh) - 一键部署脚本
