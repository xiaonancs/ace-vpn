# ACE-VPN

> **Always Free 私人 VPN 解决方案 · 白嫖 Oracle Cloud· 安全打通公司内网 / 海内 / 海外三段网络 · 全球 AI 无障碍。**
> <br>**本项目纯属技术研究，不存在其他目的，特此声明。**

**普通用户直接跳转：[用户手册 user-guide](docs/用户手册%20user-guide.md)**

Xray + Reality 自建，2–5 人家庭共享。**公司内网 DIRECT · 大陆公网直连 · 海外走代理**，客户端一次订阅全自动。

| 方案 | 费用 | 说明 |
|------|------|------|
| **白嫖** | 永久 0 元 | [Oracle Cloud Always Free ARM](docs/Oracle%20Cloud%20注册教程.md) · 4C / 24G / 10TB 流量 |
| **付费** | ¥345/年（$4/月） | HostHatch Tokyo · 稳定 · 15 分钟一键迁移 |
| **源码** | 免费 | MIT · 整套部署脚本 + 四端客户端模板 |

👉 想 0 元起步：[Oracle Cloud Always Free 申请教程（含风控踩坑）](docs/Oracle%20Cloud%20注册教程.md)

## 📍 当前状态

生产 **HostHatch Tokyo ✅** · 协议栈 **VLESS + Reality + 3x-ui + 自研 Python sub-converter** · 已接入 Mac×2 / iPhone / iPad / Android，Windows×2 待发送

## 📚 文档

| 文档 | 给谁看 |
|------|--------|
| **[Oracle Cloud 注册教程](docs/Oracle%20Cloud%20注册教程.md)** | 想 0 元白嫖的人 — Oracle Cloud Always Free 申请全教程 |
| **[ACE 架构设计](docs/ACE架构设计.md)** | 想学技术方案的人 — 系统全景 / VPS 部署 / sub-converter / DNS 设计 / 规则系统 / 多设备同步 |
| **[dev-skill（开发者日志）](docs/dev-skill.md)** | 开发者 / 维护者 — 每周新增功能 / 性能优化 / 踩坑分类 / VPS 迁移 playbook / 运维 cheatsheet |
| **[用户手册 user-guide](docs/用户手册%20user-guide.md)** | 普通用户 / 家人 — 手机 / 平板 / 电脑客户端安装 |

## 🚀 快速开始

### 新 VPS 部署（5 行命令，详见 [ACE 架构设计 §3](docs/ACE架构设计.md#3-vps-一键部署)）

```bash
ssh root@<VPS_IP>
git clone https://github.com/<you>/ace-vpn.git && cd ace-vpn
sudo AUTO_CONFIGURE=1 bash scripts/install.sh
# 浏览器改 3x-ui 面板密码/端口/path
sudo UPSTREAM_BASE='https://<VPS_IP>:2096/<sub_path>' \
     SUB_TOKENS='sub-hxn,sub-hxn01' \
     SERVER_OVERRIDE='<VPS_IP>' \
     bash scripts/install-sub-converter.sh
```

### 客户端接入（详见 [用户手册 user-guide](docs/用户手册%20user-guide.md)）

| 设备 | 软件 | 订阅 URL |
|------|------|---------|
| Mac | Mihomo Party | `http://<VPS_IP>:25500/clash/<SubId>` |
| Android 手机 / 平板 | FlClash 或 Clash Meta for Android（GitHub APK） | 同上 |
| iPhone / iPad | Stash（推荐）/ Shadowrocket | 同上（小火箭用 base64 订阅） |
| Windows | Clash Verge Rev | 同上 |

### 🏢 三网段分流（Mac 改 → VPS 热加载 → 全家同步）



详细技术方案：[ACE 架构设计](docs/ACE架构设计.md)（系统全景 / DNS 设计 / 规则系统 / 多设备同步）。日常使用：

```bash
cp private/intranet.yaml.example private/intranet.yaml
$EDITOR private/intranet.yaml      # 按公司分 profile，enabled: true/false 切换
bash scripts/sync-intranet.sh      # scp 到 VPS 的 /etc/ace-vpn/intranet.yaml

# 诊断：某个 URL 走哪条规则、哪组、延时多少
bash scripts/test-route.sh https://portal.corp-a.example/
```

- **换公司**：旧 profile `enabled: false`，新 profile `enabled: true`，再 sync 一次
- **多公司并存**：同时开多个 profile（外包 / 咨询场景）
- **VPS 热加载**：每次 HTTP 订阅请求自动重读 YAML，不用重启 systemd
- 客户端刷新订阅即生效（Mac / iPhone / Windows / Android）

### ⚡ 本地规则池（Mac 即时加规则，攒后批量推 VPS）

日常发现某个域名要走代理 / 直连 / 内网，不想每条都立刻惊动 VPS 和家人客户端：

