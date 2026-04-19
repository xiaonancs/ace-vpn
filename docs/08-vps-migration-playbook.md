# 🚚 VPS 迁移实操手册（通用 Playbook）

> 把家用 VPN 从**旧 VPS**（任何家）迁移到**新 VPS**（任何家）的通用流程。
> 策略：**数据库整库迁移**，家人端只需点一下刷新订阅，URL 仅 IP 部分变化。
> 旧机保留 1-2 个月作为冷备份，确认新机稳定后再 Destroy。

## ✅ 已执行案例

| 日期 | 从 | 到 | 状态 |
|------|-----|------|------|
| 2026-04-20 | **Vultr Tokyo $6/月** | **HostHatch Tokyo $4/月 NVMe 2GB** | ✅ 完成，pbk/sid/UUID 全部保留，家人无感 |

本手册已泛化为通用 playbook。`<OLD_VPS_IP>` / `<NEW_VPS_IP>` / `<你的 SubId>` / `<OLD_SUB_PATH>` 等占位符替换成你的真实值即可执行。

---

## 📊 迁移架构图

```
[现状]                          [迁移中]                        [迁移后]
                                                             
Family clients                  Family clients                Family clients
      │                               │                             │
      ▼                               ▼                             ▼
 ┌─────────────┐               ┌─────────────┐            ┌─────────────┐
 │   旧 VPS   │               │   旧 VPS   │            │  新 VPS    │
 │ (生产)     │     →          │ (冷备)      │     →      │ (生产)      │
 │ 旧 IP      │               │             │            │ 新 IP       │
 └─────────────┘               │ ┌─────────┐ │            │             │
                               │ │ 新 VPS  │ │            │ 旧 VPS 已关 │
                               │ │(测试)   │ │            │ 或保留冷备   │
                               │ └─────────┘ │            └─────────────┘
                               └─────────────┘
  Day 0                         Day 1-14                     Day 15+
```

---

## Phase 1: 买新 VPS（5-30 分钟）

### 1.1 选品硬指标

不管是哪家 VPS，至少要满足：

- [ ] RAM ≥ 1 GB（2 GB 更舒适）
- [ ] SSD ≥ 10 GB（NVMe 更好）
- [ ] 流量 ≥ 1 TB/月（单人 + 小家庭够用）
- [ ] 独立 IPv4（不能 IPv6-only）
- [ ] Tokyo / 新加坡 / 美西（**绝对不要香港**：AI 厂商封 HK IP）
- [ ] 有退款机制（RackNerd 30 天，BWG 30 天，HostHatch 3-7 天）
- [ ] 年付（省钱）或者月付可随时停（灵活）

### 1.2 常见靠谱家速查（截至 2026-04）

| 家 | Tokyo | 起价 | 退款 | 场景 |
|----|-------|------|------|------|
| **HostHatch** | ✅ | $4/月 ($48/年) | 3-7 天 | **均衡首选**，NVMe 2GB 合理 |
| BandwagonHost（搬瓦工）| ❌（只有大阪 $89/年起）| $49.99/年（LA CN2 GIA）| 30 天 | CN2 专线，4K 晚高峰最稳 |
| RackNerd | ❌ | $18.66/年（LA/SJC）| 30 天 | 美西最便宜，退款友好 |
| Vultr | ✅ | $6/月 ($72/年)| 无 | 月付灵活，价格偏高 |

### 1.3 下单时的通用坑

- **风控 flag**：**下单时把所有代理关掉**，用真实中国 IP 直连网站填表。IP 国家 vs 账单国家不一致会被反欺诈系统拦截。

  > 本次 HostHatch 迁移就被这个坑了一次。关代理重新下单即过。

- **账单地址**：填**真实中国地址**，Country 选 China。不要伪装新加坡/美国——这些商家卖给中国人是常态，不需要"伪装海外用户"。

