# VPS 选型决策记录（Architecture Decision Record）

> **日期**：2026-04-17  
> **决策人**：hxn  
> **状态**：已决策 —— 先白嫖 Oracle，失败降级 HostDare

---

## 1. 背景与需求

### 项目目标
自建 VPN，基于自有 VPS，代号 `ace-vpn`。

### 使用场景
- **用户**：2–5 人家庭共享
- **使用地点**：北京（中国大陆）
- **核心需求**：
  - 看 YouTube 4K 视频不卡（关键硬指标）
  - 日常访问 Google / GitHub / 海外学术资源
- **预算**：¥300/年 以下（有明显价值可适当加预算）
- **技术栈**：待定（倾向于不被 GFW 识别特征的协议）

### 隐含约束（容易被忽略的关键点）
- VPS 本身不会被封，但 **IP 会被 GFW 封锁**（用错协议几周就会墙）
- 协议选择 > VPS 品牌（再好的 VPS 用 WireGuard 也会被秒墙）
- 单节点不够保险，需要主 + 备

---

## 2. 市场调研（2026-04 最新）

### 2.1 按价位分档全景

#### 🌏 国际大厂（月付）
| 品牌 | 入门 | 中档 | 高档 | 中国线路 |
|------|------|------|------|--------|
| Vultr | $2.50/月（仅v6） | $6/月 1G/25G/1T | $96/月 | 普通 NTT |
| DigitalOcean | $4/月 | $6/月 1G/25G/1T | $96/月 | 普通 |
| Linode | $5/月 | $24/月 | $96/月 | 普通，东京略好 |
| AWS Lightsail | $3.5/月 | $12/月 | $40/月 | 一般 |

#### 🇪🇺 欧美低价
| 品牌 | 入门 | 中国线路 | 备注 |
|------|------|--------|------|
| Hetzner | €5.6/月 2C/4G | ❌ 极差 | 便宜但完全不通中国 |
| Contabo | €3.6/月 4C/8G | ❌ 差 | 配置炸裂但不通 |
| OVH | €3.5/月 | 一般 | 加拿大机房抗投诉 |

#### 💰 LEB 低价年付（便宜王者）
| 品牌 | 入门 | 中档 | 高档 | 备注 |
|------|------|------|------|------|
| **RackNerd** ⭐ | **$11.29/年** | $32.49/年 2C/3.5G | $59.99/年 | 公认性价比王 |
| CloudCone | $15/年 | $30/年 | $75/年 | 月付也便宜 |
| HostHatch | $15/年 | $40/年 | $90/年 | 年付限量抢 |
| BuyVM | $2/月 | $7/月 | — | 有 Block Storage |

#### 🇨🇳 华人优化（中国线路好）
| 品牌 | 入门 | 中档 | 高档 | 中国线路 |
|------|------|------|------|--------|
| **搬瓦工 BWH** | $49.99/年 PROMO | $169.99/年 CN2 GIA 20G | $299.99/年 CN2 GIA 40G | ⭐⭐⭐ CN2 GIA |
| **HostDare** ⭐ | **$35.99/年 CSSD0** | $55.99/年 CSSD1 | $112.99/半年 CKVM3 | ⭐⭐ 电信 CN2 GIA |
| DMIT | $6.9/月 HKG Lite | $9.99/月 LAX Pro | $29.9+/月 | ⭐⭐⭐ |

#### ☁️ 云厂商国际版（⚠️ 违反 ToS）
| 品牌 | 入门 | 备注 |
|------|------|------|
| 阿里云国际 轻量 | $3.5/月 HK | 自建 VPN 严重违规，封号不退款 |
| 腾讯云国际 轻量 | $3.5/月 东京 | 同上 |
| **Oracle Cloud** ⭐ | **免费 ARM 4C/24G** | 白嫖天花板，开通难 |

---

## 3. 评估矩阵

按 4 个关键维度打分（1–5，5 最优）：

| 方案 | 价格 | 中国线路 | 家庭 4K 体验 | 开通/维护难度 | 综合 |
|------|------|---------|------------|-------------|------|
| Oracle Cloud Free Osaka | 5 | 3 | 4 | 2（难开通）| **14** ⭐ |
| HostDare CSSD0 | 4 | 4 | 3 | 5 | **16** ⭐ |
| HostDare CSSD1 | 3 | 4 | 4 | 5 | **16** ⭐ |
| RackNerd 3.5G | 5 | 2 | 2（晚高峰卡） | 5 | 14 |
| 搬瓦工 PROMO 20G | 3 | 2 | 2 | 5 | 12 |
| 搬瓦工 CN2 GIA 20G | 1 | 5 | 4 | 5 | 15 |
| Vultr 东京 | 3 | 2 | 3 | 4 | 12 |
| 阿里云香港轻量 | 4 | 5 | 5 | 1（违规）| — 排除 |

