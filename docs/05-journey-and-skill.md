# 🧭 ace-vpn：从 0 到全家跑通的经验沉淀（Skill 文档）

> 本文档沉淀「第一次」把家庭 VPN 真正跑通的全部决策、踩坑、修复，用作**下一台 VPS 迁移**或**重建时**的「教科书」。  
> 读它的人是「半年后的自己」或「新接手的人」，没有上下文，要能一路读到底并完成复现。

---

## 0. 目标画像（5 句话讲清）

- **谁用**：2–5 人家庭（我 + 家人 Windows）；设备覆盖 Mac×2 / iPhone / iPad / Android / Win×2。
- **三个网段**：公司内网（走公司 VPN，保持直连）/ 中国境内（直连）/ 海外（代理）。
- **硬要求**：AI 工具（Claude / Cursor / ChatGPT）**永远海外 IP**；Discord / X / YouTube 4K 流畅；抖音/淘宝/B站**不被代理拖慢**。
- **预算**：≤¥300/年，白嫖 Oracle 最佳，Vultr $6/月做短期验证。
- **迁移**：今天用 Vultr，明天可能换 Oracle，**15 分钟无感迁移**，家人客户端不用重配。

---

## 1. 关键决策回顾（避免下次再花时间选型）

### 1.1 VPS 选型结论

| 档位 | 选择 | 理由 |
|------|------|------|
| 🥇 长线（白嫖，**已放弃**）| ~~Oracle Cloud Always Free ARM（Osaka）~~ | 两次注册均被风控，放弃（见 §5.2、`07-oracle-registration.md`）|
| 🥈 短线（验证用）| **Vultr Tokyo $6/月** | 按月付、东京到北京 ~80ms；2026-04 跑通后转冷备，1 个月后 destroy |
| 🥇 长线（**当前生产**）| **HostHatch Tokyo NVMe 2GB $4/月** | AMD EPYC + NVMe、东京节点、¥345/年；低延时对 AI 工具友好 |
| 🥉 年付备选 | HostDare CKVM HK CN2 GIA ¥250/年 | CN2 GIA 晚高峰稳；但 HK IP 被 AI 厂商封，不推荐首选 |
| 🆘 应急 | BandwagonHost CN2 GIA LA $49.99/年 | 晚高峰 4K 最稳；延时略高（~180ms），日常 AI 打字偏卡 |

**决定因素**：
- 需求排序：**低延时（AI / 日常）> 晚高峰稳定（家人 4K）> 价格**；
- RackNerd 无 Tokyo 节点、只有美西，放弃；
- Bandwagon CN2 GIA 稳但延时高、日常 AI 打字体验差；
- HostHatch Tokyo AMD EPYC NVMe，延时 ~50ms，单人 4K 够用，**略超预算但对** AI / Cursor **体验最好**。

**迁移已完成（2026-04-21）**：Vultr → HostHatch，数据库整库迁移，pbk/sid/UUID 全保留，家人端订阅 URL 仅 IP 变化。
**完整操作手册**：[08-vps-migration-playbook.md](08-vps-migration-playbook.md)。

### 1.2 协议 & 软件栈

| 层级 | 选择 | 为什么不是别的 |
|------|------|---------------|
| 主协议 | **VLESS + Reality (Xray-core)** | Reality 抗封锁靠「偷别家的 TLS 证书握手」，无需自己备案域名，GFW 目前还无法区分 |
| 备用协议 | Hysteria2（UDP）| 弱网/丢包强；**本次未启用**——新版 Xray 26.x 自带的 Hysteria2 支持有坑（详见 §5.3）|
| 服务端面板 | **3x-ui** | Web 管理 + 客户端管理 + 订阅 + 数据都在一张 sqlite 表（`/etc/x-ui/x-ui.db`），**整表迁移就是整站迁移** |
| 桌面客户端 | **Mihomo Party / Clash Verge Rev** | 原生 Clash Meta；支持 TUN 模式（让 Cursor / Claude Code / 终端全自动走代理）|
| iOS 客户端 | **Stash** 首选 / Shadowrocket 备选 | Stash 原生吃 Clash YAML，和 Mac 同一份规则；小火箭原生吃 v2ray 订阅，规则需自己堆 |

### 1.3 架构图（一屏）