- **SSH Key 字段**：订单页就有位置，直接贴 `cat ~/.ssh/id_ed25519.pub`，省掉拿临时密码再 `ssh-copy-id` 的过程。

- **Billing Cycle**：能年付就年付（便宜）；只能月付就月付（随时可停）。

- **IPv6 免费就勾上**，不要额外加钱的 `Additional IPv4`。

### 1.4 付款

```
Payment Method: PayPal（推荐）/ Alipay / 信用卡
Operating System: Ubuntu 22.04 LTS (64-bit)
Hostname: vpn-tyo 或任意中性名（不要 "xray" / "vpn-proxy" 之类关键词）
```

### 1.5 等开通

5-30 分钟内收开通邮件，关键信息：

- **Main IP**: e.g., `192.x.x.x`
- **Root password**: 临时的，待会要改
- **控制面板（SolusVM / KiwiVM 等）**：以后重启/重装 OS / 看流量用

**⚠️ 密码 + 面板链接立刻存密码管理器**。

---

## Phase 2: 服务器初始化（10 分钟）

### 2.1 首次 SSH + 改密码

```bash
# 本地 Mac
ssh root@<NEW_VPS_IP>
# 输邮件里的临时密码

# 立刻改强密码
passwd
# 输新密码 + 确认

# 如果下单时没贴 SSH key，现在推：
# 本地 Mac 开新终端：
ssh-copy-id root@<NEW_VPS_IP>

# 回 VPS 测试免密
ssh root@<NEW_VPS_IP> "echo ok"  # 应该直接输出 ok
```

### 2.2 禁用密码登录（强化 SSH）

```bash
# 在 VPS 上
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl restart sshd

# 本地 Mac 新开终端测一下还能登：
ssh root@<NEW_VPS_IP> "uptime"
# 如果能登 → 安全
# 如果登不上 → 回 VPS console (SolusVM 网页里有) 恢复 sshd_config
```

### 2.3 更新包

```bash
apt update && apt upgrade -y
# 中间如果问重启服务 → Tab 选 OK → 回车
```

### 2.4 检查基础环境

```bash
# RAM/CPU/磁盘都正常吗？
free -h
df -h
nproc

# 时区（装 x-ui 前最好 UTC）
timedatectl
timedatectl set-timezone UTC  # 如果不是 UTC
```

---

## Phase 3: 部署 ace-vpn 基础设施（15 分钟）

### 3.1 代码上传

**方案 A：从本地 Mac scp（推荐，不暴露 git 仓库 URL）**

```bash
# 本地 Mac
cd ~/workspace/cursor-base
scp -r ace-vpn root@<NEW_VPS_IP>:/root/

# 验证传上去了
ssh root@<NEW_VPS_IP> "ls /root/ace-vpn/scripts/"
```

**方案 B：git clone（前提：新机能连到你的私有仓库）**

```bash
# 在新机上
cd /root
git clone <你的 git URL> ace-vpn
```

### 3.2 跑 install.sh（基础安装，不用 AUTO_CONFIGURE）

```bash
# 在新机上
cd /root/ace-vpn
sudo bash scripts/install.sh

# 会做这些事：
#  - 装 xray / 3x-ui / 依赖
#  - 配 UFW 防火墙（开放 22/443/2053/2096）
```

**注意**：**不要在新机上手动改 panel port / admin / path**。这些值待会**会被旧机数据库覆盖**（数据库里存着旧机的所有面板配置），现在改白改。

如果 3x-ui 安装脚本询问，接受默认值即可：

```
Q: Continue? → y
Q: Panel port → 默认 2053
Q: Admin username/password → admin/admin（反正会被覆盖）
Q: SSL → IP-based 临时证书
```

继续 Phase 4（数据库迁移），**不要登面板创建任何 inbound**。

---

## Phase 4: 迁移 3x-ui 数据库（⭐ 关键，15 分钟）

### 4.1 在旧机上备份数据库

