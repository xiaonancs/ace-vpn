# 🛠️ 服务端部署手册（Server Setup）

> **目标**：在任意 VPS（Vultr / Oracle / HostDare / RackNerd）上用 15 分钟部署可用的 `ace-vpn` 服务端。  
> **技术栈**：3x-ui 面板 + Xray-core + VLESS+Reality（主）+ Hysteria2（备）  
> **适用**：Ubuntu 22.04 / 24.04 LTS x86_64 或 ARM64

---

## 一、为什么选 3x-ui

| 方案 | 优点 | 缺点 |
|------|------|------|
| **3x-ui**（选用） | Web 面板、多协议、一键生成订阅、SQLite 备份迁移方便 | 需要开一个管理端口 |
| Xray 手写 config | 极简、完全掌控 | 多设备/多协议时维护成本高 |
| sing-box 脚本 | 协议覆盖广 | 多为 CLI，家人友好度低 |

**核心理由**：我们要的是 **"一次部署，多端订阅，换机可迁移"**，3x-ui 的面板 + Subscription + 备份恢复最契合。

- 官方仓库：https://github.com/MHSanaei/3x-ui

---

## 二、一键部署

### 2.1 前置条件
- Ubuntu 22.04 / 24.04 LTS
- root 权限（或 sudo）
- 服务器已能 `apt update`
- 已在 VPS 供应商防火墙放行：**TCP 22 / TCP 443 / UDP 443**（以及下方面板端口）

### 2.2 运行脚本

```bash
# SSH 登录 VPS 后
git clone https://github.com/your-username/ace-vpn.git  # 或上传 scripts/ 目录
cd ace-vpn
sudo bash scripts/install.sh
```

脚本会依次完成：

1. 系统更新 + 基础工具（`curl`、`unzip`、`ca-certificates`、`vim`）
2. 时区设为 `Asia/Shanghai`
3. 开启 **BBR + fq**（加速 TCP）
4. 配置 **UFW 防火墙**（放行 SSH/TCP 443/UDP 443/面板端口）
5. 安装 **3x-ui**（官方脚本）
6. 打印后续操作提示

### 2.3 脚本完成后你会看到

```
==== 3x-ui 安装完成 ====
面板地址：http://YOUR_IP:2053/
默认用户：admin
默认密码：admin
⚠️ 请立即登录后修改用户名、密码、面板路径！
```

---

## 三、3x-ui 初始化（Web 面板里做）

### 3.1 首次登录必改 3 项

1. **面板设置 → 用户名**：改成非 admin 的随机字符串
2. **面板设置 → 密码**：强密码（≥ 16 位）
3. **面板设置 → 面板路径**：改成 `/随机路径/`（如 `/xhxwyz2026/`），然后**重启面板**

完成后新面板地址是 `http://YOUR_IP:2053/随机路径/`。

### 3.2 启用 HTTPS（强烈推荐）

- 用 **免费域名** 或自有域名解析到 VPS
- 面板 → 证书设置 → 申请 Let's Encrypt（3x-ui 内置）
- 之后面板通过 `https://your.domain/xhxwyz2026/` 访问

---

## 四、协议配置

### 4.0 ⚡ 一键自动化（推荐）

如果你不想手点面板，脚本里自带：

```bash
sudo bash scripts/configure-3xui.sh
# 或第一次装时一步到位：
sudo AUTO_CONFIGURE=1 bash scripts/install.sh
```

脚本会自动完成：

1. 登录 3x-ui（默认 admin/admin，改过就用环境变量传）
2. 生成 Reality 密钥对（`xray x25519`）
3. 生成 UUID / Hy2 密码 / ShortID
4. 创建 VLESS+Reality（TCP 443）和 Hysteria2（UDP 443）入站
5. 输出 `vless://` 和 `hysteria2://` 分享链接
6. 凭据写入 `/root/ace-vpn-credentials.txt`（chmod 600）

> **注意**：自动化脚本跑完后，**仍需手动做的事**：
> - 登录面板改 admin 账号密码和面板路径
> - 若需要开订阅（多设备共用），到面板里的"订阅设置"开启端口 2096
> - Oracle 实例需要在 VCN Security List 也放行端口

以下章节是**手动**配置流程（不用自动化时参考）。

### 4.1 添加 VLESS + Reality（主力）

**入站列表 → 添加入站**：

| 字段 | 值 |
|------|----|
| 备注 | `main-reality` |
| 协议 | `vless` |
| 监听 IP | 留空（= 所有） |
| 端口 | `443` |
| 总流量 | 0（不限） |
| 到期时间 | 0（不限） |

**传输配置**：

| 字段 | 值 |
|------|----|
| 传输方式 | `tcp` |
| Security | **`reality`** |
| uTLS | `chrome` |
| Dest | `www.cloudflare.com:443`（或其它知名 TLS 站） |
| Server Names | `www.cloudflare.com` |
| 私钥 / 公钥 | 点"获取新证书"自动生成 |
| Short Id | 点"获取新 shortId" |
| 流控（Flow） | `xtls-rprx-vision` |

**客户端配置**（添加用户）：
- 邮箱：`self@mac` / `self@iphone` / ...（用来区分设备）
- UUID：点"获取新 UUID"
- **Flow** 必须和入站一致：`xtls-rprx-vision`

### 4.2 添加 Hysteria2（备用，UDP）

**入站列表 → 添加入站**：

