# 🚀 部署脚本（Scripts）

> 一键在任意 Ubuntu VPS 上完成 `ace-vpn` 服务端部署。

---

## 一、使用

### 最简单（推荐）

```bash
# SSH 登录 VPS 后
cd /root
git clone https://github.com/your-username/ace-vpn.git
cd ace-vpn
sudo bash scripts/install.sh
```

### 自定义端口

```bash
sudo TCP_PORT=443 UDP_PORT=443 PANEL_PORT=54321 bash scripts/install.sh
```

### 只做系统初始化（不装 3x-ui）

```bash
sudo SKIP_3XUI=1 bash scripts/install.sh
```

### 全自动（安装 + 自动建入站，适合新机）

```bash
# 前提：3x-ui 默认账号还是 admin/admin
sudo AUTO_CONFIGURE=1 bash scripts/install.sh
```

### 只跑自动化配置（3x-ui 已装好）

```bash
sudo bash scripts/configure-3xui.sh
# 已改过面板账号：
sudo XUI_USER=myuser XUI_PASS='xxx' XUI_PANEL_PATH='/xyz123' bash scripts/configure-3xui.sh
```

完成后看：

```bash
sudo cat /root/ace-vpn-credentials.txt
```

里面有 `vless://...` 和 `hysteria2://...` 可直接导入客户端。

---

## 二、文件说明

| 文件 | 作用 |
|------|------|
| [`install.sh`](install.sh) | **入口脚本**：依次调用下面几个 |
| [`setup-system.sh`](setup-system.sh) | apt 更新、时区、BBR、IP 转发、句柄上限 |
| [`setup-firewall.sh`](setup-firewall.sh) | UFW 默认策略 + 放行必要端口 |
| [`install-3xui.sh`](install-3xui.sh) | 安装 3x-ui Web 面板 |
| [`configure-3xui.sh`](configure-3xui.sh) | **自动化** 登录 3x-ui + 生成 Reality 密钥/UUID + 建入站 + 输出分享链接 |
| [`install-sub-converter.sh`](install-sub-converter.sh) | 部署 Clash 订阅转换器 + 初始化内网规则文件 `/etc/ace-vpn/intranet.yaml` |
| [`sub-converter.py`](sub-converter.py) | 转换器本体；每次 HTTP 请求热加载 intranet.yaml，改完无需重启 |
| [`sync-intranet.sh`](sync-intranet.sh) | **Mac 本地工具**：把 `private/intranet.yaml` 同步到 VPS，客户端刷新订阅即生效 |
| [`lib/common.sh`](lib/common.sh) | 共享工具函数（日志、apt 锁等待、root 检查） |

---

## 三、环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `TCP_PORT` | `443` | VLESS+Reality 监听端口 |
| `UDP_PORT` | `443` | Hysteria2 监听端口 |
| `PANEL_PORT` | `2053` | 3x-ui 面板端口 |
| `SUB_PORT` | `2096` | 订阅端口 |
| `SSH_PORT` | `22` | SSH 端口 |
| `TZ` | `Asia/Shanghai` | 时区 |
| `SKIP_3XUI` | `0` | 设为 `1` 跳过 3x-ui 安装 |
| `AUTO_CONFIGURE` | `0` | 设为 `1` 在装完 3x-ui 后自动建 Reality + Hy2 入站 |
| `XUI_USER` / `XUI_PASS` | `admin` / `admin` | 面板账号密码（configure-3xui.sh 专用） |
| `XUI_PANEL_PATH` | 空 | 若改过面板路径（如 `/xyz123`） |
| `REALITY_DEST` | `www.cloudflare.com:443` | Reality 伪装的真实站 |
| `REALITY_SNI` | `www.cloudflare.com` | Reality serverName |

---

## 四、幂等性

所有脚本设计为 **可重复执行**：

- `setup-system.sh` - 重复跑只会重复覆盖 sysctl 配置（相同内容）
- `setup-firewall.sh` - 使用 `ufw --force reset` 重置后重建
- `install-3xui.sh` - 检测到已安装会询问是否重装

---

## 五、支持的 VPS

| 供应商 | 系统 | 测试状态 |
|--------|------|---------|
| Vultr | Ubuntu 22.04 / 24.04 x86_64 | ✅ 主要测试环境 |
| Oracle Cloud | Ubuntu 22.04 ARM64 / x86_64 | 🟡 原理兼容，待测（需额外在 VCN 放行端口） |
| HostDare | Ubuntu 22.04 x86_64 | 🟡 原理兼容，待测 |
| RackNerd | Ubuntu 22.04 x86_64 | 🟡 原理兼容，待测 |
| Debian 12 | - | 🟡 大概率兼容（apt 系统） |
| CentOS / AlmaLinux | - | ❌ 不支持（脚本基于 apt/ufw） |

---

## 六、迁移流程（换 VPS）

```
旧机：
  1. systemctl stop x-ui
  2. cp /etc/x-ui/x-ui.db /root/x-ui-backup.db
  3. scp /root/x-ui-backup.db local:/safe/place/

新机：
  1. sudo bash scripts/install.sh
  2. systemctl stop x-ui
  3. scp local:/safe/place/x-ui-backup.db /etc/x-ui/x-ui.db
  4. systemctl start x-ui
  5. 登录面板 → 入站列表改对外 IP（或用域名，免改）
  6. 客户端点"更新订阅"
```

---

## 七、故障排查

### 脚本报错 "apt 被占用"
- 新装 VPS 上 cloud-init 可能还在跑，等 2-3 分钟
- 或者：`sudo systemctl stop unattended-upgrades && sudo bash scripts/install.sh`

### 3x-ui 下载失败
- 网络问题：检查 `curl https://github.com` 是否通
- 墙内机器：换出口或直接到 https://github.com/MHSanaei/3x-ui 手动下载 release

### UFW 启用后 SSH 断开
- **防御措施**：脚本里 `ufw allow 22/tcp` 在 `ufw enable` 之前
- 若真断开：通过 VPS 供应商的 Web Console（VNC）登录，执行 `sudo ufw allow 22 && sudo ufw reload`

### Oracle 实例部署后外部连不上 443
- Oracle 多一层 VCN 防火墙，见 `setup-firewall.sh` 的提示
- 去控制台 → Networking → VCN → Security List → Add Ingress Rule