```bash
# SSH 到旧机
ssh root@<OLD_VPS_IP>

# 停 x-ui 服务，保证备份时刻数据一致
systemctl stop x-ui

# 备份数据库
cp /etc/x-ui/x-ui.db /root/x-ui-backup-$(date +%F).db

# 重新启动 x-ui（家人继续正常用）
systemctl start x-ui

# 验证家人还能用（这步非常重要）
curl -sk https://127.0.0.1:2096/<OLD_SUB_PATH>/<你的 SubId> | head -c 100
# 应该返回 base64 字符串
```

### 4.2 从本地 Mac 中转

```bash
# 本地 Mac（旧机和新机之间默认不互通，走本地中转）
cd /tmp
scp root@<OLD_VPS_IP>:/root/x-ui-backup-*.db ./
scp x-ui-backup-*.db root@<NEW_VPS_IP>:/root/
```

### 4.3 恢复到新机

```bash
ssh root@<NEW_VPS_IP>

# 停 x-ui
systemctl stop x-ui

# 备份新机的空库（万一要回滚）
cp /etc/x-ui/x-ui.db /etc/x-ui/x-ui.db.fresh

# 覆盖数据库
cp /root/x-ui-backup-*.db /etc/x-ui/x-ui.db
chown root:root /etc/x-ui/x-ui.db
chmod 644 /etc/x-ui/x-ui.db

# 启动
systemctl start x-ui
systemctl status x-ui  # 必须 Active

# ⚠️ 数据库覆盖后，面板端口/账号/路径全部变成了旧机的。
#   UFW 要放行旧机的面板端口：
OLD_PANEL_PORT=<旧机的 panel port>
ufw allow $OLD_PANEL_PORT/tcp comment 'x-ui panel'
```

### 4.4 验证迁移

```bash
# 确认面板端口已迁（从旧机的端口继承）
ss -tlnp | grep x-ui
# 期望看到两行:
#   tcp  *:<OLD_PANEL_PORT>   x-ui   ← 面板
#   tcp  *:2096              x-ui   ← 订阅

# 浏览器打开新机面板，用旧机的账号密码登：
#   http://<NEW_VPS_IP>:<OLD_PANEL_PORT><OLD_PANEL_PATH>/
# Inbounds 标签应该看到所有旧机的入站和 client

# 命令行验证订阅能拉到节点
curl -sk "https://127.0.0.1:2096/<OLD_SUB_PATH>/<你的 SubId>" | base64 -d | head -c 200
# 期望：vless://... 开头
```

### 4.5 ⚠️ 同步 Reality 密钥（关键检查）

3x-ui 数据库里存着 **inbound 配置，包含 pbk/sid**，迁移过来会自动带上。但要核对：

```bash
# 在新机上
curl -sk "https://127.0.0.1:2096/<OLD_SUB_PATH>/<你的 SubId>" | base64 -d | head -1 | tr '&' '\n'
# 输出 vless:// 链接，里面 pbk=xxx 和 sid=xxx
# 必须和旧机完全一致

# 对照组（在旧机上跑同一条命令，对比输出）
ssh root@<OLD_VPS_IP> "curl -sk https://127.0.0.1:2096/<OLD_SUB_PATH>/<你的 SubId> | base64 -d | head -1"
```

**一致** → 成功，继续。
**不一致**（概率低）→ xray-core 启动时重新生成了 key。手动在面板 Edit Inbound，把旧机的 pbk/sid/spx 贴进去 Save。

---

## Phase 5: 装 sub-converter（10 分钟）

### 5.1 确认订阅路径

```bash
# 数据库迁过来后，订阅路径和旧机完全相同
curl -sk "https://127.0.0.1:2096/<OLD_SUB_PATH>/<你的 SubId>" | head -c 50
# 能看到 base64 字符串 = OK

# 如果 404 → 订阅开关被关
# 面板 → Panel Settings → Subscription settings → 确认 Enable
```

### 5.2 安装 sub-converter（多 token 模式）