```
┌─────────────────────────────────────────────────────────┐
│  VPS（生产：HostHatch Tokyo，冷备：Vultr Tokyo 1 月）      │
│                                                          │
│   TCP 443 ─── Xray VLESS+Reality  (主干)                 │
│   UDP 8443 ── Hysteria2           (备用，可选)            │
│   TCP <random panel>  3x-ui Web 面板（管理）             │
│   TCP 2096    3x-ui 订阅端口（原生 base64 vless://）     │
│   TCP 25500   ace-vpn-sub（Python Clash YAML 转换器）    │
└─────────────────────────────────────────────────────────┘
                      │
         ┌────────────┴────────────┐
         │                         │
  [订阅 URL：base64]      [订阅 URL：Clash YAML]
  Shadowrocket（iOS）      Mihomo Party / Stash / Clash Verge
  - 节点列表              - 节点 + 代理组 + 分流规则
  - 规则自己写            - 规则已在 VPS 端统一生成
```

---

## 2. 一键部署顺序（**下一台 VPS 直接抄**）

### Step 1：买 VPS 并拿到 root SSH

- 优先 Oracle Free（新邮箱、信息前后一致、冷却 24–72h 重试）
- 过不了用 Vultr Tokyo shared CPU $6/月

### Step 2：克隆仓库 + 运行 `install.sh`

```bash
git clone https://github.com/<you>/ace-vpn.git
cd ace-vpn

# 全自动：系统初始化 + 防火墙 + 3x-ui + 自动建 VLESS+Reality 入站
sudo AUTO_CONFIGURE=1 bash scripts/install.sh
```

脚本干的事（一次做完）：
1. `setup-system.sh`：apt update、BBR+fq、IP forward、文件句柄上限
2. `setup-firewall.sh`：UFW 规则（22 / 80 / 443 / 8443 UDP / 面板 / 订阅 / Clash 转换器）
3. `install-3xui.sh`：官方安装器（交互提示：端口 **2053**、用户 admin/admin、SSL 选 **2**（IP 证书））
4. `configure-3xui.sh`：调 3x-ui HTTP API 自动建 VLESS+Reality 入站

**交互点**：3x-ui 安装器会问端口和 SSL，答 `y → 2053 → admin/admin` + 选 `2`（IP 证书）即可。

### Step 3：加固面板（**必做**）

浏览器打开 `https://<VPS_IP>:2053/<生成的随机path>/`

**Panel Settings** 里改掉：
- 端口：2053 → 随机 5 位（如 41785）
- Path：随机 16 位（前后带 /）
- 用户名/密码：admin/admin → 强随机

改完**立即**：
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

### Step 4：装 sub-converter（Clash YAML 转换器）

3x-ui 原生订阅是 base64 的 `vless://` 列表，**Shadowrocket 能吃，Mihomo/Clash 不能**。  
装我们的 Python 转换器，输出带规则的 Clash YAML：

```bash
sudo UPSTREAM_SUB="https://<VPS_IP>:2096/<sub_path>/<subId>" \
     SUB_TOKEN='hxn-home-2026q2' \
     SERVER_OVERRIDE='<VPS_IP>' \
     LISTEN_PORT=25500 \
     bash scripts/install-sub-converter.sh
```

> `SERVER_OVERRIDE` 保险丝：3x-ui 根据请求 Host 头生成 `server:` 字段，不设就会变成 `127.0.0.1`，客户端谁都连不上（**踩坑#5**）。

装完拿到的两条订阅：

| 客户端 | URL |
|--------|-----|
| Shadowrocket（iOS） | `https://<VPS_IP>:2096/<sub_path>/<subId>`（base64） |
| Mihomo / Stash / Verge | `http://<VPS_IP>:25500/clash/<SUB_TOKEN>`（YAML） |

### Step 5：迁移到新 VPS

```bash
# 旧机
systemctl stop x-ui
scp /etc/x-ui/x-ui.db you@home-mac:~/backups/x-ui-$(date +%F).db
scp /etc/systemd/system/ace-vpn-sub.service you@home-mac:~/backups/

# 新机
git clone https://github.com/<you>/ace-vpn.git && cd ace-vpn
sudo AUTO_CONFIGURE=0 bash scripts/install.sh   # 只装基础
scp you@home-mac:~/backups/x-ui-2026-04-19.db /etc/x-ui/x-ui.db
systemctl restart x-ui

# sub-converter 照 Step 4 重跑，SUB_TOKEN 用原来的 → 客户端订阅 URL 只要改 IP
```

