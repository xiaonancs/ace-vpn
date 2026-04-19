# 🛂 Oracle Cloud Always Free 注册手册（Plan B / SG 路线）

> 场景：中国大陆 Visa/MC 信用卡 + 家人 +86 手机号 + SG 地址 + SG 出口 IP（SSH SOCKS5 代理）
> 目标：一次过。不行就立刻切 HostDare 年付。

---

## 0. 开工前终极检查（全部 ✅ 再动手，缺一都别开始）

### 网络层
- [ ] Terminal A：`~/sg-tunnel.sh` 前台运行中，光标停住不动
- [ ] Terminal B：`curl --socks5-hostname 127.0.0.1:1080 ipinfo.io` 返回 `country: SG`
- [ ] Mihomo Party 已 **Quit**（右上角图标 → Quit，不是隐藏）
- [ ] 系统设置 → 网络 → 代理 → **已勾选** SOCKS Proxy 127.0.0.1:1080
- [ ] Safari 隐私窗口访问 `https://ipinfo.io/json` 显示 `country: SG`

### 材料层
- [ ] 新 Outlook 邮箱（从没注册过 Oracle），能在 Safari 隐私窗口登录
- [ ] 家人手机在你身边，告诉他 "10 分钟内会收一条 Oracle 验证码，念给我"
- [ ] 大陆 Visa/MC 信用卡，卡里至少 ¥20 余额（Oracle 会预授权 $1）
- [ ] 知道信用卡上印的**英文名顺序**（例：`HE XIAONAN` 或 `XIAONAN HE`）
- [ ] 手边抄好一个全新的 SG 地址（见附录 A）
- [ ] 知道家人手机号（国家码 +86 + 11 位，不带前导 0）

### 心态层
- [ ] 预留 **不被打扰的 30 分钟**
- [ ] 不在提交过程中切换网络（不要从 Wi-Fi 切到移动热点）
- [ ] 浏览器标签页只开 Oracle 一个
- [ ] 微信/QQ 静音，避免弹窗

---

## 1. Oracle 注册表单逐字段（Safari 隐私窗口）

### 1.1 访问入口

```
地址栏手动输入：https://cloud.oracle.com/free
不要从 Google 搜过来
不要点任何"登录"按钮（那是已有账号入口）
```

### 1.2 首屏：Start for Free

```
Country / Territory:  Singapore（下拉选）
First Name:          XIAONAN     （和卡上一致，大写）
Last Name:           HE          （和卡上一致，大写）
Email:               你的新 Outlook 邮箱全称

→ 点「Verify my email」
```

**等邮件**（Outlook 收件箱 / 垃圾邮件都看）→ 点邮件里的验证链接 → 返回 Oracle 页面（应该自动跳，如果没跳就手动回到这个标签）。

### 1.3 账号密码

```
Password:    16 位以上，含大小写+数字+符号
             例：Ace!Vpn-2026-Family

→ 点 Continue
```

**⚠️ 密码立刻存到密码管理器/记事本**，Oracle 不会再让你看第二次。

### 1.4 地址信息

```
Country:      Singapore  （已锁定）
Address 1:    Blk 456 Ang Mo Kio Ave 10
Address 2:    #12-345   （井号不能漏）
City:         Singapore
Postal Code:  560456    （和地址对应，见附录 A）
State / Province:  Singapore（有些版本没这项）

→ Continue
```

### 1.5 手机验证

```
Country Code:  选 China (+86)    ← 下拉，不是 Singapore
Phone Number:  家人的 11 位手机号（不带 0 和国家码）

→ 点 Send Verification Code
→ 家人手机 30 秒内收到 SMS
→ 立刻把 6 位验证码输入
→ 点 Verify
```

**如果验证码超时**（120 秒没填）：点「Resend」再来一次。超过 3 次重发会进入冷却，这种情况下**换个家人的号**重来。

### 1.6 付款信息（最关键的一步）

```
Name on Card:    XIAONAN HE        ← 必须和卡面拼写完全一致
Card Number:     你的 Visa/MC 卡号，16 位，无空格
Expiration:      MM / YY
CVV:             卡背后 3 位数字
Billing Address: 自动继承上面的 SG 地址（不要改）
```

