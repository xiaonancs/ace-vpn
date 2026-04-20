# ACE-VPN

> **Aways Free 终身免费的私人专用 VPN，全球 AI 无障碍使用。**
>
> 基于 **Xray + Reality 协议** 自建家庭 VPN，2–5 人共享、**YouTube 4K 流畅**、**Claude / ChatGPT / Cursor 永不掉线**、抗 GFW、全设备自动分流（公司内网 / 国内 / 海外三网段）。
>
> **0 元方案**：白嫖 [甲骨文云 Always Free ARM](docs/oracle-register.md)（4 核 24G）**永久免费运行**。
> **付费方案**：HostHatch Tokyo **¥345/年**（~$4/月），15 分钟一键部署，可一键迁移。

## 💸 为什么终身免费？

- **方案本身完全开源**（MIT），代码和部署脚本永久免费
- **甲骨文云 Always Free ARM**：4 vCPU / 24 GB RAM / 200 GB 存储 / 10 TB 流量 — **永久 0 元（个别地区除外）**
- 搞不定白嫖？HostHatch **¥345/年** 兜底，仍远低于商业 VPN 订阅（Surfshark ~¥200/年 仅够 1 人，本项目够全家）
- **15 分钟无感迁移**：任意 VPS 挂了，新机 5 行命令重建，家人端仅改个 IP

👉 **开始白嫖**：[甲骨文云 Always Free 申请教程（含踩坑实录）](docs/oracle-register.md)

## 📍 当前状态

**生产：HostHatch Tokyo ✅**（Vultr 冷备 1 个月，2026-05 destroy）

- VPS：HostHatch NVMe 2GB, AMD EPYC Milan, Tokyo, $4/月 ≈ ¥345/年
- 协议栈：VLESS + Reality (Xray) + 3x-ui + 自研 Python sub-converter
- 已接入：Mac ×2 / iPhone / iPad / Android；家人 Windows ×2 待发送

## 📚 文档

| 文档 | 给谁看 |
|------|--------|
| **[docs/oracle-register.md](docs/oracle-register.md)** | **想白嫖 0 元方案的人** — 甲骨文云 Always Free 申请全教程（含踩坑） |
| **[docs/skill.md](docs/skill.md)** | **开发者 / 维护者** — 架构、部署、迁移 playbook、踩坑 |
| **[docs/user-guide.md](docs/user-guide.md)** | **普通用户 / 家人** — 四端客户端安装和使用 |

## 🎯 目标

- 2–5 人家庭共享；**公司内网 / 国内 / 海外三网段自动分流**
- 4K YouTube 流畅（北京使用）
- Claude / Cursor / ChatGPT 等 AI 工具**永远海外 IP**
- Discord 走代理、抖音/淘宝直连，**iOS / Android / Mac / Win 都不用手动切换**
- 预算 ≤ ¥400/年
- **15 分钟无感迁移**到新 VPS（已实战：Vultr → HostHatch）

## 🚀 快速开始

### 新 VPS 到手（5 行命令，详见 [skill.md §4](docs/skill.md#4-一键部署新-vps-到手-5-分钟)）

```bash
ssh root@<VPS_IP>
git clone https://github.com/<you>/ace-vpn.git && cd ace-vpn
sudo AUTO_CONFIGURE=1 bash scripts/install.sh
# → 浏览器改 3x-ui 面板密码/端口/path
sudo UPSTREAM_BASE='https://<VPS_IP>:2096/<sub_path>' \
     SUB_TOKENS='sub-hxn,sub-hxn01' \
     SERVER_OVERRIDE='<VPS_IP>' \
     bash scripts/install-sub-converter.sh
```

### 客户端接入（详见 [user-guide.md](docs/user-guide.md)）

| 设备 | 软件 | 订阅 URL |
|------|------|---------|
| Mac / Android | Mihomo Party | `http://<VPS_IP>:25500/clash/<SubId>` |
| iPhone / iPad | Stash（推荐）/ Shadowrocket | 同上 / 或 3x-ui 原生 base64 URL |
| Windows（家人）| Clash Verge Rev | `http://<VPS_IP>:25500/clash/<SubId>` |