---

## 3. 客户端分发策略（5 台设备，1 条订阅）

| 设备 | 软件 | 订阅 URL | 备注 |
|------|------|---------|------|
| Mac ×2 | Mihomo Party | Clash YAML | 开 TUN 模式给 Cursor 用 |
| iPhone / iPad | Stash（首选）/ Shadowrocket | 对应两条 URL 二选一 | iOS 系统限制不能按 App 代理，全靠域名规则 |
| Android（你）| Mihomo Party Android | Clash YAML | |
| Windows（家人）| Clash Verge Rev | Clash YAML | 开机自启、开 TUN，家人零维护 |

**每人一个 Client（UUID），SubId 按家庭分组**：

| 角色 | Email | SubId | 订阅 URL |
|------|-------|-------|---------|
| 我 | `xiaonan-mac` / `xiaonan-iphone` / `xiaonan-ipad` / `xiaonan-android` | 全部用 `sub-hxn` | 自己三台设备共用同一条 |
| 爸爸 | `dad-win` | `dad-home` | 独立 URL |
| 妈妈 | `mom-win` | `mom-home` | 独立 URL |

独立 SubId 的价值：**家人 UUID 泄露只吊销他一个**，不影响全家。

详细每端操作见 [06-client-setup.md](06-client-setup.md)。

---

## 4. 分流规则（写在 sub-converter.py 里集中维护）

规则由 Python 转换器在下发时**按顺序拼装**，客户端不需要自己配规则。

```
1. 公司内网 CIDR / 公司域名 后缀        → DIRECT
2. 私有网段（127/192.168/10.0/172.16） → DIRECT
3. AI（OpenAI/Claude/Gemini/Cursor/Copilot） → 🤖 AI 组（代理）
4. 社交/工具（Discord/X/Telegram/Google/GitHub）→ 🚀 PROXY
5. 流媒体（YouTube/Netflix/Disney+/Spotify）    → 📺 MEDIA
6. 国内（抖音/淘宝/B站/微博/QQ/百度）            → DIRECT
7. GEOIP CN / PRIVATE                             → DIRECT
8. MATCH                                          → 🐟 FINAL（默认代理）
```

**改规则的正确流程**（重要，家人能全体自动同步）：

```bash
# 1. 本地 Mac 编辑 scripts/sub-converter.py（改 AI_DOMAINS / SOCIAL_PROXY / CHINA_DIRECT）
# 2. 推到 VPS
scp scripts/sub-converter.py root@$VPS_IP:/opt/ace-vpn-sub/sub-converter.py
ssh root@$VPS_IP "systemctl restart ace-vpn-sub"
# 3. 家人客户端「更新订阅」，10 秒全家生效
```

**添加公司内网**：
```bash
ssh root@$VPS_IP "systemctl edit ace-vpn-sub"
# 在 [Service] 段加：
# Environment=COMPANY_CIDRS=10.128.0.0/16
# Environment=COMPANY_SFX=corp.example.com
ssh root@$VPS_IP "systemctl restart ace-vpn-sub"
```

---

## 5. 踩过的坑 & 根因（强烈建议看完再动下一台）

### 5.1 Oracle 注册被风控

**现象**：「无法完成您的注册」，第一次填日本后再改新加坡后更容易触发。

**根因**：Oracle WAF + 反欺诈规则检查「国家 / 卡 BIN / IP / 主区域」一致性，频繁改字段、信用卡 BIN 与国家不匹配都会挂。

**修复**：
- 换新邮箱
- 信息前后一致：卡 BIN = 新加坡 → 账单 = 新加坡 → 出口 IP = 新加坡 → 主区域 = Osaka（Osaka 不限制国家）
- 24–72h 冷却再试

### 5.2 3x-ui 安装器交互提示

**现象**：`install.sh` 跑到官方安装器时会问 panel port、admin 账号、SSL 方式。

