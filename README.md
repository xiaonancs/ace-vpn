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

## 📄 许可

个人项目，MIT（代码层面，见 [LICENSE](LICENSE)）。运行时配置、家庭部署信息不开源。