提交后 Oracle 会：

1. 向银行发送 **$1 预授权请求**
2. 你手机收到银行 SMS（招行/中信/浦发等）→ **不要点短信里的链接**
3. 如果是 **3D-Secure 验证**（Verified by Visa / MasterCard SecureCode）：
   - 弹窗会让你输银行短信里的动态码
   - 输对 → 预授权成功
   - 输错 3 次 → 卡被锁，找银行

### 1.7 Home Region 选择

```
Home Region:  Asia Pacific (Singapore)   ← 必须选这个
```

**千万不要选 Tokyo / Osaka / Seoul**。必须和 Country = Singapore **一致**。选错 Region 会被风控标记且**以后不能改**。

### 1.8 Agreement + Submit

```
勾选：I agree to ...
勾选：I have reviewed and understood Oracle's Use of Free Credit...

→ Start my free trial
```

---

## 2. 提交后的 3 种情况

### 🟢 场景 A：立刻跳转 Dashboard → 注册成功

```
URL 变成 https://cloud.oracle.com/?region=ap-singapore-1
看到 Oracle Cloud Console
```

**立刻做的 3 件事**：

1. **记下租户 ID**（URL 里 `tenancy=xxx` 那段）
2. **截屏保存** Dashboard 首屏
3. **不要立刻去开虚拟机**，等 10-30 分钟让后台真正就绪，否则容易触发"自动化行为"检测

### 🟡 场景 B：瞬间弹红字 "We were unable to process your registration"

**直接失败，没救**。立刻走 Fallback（Part 4）。

常见原因：

- 卡 BIN 被风控（中国 Visa/MC 名单）
- 邮箱/手机号/IP 组合曾经在黑名单
- 地址格式不规范

**不要立刻重试** —— 重试瞬拒概率 > 95%，而且每次失败都加黑记录。

### 🟡 场景 C：显示 "Your account is being verified" / "Processing"

最常见。Oracle 进入**异步人工审核**，1-48 小时出结果。

**这期间绝对不要做**：
- ❌ 不要反复刷新页面
- ❌ 不要换浏览器/IP 再次登录
- ❌ 不要开工单问状态
- ❌ 不要修改账号信息

**可以做**：
- ✅ 关掉 SG 代理，重新打开 Mihomo Party
- ✅ 恢复正常上网
- ✅ 检查邮箱（Outlook 包括垃圾邮件），Oracle 邮件会在 24-48 小时内到

结果：
- 📧 收到 "Your Oracle Cloud account is now active" → 成功
- 📧 收到 "Unable to complete your registration" → 失败，走 Fallback
- 📭 48 小时都没邮件 → 大概率失败，也走 Fallback

---

## 3. 无论成功失败，立刻做的清理（10 分钟）

**重要**：Oracle 注册流程结束（不管 A/B/C 三种），**立即**做这个，别拖：

```
1. 系统设置 → 网络 → 代理 → 取消勾选 SOCKS Proxy → OK
2. Terminal A 的 ssh 隧道 Ctrl+C 关掉
3. Safari 关闭所有 Oracle 标签
4. Mihomo Party → 启动 → 恢复 TUN + 系统代理
5. 验证：curl ipinfo.io 显示 JP（你家人又能翻墙了）

# 【等】如果是场景 A/B，立刻继续：
6. Vultr 控制台 → SG 实例 → Settings → Destroy Server → 确认
   （按小时计费只收 ~¥1，别省这个钱拖着）

# 【等】如果是场景 C（审核中），SG 实例可以：
   - 选 A：立刻 Destroy（反正结果邮件跟 IP 无关）← 推荐
   - 选 B：留到收到结果邮件再 Destroy（多花 ¥5）
```

---

## 4. Fallback：Oracle 失败后立刻买 HostDare（15 分钟）

### 4.1 选型

**首选：CKVM 9 (LAX)** 或 **HKVM系列**，¥300/年预算内