### 本地环境变量

```bash
cp private/env.sh.example private/env.sh
$EDITOR private/env.sh      # 填真实值
chmod 600 private/env.sh
source private/env.sh       # $VPS_IP / $URL_CLASH_SELF 等变量即可用
```

## 📂 目录结构

```
ace-vpn/
├── README.md                    本文件
├── .gitignore                   🔐 排除 private/ 和所有凭据文件
│
├── docs/                        📚 文档（公开）
│   ├── skill.md                 开发者技术文档（架构/部署/迁移/踩坑）
│   └── user-guide.md            普通用户手册（四端客户端配置）
│
├── scripts/                     🛠️ VPS 端部署脚本（公开模板）
│   ├── install.sh               入口：系统 → 防火墙 → 3x-ui → 自动配置
│   ├── setup-system.sh          系统初始化 + BBR
│   ├── setup-firewall.sh        UFW 防火墙
│   ├── install-3xui.sh          3x-ui 安装
│   ├── configure-3xui.sh        通过 API 自动建 Reality 入站
│   ├── install-sub-converter.sh Clash YAML 转换器 systemd 部署
│   ├── sub-converter.py         Python 转换器（原生支持 Reality + 多 token）
│   ├── lib/common.sh            共享工具
│   └── README.md                脚本总览
│
├── clients/                     💻 本地客户端配置模板（公开）
│   ├── README.md                客户端总览
│   ├── mac-clash-meta.yaml      Mac/Win/Android 参考 YAML
│   ├── iphone-shadowrocket.md   iOS 手动配置指南
│   ├── shell-proxy.sh           Mac 终端代理开关（.zshrc）
│   └── cursor-proxy.md          Cursor / VS Code 专用
│
└── private/                     🔐 真实凭据（.gitignore 排除）
    ├── README.md                ⚠️ 目录使用说明（会提交）
    ├── env.sh.example           模板（会提交）
    ├── credentials.txt.example  模板（会提交）
    ├── env.sh                   真实 IP/Token/账号（不提交）
    └── ace-vpn-credentials.txt  面板凭据 + UUID（不提交）
```

## ⚠️ 安全红线

- **`private/` 下所有实际值都不会提交**（`.gitignore` 强制排除）
- **`docs/`、`scripts/`、`clients/` 里不得出现真实 IP / UUID / pbk / token / 订阅 URL**
  - 修改时用占位符：`<VPS_IP>`、`<SUB_TOKENS>`、`<sub_path>`
- **面板**端口、路径、账号**不得使用默认值**（2053 / admin / admin = 裸奔）
- 每 3–6 个月**轮换** `SUB_TOKENS`（3x-ui 里改 SubId + 白名单同步 + `systemctl restart ace-vpn-sub`）
- 迁移后**卸载旧 VPS 的 3x-ui 并销毁磁盘**

## 📝 开发日志

- **2026-04-17** 项目启动；VPS 选型对比；Oracle 注册尝试（WAF 风控挂）
- **2026-04-18** 甲骨文云 Always Free 申请教程（`docs/oracle-register.md`），提供永久 0 元方案
- **2026-04-18** 测试方案 Vultr Tokyo；3x-ui 部署脚本 / 客户端模板 / Cursor/Claude Code 代理
- **2026-04-19** `configure-3xui.sh` + `sub-converter.py` 打通整个链路；Mac/iPhone/Android 跑通 4K YouTube / Discord / Cursor；首次提交私有 Git 仓库；`sub-converter` 重构为多 token 单实例模式
- **2026-04-21** 正式付费方案 HostHatch Tokyo $4/月；下单被风控 → 关代理用真实中国 IP 重下通过；**Vultr → HostHatch 数据库整库迁移完成**，pbk/sid/UUID 全保留，家人端仅改 IP
- **2026-04-22** 文档瘦身：把 00-09 多份 doc 合并为 `docs/skill.md`（开发者）+ `docs/user-guide.md`（用户）两份

## 📄 许可

个人项目，MIT（代码层面）。运行时配置、家庭部署信息不开源。
