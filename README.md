# ACE-VPN

> **Always Free 私人 VPN 解决方案 · 白嫖 Oracle Cloud· 安全打通公司内网 / 海内 / 海外三段网络 · 全球 AI 无障碍。**
> <br>**本项目纯属技术研究，不存在其他目的，特此声明。**

**普通用户直接跳转：[用户手册 user-guide](docs/用户手册%20user-guide.md)**

Xray + Reality 自建，2–5 人家庭共享。**公司内网 DIRECT · 大陆公网直连 · 海外走代理**，客户端一次订阅全自动。

| 方案 | 费用 | 说明 |
|------|------|------|
| **白嫖** | 永久 0 元 | [Oracle Cloud Always Free ARM](docs/Oracle%20Cloud%20注册教程.md) · 4C / 24G / 10TB 流量 |
| **付费** | $6/月起 | Vultr Tokyo 现役 · HostHatch/其它 VPS 可按同一迁移流程替换 |
| **源码** | 免费 | MIT · 整套部署脚本 + 四端客户端模板 |

👉 想 0 元起步：[Oracle Cloud Always Free 申请教程（含风控踩坑）](docs/Oracle%20Cloud%20注册教程.md)

## 📍 当前状态

生产 **Vultr Tokyo ✅ (`<VPS_IP>`)** · 协议栈 **VLESS + Reality + 3x-ui + 自研 Python sub-converter** · 已接入 Mac / iPhone / Android / Windows，客户端刷新订阅自动同步规则

## 📚 文档

| 文档 | 给谁看 |
|------|--------|
| **[ACE 宪法](docs/ACE宪法.md)** | 维护者 — 项目不变式 / 文档职责 / 变更前检查表 |
| **[Oracle Cloud 注册教程](docs/Oracle%20Cloud%20注册教程.md)** | 想 0 元白嫖的人 — Oracle Cloud Always Free 申请全教程 |
| **[ACE 架构设计](docs/ACE架构设计.md)** | 想学技术方案的人 — 系统全景 / VPS 部署 / sub-converter / DNS 设计 / 规则系统 / 多设备同步 |
| **[开发者日志](docs/开发者日志.md)** | 开发者 / 维护者 — 每周新增功能 / 性能优化 / 踩坑分类 / VPS 迁移 playbook / 运维 cheatsheet |
| **[用户手册 user-guide](docs/用户手册%20user-guide.md)** | 普通用户 / 家人 — 手机 / 平板 / 电脑客户端安装 |

## 🚀 快速开始

### 新 VPS 部署（5 行命令，详见 [ACE 架构设计 §3](docs/ACE架构设计.md#3-vps-一键部署)）

```bash
ssh root@<VPS_IP>
git clone https://github.com/<you>/ace-vpn.git && cd ace-vpn
sudo AUTO_CONFIGURE=1 bash scripts/deploy/install.sh
# 用 SSH 隧道登录 3x-ui 面板，改密码/端口/path
sudo UPSTREAM_BASE='https://127.0.0.1:2096/<sub_path>' \
     SUB_TOKENS='ace-main,ace-fork' \
     TUN_TOKENS='ace-main,ace-fork' \
     SERVER_OVERRIDE='<VPS_IP>' \
     bash scripts/deploy/install-sub-converter.sh
```

### 客户端接入（详见 [用户手册 user-guide](docs/用户手册%20user-guide.md)）

Mac 首次接入 / 换 VPS 后，如果本机还没法翻墙，先用 SSH 带外导入 Mihomo Party 配置：

```bash
bash scripts/common-tools/bootstrap-mihomo-party.sh --replace-current
```

| 设备 | 软件 | 订阅 URL |
|------|------|---------|
| Mac | Mihomo Party | `http://<VPS_IP>:25500/<SUB_PATH_PREFIX>/<SubId>` |
| Android 手机 / 平板 | FlClash 或 Clash Meta for Android（GitHub APK） | 同上 |
| iPhone / iPad | Stash（推荐）/ Shadowrocket | 同上（小火箭用 base64 订阅） |
| Windows | Clash Verge Rev | 同上 |

Windows / 家人端第一次把旧 URL 替换成新的 `ace-fork` URL；之后只需要点"更新订阅"。订阅端口是 IP 直连，刷新本身不需要翻墙。上线前可在 Mac 上做直连烟测：