```
官网：https://hostdare.com/
入口：Services → CKVM（中国优化）或 HKVM（香港 KVM）

推荐规格（按年付大致价格）：
├── CKVM 9 LAX Special              $49.99/年 ≈ ¥365
│   1C / 756MB / 20GB SSD / 600GB流量 / CN2 GIA
├── CKVM 10 LAX Premium             $79.99/年 ≈ ¥580（超预算）
└── HKVM 2 HK                        $99.99/年（超预算）

如果只要便宜 + 能用：
└── CKVM 5 (LAX Special Promo)      $34.99/年 ≈ ¥255
    1C / 512MB / 10GB SSD / 300GB流量 / CN2 GIA
    （内存小，3x-ui + xray 跑够用）
```

**操作系统选 Ubuntu 22.04**（我们 `install.sh` 测过的版本）。

### 4.2 优惠码 / 促销入口

- 官网首页顶部常年有 Special Promo 横幅
- `/services.php` 页面拉到底有 Black Friday / 特价规格
- 搜 "hostdare special" 常能在 LowEndBox 发现码

### 4.3 付款方式

- PayPal（最快，不用验证）
- 支付宝（官网 → Cart → Payment Method 选 Alipay，有时候限区）

### 4.4 买完立刻做的事

```bash
# 1. 等邮件（通常 5-30 分钟到）
#    邮件里有：IP / root 密码 / SolusVM 控制台链接

# 2. SSH 登录验证
ssh root@<HOSTDARE_IP>

# 3. 从本地 Mac clone 仓库（或从现在的 Vultr 机器 scp）
cd ~/workspace/cursor-base
scp -r ace-vpn root@<HOSTDARE_IP>:/root/

# 4. 在 HostDare 上一键部署
ssh root@<HOSTDARE_IP>
cd /root/ace-vpn
sudo AUTO_CONFIGURE=1 bash scripts/install.sh

# 5. 登面板，改端口/路径/密码，加 Reality 入站
#    把旧 Vultr 的 pbk/sid 搬过来（从 private/env.sh 读）

# 6. 装 sub-converter（多 token 模式）
sudo UPSTREAM_BASE='https://<HOSTDARE_IP>:2096/<new_sub_path>' \
     SUB_TOKENS='sub-hxn,sub-hxn01' \
     SERVER_OVERRIDE='<HOSTDARE_IP>' \
     bash scripts/install-sub-converter.sh

# 7. 你和家人的订阅 URL 只换 IP 部分
#    http://<HOSTDARE_IP>:25500/clash/sub-hxn
#    http://<HOSTDARE_IP>:25500/clash/sub-hxn01

# 8. 客户端刷新订阅（Mihomo Party 左侧订阅页 → 右上刷新）

# 9. Vultr Tokyo 保留 1-2 周观察，确认稳了再 Destroy
```

---

## 5. Oracle 成功后的下一步（场景 A 专用）

### 5.1 开 ARM Always Free 实例（永久免费 4C 24G）

```
Oracle Console → 左上汉堡菜单 → Compute → Instances → Create Instance

Name:        ace-vpn-oracle
Compartment: root
Image:       Canonical Ubuntu 22.04
Shape:       Ampere  →  VM.Standard.A1.Flex
             OCPU: 4
             Memory: 24 GB
Networking:  Create new VCN (默认就行)
SSH Keys:    Paste your public key
             （~/.ssh/id_ed25519.pub 的内容）

→ Create
```

**等 30 秒**实例启动。如果卡在 "out of capacity" → 多 **重试几次**，Tokyo/SG 容量紧张时需要抢。

### 5.2 部署 ace-vpn

```bash
# SSH 到新 Oracle 实例
ssh ubuntu@<ORACLE_PUBLIC_IP>

# 切 root
sudo -i

# 传代码
# 方法 1：git clone（推荐）
cd /root
git clone <你的私有 git URL> ace-vpn
cd ace-vpn

# 方法 2：从 Mac 推
# 本地 Mac：
# scp -r ~/workspace/cursor-base/ace-vpn ubuntu@<IP>:/tmp/
# 远程：sudo mv /tmp/ace-vpn /root/ && sudo chown -R root /root/ace-vpn

# 放行防火墙（Oracle 的 VCN Security List 也要开）
sudo AUTO_CONFIGURE=1 bash scripts/install.sh
```

### 5.3 Oracle 特有步骤：VCN Security List

