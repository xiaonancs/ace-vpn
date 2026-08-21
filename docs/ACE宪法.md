# ACE 宪法

> 本文件定义 ace-vpn 的长期不变式。脚本可以迭代，VPS 可以迁移，客户端可以换，但这里列出的目标、边界、安全规则和文档同步规则必须保持稳定。任何改动如果违反本文件，必须先改宪法并说明理由。

---

## 1. 项目目标

ace-vpn 是一套家庭自建网络分流系统，不只是一个节点配置仓库。它服务 2-5 人家庭，目标是：

- 海外服务稳定可用，尤其是 Cursor / Claude / ChatGPT / Gemini / YouTube。
- 国内公网直连，不让抖音、淘宝、B 站、银行、政务站被代理拖慢或触发风控。
- 公司内网交给公司 VPN / 系统路由处理，ace-vpn 不接管本不该接管的内网流量。
- 换 VPS、换 IP、换设备时，管理员能在 15 分钟内恢复自己，家人只做最少操作。
- 所有真实凭据、公司域名、内网 IP、token 都留在私有仓库，不进入公开仓库历史。

---

## 2. 核心不变式

### 2.1 三网段模型

所有规则最终只能落到三类目标：

| 目标 | 含义 | 典型内容 |
|---|---|---|
| `IN` | 公司内网，客户端规则为 `DIRECT`，由公司 VPN / 系统路由接管 | 私有 CIDR、内网域名、只有公司 DNS 能解析的 host |
| `DIRECT` | 国内公网直连 | 国内 SaaS、国内 CDN、企业零信任公网入口、误判为海外的中文站 |
| `VPS` | 经过 ace-vpn 出口 | AI、GitHub、YouTube、Discord、海外 API |

新增 target 名称必须有明确收益；仅为了代码好看不得增加第四类。

### 2.2 源头配置

| 数据 | 事实源 | 说明 |
|---|---|---|
| 代码、脚本、公开文档 | public 仓库 `ace-vpn` | 可开源、必须脱敏 |
| 真实 VPS、token、公司规则 | private 仓库 `ace-vpn-private` | 通过 symlink 挂到 `private/` |
| 远端运行参数 | VPS 上 `ace-vpn-sub.service` | `LISTEN_PORT`、`SUB_PATH_PREFIX`、`SUB_TOKENS` 以远端为准 |
| 客户端当前 profile | Mihomo Party `profile.yaml` + `profiles/<id>.yaml` | 可能落后于远端；不得作为服务端事实源 |
| 本机临时规则 | `private/local-rules.yaml` | 本机优先生效，promote 后才进入全家共享 |

### 2.3 订阅路径

公网 Clash YAML 订阅路径一律视为：

```text
http://<VPS_IP>:25500/<SUB_PATH_PREFIX>/<SubId>
```

`/clash/<token>` 只作为历史兼容示例出现；新增文档、脚本提示和校验都必须使用 `/<SUB_PATH_PREFIX>/<SubId>`。

### 2.4 客户端恢复通道

第一次安装、换 VPS、换 IP、Party 自身更新死锁时，客户端不能依赖“先翻墙再更新配置”。当前约束：

1. 不再提供脚本直接写入 Mihomo Party 本地 profile 的冷启动导入链路。
2. 客户端 profile URL 变更走手动 Remote Profile 编辑 / 新建。
3. 本机异常先跑 `bash scripts/ace-vpn.sh party`，必要时 `bash scripts/ace-vpn.sh party --fix` 清理多个 core、socket、root-owned cache。
4. 若 SSH key 未授权，必须先修 SSH；SSH 只用于部署/同步 VPS，不用于自动改本机 profile。

### 2.5 安全推送

会影响数据面的改动必须满足：

1. 推前本地校验。
2. 远端滚动备份。
3. 原子替换。
4. 推后 healthz / 订阅 YAML 校验。
5. 失败可回滚，且回滚不依赖 GitHub 或 Clash 可用。

`sub-converter.py`、`intranet.yaml`、Mihomo override 都属于数据面配置。

### 2.6 流量统计边界

流量统计只能作为本地观测面，不得进入代理数据面：

- 采集器必须是独立后台进程，不能阻塞或代理真实网络连接。
- 默认关闭进程归因；只有管理员自己的订阅显式加 `?process=1` 时，才允许开启 `find-process-mode`。
- 不做 HTTPS 解密，不保存完整 URL path，只记录 Mihomo API 能看到的 host、规则、链路、来源 IP、进程名、时长和流量。
- SQLite / CSV 默认留在本机；分享报表前必须确认没有真实公司域名、内网 IP、token 或可识别家人隐私的数据。
- 为了追求统计完整性而影响上网速度，视为违反本项目目标。

---

## 3. 运行与排障准则

### 3.1 排障顺序

遇到“Clash 不能用”时按这个顺序，不要跳步：

