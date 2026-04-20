# Oracle Cloud Always Free 申请教程

> **目标**：白嫖一台 **Oracle Cloud**（业界常称「甲骨文云」）ARM 免费机（4 核 / 24 GB / 200 GB）**永久免费**运行 ace-vpn，**每年 0 元**。
>
> **难度**：⭐⭐⭐⭐（全网最难白嫖的免费云，本项目作者两次注册被风控，经验都写在这）
>
> **成功率**：首次注册 **约 50%**，二次重试 **70%+**，踩完所有坑后 **接近 100%**
>
> **时间预算**：顺利 30 分钟；踩坑 1–3 天

---

## 为什么值得折腾

| 方案 | 规格 | 年费 | 备注 |
|------|------|------|------|
| **Oracle Always Free ARM** | 4 vCPU / 24 GB RAM / 200 GB | **¥0** 永久 | 本教程目标 |
| HostHatch Tokyo（本项目现用）| 1 vCPU / 2 GB / 20 GB | ~¥345 | Oracle 搞不定的降级方案 |
| Vultr Tokyo | 1 vCPU / 1 GB / 25 GB | ~$72 ≈ ¥520 | 按小时计费备选 |
| 搬瓦工 CN2 GIA 20G | 1 vCPU / 1 GB / 20 GB | ~$170 ≈ ¥1225 | CN2 线路最稳但贵 |