```bash
cd /root/ace-vpn/scripts

sudo UPSTREAM_BASE='https://127.0.0.1:2096/<OLD_SUB_PATH>' \
     SUB_TOKENS='<SubId1>,<SubId2>' \
     SERVER_OVERRIDE='<NEW_VPS_IP>' \
     LISTEN_PORT=25500 \
     bash install-sub-converter.sh
```

**关键**：`SERVER_OVERRIDE` 必须是**新机**的 IP，否则家人订阅拿到的 YAML 里 server 字段还是旧机，等于没迁。

防火墙放行 25500：

```bash
ufw allow 25500/tcp comment 'ace-vpn sub converter'
```

### 5.3 验证

```bash
# 内网测试（每个 token 都要有节点）
curl -s http://127.0.0.1:25500/clash/<SubId1>  | grep -c '^- name:'
curl -s http://127.0.0.1:25500/clash/<SubId2>  | grep -c '^- name:'

# server 字段必须是新机 IP
curl -s http://127.0.0.1:25500/clash/<SubId1>  | grep 'server:' | head -3
# 期望每行都是: server: <NEW_VPS_IP>

# 公网测试（本地 Mac）
curl -s http://<NEW_VPS_IP>:25500/clash/<SubId1> | head -30
```

---

## Phase 6: 你自己先试用 3-5 天（观察期 1）

### 6.1 只切换你自己的客户端

**不要通知家人！** 先你自己用 3-5 天，观察新机稳不稳。

**Mac (Mihomo Party)**：

```
新建 Profile (不删旧的)：
  Name: ace-vpn-<新机代号>  (例 ace-vpn-tokyo)
  URL:  http://<NEW_VPS_IP>:25500/clash/<你的 SubId>

左侧切换到新 Profile → 测试
```

**iPhone/iPad (Stash or Shadowrocket)**：

```
Stash:
  Profiles → + → From URL
  填 http://<NEW_VPS_IP>:25500/clash/<你的 SubId>
  命名 "<新机代号>"

Shadowrocket:
  加一条订阅: https://<NEW_VPS_IP>:2096/<OLD_SUB_PATH>/<你的 SubId>
```

**Android**：同 Mac。

### 6.2 观察指标（每天至少测一次）

```bash
# 在客户端切到新机节点后，本地 Mac 跑:
curl -w "@-" -o /dev/null -s https://www.youtube.com/ <<'EOF'
   time_namelookup:  %{time_namelookup}\n
      time_connect:  %{time_connect}\n
   time_appconnect:  %{time_appconnect}\n
  time_pretransfer:  %{time_pretransfer}\n
     time_redirect:  %{time_redirect}\n
time_starttransfer:  %{time_starttransfer}\n
                   ——————————\n
        time_total:  %{time_total}\n
EOF
# time_total 稳定在 1-2 秒 = 质量 OK

# 下载速度测试
curl -o /dev/null https://speed.cloudflare.com/__down?bytes=104857600 -w "\n速度: %{speed_download} bytes/s\n"
# 期望: 10+ MB/s (白天), 5+ MB/s (晚高峰 4K YouTube 够用)
```

**每天记录 3 个时段**：

| 时段 | YouTube 4K 能否不缓冲 | curl 测试下载速度 |
|------|---------------------|------------------|
| 工作日 10:00 | | |
| 工作日 20:00 | | |
| 工作日 23:00 | | |

如果有任意一晚速度掉到 **< 3 MB/s** 或者 YouTube 4K 频繁 buffer，记下来。

### 6.3 对照组

**同时用旧机测一次**，确认旧机还活着（家人正常用的保证）：

```bash
# 切 Mac 客户端回旧机 Profile，测同样的 URL
# 记录成绩
```

---

## Phase 7: 通知家人切换（观察期 2，1-2 天）

### 7.1 判断标准

观察 3-5 天后：