```bash
bash scripts/test/subscription-smoke.sh --direct
```

### 🏢 三网段分流（Mac 改 → VPS 热加载 → 全家同步）



详细技术方案：[ACE 架构设计](docs/ACE架构设计.md)（系统全景 / DNS 设计 / 规则系统 / 多设备同步）。日常使用：

```bash
cp private/intranet.yaml.example private/intranet.yaml
$EDITOR private/intranet.yaml      # 按公司分 profile，enabled: true/false 切换
bash scripts/rules/sync-intranet.sh      # scp 到 VPS 的 /etc/ace-vpn/intranet.yaml

# 诊断：某个 URL 走哪条规则、哪组、延时多少
bash scripts/test/test-route.sh https://portal.corp-a.example/
```

- **换公司**：旧 profile `enabled: false`，新 profile `enabled: true`，再 sync 一次
- **多公司并存**：同时开多个 profile（外包 / 咨询场景）
- **VPS 热加载**：每次 HTTP 订阅请求自动重读 YAML，不用重启 systemd
- 客户端刷新订阅即生效（Mac / iPhone / Windows / Android）

### 🛡️ 更新服务端代码（`sub-converter.py`）— 带 validator、滚动备份、自动回滚

改完本地 `scripts/server/sub-converter.py` 别直接 scp，用**安全推送脚本**（推前 3 关 + 推后 3 关 + 5 份滚动备份 + 失败自动回滚）：

```bash
# 本地三层预校验（py_compile + dry import + 语义 validator），不推远端
bash scripts/rules/sync-subconverter.sh --dry-run

# 推全部 VPS（每台备份当前版 → 原子替换 → restart → healthz → 拉真实 YAML 再校验）
bash scripts/rules/sync-subconverter.sh

# 只推某一台
bash scripts/rules/sync-subconverter.sh --vps vultr

# 改坏了从备份一键回滚（不用 git 不用 scp）
bash scripts/rules/sync-subconverter.sh --rollback

# 独立跑 validator，校验任意一份 mihomo YAML 配置
python3 scripts/server/validate-config.py <yaml-file>          # 文件模式
curl -s http://<VPS>:25500/<SUB_PATH_PREFIX>/<tok> | python3 \
  scripts/server/validate-config.py -                           # pipe 模式
```