> 免费 ARM 机的规格（4C/24G）比付费 $40/月 的机器还高。**开通难 = 唯一门槛**，跨过去就是永久免费。
>
> 如果你**不想折腾**，跳到 [第 8 节 · 降级方案](#8-实在搞不定就直接付费)。

---

## 目录

1. [注册前：必备物料清单](#1-注册前必备物料清单)
2. [注册流程（含 3 个关键决策）](#2-注册流程含-3-个关键决策)
3. [地域选择：为什么推荐大阪](#3-地域选择为什么推荐大阪)
4. [信用卡验证：风控应对](#4-信用卡验证风控应对)
5. [开 ARM 机器：抢资源 + 抢不到怎么办](#5-开-arm-机器抢资源--抢不到怎么办)
6. [长期保活：3 个会导致机器被回收的雷区](#6-长期保活3-个会导致机器被回收的雷区)
7. [IP 被墙后的换 IP 策略](#7-ip-被墙后的换-ip-策略)
8. [实在搞不定就直接付费](#8-实在搞不定就直接付费)
9. [申请成功后：接入 ace-vpn](#9-申请成功后接入-ace-vpn)

---

## 1. 注册前：必备物料清单

缺一项就会挂在某步，**务必全部准备好再开始**。

### ✅ 必须项

- [ ] **实体 Visa / Mastercard 信用卡**（国内银行发的就行）
  - **招商银行 / 中信银行 / 浦发银行** 的 Visa 全币卡通过率最高
  - ⚠️ **不能用**：银联卡、储蓄卡、虚拟信用卡（Dupay / WildCard / OneKey）
  - ⚠️ 信用卡必须已**开通境外消费**（中信、浦发的 App 里一键开）

- [ ] **Gmail / Outlook 邮箱**
  - ⚠️ **不能用**：QQ / 163 / 新浪等国内邮箱（送审概率激增）

- [ ] **海外 IP 代理**
  - 新节点，非共享节点，**IP Fraud Score < 50**（见下方验证法）
  - 别用免费 VPN 或 Cloudflare Warp

- [ ] **能收短信的手机号**（+86 真实号 OK）

### 🔍 验证代理节点是否"干净"

打开浏览器先挂好 VPN，然后：

```bash
# 查当前出口 IP
curl https://www.cloudflare.com/cdn-cgi/trace | grep ip=
# 然后打开下面这个链接，替换 xxx 为你的 IP
# https://scamalytics.com/ip/xxx.xxx.xxx.xxx
```

| Fraud Score | 结论 |
|-------------|------|
| 0–25 | ✅ 非常干净，放心用 |
| 25–50 | 🟡 可以用，但注意操作别太快 |
| 50–75 | ⚠️ 高风险，换个节点 |
| 75–100 | ❌ 必被 Oracle 风控，换节点 |

---

## 2. 注册流程（含 3 个关键决策）

打开 https://signup.cloud.oracle.com/（**必须挂着海外 VPN**）。

### Step 1 · Email

填 Gmail，收验证邮件，点确认。

### Step 2 · Account Information（🔑 关键决策 1）

| 字段 | 填什么 | 踩坑提示 |
|------|-------|---------|
| **Country / Territory** | **和你信用卡账单地址一致** | **一旦选定不能改！** |
| Name | 拼音全名 | 和信用卡持卡人完全一致 |

**关于 Country**：
- **不影响服务器位置**，只决定账单货币 + 税务归属
- 信用卡是**中国境内办的** → 选 **Hong Kong** 或 **Singapore**（成功率最高）
- 信用卡是**中国银行的 Visa 全币卡** → 可以选 **Singapore**（通过率最高）
- ❌ **千万别选 Japan**：日本 Country + 中国发卡行 → 被迫填日本地址，Oracle AVS 风控容易挂

> ⚠️ 本项目作者第一次注册选了 Japan，结果被迫填日本地址 + 中国发卡行 → 付款验证被 WAF 拉黑，账号卡死。

### Step 3 · Password + Cloud Account Name

- Password：强密码 ≥ 12 位，记到密码管理器
- **Cloud Account Name**：全局唯一英文名，比如 `mycloud2026`
  - ⚠️ 一旦定了不能改
  - ⚠️ 不要用敏感词（`vpn` / `proxy` / `shadowsocks`）会触发审核
  - ✅ 推荐：无害名字 `acelab2026` / `mycloud2026` / `personal2026`

### Step 4 · Home Region（🔑 关键决策 2）

**一旦选定永远不能改！**

📖 详细对比见 [第 3 节](#3-地域选择为什么推荐大阪)。**简版答案**：

```
✅ 推荐：Osaka（大阪） — ARM 最容易抢到，延迟 70-90ms
🟡 次选：Tokyo（东京） — 延迟最低但 ARM 超难抢
❌ 不选：Singapore / Seoul / Hong Kong
```

### Step 5 · Address Information

**地址下拉会按 Country 字段限制**。因此 Step 2 选什么 Country，这里地址模板要对应：

#### 如果 Country = Singapore
```yaml
Address Line 1: 1 Marina Boulevard
Address Line 2: (空)
City:           Singapore
Postal Code:    018989
Phone:          +86 你的真实手机号
```

#### 如果 Country = Hong Kong
```yaml
Address Line 1: 15 Queen's Road Central
Address Line 2: (空)
City:           Central
Postal Code:    (HK 不要求)
Phone:          +86 你的真实手机号
```

#### 如果 Country = Japan（不推荐，但已选了救补）
```yaml
Address Line 1: 2-21-1 Shibuya
Address Line 2: (空)
City:           Shibuya
State:          Tokyo
Postal Code:    150-0002
Phone:          +86 你的真实手机号
```

> ⚠️ **别填 1-1-1 这种明显假地址**。Oracle 会用 Google Maps 校验。给的模板都是真实商业区地址。

### Step 6 · Payment Verification（🔑 关键决策 3）

**这是最容易挂的一关**。详见 [第 4 节](#4-信用卡验证风控应对)。

### Step 7 · 完成

看到 "Your account is being created" → 等 2–10 分钟 → 收到 Welcome 邮件 = 成功。

⚠️ 但还可能被标记 **Under Review**：
- 能登录控制台，但开机器时报"您的租户正在审核中"
- 一般 2–48 小时自动放行
- 超过 72 小时没动 → 发工单催（模板在 [第 4 节末尾](#申请被卡在-under-review-怎么办)）

---

## 3. 地域选择：为什么推荐大阪

北京用户实测对比（2026 数据）：

| Home Region | 代号 | 北京延迟（白天 / 高峰）| 丢包 | ARM 可用性 | IP 干净度 | 综合 |
|-------------|------|--------------------|------|-----------|---------|------|
| 🇯🇵 **Osaka** | ap-osaka-1 | 60–90ms / 80–130ms | <1% / 2-5% | ⭐⭐⭐⭐ **最容易抢** | ⭐⭐⭐⭐ 较新 | **⭐⭐⭐⭐⭐** |
| 🇯🇵 Tokyo | ap-tokyo-1 | 50–80ms / 70–120ms | <1% / 2-5% | ⭐ **极难抢** | ⭐⭐⭐ | ⭐⭐⭐ |
| 🇰🇷 Seoul | ap-seoul-1 | 40–70ms / 50–100ms | <1% / 3-8% | ⭐⭐⭐ | ⭐⭐ 半被墙 | ⭐⭐⭐ |
| 🇸🇬 Singapore | ap-singapore-1 | 120–200ms / 200–300ms | 1-3% / 8-15% | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| 🇭🇰 Hong Kong | — | — | — | ❌ **Always Free 已撤销** | — | **❌ 绝对不选** |

### 结论

- **90% 用户选 Osaka**：综合最优，ARM 1–2 天能抢到，4K 流畅
- **追求极致延迟选 Tokyo**：但做好抢机 3–7 天的心理准备
- **追求最低延迟可选 Seoul**：但 IP 段被大量滥用，后续被墙要换 IP
- **不要选 Singapore**：北京到新加坡绕海底光缆，晚高峰丢包 8-15%，4K 会卡
- **千万别选 Hong Kong**：Always Free ARM 在 HK 已撤销，选了浪费账号

---

## 4. 信用卡验证：风控应对

### 验证流程

Oracle 会：
1. 做 AVS 地址校验（地址 vs 发卡行档案）
2. 预授权 $1 验证（之后退回）
3. 可能触发 3D Secure 短信二次验证

### 常见报错 & 应对

#### ❌ "Unable to verify card" / "Card declined"

**第一次失败**：
1. 先别刷新，停 3 分钟（Oracle 风控冷却窗口）
2. **换 VPN 节点**（日本 → 美国、或反之）
3. 确认节点 Fraud Score < 50
4. 重新提交

**连续 2 次失败**：
1. 换**另一家银行**的信用卡
2. 检查信用卡是否开通"境外消费"
3. 等 **24 小时** 再试（Oracle 临时风控）

**连续 3+ 次失败**：
1. 当前账号基本废了，换新 Gmail 重开
2. Gmail 别名技巧：`yourname+oracle2@gmail.com` 可以复用主邮箱
3. 这次 Country / Region 按教程重新选

#### ❌ "禁止：已超出请求数"（Cloudflare WAF 限流）

**现象**：页面转圈几秒后显示一行中文拒绝。

**应对**：
1. **别刷新**，关所有 Oracle 标签页
2. 等 **30–60 分钟**（WAF 限流窗口）
3. 换 VPN 节点 + 换浏览器（从 Chrome 换 Safari / 反之）
4. 清 `oracle.com` / `cloud.oracle.com` / `oraclecloud.com` 所有 Cookie
5. 重新进 signup 页，用**原邮箱登录**（Oracle 会记住你的进度，不用重填）

### 申请被卡在 Under Review 怎么办

超过 **72 小时** 还是 Under Review → 发工单催：

1. 登录 https://cloud.oracle.com/
2. 右下角 💬 图标 / Help → Submit Request
3. Category：`Account Issues`
4. 标题 + 正文复制这个模板：

```
Subject: Please release my account from review

Hi Oracle Support,

My tenancy [你的 Cloud Account Name] has been under review for over 72 hours.
I have verified my credit card and email successfully. Could you please
expedite the review? I'm using Always Free tier for personal learning
and small self-hosted projects.

Thanks,
[你的 Name]
```

通常 24 小时内会放行。

---

## 5. 开 ARM 机器：抢资源 + 抢不到怎么办

### 一个残酷的事实

> **Oracle 免费 ARM 资源全年紧缺**。手动点创建 90% 概率报 `Out of host capacity`。

这**不代表注册失败**，而是需要用脚本刷。

### 手动尝试（先试一次）

1. 登录 https://cloud.oracle.com/
2. 左上 ☰ → **Compute → Instances**
3. 确认右上角 Region 是 **Osaka**（或你选的）
4. **Create instance**：
   - Name：`ace-vpn`
   - Image：**Canonical Ubuntu 22.04 Minimal (ARM64)**
   - Shape：点 Change → 选 **Ampere** → **VM.Standard.A1.Flex**
     - OCPUs：**4**
     - Memory：**24 GB**
   - Networking：Assign a public IPv4 address ✅
   - SSH Keys：**上传你的公钥**（`~/.ssh/id_ed25519.pub`）
   - Boot volume：默认 47 GB 就够（VPN 用不了多少）
5. **Create**

### 90% 概率报错

```
Out of host capacity
Limit exceeded for the flexible shape configuration
```

### 用抢机脚本刷（推荐）

GitHub 上成熟的工具，挂一两天基本能抢到：

```bash
# 方案 A：Cyberbolt/oci-help（中文友好）
git clone https://github.com/Cyberbolt/oci-help.git
cd oci-help
pip install oci
# 按 README 配置 ~/.oci/config（需要 Tenancy OCID / User OCID / 公钥）
python3 main.py

# 方案 B：Docker 一行启动
docker run -d \
  -v ~/.oci:/root/.oci \
  -e OCI_CONFIG_FILE=/root/.oci/config \
  -e OCI_SHAPE=VM.Standard.A1.Flex \
  -e OCI_OCPUS=4 \
  -e OCI_MEMORY_IN_GBS=24 \
  --restart always \
  hitrov/oci-arm-host-capacity
```

### 生成 API 凭证

抢机脚本需要 Oracle API 凭证：

1. 控制台右上头像 → **User Settings**
2. 左侧 **API Keys → Add Public Key**
3. 生成：
   ```bash
   openssl genrsa -out ~/.oci/oci_api_key.pem 2048
   openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem
   ```
4. 把 `oci_api_key_public.pem` 贴到 Oracle → 保存
5. 把显示的"Configuration File Preview"粘贴到 `~/.oci/config`，并修改 `key_file=~/.oci/oci_api_key.pem`

### 小技巧：降低规格更容易抢

如果 4C/24G 抢不到，可以：
- 先抢 **2 OCPU / 12 GB**（宽松），抢到后面板里 **Resize** 升到 4C/24G
- 先抢 **1 OCPU / 6 GB**，跑 ace-vpn 绰绰有余

---

## 6. 长期保活：3 个会导致机器被回收的雷区

Oracle 免费账户有几个**隐藏规则**，踩了机器会被销毁、数据全没。

### 雷区 1：CPU 空闲 → 回收

**规则**：免费实例 **连续 7 天 CPU 平均使用率 < 20%** → Oracle 邮件警告 → 再几天直接销毁。

**应对**（开机后立即做）：

```bash
# Ubuntu / Debian
sudo apt update && sudo apt install -y stress-ng

# 加 cron：每小时跑 10 分钟低优先级 CPU 压测
(sudo crontab -l 2>/dev/null; echo "0 * * * * nice -19 stress-ng --cpu 1 --timeout 600s >/dev/null 2>&1") | sudo crontab -
```

### 雷区 2：账号 30 天不登录 → 休眠 → 清空资源

**应对**：日历每月提醒一次，登录控制台点一下 Compute → Instances。**什么都不用做，只是登录触发活跃状态**。

### 雷区 3：Oracle 邮件警告不回 → 关机

偶尔 Oracle 会发邮件询问"你还在用这台实例吗"。**必须 7 天内回复**。

回复模板：

```
Hi Oracle Support,

Yes, I'm actively using this instance [OCID] for a personal VPN
server. The CPU usage is low because my workload is network-bound,
not CPU-bound. Please keep the instance running.

Thanks.
```

---

## 7. IP 被墙后的换 IP 策略

Oracle 免费 IP 被墙是**常态**（尤其首尔机房）。ace-vpn 用 Reality 协议已经极大降低被墙概率，但真遇到了，换 IP 流程：

### 方案 A：保留实例，只换 IP（推荐）

```
1. 控制台 → Networking → Reserved IPs（右上切 Region）
2. 免费账户只能有 2 个公 IP，先释放旧的
3. Compute → Instances → 你的实例 → Attached VNICs → 主 VNIC
4. IPv4 Addresses → Edit → Reserve new Ephemeral Public IP
5. 新 IP 出来了，改 ace-vpn 客户端订阅 URL 即可
```

### 方案 B：销毁重建（激进但有效）

```bash
# 在 VPS 上先备份凭据
cd ~/ace-vpn
sudo cat /etc/x-ui/x-ui.db | base64 > /tmp/x-ui-db.b64
# scp /tmp/x-ui-db.b64 到本地

# 然后控制台：Terminate Instance（勾选 Permanently delete boot volume）
# 重新 Create Instance，新 IP 段概率高

# 按 ace-vpn README 快速重新部署（5 分钟）
# 或者用 dev-skill.md §6 迁移 playbook 恢复整库
```

---

## 8. 实在搞不定就直接付费

如果出现以下任一情况，**别硬磕**，及时止损：

- 信用卡连续 5 次被拒
- 账号 Under Review 超过 7 天不动
- 换了 3 个 Gmail 都注册失败
- 花了超过 5 小时仍无进展

### 降级方案（ace-vpn 作者亲测）

#### 🥇 首选：HostHatch Tokyo $4/月

```
网址：https://hosthatch.com/vps
规格：1 vCPU / 2 GB / 20 GB NVMe / 1 TB 流量
实付：$48 / 年 ≈ ¥345
机房：Tokyo（AMD EPYC Milan）
下单提示：关掉代理用真实中国 IP 下单（海外 IP 会被风控）
```

本项目**当前生产环境就是这台**，延迟 80–100ms，4K YouTube 流畅，已稳定运行 1 个月。

#### 🥈 预算极紧：RackNerd LA $11/年

```
网址：https://racknerd.com/specials/
规格：1C / 1G / 24G SSD / 2TB
年付：$11.29 ≈ ¥80
线路：美西普通，晚高峰一般，但 Reality 协议抗墙
```

#### 🥉 对中国优化线路有要求：HostDare CN2 GIA

```
网址：https://www.hostdare.com/cn2giakvmvps.html
规格：CSSD0 1C / 512M / 10G / 250G / 30Mbps
优惠码：VU6E1H58UY（20% 终身折扣）
实付：$28.79 ≈ ¥207 / 年
线路：CN2 GIA 电信直连
```

---

## 9. 申请成功后：接入 ace-vpn

拿到 Oracle ARM 机器 + SSH 可登录后：

```bash
# 1. SSH 进去
ssh ubuntu@<你的 Oracle IP>

# 2. 先做 Oracle 特有的防火墙开洞（重要！）
#    Oracle Ubuntu 镜像默认 iptables 封死所有端口
sudo iptables -I INPUT 5 -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT 5 -p tcp --dport 2053 -j ACCEPT  # 面板端口
sudo iptables -I INPUT 5 -p tcp --dport 2096 -j ACCEPT  # 订阅端口
sudo apt install -y iptables-persistent
sudo netfilter-persistent save

# 3. 同时去 OCI 控制台开 VCN Security List：
#    Networking → Virtual Cloud Networks → 你的 VCN → Security Lists
#    → Default Security List → Add Ingress Rules
#    加上 443 / 2053 / 2096 的 TCP 入站（Source 0.0.0.0/0）

# 4. 切 root（Oracle 默认 ubuntu 用户需要 sudo）
sudo -i

# 5. 按 ace-vpn README 跑一键部署
git clone https://github.com/xiaonancs/ace-vpn.git && cd ace-vpn
AUTO_CONFIGURE=1 bash scripts/install.sh

# 6. 剩下按 README → "新 VPS 到手" 小节继续
```

---

## 📚 延伸阅读

- 甲骨文抢机脚本：[Cyberbolt/oci-help](https://github.com/Cyberbolt/oci-help)
- Oracle Always Free 官方：https://www.oracle.com/cloud/free/
- 本项目技术文档：[dev-skill.md](dev-skill.md)
- 用户使用手册：[用户手册 user-guide.md](用户手册%20user-guide.md)

---

## 💬 作者吐槽

本项目作者 **两次注册 Oracle 均失败**：

1. 第一次：Country 选了 Japan + 中国信用卡 + VPN 节点 Fraud Score 过高 → 付款验证 WAF 拉黑
2. 第二次：换 Gmail 重新注册 + Country 选 Singapore → 仍然被"无法完成您的注册"挡住

**最后改年付 HostHatch**（¥345/年）。本教程是**把两次失败的血泪经验**总结出来给你，让你少走弯路。

如果你按本教程**注册成功了**，欢迎到项目 Issue 留言分享经验，帮其他人提高成功率。

如果你**失败了**，别灰心，年付一台机器也很值。ace-vpn 项目原本就是为了"不依赖任何单一 VPS 商家"而设计，**15 分钟可迁移到新机**。

---

**文档版本**：v1.0（2026-04-22）
