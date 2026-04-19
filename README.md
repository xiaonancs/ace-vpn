# ace-vpn

> 基于自有 VPS 的家庭 VPN 方案：2–5 人共享、YouTube 4K 流畅、抗 GFW、全设备自动分流。

## 📍 项目状态

**阶段**：Vultr 跑通 ✅ 家人接入进行中 / Oracle 冷却重试

- ✅ VPS 选型（[docs/01-vps-decision.md](docs/01-vps-decision.md)）
- ✅ 需求 & 方案（[docs/04-requirements-summary.md](docs/04-requirements-summary.md)）
- ✅ 服务端部署手册（[docs/03-server-setup.md](docs/03-server-setup.md)）
- ✅ 一键部署脚本（`scripts/install.sh` + `configure-3xui.sh` + `install-sub-converter.sh`）
- ✅ **经验沉淀 / Skill 文档**（[docs/05-journey-and-skill.md](docs/05-journey-and-skill.md)）
- ✅ **四端客户端手册**（[docs/06-client-setup.md](docs/06-client-setup.md)）
- ✅ Vultr Tokyo 主 VPS 跑通，Mac + iPhone + Android 完成接入
- 🟡 家人 Windows × 2 待发送订阅
- 🔴 Oracle Free 注册：冷却中，24–72h 后换邮箱重试

## 🎯 目标

- 2–5 人家庭共享；**公司内网 / 国内 / 海外三网段自动分流**
- 4K YouTube 流畅（北京使用）
- Claude / Cursor / ChatGPT 等 AI 工具**永远海外 IP**
- Discord 走代理、抖音/淘宝直连，**iOS / Android / Mac / Win 都不用手动切换**
- 预算 ≤ ¥300/年（白嫖 Oracle 最佳，付费降级 HostDare ¥259/年）
- **15 分钟无感迁移**到新 VPS

## 🏗️ 技术选型

