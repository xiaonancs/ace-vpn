# 📌 会话交接文档（Handover）

> **上一次会话时间**：2026-04-17 晚上（北京）  
> **下一次会话地点**：家里的 Cursor  
> **核心目标**：在 Oracle Cloud 白嫖一台 ARM 4C/24G 的免费 VPS，部署自用 VPN（`ace-vpn` 项目）

---

## 🎯 当前状态：卡在哪儿

### 进度条

```
[✅] Step 1  研究 VPS 选型（见 01-vps-decision.md）
[✅] Step 2  决定白嫖 Oracle Cloud Always Free ARM
[✅] Step 3  编写 Oracle 开通手册（见 02-oracle-setup.md）
[✅] Step 4  开始注册：Email → Password → Cloud Account Name
[🟡] Step 5  地址信息（已填日本地址）
[🔴] Step 6  信用卡验证 —— ⚠️ 卡在这里，Oracle WAF 限流报错
[ ]  Step 7  账号激活 "Account is ready"
[ ]  Step 8  抢 ARM 实例
[ ]  Step 9  部署 Xray + Reality
[ ]  Step 10 家庭共享配置
```

### 你卡住的报错（2026-04-17 傍晚）

```
地址信息 / 付款验证阶段：

"禁止
 已超出请求数。请重新加载页面或重试该操作。
 如果问题仍然存在..."
```

这是 **Oracle Cloudflare WAF 层的 Rate Limit 限流**，不是账号被封。触发原因：VPN 节点被 Oracle 识别为"共享 IP"，或者短时间请求太密集。

---

## 🔑 注册已填信息（重要，不能再改）

以下字段**一旦 Country 锁定就不可变**：

| 字段 | 已填值 | 备注 |
|------|--------|------|
| **Country / Territory** | **Japan** 🇯🇵 | 不可改 |
| **Cloud Account Name** | （你自己填的，忘了的话看邮箱 Welcome 邮件） | 不可改 |
| **Home Region** | 待确认（建议 Osaka） | 不可改 |
| **Email** | 你注册时用的 Gmail | 密码管理器里查 |
| **账单地址** | 东京的日本地址 | 可改 |

### 信用卡情况
- **卡种**：中国发行的 Visa 或 Mastercard
- **银行档案账单地址**：新加坡（你平时填新加坡的习惯）
- **Oracle 处的账单地址**：被迫填日本（因为 Country = Japan，地址下拉只能选日本）
- **过关预期**：50–65% 成功率（中国发卡行对 AVS 地址校验宽松）

---

## 🚀 回家后立刻做这些（按顺序）

### 第 1 步：确认当前账号是否还活着（3 分钟）

```
1. 开无痕浏览器
2. 访问 https://cloud.oracle.com/
3. 用你的 Gmail + 密码登录
4. 如果能登进去 → 账号还在，继续第 2 步
5. 如果看到 "Account is ready" → 直接跳到"第 4 步抢 ARM"
6. 如果提示 "not found" → 账号没创建完，看"Plan B 重开账号"
```

### 第 2 步：换干净的 VPN 节点（5 分钟）

**绝对别用原来那个节点！** 换到以下任一节点：
- 🇺🇸 美国西部（Seattle / San Francisco，非热门机场）
- 🇯🇵 日本大阪（不要东京，东京节点被用烂了）
- 🇰🇷 韩国首尔（冷门节点）
- 🇨🇦 加拿大

**验证节点干净度**：
```bash
# 1. 查看当前出口 IP
curl https://www.cloudflare.com/cdn-cgi/trace | grep ip=

# 2. 把 IP 贴到 scamalytics
# https://scamalytics.com/ip/你的IP
# Fraud Score < 50 = 能用
# Fraud Score > 75 = 换节点
```

### 第 3 步：继续注册流程（15–30 分钟）

**关键：慢速、单次操作**。Oracle 反爬很敏感。

```
1. 开新的无痕浏览器窗口
2. 清除所有 Oracle 相关 Cookie（如果非无痕）
3. 访问 https://signup.cloud.oracle.com/
4. 用原邮箱登录，系统会记住进度，直接跳到你上次那一步
5. 填地址：用 02-oracle-setup.md 里的 Tokyo 模板
6. 提交，等信用卡验证
```

**地址建议（复制粘贴用）**：
```yaml
Address Line 1: 2-21-1 Shibuya
Address Line 2: (留空)
City:           Shibuya
State:          Tokyo
Postal Code:    150-0002
Phone:          +86 你的真实手机号
```

### 第 4 步：信用卡验证

- 用你那张中国发的 Visa/Master（不是银联！）
- 账单地址 Oracle 会默认用 Step 5 的日本地址
- 提交，等结果

**可能的结果：**

| 结果 | 应对 |
|------|------|
| ✅ 成功，看到 "Account is ready" | 继续第 5 步抢 ARM |
| ❌ "Unable to verify card" | 等 5 分钟，换 VPN 节点再试 |
| ❌ 连续 3 次失败 | 换另一张卡（不同银行） |
| ❌ 再次限流 | 切手机热点 + 换浏览器 + 换节点 |
| ❌ 5 次都失败 | 看下面"Plan B 重开账号" |