validator 覆盖的 mihomo 字段联动硬校验（截至 2026-04-28）：`respect-rules ↔ proxy-server-nameserver` / `fake-ip ↔ fake-ip-range` / `default-nameserver 必须是 IP` / `proxy-groups & rules 引用的 target 存在` / `MATCH 兜底` 等 —— 专门拦"语法对但语义错"的组合，详见 [开发者日志 §2.-1](docs/开发者日志.md#2-1-2026-04-28-晚-安全推送工具链validate-configpy--sync-subconvertersh5-份滚动备份--自动回滚) + [§4.C.5](docs/开发者日志.md#4c5-2026-04-28-sub-converterpy-推送无备份无校验--改坏--全军覆没-)。

### 🧰 统一脚本入口

日常可以只记一个入口，底层脚本仍保留给部署、定时任务和回滚使用：

```bash
bash scripts/ace-vpn.sh help
bash scripts/ace-vpn.sh route https://www.forbes.com/
bash scripts/ace-vpn.sh add waimai.meituan.com DIRECT --note "Meituan"
bash scripts/ace-vpn.sh smoke --direct
bash scripts/ace-vpn.sh report
```

### 📊 本地流量月报（可选）

月报从本机 Mihomo API 采集，默认只记录域名、规则、链路、来源 IP、进程名和流量；不做 HTTPS 解密，也不保存完整 URL path。采集器是单独后台进程，不在代理数据路径里；默认 30 秒轮询、低优先级运行，避免影响上网速度。

```bash
# 手动采一轮，确认 Mihomo external-controller 可读
python3 scripts/telemetry/mihomo-traffic-collector.py --once

# macOS 自动常驻采集
cp scripts/launchd/ace-vpn.mihomo-traffic-collector.example.plist \
  ~/Library/LaunchAgents/com.xiaonancs.ace-vpn.mihomo-traffic-collector.plist
sed -i '' -e "s#__REPO_ROOT__#$(pwd)#g" -e "s#__HOME__#$HOME#g" \
  ~/Library/LaunchAgents/com.xiaonancs.ace-vpn.mihomo-traffic-collector.plist
launchctl load ~/Library/LaunchAgents/com.xiaonancs.ace-vpn.mihomo-traffic-collector.plist
launchctl start com.xiaonancs.ace-vpn.mihomo-traffic-collector

# 生成当月汇总；如需明细 CSV，追加 --details-csv ~/Desktop/traffic.csv
python3 scripts/telemetry/monthly-traffic-report.py
```

如果要统计"来源于哪个 App"，订阅 URL 可给自己的设备追加 `?process=1`。默认保持 `find-process-mode: off`，优先保证速度和隐私。
如果采集器返回 401，在 Mihomo 客户端设置里查看 external-controller secret，填进 LaunchAgent 的 `MIHOMO_SECRET`。

### ⚡ 本地规则池（Mac 即时加规则，攒后批量推 VPS）

日常发现某个域名要走代理 / 直连 / 内网，不想每条都立刻惊动 VPS 和家人客户端：

```bash
# 加规则（秒级在本机生效，VPS 不动）—— TARGET = IN | DIRECT | VPS
bash scripts/rules/add-rule.sh https://gitlab.corp-a.example/   IN     --note "内网 GitLab"
bash scripts/rules/add-rule.sh https://claude-foo.example       VPS    --note "新 AI（走 VPS 出去）"
bash scripts/rules/add-rule.sh https://misclassified-cn.example DIRECT --note "国内站被误判"

# 第 3 个位置参数可选：自定义 host（覆盖从 URL 自动解析的结果）
# 例：URL 解析出来是 aaa.api.corp-a.example，但你想加宽到整个 *.api.corp-a.example
bash scripts/rules/add-rule.sh https://aaa.api.corp-a.example/x.dmg IN api.corp-a.example

bash scripts/rules/list-rules.sh                  # 看积累了啥
bash scripts/rules/promote-to-vps.sh --dry-run    # 预览批量推
bash scripts/rules/promote-to-vps.sh              # 推 VPS + 清空本地池

# 出问题了？三层安全网保你 30 秒回到能上网的状态
bash scripts/rules/rollback-overrides.sh --last     # 回退到最近一个备份
bash scripts/rules/rollback-overrides.sh --disable  # 应急核选项：彻底禁用本地 override
```

机制：写入 `private/local-rules.yaml` → **pre-flight 校验**（坏规则永远写不进 override）→ **自动备份**当前 override → 渲染成 Mihomo Party 的 `override.yaml`（`+rules:` prepend，本地优先级最高）→ Mihomo GUI 秒级自动 reload。promote 时三种 target 全部入 `intranet.yaml`（`IN` → `profile.domains`、`VPS` → `extra.overseas`、`DIRECT` → `extra.cn`）→ scp VPS 热加载 → 全设备同步。详见 [user-guide §7](docs/用户手册%20user-guide.md#7-如何自定义新增-url-和规则) + [§9.4 安全网](docs/用户手册%20user-guide.md#94仅管理员安全网应急回退别让一条坏规则把自己的网砍了)。

内置路由有回归测试，改规则后先跑：

```bash
python3 scripts/test/route-regression.py
```

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
> 深度解析：[ACE 架构设计 §7 DNS 设计](docs/ACE架构设计.md#7-dns-设计) + [开发者日志 §4.A.1](docs/开发者日志.md#4a1-2026-04-19-mihomo-party-吞掉订阅的-dns-段-)

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
- 流量统计只保留本地 SQLite，不上传到 VPS；需要分享报表时先确认 CSV 中没有敏感公司域名

## 📝 开发日志

- **2026-04-17** 项目启动；VPS 选型对比；Oracle 注册尝试（WAF 风控挂）
- **2026-04-17** Oracle Cloud Always Free 申请教程上线（`docs/Oracle Cloud 注册教程.md`），0 元方案就位
- **2026-04-17** Vultr Tokyo 验证部署；3x-ui + 客户端模板 + Cursor / Claude Code 代理打通
- **2026-04-18** `configure-3xui.sh` + `sub-converter.py` 完整链路打通；Mac / iPhone / Android 跑通 4K YouTube / Discord / Cursor；`sub-converter` 重构为多 token 单实例
- **2026-04-18** HostHatch Tokyo 付费方案（$4/月）上线；**Vultr → HostHatch 整库迁移**，pbk / sid / UUID 全保留，家人端仅改 IP
- **2026-06-13** 现网回到 Vultr Tokyo `<VPS_IP>`；私有配置只保留 `vultr:<VPS_IP>`，订阅路径统一为 `/<SUB_PATH_PREFIX>/ace-main` / `ace-fork`
- **2026-06-14** 扩展手机 App / 英文媒体 / AI 分流规则，新增本地流量月报和 `scripts/ace-vpn.sh` 统一入口；Vultr Tokyo 已通过安全推送和订阅烟测
- **2026-04-18** 文档瘦身：多份 00-09 doc 合并为 `docs/开发者日志.md` + `docs/用户手册 user-guide.md` 两份
- **2026-04-19** 内网分流重构：`private/intranet.yaml` 多 profile + `enabled` 开关，`sync-intranet.sh` 一键 scp，VPS 端热加载无需重启。支持「换公司」/「多公司并存」零配置切换
- **2026-04-19** sub-converter 新增 `/match` 权威匹配接口 + `scripts/test/test-route.sh` 诊断工具，一行命令输出 URL 走哪条规则、经哪个代理组、各阶段延时
- **2026-04-19** per-profile `dns_servers` 定向解析；修复 Clash Party GUI 吞订阅 DNS 的深坑（详见 [ACE 架构设计 §7 DNS 设计](docs/ACE架构设计.md#7-dns-设计)）
- **2026-04-19** 公私仓库分离：新增 `docs/ACE架构设计.md`（对外技术方案，含架构 / 流程 / 时序图）；真实配置迁入私有仓库 `ace-vpn-private`，public 仓库通过 symlink 接入
- **2026-04-23** 本地规则三层安全网：`add-rule.sh` / `apply-local-overrides.sh` 写 override 前 pre-flight 校验本地池里所有 `VPS` 类规则的 proxy group 在当前 active profile 里存在；坏规则直接拒写、网络不受影响。每次写入前自动备份旧 override 到 `override/.bak/`（保留最近 10 个）。新增 `rollback-overrides.sh` 一键回退（`--last` / `--disable` / `--clear` / 交互选）。详见 [user-guide §9.4](docs/用户手册%20user-guide.md#94仅管理员安全网应急回退别让一条坏规则把自己的网砍了)
- **2026-04-21** 本地规则池工作流：`add-rule.sh` / `list-rules.sh` / `apply-local-overrides.sh` / `promote-to-vps.sh` 四脚本闭环。Mac 单机加规则秒级生效（渲染 Mihomo Party `override.yaml` 的 `+rules` prepend），积累后批量 promote 进 `intranet.yaml` 推 VPS 同步全设备。本地池 `local-rules.yaml` 由 private 仓库托管，多 Mac 之间通过 git pull 同步
- **2026-04-21** sub-converter 扩展 `intranet.yaml` 顶层 `extra: {overseas, cn}`，promote 闭环补完：三种 target 全部能 promote 到 VPS 全设备共享；extra 在内置 AI / SOCIAL_PROXY / CHINA_DIRECT 之前 prepend，用户手加规则永远赢内置默认；`/healthz` 暴露 extra 计数便于验证
- **2026-04-21** target 命名从 `intranet/cn/overseas` 改成更直观的 `IN/DIRECT/VPS`（用户视角：内网 / 直连 / 经过 VPS）；大小写无关 + 老名兼容自动归一；用户手册顶部加亮点功能索引
- **2026-04-23** WARP 备选方案实战跑通后弃用（HostHatch JP 当前 IP 没被 Google 封）；`fscarmen/warp` Non-global 接入 + Xray `outbounds[0]=direct` + 第一条 routing 把 VPS 自身 `/32` 强制 `direct`，避免 SSH 自指环路；改 xray 必须改 `/etc/x-ui/x-ui.db` 的 `xrayTemplateConfig`（直接编 `config.json` 会被 systemctl restart 回滚）。完整流程精简版沉淀进 [开发者日志 §5 WARP 备选方案](docs/开发者日志.md#5-warp-备选方案cloudflare-warp-outbound)
- **2026-04-24** intranet schema 重构：明确"真·内网 / SaaS / 零信任网关"三类域名分类，`profiles.<>.domains` 只放公网解不到的内网域名，公网公司域名（SaaS 应用、零信任网关后挂的内部服务）改放 `extra.cn`。`sub-converter.py` 给 `extra.cn` 强制配国内 UDP 公网 DNS（`119.29.29.29` + `223.5.5.5`），并加进 `fake-ip-filter`，避免默认 DoH 经海外 PROXY 解析到海外 CDN 节点 IP 导致 TLS 握手卡死。`promote-to-vps.sh` 默认 local-wins + 冲突日志，`sync-intranet.sh` VPS 端自动滚动备份最近 5 份 `intranet.yaml`。详见 [ACE 架构设计 §7 DNS 设计](docs/ACE架构设计.md#7-dns-设计) + [开发者日志 §4.A.6/4.A.7/4.A.8](docs/开发者日志.md#4a6-2026-04-24-把零信任--saas-公网域名误当成真内网域名-)
- **2026-04-25** 文档体系重构：`开发者日志.md` 改为"开发者日志"（按"新增功能 / 性能优化 / 踩坑分类"组织 14 个功能时间线 + 7 项性能优化 + 16 个踩坑按 DNS / 部署 / 客户端三类归档）；`ACE架构设计.md` 改为"ACE 架构设计"（吸收 VPS 选型 / 部署 / sub-converter / 客户端分发 / DNS / 规则系统 / 多设备同步等系统级章节，新增「规则系统：更新/同步/冲突」「多设备/多云端同步」两节专门讲 add-rule → promote → sync 流水线和多 Mac / 多 VPS 协作）
- **2026-04-28** AI 长流式响应稳定性修复：`sub-converter.py` 新增 `OVERSEAS_DOH` + `AI_STREAMING_DOMAINS` 常量，覆盖 Cursor / Claude Code / Codex / OpenCode / Gemini / Copilot / Perplexity / Mistral / DeepSeek 等主流 AI 域名，强制 DNS 走境外 DoH（`1.1.1.1` / `8.8.8.8` / `dns.cloudflare.com`）+ 加入 `fake-ip-filter` 防假 IP 缓存；新增顶层 `sniffer` 段（HTTP/TLS/QUIC `override-destination: true`），修复 fake-ip 模式下 Cursor agent 长流偶发的 "SNI mismatch → RST" 断连；`dns.respect-rules: true` 让 DNS 解析遵从 rules 分流决策。所有 mihomo 端（Mac / iPhone / 家人端）刷订阅即生效，不依赖客户端 override。详见 [开发者日志 §4.A.9](docs/开发者日志.md#4a9-2026-04-28-cursor--claude-code--codex-等-ai-长流式响应被-dns-污染断连-)
- **2026-04-28 晚** 安全推送工具链：新增 `scripts/server/validate-config.py`（独立的 mihomo YAML 语义校验器，拦 `respect-rules` ↔ `proxy-server-nameserver` 等联动问题）+ `scripts/rules/sync-subconverter.sh`（推前本地三关校验 + 远端 5 份滚动备份 + 原子替换 + 推后 healthz + YAML 二次校验 + 任一失败自动回滚 + `--rollback` 独立模式）。新增 `PROXY_SERVER_DNS` 常量修复 `respect-rules: true` 下缺 `proxy-server-nameserver` 导致客户端 `Profile Check Failed` 的 bug。从此 `sub-converter.py` 推送永远不会留下"改坏了、回不去了"的 VPS。详见 [开发者日志 §2.-1](docs/开发者日志.md#2-1-2026-04-28-晚-安全推送工具链validate-configpy--sync-subconvertersh5-份滚动备份--自动回滚) + [§4.A.10](docs/开发者日志.md#4a10-2026-04-28-respect-rules-true-必须配-proxy-server-nameserver4a9-的后续坑-) + [§4.C.5](docs/开发者日志.md#4c5-2026-04-28-sub-converterpy-推送无备份无校验--改坏--全军覆没-)

## 📄 许可

个人项目，MIT（代码层面，见 [LICENSE](LICENSE)）。运行时配置、家庭部署信息不开源。