**修复**：用脚本包一层交互也搞得定，但更简单**直接手动响应**：
- `Customize Panel Port? y` → `2053`
- `Username?` `admin` / `Password?` `admin` / `Confirm Password?` `admin`
- SSL 选 `2`（Let's Encrypt for IP）→ 先确保 `sudo ufw allow 80/tcp` 已开

装完 **立刻** 到 Web 面板改 admin / admin 和 path（见 Step 3）。

### 5.3 Hysteria2 在 Xray 26.x 里「unknown config id」

**现象**：
```
ERROR - XRAY: Failed to start: ... infra/conf: unknown config id: hysteria2
```

**根因**：3x-ui 能保存 Hysteria2 入站到 db，但 **Xray 主线代码** 把 Hysteria2 的 inbound 协议 ID 改掉 / 或该版本分支未合进这个 commit，启动时 xray 直接报错。一旦报错，**整个 xray 进程挂，VLESS 也一起废**。

**修复**：
1. 面板里**删掉 Hy2 入站** 或 `sqlite3 /etc/x-ui/x-ui.db "DELETE FROM inbounds WHERE port=8443"`
2. `systemctl restart x-ui`
3. 暂时放弃 Hy2（Reality 完全够用）

### 5.4 `configure-3xui.sh` 提示 `pbk` 为空 / 入站创建失败

多重踩坑合集：

| 子问题 | 根因 | 修复 |
|-------|------|------|
| `pbk` 空 | `xray x25519` 新版输出 `Password:` 而不是 `PublicKey:` | `grep PublicKey` 匹配不到时 fallback 读 `Password:` 行 |
| 入站创建失败 | 3x-ui v2 的 API 路径 `/panel/inbound/add` → 改成 `/panel/api/inbounds/add`；需要 `X-Requested-With: XMLHttpRequest` | 脚本已统一 |
| Hy2 `empty client ID` | 3x-ui 对非 trojan / ss 协议要求 `clients[].id` 非空 | Hy2 payload 里给 `clients[0].id` 塞 UUID（即使 Hy2 实际用 password 认证）|
| `Port already exists: 443` | 3x-ui 的端口校验**不分 TCP/UDP**，VLESS 443/TCP 已占，Hy2 443/UDP 被拒 | Hy2 默认 UDP 端口改成 **8443** |
| `set -e` 导致脚本提前退出 | `grep` 匹配不到时退出码非 0，`pipefail` 触发 `set -e` | `( ... ) || true` 包裹 |

### 5.5 sub-converter 所有节点 `server: 127.0.0.1`

**现象**：Clash YAML 里 `server: 127.0.0.1`，客户端全部 timeout。

**根因**：3x-ui 根据 HTTP Host 头生成 vless 链接的 server 字段。`UPSTREAM_SUB` 写 `https://127.0.0.1:2096/...` → 返回的 vless 里 host 就是 127.0.0.1。

**修复**：
- `UPSTREAM_SUB` 用**公网 IP** 而非 127.0.0.1
- **双保险**：`sub-converter.py` 加 `SERVER_OVERRIDE` 环境变量强制覆盖 `server:`

### 5.6 老版 subconverter 不认 Reality

**现象**：`tindy2013/subconverter` / `stilleshan/subconverter` 喂 vless+reality base64 全部 `No nodes were found!`

**根因**：这些 fork 的 vless 解析器不认 `pbk`、`sid`、`spx` 这些 Reality 参数。

**修复**：自己写 `sub-converter.py`（~200 行 Python），原生支持 Reality，且规则可自定义。

### 5.7 颜色转义字符 `\033[...]` 原样打印

**根因**：`common.sh` 用单引号 `'\033[0;33m'` 只能在 `echo -e` 下生效，`cat <<EOF` 里直接原样输出。

**修复**：改成 ANSI-C 引号 `$'\033[0;33m'`，所有 `log_*` 用 `printf`。

### 5.8 Mihomo Party 同时有 Profile 和 Override 时规则被覆盖

**现象**：订阅 OK，节点 OK，但打开 google 就是不通。

**根因**：Override 里写了 `rules:` 字段会**整体替换** Profile 的 300+ 条规则。

**修复**：**只用 Profile，别写 Override**（除非你真要在客户端本地加公司 CIDR 直连，且不想污染订阅）。

### 5.9 改了 sub-converter 环境变量但不生效 / 新 token 返回 0 节点