| 层级 | 当前选择 | 备注 |
|------|---------|------|
| 主力 VPS（验证）| Vultr Tokyo $6/月 | 月付、立用 |
| 主力 VPS（长线）| Oracle Cloud Always Free ARM（Osaka）| 4C/24G 免费 |
| 降级 / 备线 | HostDare CSSD0 CN2 GIA ¥259/年 / RackNerd 2G ¥132/年 | |
| 服务端面板 | 3x-ui | [MHSanaei/3x-ui](https://github.com/MHSanaei/3x-ui) |
| 主协议 | **VLESS + Reality**（Xray-core）| 抗封锁主力 |
| 备用协议 | Hysteria2（UDP）| **当前禁用**（Xray 26.x 不兼容，[05 §5.3](docs/05-journey-and-skill.md)） |
| 订阅转换 | 自研 Python `sub-converter.py` | 原生支持 Reality + 规则集 |
| Mac/Win/Android 客户端 | Mihomo Party / Clash Verge Rev | Clash Meta 全兼容 |
| iOS/iPad 客户端 | Stash（首选）或 Shadowrocket | |

## 📂 目录结构

```
ace-vpn/
├── README.md                    本文件
├── .gitignore                   🔐 排除 private/ 和所有凭据文件
│
├── docs/                        📚 文档（所有文件不含敏感信息）
│   ├── 00-handover.md           会话交接
│   ├── 01-vps-decision.md       VPS 选型决策
│   ├── 02-oracle-setup.md       Oracle 开通手册
│   ├── 03-server-setup.md       服务端部署手册
│   ├── 04-requirements-summary.md  需求 & 方案总结
│   ├── 05-journey-and-skill.md  🆕 经验沉淀 / Skill（整个项目的教科书）
│   └── 06-client-setup.md       🆕 四端客户端详细配置
│
├── scripts/                     🛠️ VPS 端部署脚本（公开模板）
│   ├── install.sh               入口：系统 → 防火墙 → 3x-ui → 自动配置
│   ├── setup-system.sh          系统初始化 + BBR
│   ├── setup-firewall.sh        UFW 防火墙
│   ├── install-3xui.sh          3x-ui 安装
│   ├── configure-3xui.sh        通过 API 自动建入站
│   ├── install-sub-converter.sh 🆕 Clash YAML 转换器 systemd 部署
│   ├── sub-converter.py         🆕 Python 转换器（原生支持 Reality + 规则）
│   ├── lib/common.sh            共享工具（日志、apt、root check）
│   └── README.md                脚本总览 & 用法
│
├── clients/                     💻 本地客户端配置模板（公开）
│   ├── README.md                客户端总览
│   ├── mac-clash-meta.yaml      Mac/Win/Android 参考 YAML
│   ├── iphone-shadowrocket.md   iOS 手动配置指南
│   ├── shell-proxy.sh           Mac 终端代理开关（.zshrc）
│   └── cursor-proxy.md          Cursor / VS Code 专用
│
└── private/                     🔐 真实凭据存放区（.gitignore 排除）
    ├── README.md                ⚠️ 目录使用说明（会提交）
    ├── env.sh.example           环境变量模板（会提交）
    ├── credentials.txt.example  凭据文件模板（会提交）
    ├── env.sh                   真实 IP / Token / 账号（不提交）
    ├── credentials.txt          3x-ui 实际输出（不提交）
    └── *.md                     家人清单 / 订阅 URL 等（不提交）
```

**两个 2 级目录的分工**：

- **`scripts/`** = VPS 端，所有脚本都设计成「幂等」和「可迁移」
- **`clients/`** = 本地端（Mac / iOS / 等），含终端代理、Mihomo Party YAML 模板

## 🚀 快速开始

### 新 VPS 到手 / 迁移到新 VPS（5 行命令）

```bash
# 1. SSH 登录新 VPS
ssh root@<VPS_IP>

# 2. 克隆仓库
git clone https://github.com/<you>/ace-vpn.git && cd ace-vpn

# 3. 一键：系统 + 防火墙 + 3x-ui + 自动建 Reality 入站
sudo AUTO_CONFIGURE=1 bash scripts/install.sh

# 4. 登录面板改掉默认 admin/admin、端口、随机 path
#    浏览器：https://<VPS_IP>:2053/<random-path>/

# 5. 装 Clash 订阅转换器（让 Mac/Win/Android 直接吃一条 URL）
sudo UPSTREAM_SUB='https://<VPS_IP>:2096/<sub_path>/<subId>' \
     SUB_TOKEN='hxn-home-2026q2' \
     SERVER_OVERRIDE='<VPS_IP>' \
     bash scripts/install-sub-converter.sh
```

完整流程 + 每一步的踩坑解决见 [docs/05-journey-and-skill.md](docs/05-journey-and-skill.md)。

### 客户端接入

| 设备 | 软件 | 订阅 URL |
|------|------|---------|
| Mac | Mihomo Party | `http://<VPS_IP>:25500/clash/<SUB_TOKEN>` |
| iPhone/iPad | Stash（推荐）或 Shadowrocket | 同上 / 或 3x-ui 原订阅 |
| Android | Mihomo Party | 同 Mac |
| Windows（家人）| Clash Verge Rev | 同 Mac |

**每端的详细步骤**：[docs/06-client-setup.md](docs/06-client-setup.md)。

### 本地环境变量

```bash
cp private/env.sh.example private/env.sh
$EDITOR private/env.sh     # 填真实值
chmod 600 private/env.sh
source private/env.sh       # 之后 $VPS_IP / $URL_CLASH_HOME 都可用
```

## 🔄 迁移到 Oracle（15 分钟无感）

```bash
# 旧机
systemctl stop x-ui
scp /etc/x-ui/x-ui.db you@home-mac:~/backup/x-ui-$(date +%F).db

# 新机（Oracle）
git clone <this-repo> && cd ace-vpn
sudo bash scripts/install.sh             # 不带 AUTO_CONFIGURE，只装基础
scp you@home-mac:~/backup/x-ui-*.db /etc/x-ui/x-ui.db
systemctl restart x-ui
# sub-converter 用原 SUB_TOKEN 重装
# 家人客户端仅需改订阅 URL 的 IP（或用域名就不用改）
```

## ⚠️ 安全红线

- **`private/` 目录下所有实际值都不会提交**（`.gitignore` 强制排除）
- **`docs/`、`scripts/`、`clients/` 里不得出现真实 IP / UUID / pbk / token / 订阅 URL**
  - 修改时用占位符：`<VPS_IP>`、`<SUB_TOKEN>`、`<sub_path>`
  - 提交前 `git diff` 过一眼，或跑：`scripts/check-secrets.sh`（待写）
- **面板**端口、路径、账号**不得使用默认值**（2053 / admin / admin = 裸奔）
- 每 3–6 个月**轮换** `SUB_TOKEN`，`sub-converter` 重启即生效
- 迁移后**卸载旧 VPS 的 3x-ui 并销毁磁盘**

## 📝 开发日志

- **2026-04-17** 项目启动；VPS 选型对比；Oracle 注册尝试（WAF 风控挂）
- **2026-04-18** 改买 Vultr Tokyo；3x-ui 部署脚本 / 客户端模板 / Cursor/Claude Code 代理
- **2026-04-19** `configure-3xui.sh` + `sub-converter.py` 打通整个链路；Mac/iPhone/Android 跑通 4K YouTube / Discord / Cursor；沉淀 `05-journey-and-skill.md` / `06-client-setup.md`；首次提交私有 Git 仓库

## 📄 许可

个人项目，MIT（代码层面）。运行时配置、家庭部署信息不开源。