| 字段 | 值 |
|------|----|
| 备注 | `backup-hy2` |
| 协议 | `hysteria2` |
| 端口 | `443`（UDP，和 Reality 不冲突因为协议不同） |
| 密码 | 16+ 位随机 |
| 伪装类型 | `none` 或 `salamander` |
| 混淆密码 | 16+ 位随机 |

### 4.3 生成订阅

- 3x-ui 面板 → **订阅设置**：
  - 开启订阅
  - 订阅端口：`2096`（或其它没冲突的端口，记得防火墙放行）
  - 订阅路径：改成随机路径
- 每个用户会有一个独立的 **Subscription URL**，格式形如：

```
http://YOUR_IP:2096/sub/<token>
```

这个 URL 就是给客户端用的。

---

## 五、备份与迁移

### 5.1 导出备份（迁移 Oracle 时用）

```bash
# 3x-ui 的数据在：
/etc/x-ui/x-ui.db

# 停服务 → 备份 → 启动
systemctl stop x-ui
cp /etc/x-ui/x-ui.db /root/x-ui-backup-$(date +%Y%m%d).db
systemctl start x-ui
```

把 `x-ui-backup-*.db` **加密后**放 1Password / keyring / 本地私密目录。**千万不要 commit 进仓库**（`.gitignore` 已排除）。

### 5.2 在新 VPS 恢复

```bash
# 新 VPS 装完 3x-ui 后
systemctl stop x-ui
cp /path/to/x-ui-backup.db /etc/x-ui/x-ui.db
systemctl start x-ui
```

登录新面板 → 入站列表里把旧 IP 全改成新 VPS 的 IP（或直接用域名，更好）→ 客户端点"更新订阅"即可。

---

## 六、安全加固（可选但建议）

### 6.1 关闭 SSH 密码登录（只允许密钥）

```bash
sudo vim /etc/ssh/sshd_config
# 修改：
# PasswordAuthentication no
# PermitRootLogin prohibit-password
sudo systemctl restart ssh
```

### 6.2 装 Fail2ban

```bash
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
```

### 6.3 面板端口限 IP

如果你只从固定几个 IP 登面板：

```bash
sudo ufw delete allow 2053/tcp
sudo ufw allow from YOUR_HOME_IP to any port 2053 proto tcp
```

---

## 七、常见问题

### Q1：443 被 Vultr/Oracle 默认封了？
- Vultr 默认无软件防火墙，只要 UFW 放行即可
- Oracle 需要去 **VCN → Security List → Ingress Rules** 手动加 TCP/UDP 443 规则（见 `02-oracle-setup.md` 坑 2）

### Q2：客户端连上但不通？
1. 先 `ping YOUR_IP`，看 ICMP 通不通
2. `ssh` 能上 → 底层 TCP 没问题
3. `sudo ufw status` 确认 443 开放
4. 3x-ui 面板看入站的**在线用户数**是否 +1
5. 看 Xray 日志：面板 → 日志 → Xray log

### Q3：Reality 的 Dest 该选什么？
- 必须是 **TLS 1.3 + H2 的真实大站**
- 推荐：`www.cloudflare.com`、`www.microsoft.com`、`dash.cloudflare.com`、`www.apple.com`
- 不要选被墙站（`www.google.com` 虽然技术上可以，但流量特征会被关注）

### Q4：`vless://` 里 `pbk=` 为空 / 脚本提示入站创建失败

**原因**：

1. 部分 `xray` 版本 `xray x25519` 输出里公钥字段名是 **`Password:`**（与登录密码无关，实为 X25519 公钥）而不是 `PublicKey:`，旧版脚本解析失败。**`Hash32:` 不是客户端 `pbk`，不要用。**
2. 端口 **443 已被其它入站占用**，API 创建失败；脚本若仍用「刚生成但未写入面板」的 UUID 拼链接，会得到无效链接。

**处理**：把仓库里的 **`scripts/configure-3xui.sh` 更新到最新** 后重新执行：

```bash
sudo PANEL_PORT=2053 XUI_PANEL_PATH='/你的路径' XUI_USER=… XUI_PASS='…' \
  bash /root/ace-vpn/scripts/configure-3xui.sh
```

新版会：**正确解析 x25519**；若创建失败则 **从面板 `/panel/inbound/list` 拉取已有 VLESS+Reality**；仍失败则 **直接退出**，不再写入错误的 `vless://`。

**切勿使用 `pbk=` 为空的链接。**

### Q5：脚本提示「入站创建失败」且无法从面板读取

**常见原因**：3x-ui **v2** 的 HTTP API 路径是 **`/panel/api/inbounds/add`** 与 **`GET /panel/api/inbounds/list`**（`inbounds` 为复数，且在 `api` 下）。若脚本误用旧路径 `/panel/inbound/...` 会全部失败。

仓库里的 `configure-3xui.sh` 已按 v2 路径修正；请更新脚本后重跑。

### Q6：家人 Windows 家人端怎么最简化？
- 让他们装 **Clash Verge Rev**
- 把订阅 URL 发给他们一次，导入后勾选"开机启动"
- 规则自动更新，后续无感

---

## 八、关联文件

- [`scripts/install.sh`](../scripts/install.sh) - 一键部署入口
- [`scripts/setup-system.sh`](../scripts/setup-system.sh) - 系统初始化（BBR、时区）
- [`scripts/setup-firewall.sh`](../scripts/setup-firewall.sh) - UFW 防火墙
- [`clients/README.md`](../clients/README.md) - 客户端配置