**现象**：改 `SUB_TOKENS`、`UPSTREAM_BASE` 等环境变量后 `install-sub-converter.sh` 成功，`systemctl show -p Environment` 显示新值，但服务行为和没改一样。

**根因**：旧脚本只做 `systemctl enable --now`，对已运行的服务**不触发重启**。daemon-reload 只加载新 unit 文件，旧进程仍在用老环境。

**修复**：
- 每次重装后手动 `sudo systemctl restart ace-vpn-sub`
- install 脚本已改成 `enable` + 显式 `restart`，并在最后自检每条 token 节点数

---

## 6. 重复使用这个经验的「Cheatsheet」

**新 VPS 到手的 5 行命令**：

```bash
git clone https://github.com/<you>/ace-vpn.git && cd ace-vpn
sudo AUTO_CONFIGURE=1 bash scripts/install.sh
# 改面板端口/path/密码、记下 3x-ui 订阅 URL
sudo UPSTREAM_SUB='<base64 订阅 URL>' SUB_TOKEN='hxn-home-2026q2' \
     SERVER_OVERRIDE='<VPS_IP>' bash scripts/install-sub-converter.sh
# 客户端订阅 URL 改 IP，各端点「更新订阅」即可
```

**需要恢复历史数据时**：

```bash
systemctl stop x-ui
cp ~/backups/x-ui-<date>.db /etc/x-ui/x-ui.db
systemctl restart x-ui
```

**每次新加一家人**：

3x-ui 面板 → Inbounds → Clients → **+ Add Client** → Email/SubId 填好 → Save → 给他发 `http://<VPS_IP>:25500/clash/<TOKEN>`（或 base64 订阅）即可。

---

## 7. 待办 / 下次提升点

- [x] ~~sub-converter 支持多 SubId 合并/路由~~ — 已实现：`UPSTREAM_BASE` + `SUB_TOKENS` 多 token 模式，一个实例服务全家
- [ ] 改成通过域名 + Let's Encrypt 证书访问面板（目前 IP 证书 6 天一续）
- [ ] 加 Fail2ban + 面板 IP 白名单
- [ ] 把 `install.sh` 封装成「幂等、支持升级」
- [ ] 写个 `migrate.sh` 自动化新旧 VPS 之间的整库迁移
- [ ] `ace-vpn-sub.service` 支持域名 / HTTPS（当前明文 HTTP，内容是公开规则 + UUID，属中风险）
- [ ] 备份脚本：`scripts/backup.sh` 定时 tar + gpg 上传 S3

---

## 8. 相关文档索引

- [00-handover.md](00-handover.md) — 会话交接（跨设备继续时先读）
- [01-vps-decision.md](01-vps-decision.md) — VPS 选型详细比价
- [02-oracle-setup.md](02-oracle-setup.md) — Oracle 注册完整流程（含风控应对）
- [03-server-setup.md](03-server-setup.md) — 3x-ui 服务端部署手册
- [04-requirements-summary.md](04-requirements-summary.md) — 需求与方案总结
- **[05-journey-and-skill.md](05-journey-and-skill.md)** — 本文，skill 总结
- [06-client-setup.md](06-client-setup.md) — 四端客户端详细配置
- [07-oracle-registration.md](07-oracle-registration.md) — Oracle Cloud 注册全流程 + Fallback（失败归档）
- [08-vps-migration-playbook.md](08-vps-migration-playbook.md) — 通用 VPS 迁移 playbook（含 Vultr → HostHatch 实战案例）
- [09-new-mac-quickstart.md](09-new-mac-quickstart.md) — 新 Mac 30 分钟快速配置

---

## 9. 约束 / 红线（别踩）

1. **不提交任何 UUID / pbk / 面板 URL / 订阅 URL / 真实 VPS IP** 到 Git（见 `.gitignore`）
2. **面板端口/路径/账号绝不用默认值**（2053/admin/admin 的面板等于裸奔）
3. **订阅端口**（2096 / 25500）**永远走内部 path + 随机 token**，别让路径可枚举
4. **每半年**滚动一次 SubToken 和 UUID（用 `x-ui` 菜单重置或脚本批量更新）
5. **迁移后**旧 VPS 的 3x-ui **至少卸载 + 销毁磁盘**，不能留着