- ✅ **质量达标**（晚高峰 4K 不卡 + 白天流畅）→ 通知家人切换
- ⚠️ **偶尔卡顿但可接受**（一周 1-2 次）→ 继续观察，考虑再买备线
- ❌ **质量严重不达标**（频繁卡、断流）→ 在退款窗口内开 ticket 退款

### 7.2 家人切换话术（微信群复制）

```
家人群通知模板：
——————————————————
🔧 [家用梯子升级通知]

大家好，我把家里梯子换了新服务器，更稳了。你们只需要：

1️⃣ 打开 Clash Verge（桌面右下角图标）
2️⃣ 左侧「订阅」- 找到订阅名字「家用VPN」
3️⃣ 把 URL 改成新的：
   http://<NEW_VPS_IP>:25500/clash/<家人的 SubId>
4️⃣ 点「更新」按钮，等 3 秒
5️⃣ 右下角打勾激活

完成。如果出问题回我。
——————————————————
```

### 7.3 帮每个家人操作一次（建议）

远程控制（TeamViewer / 向日葵 / AnyDesk）帮每个家人换一遍，确认：
- 订阅 URL 确实改了
- 能正常上 Google
- 能看 YouTube

比让他们自己操作更高效（你没在场他们 90% 会说"不会搞"）。

---

## Phase 8: 旧机冷备阶段（1-2 个月）

### 8.1 旧机保持运行

```bash
# 旧机不动，任何配置都不改
# 家人客户端里可以保留旧机订阅作为 fallback Profile

# 定期检查旧机还活着（每周一次）
ssh root@<OLD_VPS_IP> "systemctl status x-ui | head -5; df -h /"
```

### 8.2 家人客户端保留旧机作为备份 Profile

**在 Clash Verge Rev / Mihomo Party 里**：

```
订阅列表:
  ✓ 家用VPN-新 (新机) ← 默认使用
    http://<NEW_VPS_IP>:25500/clash/<SubId>
  
  □ 家用VPN-备份 (旧机)
    http://<OLD_VPS_IP>:25500/clash/<SubId>
```

如果哪天新机出问题，家人可以自己切到旧机备份（你记得教一遍怎么切）。

### 8.3 成本计算（本次案例：Vultr → HostHatch）

```
新机 HostHatch:  $4/月 × 12 = $48/年 ≈ ¥345
旧机 Vultr:      $6/月 × 12 = $72/年 ≈ ¥520/年
冷备 1 月:        额外 ¥44
冷备 2 月:        额外 ¥88
```

建议冷备 **1 个月**（¥44 换 4 周观察期，划算），第 5 周决定：

- 新机无问题 → Destroy 旧机
- 新机偶尔抽风 → 继续保留旧机冷备或加买备线

### 8.4 Destroy 旧机

```
Vultr:     https://my.vultr.com  → Instances → 右上角 ⋮ → Destroy
RackNerd:  https://my.racknerd.com → Services → Cancel
HostHatch: https://my.hosthatch.com → Services → Cancel/Refund

注销前做:
  1. 降级 DNS 记录（如有域名解析到旧机）
  2. 删掉 API key / cloud console 里和旧机绑的 SSH key
  3. Billing 页看是否有按天退费（prorated refund）
```

---

## 🆘 迁移过程常见问题

| 现象 | 原因 | 处理 |
|------|------|------|
| 装完 x-ui 后连不上面板 | UFW 没放 panel port（尤其数据库迁移后端口变了）| `ufw allow <OLD_PANEL_PORT>/tcp && ufw reload` |
| 数据库迁移后 3x-ui 起不来 | 数据库版本不匹配 | 恢复备份 `cp /etc/x-ui/x-ui.db.fresh /etc/x-ui/x-ui.db && systemctl restart x-ui`，然后在旧机 `x-ui` 菜单看版本号，新机装同版本 |
| 节点能连但网页打不开 | Reality 密钥没同步 | 手动编辑 inbound，粘贴旧机的 pbk/sid/spx |
| sub-converter 返回 0 节点 | 常见坑 5.9（服务没重启 / token 白名单）| `systemctl restart ace-vpn-sub` + 检查 `SUB_TOKENS` 环境变量 |
| 订阅 YAML 里 server 还是旧 IP | `SERVER_OVERRIDE` 没带或带错 | 重跑 install-sub-converter.sh，把 `SERVER_OVERRIDE=<NEW_VPS_IP>` 加上 |
| 家人刷新订阅后节点名变了 | 数据库迁移成功的副作用 | 让他们重新激活新 Profile 即可 |
| 新机白天快晚上慢 | 普通路由晚高峰拥堵 | 在 Mihomo Party 里手动选延迟最低的节点；或加买 CN2 GIA 线路备用 |