---

## 🆘 Plan B：放弃当前账号，重新注册

**成本评估**：损失 20 分钟填表时间，信用卡没扣钱，不影响征信。

**操作步骤**：
```
1. 换一个全新 Gmail 邮箱
   （技巧：旧 Gmail 别名也能用，比如 yourname+oracle2@gmail.com）
2. 彻底清除浏览器 Cookie
3. 换干净 VPN 节点
4. 这次注册 Country 选 Singapore（和你信用卡账单地址一致，成功率高）
5. Home Region 选 Osaka
6. 剩下按 02-oracle-setup.md 手册走
```

---

## 🏆 Plan C：如果 Oracle 彻底搞不定

**及时止损，直接付费**。参考 `01-vps-decision.md`，推荐：

### 首选：HostDare CSSD0 年付
```
价格：$35.99/年 ≈ ¥259
优惠码：VU6E1H58UY（20% 终身折扣，可叠加）
规格：1C / 512MB / 10GB NVMe / 250GB / 30Mbps / CN2 GIA
下单：https://www.hostdare.com/cn2giakvmvps.html
付款：支付宝 / PayPal / 加密货币
到货时间：5 分钟自动开通
```

### 备用：RackNerd 2GB 年付
```
价格：$18.29/年 ≈ ¥132
规格：1C / 2G / 40G SSD / 3.5TB / 普通 163 线路
找特价：https://lowendbox.com/tag/racknerd
```

---

## ✅ Oracle 成功后的下一步（未来的你）

拿到 ARM 机器后：

1. **告诉新会话的 Cursor**：
   ```
   "Oracle 抢到了一台 ARM 4C/24G，Ubuntu 22.04 Minimal ARM64，
   Home Region 是 Osaka。IP 是 xxx.xxx.xxx.xxx。
   按 02-oracle-setup.md 我已经完成开通，
   接下来请帮我写 Xray + Reality 部署脚本。"
   ```

2. Cursor 接下来会帮你写：
   - `03-xray-reality-setup.md` —— 部署手册
   - `scripts/install-xray-reality.sh` —— 一键安装脚本
   - `scripts/oracle-firewall.sh` —— 开端口脚本
   - `scripts/setup-bbr.sh` —— BBR 加速
   - `scripts/keep-alive.sh` —— 防 Oracle 回收保活脚本
   - `scripts/gen-client-config.sh` —— 客户端配置生成

3. 家庭共享配置：
   - 给 2-5 人各生成独立的 `vless://` 链接
   - 生成二维码方便手机扫码
   - 提供 Shadowrocket / V2RayN / Clash 模板

---

## 📚 项目文件导航

```
ace-vpn/
├── README.md                    ← 项目总览
├── docs/
│   ├── 00-handover.md           ← 你正在看的这个，会话交接
│   ├── 01-vps-decision.md       ← VPS 选型调研结论
│   ├── 02-oracle-setup.md       ← Oracle 开通手册（569 行详细版）
│   └── 03-xray-reality-setup.md ← 待写（Oracle 开通后）
├── scripts/                     ← 待写（Oracle 开通后）
└── clients/                     ← 待写（Oracle 开通后）
```

---

## 💬 给未来的你（回家后的自己）的话

1. **别慌**：Oracle 限流只是临时的，等 30 分钟自动恢复
2. **别纠结 Country = Japan**：这个选择不影响使用，只是账单货币是日元
3. **信用卡一次不过很正常**：中国发卡行跨境 1/3 概率被 soft-decline，换卡或等一天再试
4. **如果失败 5 次以上**：直接上 Plan B（重开账号）或 Plan C（HostDare 付费），别在这上面耗超过 1 小时
5. **整个 VPN 项目的核心不是白嫖 Oracle**：是把自建 VPN 这件事搞定。白嫖失败就花 ¥260 买 HostDare，完全值得
6. **信息安全**：密码和 Cloud Account Name 记在密码管理器里；任何敏感配置（API Key、服务器 IP、订阅链接）都别 commit 到 git 仓库

---

## 📞 恢复会话的开场白模板（复制给 Cursor 用）

回家后打开新 Cursor 会话，把下面这段直接贴给 AI：

```
我在 ace-vpn/ 项目里有一个自建 VPN 任务，请先读 docs/00-handover.md
和 docs/02-oracle-setup.md 了解上下文。

当前状态：Oracle Cloud 注册卡在付款验证（WAF 限流），
Country=Japan 已锁定，信用卡是中国发的 Visa。

我现在已经[填：换了 VPN / 等了 30 分钟 / xxx]，接下来想[填：
重试注册 / 改用 HostDare / xxx]，请帮我继续推进。
```

---

**文档版本**：v1.0  
**下次更新时机**：Oracle 注册成功 或 切换到 Plan B/C 之后
