w# Oracle Cloud Always Free 开通手册 & 避坑指南（2026 年 4 月实操版）

> **目标**：免费白嫖 Oracle Cloud 的 ARM Ampere A1 实例（4 OCPU / 24GB RAM / 200GB 存储），用于 `ace-vpn` 项目
>
> **难度**：⭐⭐⭐⭐（全网最难白嫖的免费云，但回报也最高）
>
> **预估时间**：顺利 1 小时；踩坑 1-7 天
>
> **成功率**：新用户首次注册约 50%，二次重试 70%+

---

## 📋 目录

- [一、Always Free 到底送什么](#一always-free-到底送什么)
- [二、注册前准备清单](#二注册前准备清单)
- [三、注册全流程（含避坑点）](#三注册全流程含避坑点)
- [四、地域选择指南](#四地域选择指南)
- [五、ARM 实例创建 & 抢机器](#五arm-实例创建--抢机器)
- [六、网络/防火墙的隐藏坑](#六网络防火墙的隐藏坑)
- [七、3 个长期运维雷区](#七3-个长期运维雷区)
- [八、IP 被墙后的换 IP 策略](#八ip-被墙后的换-ip-策略)
- [九、失败降级方案](#九失败降级方案)
- [十、Checklist 总清单](#十checklist-总清单)

---

## 一、Always Free 到底送什么

### 核心福利（永久免费，ARM 白嫖王者）

| 资源 | 额度 | 备注 |
|------|------|------|
| **ARM Ampere A1 Compute** | 4 OCPU + 24 GB RAM | 可拆成多台，总和不超上限 |
| **块存储** | 200 GB | ARM/AMD 实例共享 |
| **x86 AMD Compute** | 2 台 1/8 OCPU + 1 GB RAM | 基本没用，聊胜于无 |
| **出站流量** | 10 TB/月 | 家用 VPN 绰绰有余 |
| **公网 IPv4** | 2 个 | 够主力 + 备用 |
| **Object Storage** | 20 GB | 可做备份用 |
| **Autonomous Database** | 2 × 1 OCPU + 20GB | 跑个小网站也行 |

### 新户额外福利

- **$300 Free Credit**：30 天内可用于付费服务（ARM A1 不消耗这个额度）
- 过期后自动降级到 Always Free Tier，不会误扣费

### 💡 对 VPN 用户的意义

一台 ARM 4C/24G/200G 的机器，在其他家对标配置是 **$40-80/月**。Oracle 免费送，省 **¥3000-6000/年**。缺点是开通难 + 运维有坑，但值得。

---

## 二、注册前准备清单

### 必须项（缺一不可）

- [ ] **Visa/Mastercard 信用卡**（国际卡，非银联）
- [ ] **Gmail/Outlook 邮箱**（别用 QQ/163/国内邮箱）
- [ ] **海外 IP 的网络**（朋友的 VPN 临时借一下）
- [ ] **真实手机号**（能收短信，用 +86 即可）
- [ ] **英文地址信息**（按信用卡账单地址填）

### 强烈推荐项

- [ ] **已登录海外 IP 的浏览器环境**（无痕窗口 + 海外 VPN）
- [ ] **备用信用卡一张**（第一张被拒时立刻换）
- [ ] **下载 Oracle Cloud 官方 App**（国内应用商店搜不到，走 apk 或 TestFlight）

### ⚠️ 踩雷清单（用了必挂）

| ❌ 不要用 | 为什么 |
|---------|--------|
| 虚拟信用卡（Dupay, WildCard, OneKey, Nobepay） | Oracle 二次审核会识别并拒绝 |
| 银联卡 / 储蓄卡 / 借记卡 | 100% 验证失败 |
| 国内 IP 注册 | 高概率进"Under Review"永久卡死 |
| QQ/163/新浪邮箱 | 送审核概率暴涨 |
| 中文拼写的地址 | 系统可能拒绝 |
| 跟别人共用信用卡 | Oracle 会识别"一卡一户"，二次注册必挂 |

---

## 三、注册全流程（含避坑点）

### Step 1：打开注册页

```
https://signup.cloud.oracle.com/
```

⚠️ **必须用海外 VPN**，推荐日本/韩国/美国节点。国内 IP 点开 = 高概率进评估队列。

### Step 2：Account Information

| 字段 | 填写建议 | 避坑要点 |
|------|---------|--------|
| Country / Territory | **和信用卡账单地址国家保持一致**（一旦选定不能改） | 信用卡是新加坡地址 → 选 Singapore；香港卡 → 选 Hong Kong |
| Name | 拼音全名 | 与信用卡持卡人姓名完全一致 |
| Email address | Gmail / Outlook | 会发验证邮件 |

> 💡 **关于 Country**：这个字段决定税务归属和账单货币，**不影响服务器物理位置**。选对 Country 的核心原则是"和信用卡账单地址一致"，能大幅降低支付风控失败率。
>
> **服务器放哪儿是 Step 4（Home Region）决定的**，两个字段相互独立，详见第四章。

点击 "Verify my email" → 去邮箱点确认链接。

### Step 3：Password & Cloud Account Name

- Password：强密码，至少 12 位，带大小写+数字+符号
- Cloud Account Name：**随便取一个英文名**（如 `acevpn2026`），这是你 Oracle 租户的全局唯一名，一旦定了不能改

### Step 4：Home Region（🔥 最关键一步）

**一旦选定永远不能改！！！** 详见第四章"地域选择指南"。

北京用户的简版答案：
- **90% 用户选 Osaka（大阪）** —— 综合最优，1-2 天能抢到 ARM
- 有耐心追求极致延迟 → Tokyo（东京），但可能抢机 3-7 天
- **不要选 Singapore**（绕路、晚高峰丢包高）
- **绝对不要选 Hong Kong**（ARM 免费额度已撤销）

### Step 5：Address Information

全部用英文填，按信用卡账单地址写。中国地址示例：

```
Address Line 1: No. 100 Zhongshan Rd, Haidian District
Address Line 2: Room 1101
City: Beijing
State / Province: Beijing
Postal Code: 100080
Phone: +86 138 0000 0000
```

### Step 6：Payment Verification（🔥 最难一步）

- 填信用卡：卡号、CVV、到期日、持卡人姓名
- **点 "Add Card" 时**：
  - 成功 → 扣 $1 验证，3-5 天退回
  - 失败 → 换卡 或 换浏览器/VPN 重来

**如果连续 3 次失败**：
1. 关闭浏览器所有 Oracle 相关 Cookie
2. 换 VPN 节点（比如从日本换到美国）
3. 换一张不同银行的信用卡
4. 等 24 小时再试（Oracle 会临时风控）

### Step 7：注册完成

看到 "Account is ready" 页面 = 第一关过了。

⚠️ **但这不代表你能立刻用！** 很多账号会被后台审核标记为 **Under Review（评估中）**，状态是：
- 能登录控制台
- 但 Compute → Create Instance 时报错 "Your tenancy is currently being reviewed"

**应对方案**：
1. 等 2-48 小时，通常会自动通过
2. 如果 72 小时还没通过 → 发工单：`Oracle Cloud Support → Submit Request → Account Issues`
3. 工单模板（复制粘贴）：
   ```
   Subject: Please release my account from review
   
   Hi Oracle Support,
   
   My tenancy [your-account-name] has been under review for over 72 hours.
   I have verified my credit card and email. Could you please expedite the
   review process? I'm trying to use the Always Free tier for personal
   learning purposes.
   
   Thanks,
   [your name]
   ```

---

## 四、地域选择指南

### 🔑 先搞清楚：Country 和 Home Region 是两个独立字段

Oracle 注册时的两个"地域相关"字段经常被搞混，先澄清：

| 字段 | 含义 | 是否可改 | 填法原则 |
|------|------|---------|---------|
| **Country / Territory** | 账单国家、税务归属、语言偏好 | 注册后不可改 | **跟信用卡账单地址保持一致**（减少支付风控失败率）|
| **Home Region** | 你所有服务器实际运行的物理地域 | 注册后不可改 | **选离你真实使用地最近的机房**（决定延迟）|

**这两个字段相互独立**，Oracle 允许你：
- `Country = Singapore` + `Home Region = Tokyo` ✅
- `Country = Hong Kong` + `Home Region = Osaka` ✅
- `Country = Japan` + `Home Region = Seoul` ✅

> 💡 **关键结论**：如果你的信用卡账单地址在新加坡（华人常见操作），不要因此就把 Home Region 也选新加坡。Country 填 Singapore 保证支付顺畅，Home Region 该选哪就选哪。

### 🎯 对中国大陆用户的推荐排序（2026 年北京实测）

| 地域 | 代号 | 北京延迟（白天/高峰）| 丢包（白天/高峰）| ARM 可用性 | IP 干净度 | 综合推荐 |
|------|------|---------------------|-----------------|-----------|----------|--------|
| 🇰🇷 Seoul | ap-seoul-1 | 40-70ms / 50-100ms | <1% / 3-8% | ⭐⭐⭐ | ⭐⭐ 半被墙 | ⭐⭐⭐⭐ |
| 🇯🇵 **Osaka** | ap-osaka-1 | 60-90ms / 80-130ms | <1% / 2-5% | ⭐⭐⭐⭐ **最容易抢** | ⭐⭐⭐⭐ 较新 | **⭐⭐⭐⭐⭐** |
| 🇯🇵 Tokyo | ap-tokyo-1 | 50-80ms / 70-120ms | <1% / 2-5% | ⭐ **超难抢** | ⭐⭐⭐ | ⭐⭐⭐ |
| 🇸🇬 Singapore | ap-singapore-1 | 120-200ms / 200-300ms | 1-3% / **8-15%** | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| 🇺🇸 San Jose | us-sanjose-1 | 150-200ms / 200-350ms | 2-5% | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| 🇺🇸 Phoenix | us-phoenix-1 | 200-250ms | 3-5% | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐ |
| 🇭🇰 Hong Kong | ap-hongkong-1 | 40-60ms 最低 | — | ❌ **Always Free 已撤销** | — | ❌ **千万别选** |

### 🏆 个人强烈建议

**首选 Osaka（大阪）** ⭐⭐⭐⭐⭐ —— 综合最优解：
- ARM 资源最容易抢到（1-2 天出机）
- IP 段较新，被墙概率比 Seoul 低
- 延迟只比 Tokyo 慢 10-20ms，**人类几乎无感差别**
- 4K YouTube 流畅无压力

**次选 Tokyo（东京）** ⭐⭐⭐ —— 追求极致延迟时：
- 延迟最低（50-80ms）
- 但 **ARM 资源极度紧张**，挂抢机脚本 3-7 天常见，心态考验
- 适合有耐心 + 有抢机脚本经验的用户

**备选 Seoul（首尔）** ⭐⭐⭐⭐ —— 北京最近的机房：
- 延迟最低（40-70ms），物理距离最近
- 但 IP 段被大量滥用，半数 IP 已被墙
- 适合愿意频繁换 IP 的折腾党

**⚠️ 不推荐 Singapore**：
- 北京 → 新加坡绕海底光缆，物理距离 4500+ km
- 家用宽带出海走 163 骨干，晚高峰丢包 8-15%
- 4K YouTube 晚高峰会明显卡顿
- **即使你信用卡账单地址在新加坡，也应该 Country 填 Singapore、Home Region 另选日本或韩国**

**❌ 千万别选 Hong Kong**：Always Free ARM 在 HK 已被 Oracle 撤销，选了就白白浪费一个账号。

### 📝 北京用户 × 新加坡信用卡地址 推荐配置

```yaml
# 综合最优（90% 用户推荐此方案）
Country / Territory: Singapore        # 和信用卡账单地址一致
Home Region:         Osaka (ap-osaka-1)
预期体验:             70-90ms 延迟，1-2 天抢到 ARM，4K 流畅

# 追求极致延迟
Country / Territory: Singapore
Home Region:         Tokyo (ap-tokyo-1)
预期体验:             50-80ms 延迟，但可能抢机 3-7 天

# 备用选项
Country / Territory: Singapore
Home Region:         Seoul (ap-seoul-1)
预期体验:             40-70ms 延迟，但 IP 被墙风险高
```

---

## 五、ARM 实例创建 & 抢机器

### 前置：熟悉 OCI 控制台

登录 https://cloud.oracle.com/ 后：
- 左上角☰ → Compute → Instances
- 右上角切换 Region（显示为 "Seoul" 或 "Osaka"）

### Step 1：手动尝试

1. Compute → Instances → **Create instance**
2. Name：`ace-vpn-main`（随便起）
3. Compartment：默认 root
4. Placement：选一个 Availability Domain（比如 AD-1）
5. Image：**Canonical Ubuntu 22.04 Minimal**（ARM64 版本）
6. Shape：
   - 点 "Change shape"
   - 选 **Ampere** 分类
   - 选 **VM.Standard.A1.Flex**
   - OCPUs：**4**，Memory：**24** GB
7. Networking：用默认 VCN，勾选 "Assign a public IPv4 address"
8. SSH Keys：上传你的 `~/.ssh/id_rsa.pub` 或让系统生成
9. Boot Volume：默认 46.6 GB 就够（最大可以 200 GB，但用完就开不了别的机器）
10. 点 **Create**

### 90% 概率遇到这个错误

```
Error: Out of host capacity
```

这是 Oracle ARM 资源永恒紧缺的表现。不要沮丧，继续看下面。

### Step 2：脚本抢机（成功率 > 95%）

GitHub 上有成熟的开源工具，推荐：

```bash
# 方案 A：oci-help（Python，全功能）
pip install oci
git clone https://github.com/Cyberbolt/oci-help.git
# 按 README 配置 ~/.oci/config 后运行

# 方案 B：oracle-freetier-instance-creator（Docker，简单）
docker run -d \
  -v ~/.oci:/root/.oci \
  -e OCI_CONFIG_FILE=/root/.oci/config \
  -e OCI_SHAPE=VM.Standard.A1.Flex \
  -e OCI_OCPUS=4 \
  -e OCI_MEMORY_IN_GBS=24 \
  hitrov/oci-arm-host-capacity

# 方案 C：甲骨文永久免费白嫖脚本（中文友好）
https://github.com/Spiritreader/cyberbolt-oci
```

**挂 1-3 天内基本能抢到**。抢到后立刻给 Oracle 发邮件确认机器 OK，防止被意外回收。

### Step 3：配置 API 凭证（给抢机脚本用）

```bash
# 本地安装 OCI CLI
brew install oci-cli

# 配置
oci setup config
# 按提示填 Tenancy OCID / User OCID / Region / 生成密钥对

# Tenancy OCID 在哪找：
# OCI 控制台 → 右上角头像 → Tenancy → 复制 OCID

# User OCID：
# OCI 控制台 → 右上角头像 → User Settings → 复制 OCID

# 生成的 API 公钥需要粘贴到：
# User Settings → API Keys → Add Public Key
```

---

## 六、网络/防火墙的隐藏坑

### 坑 1：Oracle iptables 默认全封

Ubuntu/Debian 镜像在 Oracle 里会有一条"拒绝所有"的 iptables 规则。SSH 能连只是因为 22 端口有白名单。

**必须手动开端口**：

```bash
# 查看当前规则
sudo iptables -L INPUT -n --line-numbers

# 开放你的 VPN 端口（例如 443）
sudo iptables -I INPUT 5 -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT 5 -p udp --dport 443 -j ACCEPT

# 保存规则（重启后仍生效）
sudo apt install -y iptables-persistent
sudo netfilter-persistent save
```

### 坑 2：VCN Security List 也要开

光开 iptables 不够！Oracle 的 VCN（Virtual Cloud Network）还有一层云防火墙：

1. OCI 控制台 → Networking → Virtual Cloud Networks
2. 点你的 VCN → Security Lists → Default Security List
3. **Add Ingress Rules**：
   ```
   Source CIDR: 0.0.0.0/0
   IP Protocol: TCP
   Destination Port Range: 443
   Description: VPN Reality
   ```
4. 如果用 UDP 协议（Hysteria2），再加一条 UDP 规则

### 坑 3：BBR 必须手动开

```bash
cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sudo sysctl -p

# 验证
sysctl net.ipv4.tcp_congestion_control
# 应输出: net.ipv4.tcp_congestion_control = bbr
```

不开 BBR，ARM 机器对中国方向速度能差 30-50%。

---

## 七、3 个长期运维雷区

### 雷区 1：CPU 空闲回收（最严重）

**规则**：免费 ARM 实例若**连续 7 天 CPU 平均利用率 < 20%**，Oracle 会发警告邮件，并在之后某天**强制回收**实例，数据全毁。

**验证方法**：`cloud.oracle.com → Governance → Service Limits` 看是否有 "Reclaimable" 标识。

**应对方案**：

```bash
# 方案 A：cron 定期跑一个低优先级 CPU 任务（推荐）
sudo apt install -y stress-ng
sudo crontab -e
# 加一行：每小时跑 10 分钟 CPU 压力测试，保持 CPU 不完全空闲
0 * * * * nice -19 stress-ng --cpu 1 --timeout 600s >/dev/null 2>&1

# 方案 B：升级到付费账户（Pay As You Go）
# 此规则只针对 Always Free 实例，升级后不会被回收
# 但信用卡有 $0 支出，只是升级状态
```

### 雷区 2：账号休眠

**规则**：超过 30 天没登录 Oracle Cloud 控制台 → 账号进入休眠 → 资源可能被清空。

**应对**：每月登录一次（即使什么都不做，登录就行）。可以设日历提醒。

### 雷区 3：邮件警告必须回复

偶尔 Oracle 会发邮件问你是否在使用实例（尤其在 CPU 很低时）。**必须在 7 天内回复邮件**说明在用，否则机器可能被关。

邮件模板回复：
```
Hi Oracle Support,

Yes, I'm actively using the instance [OCID] for personal
projects. The CPU usage appears low because my workload is
network-bound (not CPU-bound). I will maintain the instance.

Thanks,
[your name]
```

---

## 八、IP 被墙后的换 IP 策略

Oracle 免费 IP 被墙是常态，**首尔机房平均 3-6 个月会墙一次**（根据 2025-2026 年数据）。换 IP 流程：

### 方案 A：保留实例，只换 IP（推荐）

```
1. OCI 控制台 → Networking → Reserved IPs
2. 先申请一个新的 Ephemeral Public IP（注意不能是 Reserved，Free Tier 只能用 2 个）
3. Compute → Instances → 你的实例 → 点击实例名
4. Attached VNICs → 点主 VNIC
5. IPv4 Addresses → 点 "..." → Edit
6. Public IP Type: Ephemeral → 选新 IP

❌ 踩坑警告：Oracle 免费账户只能有 2 个 Ephemeral IP，超了要付费
✅ 小技巧：先释放旧 IP 再申请新的
```

### 方案 B：销毁实例重建（激进但有效）

```
1. 先导出配置 / 备份 /etc/xray/ 等关键目录
   tar czf /tmp/xray-backup.tar.gz /etc/xray /usr/local/etc/xray
   scp user@ip:/tmp/xray-backup.tar.gz ./
   
2. OCI → Compute → Instances → Terminate Instance（勾选 Permanently delete boot volume）

3. 重新创建实例（参考第五章）

4. 新 IP 很可能和旧 IP 不在一个段，继续能用
```

### 方案 C：多 IP 轮询

免费账户可以开多个小 ARM 实例：
- 实例 1：2 OCPU / 8 GB
- 实例 2：2 OCPU / 16 GB
- 两个 IP 做主备，一个被墙立刻切另一个

---

## 九、失败降级方案

### 评估标准

如果遇到以下情况之一，**放弃 Oracle，立刻上付费**：

- [ ] 信用卡连续 5 次被拒
- [ ] 账号 Under Review 超过 7 天不动
- [ ] ARM 实例抢了 7 天仍 Out of capacity（极罕见）
- [ ] 注册了但发现选错了 Region 且是 Hong Kong

### Plan B：HostDare CSSD0（¥259/年）

```
官网：https://www.hostdare.com/cn2giakvmvps.html
选择：CSSD0 套餐，Annual 年付
优惠码：VU6E1H58UY（20% 终身折扣，可叠加）

规格：1C / 512MB / 10GB NVMe / 250GB 流量 / 30Mbps / CN2 GIA
实付：约 $35.99 × 0.8 = $28.79 首年，续费同价
支付：支付宝 / PayPal / 加密货币

部署：5 分钟到货，自带 CN2 GIA，稳定可预期
```

### Plan C：RackNerd 2GB（¥132/年）—— 纯备用

```
LowEndBox 上找最新促销：
https://lowendbox.com/tag/racknerd-kvm-vps

常见特价：
- 1C/1G/24G/2T · $11.29/年
- 1C/2G/40G/3.5T · $18.29/年（推荐）
- 2C/3.5G/65G/7T · $32.49/年

机房建议：Los Angeles 或 San Jose
支付：PayPal / Credit Card / 加密货币
```

---

## 十、Checklist 总清单

打印或抄一份放在旁边，一步一步对着做。

### 注册前

- [ ] 准备 Visa/Mastercard 信用卡
- [ ] 准备 Gmail/Outlook 邮箱
- [ ] 开通海外 VPN（朋友的账号也行）
- [ ] 选好地域（推荐 Osaka）
- [ ] 想好 Cloud Account Name（不能改）

### 注册中

- [ ] 使用海外 VPN 打开注册页
- [ ] 选择正确的 Home Region
- [ ] 信用卡一次过（失败立刻换卡）
- [ ] 邮箱收到 Welcome 邮件

### 注册后 24-72 小时

- [ ] 登录控制台检查是否 Under Review
- [ ] 如果 72 小时仍 Review → 发工单
- [ ] 配置 API 凭证

### 开 ARM 机器

- [ ] 先手动尝试创建
- [ ] Out of capacity → 挂脚本
- [ ] 抢到后立即配置 SSH
- [ ] 开启 VCN Security List 端口
- [ ] 开启 iptables 端口
- [ ] 启用 BBR

### 长期运维

- [ ] 每月登录一次控制台
- [ ] 设置 cron 保持 CPU 非空闲
- [ ] 收到 Oracle 邮件 7 天内回复
- [ ] IP 被墙时按"第八章"换 IP

---

## 📚 参考资源

- [Oracle Cloud Always Free 官方文档](https://www.oracle.com/cloud/free/)
- [OCI Python SDK](https://docs.oracle.com/en-us/iaas/tools/python/latest/)
- [甲骨文抢机脚本（中文）](https://github.com/Cyberbolt/oci-help)
- [LowEndTalk Oracle 子版讨论](https://www.lowendtalk.com/categories/offers-requests)

---

**最后更新**：2026-04-17  
**下一步**：Oracle 开通后，进入 `03-xray-reality-setup.md` 部署 VPN 协议