---

## 📦 后续优化（可选，不急）

### 自动备份数据库

```bash
# 在新机上
cat > /etc/cron.daily/ace-vpn-backup <<'EOF'
#!/bin/bash
BACKUP_DIR=/root/backup
mkdir -p "$BACKUP_DIR"
cp /etc/x-ui/x-ui.db "$BACKUP_DIR/x-ui-$(date +%F).db"
# 保留最近 14 天
find "$BACKUP_DIR" -name "x-ui-*.db" -mtime +14 -delete
EOF
chmod +x /etc/cron.daily/ace-vpn-backup
```

### 健康检查 + 自恢复

```bash
# 如果 ace-vpn-sub 意外挂了自动重启
cat > /etc/cron.hourly/ace-vpn-healthcheck <<'EOF'
#!/bin/bash
for svc in x-ui ace-vpn-sub; do
  systemctl is-active --quiet $svc || systemctl restart $svc
done
EOF
chmod +x /etc/cron.hourly/ace-vpn-healthcheck
```

### 家人添加 新机 + 旧机 双订阅的 failover

Clash Meta 支持 `fallback` 策略组，高级玩法，需要时再搞。

### 日志自动清理（小盘 NVMe 必做）

HostHatch / RackNerd 入门套餐普遍只有 10-20 GB 盘，journal 和 access.log 不清会把盘挤满：

```bash
cat > /etc/cron.daily/ace-vpn-logclean <<'EOF'
#!/bin/bash
journalctl --vacuum-time=7d
find /usr/local/x-ui/bin/ -name '*.log' -mtime +7 -delete 2>/dev/null
find /var/log -name '*.log' -size +100M -exec truncate -s 50M {} \; 2>/dev/null
EOF
chmod +x /etc/cron.daily/ace-vpn-logclean
```

---

## ✅ 迁移完成验收清单

- [ ] 新机买到，Ubuntu 22.04 跑起来
- [ ] SSH key 配好，密码登录已禁用
- [ ] `install.sh` 跑完，UFW 防火墙放行 22/443/2096/25500 + 旧机 panel port
- [ ] 3x-ui 数据库从旧机迁到新机，面板能登，clients/inbounds 可见
- [ ] Reality pbk/sid 两边一致
- [ ] sub-converter 每个 token 都能返回节点，server 字段是新机 IP
- [ ] 你自己 Mac/iPhone/iPad/Android 切到新机，测 3 天稳定
- [ ] 家人订阅 URL 更新到新机，全家能用
- [ ] 旧机保留冷备 1 月，观察新机稳定性
- [ ] 第 5 周决定 Destroy 旧机或保留

---

## 🛟 紧急回滚（任何阶段都能用）

如果新机出了严重问题：

```
场景 1: 还没通知家人，你一个人在测 → 把自己客户端切回旧机订阅即可
场景 2: 已通知家人但没全换 → 微信群撤销通知，让所有人切回旧机订阅
场景 3: 全员切到新机后新机挂了 → 家人切到旧机 fallback Profile
          （如果 Profile 留着）；或你临时在 DNS / sub-converter 层做导流
```

**核心心法**：冷备期内**旧机永远不要手动碰它**，它就是你的红色按钮，随时能按下。

---

**Migration done. 祝一把过 🎯**