Oracle 的网络安全组是独立的，需要在 Web 控制台手动放行：

```
Oracle Console → Networking → Virtual Cloud Networks
  → 点你的 VCN
  → Security Lists → Default Security List
  → Add Ingress Rules
  
放行：
  443/tcp     Reality
  2096/tcp    订阅
  25500/tcp   sub-converter
  （如果改了面板端口，那个也加）
```

**不做这步，UFW 放行了但外面还是连不通**。

### 5.4 迁移完关 Vultr

```
1. HostDare / Oracle 上 ace-vpn 跑稳 1-2 周
2. 家人客户端刷新订阅 URL（换 IP 部分）
3. 全员确认正常后，Vultr Tokyo Destroy
4. Vultr 账单停止计费
```

---

## 附录 A：备用的 SG HDB 地址（随便挑一个，别全用同一个）

**都是真实的新加坡组屋地址**，postal code 和街道对得上，Oracle 地址校验能过：

```
Option 1:
  Blk 456 Ang Mo Kio Avenue 10
  #12-345
  Singapore 560456

Option 2:
  Blk 328 Jurong East Street 32
  #08-210
  Singapore 600328

Option 3:
  Blk 217 Tampines Street 23
  #10-148
  Singapore 520217

Option 4:
  Blk 101 Yishun Avenue 5
  #05-72
  Singapore 760101

Option 5:
  Blk 782 Woodlands Crescent
  #15-503
  Singapore 730782
```

**注意**：

- 每个地址的 postal code 都是**真实**的（Singapore postal code 前 2 位是区号）
- 楼层-单元号 `#XX-XXX` 这个格式必填
- Address Line 1 的街名/Ave 编号不能省
- **不要选已经住过的或用过的地址**（Oracle 可能去重）

---

## 附录 B：注册中途常见问题

| 现象 | 处理 |
|------|------|
| 邮箱验证链接 404 | 等 2 分钟，Oracle 有时链接要慢生效；还不行就重新发 |
| 手机验证码超时 | 在界面里点 Resend，不要刷新整个页面 |
| 信用卡 3D-Secure 弹窗白屏 | Safari 隐私窗口可能阻止 3rd-party cookie → **关掉隐私模式**，但保留 SOCKS5 代理 |
| 付款报 "Payment verification failed" | 卡有中银级限额，**给银行打电话** 开"线下境外交易" + 提升限额，或换另一张卡 |
| 整个页面变白 / 不响应 | 隧道掉了。Terminal A 看 ssh 状态，重启隧道（`~/sg-tunnel.sh bg`），**等 5 分钟再刷新 Oracle 页面**（别立刻，避免 IP 跳变被风控） |
| 提交后卡在转圈超过 1 分钟 | 不要重复提交！耐心等。Oracle 后端慢，重复提交会触发双重扣款 |

---

## 附录 C：通关后的安全 TODO（一周内完成）

Oracle 成功后别松懈，新账号需要加固：

- [ ] 登陆 Oracle Cloud 后**立刻**开启 MFA（Security → MFA → Enroll Device）
- [ ] 把 Oracle 账号密码存到密码管理器
- [ ] 记录：租户 ID / 账号 email / Home Region
- [ ] 更新 `private/env.sh`：加上 Oracle 相关变量
- [ ] 在本地 Git 仓库写一个 commit，不提交真实值

---

## 附录 D：决策树（遇到问题先看这个）

```
提交后界面是啥？
├── 红字瞬拒 (场景 B)
│   └── 走 Fallback → HostDare CKVM 5 ($34.99/年)
│
├── 卡在 Processing (场景 C)
│   ├── 24h 内无邮件 → 继续等
│   ├── 48h 内收成功邮件 → 按 Part 5 开 ARM
│   └── 48h 内收拒绝邮件 → 走 Fallback
│
└── 跳 Dashboard (场景 A) ✅
    └── 等 30 分钟，按 Part 5 开 ARM 实例
```

---

## 一句话心法

> **Oracle 不给机会解释，一把过或走人。**
> **家人 Vultr 生产环境动都别动。**
> **SG 隧道 + 代理只活在你 Mac 的那 30 分钟。**

祝一把过 🎯。
