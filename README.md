# ace-vpn

> 基于自有 VPS 的家庭 VPN 方案，目标：2–5 人共享，YouTube 4K 流畅，抗 GFW 封锁。

## 📍 项目状态

**阶段**：Oracle Cloud Always Free 白嫖中（注册流程卡在付款验证，详见 [docs/00-handover.md](docs/00-handover.md)）

## 🎯 目标

- 2–5 人家庭共享使用
- 4K YouTube 流畅观看（北京使用）
- IP 抗封锁（协议层伪装）
- 预算：¥300/年以下（白嫖最佳，付费降级方案 ¥259/年）

## 🏗️ 技术选型

| 层级 | 选择 | 备注 |
|------|------|------|
| **主力 VPS** | Oracle Cloud Always Free ARM（Osaka）| 4C/24G/200G 免费 |
| **降级 VPS** | HostDare CSSD0 CN2 GIA | ¥259/年 |
| **应急备线** | RackNerd 2G（LA）| ¥132/年 |
| **主协议** | VLESS + Reality（Xray-core）| 抗封锁 |
| **备用协议** | Hysteria2 | UDP 加速 |

## 📂 目录结构

```
ace-vpn/
├── README.md                    本文件
├── docs/
│   ├── 00-handover.md           🔴 会话交接文档（回家/换设备先读这个）
│   ├── 01-vps-decision.md       VPS 选型决策记录
│   ├── 02-oracle-setup.md       Oracle Cloud 开通手册（569 行详细版）
│   └── 03-xray-reality-setup.md 待写：协议部署手册
├── scripts/                     待写：一键部署脚本
└── clients/                     待写：客户端配置模板
```

## 🚀 快速开始（未来的你）

**回家 / 换设备继续时**：先读 [`docs/00-handover.md`](docs/00-handover.md) 了解上下文。

**从零开始部署**（待 VPS 就绪后）：

```bash
# 1. SSH 登录 VPS
ssh ubuntu@<your-vps-ip>

# 2. 克隆本仓库
git clone <this-repo-url> && cd ace-vpn

# 3. 运行一键部署
sudo ./scripts/install-xray-reality.sh

# 4. 生成客户端配置
./scripts/gen-client-config.sh
```

## ⚠️ 安全注意事项

- **禁止** commit 以下敏感信息到本仓库：
  - 服务器 IP、SSH 私钥
  - Xray 的 UUID、Reality 的 private key
  - 订阅链接、客户端配置
  - Oracle API 凭证
- 所有密钥放 `.env` 或系统 keyring，通过 `.gitignore` 排除
- 本项目代码公开，**但运行时配置必须保密**

## 📝 开发日志

- **2026-04-17**：项目启动，完成 VPS 选型调研（搬瓦工 vs Vultr vs Oracle vs HostDare vs RackNerd），决定先白嫖 Oracle Cloud。开始 Oracle 注册，卡在付款验证的 WAF 限流。

## 📄 许可

个人项目，MIT License（代码层面）。运行时配置不开源。