---

## 4. 最终决策

### 决策：两阶段策略

```
阶段 1（零成本试水）：Oracle Cloud Always Free ARM
  → Home Region: Osaka (ap-osaka-1)
  → 规格: 4 OCPU / 24 GB RAM / 200 GB 存储
  → 成本: ¥0
  → 风险: 开通成功率约 50%

阶段 2（Oracle 失败降级）：HostDare CSSD0 CN2 GIA 年付
  → 规格: 1C / 512MB / 10G NVMe / 250G / 30Mbps / CN2 GIA
  → 成本: $35.99 × 0.8（优惠码 VU6E1H58UY）= $28.79 ≈ ¥207/年
  → 风险: 极低，5 分钟到货

备选（HostDare 不满意）：RackNerd 2GB 年付 + 主 Oracle 组合
  → 规格: 1C / 2G / 40G / 3.5TB
  → 成本: $18.29 ≈ ¥132/年
  → 用途: Oracle 被墙时的应急备用
```

### 为什么这样选

**为什么先试 Oracle**：
- 白嫖 4C/24G 的机器，市场对标价 $40–80/月，一年能省 ¥3000+
- 失败也没成本，只是浪费 1–2 小时
- 配置超高，能长期用，抗未来需求升级

**为什么 HostDare 是降级首选**：
- 对比搬瓦工 CN2 GIA 入门档 ¥1225/年，HostDare ¥259 只要 1/5 的钱
- 同样是 CN2 GIA 级别线路（虽然只是电信单线，联通/移动走 CUII）
- 5 分钟到货，不用折腾
- 20% 终身折扣码 `VU6E1H58UY` 续费不涨价

**为什么排除这些方案**：

| 排除方案 | 原因 |
|---------|------|
| Vultr 按小时 | 线路普通，晚高峰 4K 不稳，换 IP 收费 |
| 搬瓦工普通 PROMO | $49.99 已超预算且线路一般 |
| 搬瓦工 CN2 GIA 入门 | $169.99/年超预算 |
| RackNerd 单买 | 晚高峰 4K 大概率卡，家庭体验差 |
| 阿里云/腾讯云国际版 | 自建 VPN 严重违反 ToS，封号不退款 |
| Hetzner / Contabo | 欧洲机房，对中国线路极差 |

---

## 5. 协议选型（确定方向）

基于"怕被墙"的核心诉求，选定：

```
主力协议：VLESS + Reality（抗封锁 2026 最强）
  → 伪装成真实 HTTPS 流量
  → 工具: Xray-core
  → 管理面板: 3X-UI 或手动配置

备用协议：Hysteria2（UDP / QUIC，速度快）
  → 4K 体验最好
  → 国内 UDP 有 QoS，作为备线

❌ 明确不用：WireGuard / OpenVPN / 原版 Shadowsocks
  → 协议特征明显，IP 1-2 周必被墙
```

---

## 6. 下一步行动

- [x] 编写 Oracle 开通手册（`02-oracle-setup.md`）
- [ ] 完成 Oracle 注册（当前卡在付款验证限流）
- [ ] 抢 ARM 实例（Osaka）
- [ ] 编写 `03-xray-reality-setup.md` 部署手册
- [ ] 编写 scripts 一键部署脚本
- [ ] 家庭成员客户端配置分发

---

## 7. 参考来源

- [搬瓦工官网定价](https://bwh81.net/cart.php)
- [Vultr Cloud Compute 定价](https://www.vultr.com/pricing)
- [HostDare CN2 GIA 套餐](https://www.hostdare.com/cn2giakvmvps.html)
- [RackNerd LEB 特价](https://lowendbox.com/tag/racknerd)
- [DMIT 套餐汇总](https://dmitvps.github.io/plans/)
- [Oracle Cloud Always Free](https://www.oracle.com/cloud/free/)
- [CN2 GIA vs 普通线路实测对比 2026](https://dev.to/devguoo/cn2-gia-vs-regular-vps-speed-comparison-2026-real-data-bao)

---

**决策版本**：v1.0  
**可能触发修订的事件**：Oracle 彻底失败 / HostDare 线路恶化 / 需求升级（更多人共享或更高带宽）