```bash
# 加规则（秒级在本机生效，VPS 不动）—— TARGET = IN | DIRECT | VPS
bash scripts/add-rule.sh https://gitlab.corp-a.example/   IN     --note "内网 GitLab"
bash scripts/add-rule.sh https://claude-foo.example       VPS    --note "新 AI（走 VPS 出去）"
bash scripts/add-rule.sh https://misclassified-cn.example DIRECT --note "国内站被误判"

# 第 3 个位置参数可选：自定义 host（覆盖从 URL 自动解析的结果）
# 例：URL 解析出来是 aaa.api.corp-a.example，但你想加宽到整个 *.api.corp-a.example
bash scripts/add-rule.sh https://aaa.api.corp-a.example/x.dmg IN api.corp-a.example

bash scripts/list-rules.sh                  # 看积累了啥
bash scripts/promote-to-vps.sh --dry-run    # 预览批量推
bash scripts/promote-to-vps.sh              # 推 VPS + 清空本地池

# 出问题了？三层安全网保你 30 秒回到能上网的状态
bash scripts/rollback-overrides.sh --last     # 回退到最近一个备份
bash scripts/rollback-overrides.sh --disable  # 应急核选项：彻底禁用本地 override
```

机制：写入 `private/local-rules.yaml` → **pre-flight 校验**（坏规则永远写不进 override）→ **自动备份**当前 override → 渲染成 Mihomo Party 的 `override.yaml`（`+rules:` prepend，本地优先级最高）→ Mihomo GUI 秒级自动 reload。promote 时三种 target 全部入 `intranet.yaml`（`IN` → `profile.domains`、`VPS` → `extra.overseas`、`DIRECT` → `extra.cn`）→ scp VPS 热加载 → 全设备同步。详见 [user-guide §7](docs/用户手册%20user-guide.md#7-如何自定义新增-url-和规则) + [§9.4 安全网](docs/用户手册%20user-guide.md#94仅管理员安全网应急回退别让一条坏规则把自己的网砍了)。

> ⚠️ **Clash Party / Mihomo Party 用户必做一次性 DNS 配置修复**：默认
> `controlDns: true` 会把订阅的 DNS 段整块替换，导致 `fake-ip-filter` /
> `nameserver-policy` 失效，内网域名永远拿假 IP。一次性命令：
>
> ```bash
> sed -i '' 's/^controlDns: true$/controlDns: false/' \
>   ~/Library/Application\ Support/mihomo-party/config.yaml
> sed -i '' 's/^useNameserverPolicy: false$/useNameserverPolicy: true/' \
>   ~/Library/Application\ Support/mihomo-party/config.yaml
> # 重开 Clash Party
> ```
>
> 深度解析：[ACE 架构设计 §7 DNS 设计](docs/ACE架构设计.md#7-dns-设计) + [开发者日志 §4.A.1](docs/dev-skill.md#4a1-2026-04-19-mihomo-party-吞掉订阅的-dns-段-)

## 🔐 隐私分离

真实配置（`private/intranet.yaml` / `env.sh` / `credentials.txt`）在独立私有仓库
`ace-vpn-private` 维护，public 仓库通过 symlink 接入。**任何公司名 / 内网 IP /
DNS / 凭据都不会进本仓库 git 历史**。详见 [private/README.md](private/README.md)。

## ⚠️ 安全红线

- `private/` 下所有真实值强制 gitignore
- `docs/` `scripts/` `clients/` 不得出现真实 IP / UUID / pbk / token / 订阅 URL（用 `<VPS_IP>` / `<SUB_TOKENS>` 等占位）
- 面板端口 / 路径 / 账号**不得使用默认值**（2053 / admin / admin = 裸奔）
- 每 3–6 个月轮换 `SUB_TOKENS`
- 迁移后销毁旧 VPS 磁盘

## 📝 开发日志

- **2026-04-17** 项目启动；VPS 选型对比；Oracle 注册尝试（WAF 风控挂）
- **2026-04-17** Oracle Cloud Always Free 申请教程上线（`docs/Oracle Cloud 注册教程.md`），0 元方案就位
- **2026-04-17** Vultr Tokyo 验证部署；3x-ui + 客户端模板 + Cursor / Claude Code 代理打通
- **2026-04-18** `configure-3xui.sh` + `sub-converter.py` 完整链路打通；Mac / iPhone / Android 跑通 4K YouTube / Discord / Cursor；`sub-converter` 重构为多 token 单实例
- **2026-04-18** HostHatch Tokyo 付费方案（$4/月）上线；**Vultr → HostHatch 整库迁移**，pbk / sid / UUID 全保留，家人端仅改 IP
- **2026-04-18** 文档瘦身：多份 00-09 doc 合并为 `docs/dev-skill.md` + `docs/用户手册 user-guide.md` 两份
- **2026-04-19** 内网分流重构：`private/intranet.yaml` 多 profile + `enabled` 开关，`sync-intranet.sh` 一键 scp，VPS 端热加载无需重启。支持「换公司」/「多公司并存」零配置切换
- **2026-04-19** sub-converter 新增 `/match` 权威匹配接口 + `scripts/test-route.sh` 诊断工具，一行命令输出 URL 走哪条规则、经哪个代理组、各阶段延时
- **2026-04-19** per-profile `dns_servers` 定向解析；修复 Clash Party GUI 吞订阅 DNS 的深坑（详见 [ACE 架构设计 §7 DNS 设计](docs/ACE架构设计.md#7-dns-设计)）
- **2026-04-19** 公私仓库分离：新增 `docs/ACE架构设计.md`（对外技术方案，含架构 / 流程 / 时序图）；真实配置迁入私有仓库 `ace-vpn-private`，public 仓库通过 symlink 接入
- **2026-04-23** 本地规则三层安全网：`add-rule.sh` / `apply-local-overrides.sh` 写 override 前 pre-flight 校验本地池里所有 `VPS` 类规则的 proxy group 在当前 active profile 里存在；坏规则直接拒写、网络不受影响。每次写入前自动备份旧 override 到 `override/.bak/`（保留最近 10 个）。新增 `rollback-overrides.sh` 一键回退（`--last` / `--disable` / `--clear` / 交互选）。详见 [user-guide §9.4](docs/用户手册%20user-guide.md#94仅管理员安全网应急回退别让一条坏规则把自己的网砍了)
- **2026-04-21** 本地规则池工作流：`add-rule.sh` / `list-rules.sh` / `apply-local-overrides.sh` / `promote-to-vps.sh` 四脚本闭环。Mac 单机加规则秒级生效（渲染 Mihomo Party `override.yaml` 的 `+rules` prepend），积累后批量 promote 进 `intranet.yaml` 推 VPS 同步全设备。本地池 `local-rules.yaml` 由 private 仓库托管，多 Mac 之间通过 git pull 同步
- **2026-04-21** sub-converter 扩展 `intranet.yaml` 顶层 `extra: {overseas, cn}`，promote 闭环补完：三种 target 全部能 promote 到 VPS 全设备共享；extra 在内置 AI / SOCIAL_PROXY / CHINA_DIRECT 之前 prepend，用户手加规则永远赢内置默认；`/healthz` 暴露 extra 计数便于验证
- **2026-04-21** target 命名从 `intranet/cn/overseas` 改成更直观的 `IN/DIRECT/VPS`（用户视角：内网 / 直连 / 经过 VPS）；大小写无关 + 老名兼容自动归一；用户手册顶部加亮点功能索引
- **2026-04-23** WARP 备选方案实战跑通后弃用（HostHatch JP 当前 IP 没被 Google 封）；`fscarmen/warp` Non-global 接入 + Xray `outbounds[0]=direct` + 第一条 routing 把 VPS 自身 `/32` 强制 `direct`，避免 SSH 自指环路；改 xray 必须改 `/etc/x-ui/x-ui.db` 的 `xrayTemplateConfig`（直接编 `config.json` 会被 systemctl restart 回滚）。完整流程精简版沉淀进 [dev-skill §5 WARP 备选方案](docs/dev-skill.md#5-warp-备选方案cloudflare-warp-outbound)
- **2026-04-24** intranet schema 重构：明确"真·内网 / SaaS / 零信任网关"三类域名分类，`profiles.<>.domains` 只放公网解不到的内网域名，公网公司域名（SaaS 应用、零信任网关后挂的内部服务）改放 `extra.cn`。`sub-converter.py` 给 `extra.cn` 强制配国内 UDP 公网 DNS（`119.29.29.29` + `223.5.5.5`），并加进 `fake-ip-filter`，避免默认 DoH 经海外 PROXY 解析到海外 CDN 节点 IP 导致 TLS 握手卡死。`promote-to-vps.sh` 默认 local-wins + 冲突日志，`sync-intranet.sh` VPS 端自动滚动备份最近 5 份 `intranet.yaml`。详见 [ACE 架构设计 §7 DNS 设计](docs/ACE架构设计.md#7-dns-设计) + [开发者日志 §4.A.6/4.A.7/4.A.8](docs/dev-skill.md#4a6-2026-04-24-把零信任--saas-公网域名误当成真内网域名-)
- **2026-04-25** 文档体系重构：`dev-skill.md` 改为"开发者日志"（按"新增功能 / 性能优化 / 踩坑分类"组织 14 个功能时间线 + 7 项性能优化 + 16 个踩坑按 DNS / 部署 / 客户端三类归档）；`ACE架构设计.md` 改为"ACE 架构设计"（吸收 VPS 选型 / 部署 / sub-converter / 客户端分发 / DNS / 规则系统 / 多设备同步等系统级章节，新增「规则系统：更新/同步/冲突」「多设备/多云端同步」两节专门讲 add-rule → promote → sync 流水线和多 Mac / 多 VPS 协作）

## 📄 许可

个人项目，MIT（代码层面）。运行时配置、家庭部署信息不开源。