1. `bash scripts/test/doctor.sh`
2. 看当前 Party profile 是否仍指向旧 VPS。
3. 看 SSH 是否可达，区分 host key 冲突、key 未授权、网络不通。
4. 手动核对 Mihomo Party 当前 Remote Profile URL 是否指向新 VPS。
5. 运行 `bash scripts/ace-vpn.sh party` 检查多个 core、端口/TUN/cache 和关键域名。
6. 必要时运行 `bash scripts/ace-vpn.sh party --fix`，重启 Mihomo Party，再看 7890 出口和 TUN 出口。
7. 公司 VPN 开着时，优先接受“7890 可用、TUN 不接管系统路由”的现实；要全局 TUN，先退出公司 VPN。

### 3.2 SSH 前置修复

| 症状 | 含义 | 修复 |
|---|---|---|
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | `known_hosts` 里是旧主机指纹 | 确认 IP 属于自己后，`ssh-keygen -R <VPS_IP>` |
| `Permission denied (publickey,password)` | VPS 没授权当前公钥 | `ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<VPS_IP>` |
| TCP 超时 | 网络/防火墙/GFW/公司 VPN 阻断 | 换网络、关公司 VPN、检查云防火墙和 VPS UFW |

### 3.3 客户端 TUN 准则

- Mac 开发机推荐 TUN，因为 Cursor、终端、Docker、CLI 工具可能绕过系统代理。
- 家人设备优先简单可用，能用系统代理/应用 VPN 就不要暴露复杂设置。
- 公司 VPN 和 Mihomo TUN 争默认路由时，不强求共存；必要时用显式 `7890`。

---

## 4. 文档职责边界

| 文档 | 职责 | 不该放什么 |
|---|---|---|
| `README.md` | 项目首页、当前状态、最短入口、文档导航 | 长篇事故复盘、完整脚本参数、重复的用户教程 |
| `docs/ACE宪法.md` | 项目不变式、变更规则、文档治理 | 每次事故的细节流水账 |
| `docs/ACE架构设计.md` | 系统设计、组件关系、数据流、关键技术取舍 | 面向家人的逐步截图式教程 |
| `docs/开发者日志.md` | 按日期记录“做了什么 / 学到什么 / 坑怎么填” | 当前唯一正确操作入口；过期命令要指向新文档 |
| `docs/用户手册 user-guide.md` | 普通用户 + 管理员日常操作手册 | 深层实现解释、完整历史记录 |
| `scripts/README.md` | 脚本索引、脚本级工作流、参数速查 | 项目愿景、历史复盘 |
| `private/*.example` | 脱敏模板，保证新环境能填 | 真实 IP、真实 token、真实公司名 |

### 4.1 文档同步矩阵

改动触及以下内容时，必须同步对应文档：

| 改动类型 | 必改文档 |
|---|---|
| 新脚本 / 脚本参数 | `scripts/README.md`、相关用户手册章节、开发者日志 |
| 订阅 URL / token / 端口 / 环境变量 | README、架构设计、用户手册、`private/*.example` |
| 排障流程 | 用户手册 FAQ、scripts README、开发者日志踩坑 |
| 架构不变式 | ACE 宪法、ACE 架构设计 |
| 敏感信息规则 | ACE 宪法、README 安全红线、private README |

### 4.2 去冗余规则

- 同一条命令只保留一个“权威解释”，其他文档只放最短入口和链接。
- README 只放 1-2 个最短路径，不复制用户手册整段。
- 开发者日志记录历史，但过期命令必须标注“历史兼容”或改成引用当前文档。
- 用户手册里家人章节和管理员章节分开；管理员长篇运维如果超过 80 行，优先迁到架构设计或脚本 README。

---

## 5. 变更前检查表

提交前至少过一遍：

- 是否引入真实 IP、token、UUID、公司域名、内网 DNS。
- 是否改变了 `/<SUB_PATH_PREFIX>/<SubId>`、`SUB_TOKENS`、`TUN_TOKENS`、`SERVER_OVERRIDE` 的语义。
- 是否影响首次安装 / 冷启动 / 换 VPS 后恢复。
- 是否有 `--dry-run` 或只读诊断路径。
- 是否有回滚路径。
- 是否更新了文档同步矩阵要求的文档。
- 是否跑过 `bash -n`、`git diff --check`，涉及 YAML 时跑 `validate-config.py`。

---

## 6. 当前优先级

1. 先保证管理员自己的 Mac 可恢复：SSH key 可达、`bash scripts/ace-vpn.sh party` 可诊断、本机 Party profile 指向主 VPS。
2. 再保证订阅服务安全：随机 `SUB_PATH_PREFIX`、面板和 3x-ui 原生订阅不公网暴露。
3. 再保证家人端少改：SubId 稳定，必要时只换 URL 的 IP / path。
4. 最后优化性能和体验：AI 分组、测速、长期 watch、自动 fallback。
