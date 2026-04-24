# WARP 升级备选方案 & 2026-04-23 实战复盘

> 把 Cloudflare WARP 接入 hosthatch JP 节点的完整流程，作为**未来真的需要**时的备选方案保留。
> 同时附本次"以为 IP 被封 → 一通操作 → 发现没被封"踩坑全记录。
>
> 关键判定：**hosthatch 的 IP 没被 Google 封**，今天加 WARP 是过度反应。但流程已跑通，知识沉淀在此，未来一旦真被封可以照做。

---

## 目录

1. [什么时候才真的需要 WARP](#1-什么时候才真的需要-warp)
2. [如何判定一个 IP 是否被 Google AI 封了](#2-如何判定一个-ip-是否被-google-ai-封了)
3. [WARP 接入完整流程（hosthatch 实战）](#3-warp-接入完整流程hosthatch-实战)
4. [Xray 路由规则模板](#4-xray-路由规则模板)
5. [3x-ui 数据库覆盖坑（必读）](#5-3x-ui-数据库覆盖坑必读)
6. [WARP 弃用流程（如果你装了又想拆）](#6-warp-弃用流程如果你装了又想拆)
7. [本次实战教训汇总](#7-本次实战教训汇总)

---

## 1. 什么时候才真的需要 WARP

WARP 的本质是 **借 Cloudflare 的 IP 帮你出口访问**：
- 你 mac → hosthatch JP → Cloudflare WARP → Google
- 出口 IP 变成 cloudflare 段（104.28.x.x 之类）
- 不再使用 hosthatch 的原始数据中心 IP

**真正需要 WARP 的两种场景**：

| 场景 | 判定方法 |
|------|----------|
| ① VPS 的 IP 被 Google 标记为不支持地区 | 浏览器无痕窗口 + 干净 Google 账号访问 https://gemini.google.com，弹"Gemini isn't currently supported in your country" |
| ② VPS 出口到 Google 的物理路由完全不通 | `curl https://gemini.google.com/` 直接 timeout（不是慢，是连不上） |

**不需要 WARP 的场景（关键！）**：
- 直出能拿到 200 + 完整 HTML（哪怕慢） → IP 没被封，是路由慢，WARP 救不了路由慢
- 浏览器报错"isn't supported in your country"但 curl 能 200 → 是 **Google 账号绑定地区**问题，跟 IP 无关，WARP 也救不了

**判定 IP 是否被封的 SOP 见第 2 节**。

---

## 2. 如何判定一个 IP 是否被 Google AI 封了

`curl` 拿 HTML 看关键词比浏览器更可靠（不受 cookie / 账号污染）：

```bash
ssh root@<VPS_IP> 'cat <<"OUTER" | bash
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"

curl -sSL --max-time 15 -4 -H "Accept-Language: en-US,en;q=0.9" -A "$UA" \
  https://gemini.google.com/ -o /tmp/g.html \
  -w "http=%{http_code}  url=%{url_effective}  size=%{size_download}  time=%{time_total}s\n"

echo "--- <title> ---"
grep -oE "<title>[^<]+</title>" /tmp/g.html | head -1

echo "--- 关键词词频 ---"
for k in "country" "region" "notSupported" "unavailable" "restricted" "Sign in" "Gemini" "isn'"'"'t" "supported"; do
  c=$(grep -ioE "$k" /tmp/g.html | wc -l | tr -d " ")
  printf "  %-15s: %s\n" "$k" "$c"
done

echo "--- 精确地区限制短语 ---"
grep -ioE ".{0,30}(supported in your country|currently supported|notSupportedInRegion).{0,30}" /tmp/g.html | head -3 || echo "  (无匹配)"
OUTER
'
```

**判定矩阵**：

| `<title>` | 关键词 | 结论 |
|-----------|--------|------|
| `Google Gemini` | country=0, supported=0, Sign in=3+ | ✅ **未被封**，HTML 是正常 SPA |
| `Sorry, Gemini isn't available...` | country=高, isn't=高 | ❌ **被封** |
| `Google Gemini` | 关键词都接近 0 | ⚠️ HTML 是 JS bundle，必须浏览器实测 |
| HTTP 302 重定向到 `support.google.com/.../answer/13278668` | - | ❌ **被封**（典型地区受限重定向） |

**本次 HostHatch Tokyo 节点（公网 IP 记为 `<VPS_IP>`）实测结果**：
```
title:  <title>Google Gemini</title>          ← 正常
country: 0   notSupported: 0   isn't: 0       ← 全 0
Sign in: 3   Bard: 420   Gemini: 72           ← 正常 SPA HTML
size: 622607 bytes  time: 0.22s
```

**结论：hosthatch IP 没被封，WARP 不必要**。

---

## 3. WARP 接入完整流程（hosthatch 实战）

如果未来真的需要 WARP（参考第 1 节判定），以下是 hosthatch JP 上**已验证跑通**的流程。

### 3.1 用 fscarmen/warp 一键脚本（最稳）

GitHub raw 在 hosthatch 偶尔抽风，fscarmen 已迁到 GitLab：

```bash
# Hosthatch 上 root 跑
wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh
bash menu.sh 4   # 选 4 = Non-global IPv4 模式（推荐）
```

交互选择：
- `Language: 1 English` 或 `2 简体中文`
- `Install using: 1. wireguard kernel`（默认）

成功标志：
```
Got the WARP Free IP successfully, Working mode: Non-global
IPv4: 104.28.211.105 JP AS13335 Cloudflare, Inc.
Congratulations! WARP Free is turned on.
```

**Non-global 模式很重要**：只创建 wireguard 接口（叫 `warp` 或 `wg0`），**不**改默认路由。后续由 xray 决定哪些流量走 WARP，避免影响 SSH 等管理流量。

### 3.2 验证 WARP 接口可用

```bash
# Hosthatch 上
wg show                           # 看接口列表
ip -br link show | grep -iE 'warp|wg'

# 通过 warp 接口出去测试
curl --interface warp -sS https://www.cloudflare.com/cdn-cgi/trace
# 应该看到 ip=104.28.x.x  warp=on
```

### 3.3 修复 wireguard reserved 字段（**容易踩坑**）

3x-ui WireGuard outbound 的 `reserved` 字段如果是 `[0,0,0]`，**Cloudflare 会静默丢包**，表现为 SSL 握手永远完不成、curl 长时间挂起。

正确值要从 `wgcf-account.toml` 或 `warp-account.conf` 提取：

```bash
# Hosthatch 上提取真实 reserved
RESERVED=$(grep -oE 'reserved.*\[.*\]' /etc/wireguard/wgcf.conf 2>/dev/null \
  || grep -oE 'reserved.*\[.*\]' /etc/wireguard/warp-account.conf 2>/dev/null \
  || echo "[30,143,211]")  # 默认值（不一定对）
echo "real reserved: $RESERVED"
```

写入 xray config（自动）：

```bash
python3 <<'PY'
import json, shutil
p = "/usr/local/x-ui/bin/config.json"
shutil.copy(p, p + ".bak")
cfg = json.load(open(p))
for o in cfg["outbounds"]:
    if o.get("tag") == "warp" and o.get("protocol") == "wireguard":
        o["settings"]["reserved"] = [30, 143, 211]   # ← 改成你的真实值
json.dump(cfg, open(p, "w"), indent=2)
print("✓ reserved 已修正")
PY
systemctl restart x-ui
```

### 3.4 处理 fscarmen 残留的系统级路由（关键陷阱）

`fscarmen/warp` 安装时为了保证全局 WARP 可用，会下发：
- `wg-quick@warp.service` systemd 服务
- `ip rule` 规则把流量强制路由到 wg0/warp 接口
- `/etc/wireguard/NonGlobalUp.sh` 启动脚本

如果你只想让 **xray 路由特定域名走 WARP**，必须**禁用这些系统级强制路由**，否则会 SSH 自指环路（VPS 自己访问自己出去再回来）：

```bash
# Hosthatch 上清理
systemctl disable --now wg-quick@warp.service 2>/dev/null
ip rule del table 51820 2>/dev/null
ip rule del lookup main 2>/dev/null

# 仅保留接口本身（让 xray 仍能 dial 它）
wg show interfaces  # 应该看到 warp 还在
```

---

## 4. Xray 路由规则模板

加 WARP outbound + 给 Google AI 域名走 WARP，其他直出。

### 4.1 outbounds 段

```json
{
  "outbounds": [
    { "tag": "direct",  "protocol": "freedom",   "settings": {} },
    {
      "tag": "warp",
      "protocol": "wireguard",
      "settings": {
        "secretKey": "<填入 wgcf 生成的 PrivateKey>",
        "address":   ["172.16.0.2/32", "<IPv6 地址>/128"],
        "peers": [{
          "publicKey":  "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "endpoint":   "engage.cloudflareclient.com:2408",
          "keepAlive":  30,
          "allowedIPs": ["0.0.0.0/0", "::/0"]
        }],
        "reserved": [30, 143, 211],   <-- 必须正确，否则静默丢包
        "mtu": 1280
      }
    },
    { "tag": "blocked", "protocol": "blackhole", "settings": {} }
  ]
}
```

**`outbounds[0]` 必须是 `direct`**！这是默认出口。如果是 `warp` 会让 VPS 自身管理流量自指环路（SSH 都连不上自己）。

### 4.2 routing 段

只给 Google AI 域名走 WARP，其他全 direct：

```json
{
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": ["<VPS_PUBLIC_IPV4>/32"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "domain": [
          "domain:gemini.google.com",
          "domain:generativelanguage.googleapis.com",
          "domain:aistudio.google.com",
          "domain:bard.google.com",
          "domain:makersuite.google.com",
          "domain:notebooklm.google.com",
          "domain:labs.google"
        ],
        "outboundTag": "warp"
      },
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "blocked" },
      { "type": "field", "protocol": ["bittorrent"], "outboundTag": "blocked" }
    ]
  }
}
```

**不要把 cursor / openai / claude / anthropic 加到 warp 路由**！它们的 IP 没被封，走 WARP 反而绕远 + 可能因为 cloudflare WARP IP 段被对方风控而**变得更慢**。

实测：把这些域名从 warp 移除后，cursor 响应从 5s 降到 1s 左右。

---

## 5. 3x-ui 数据库覆盖坑（必读）

**这是本次最深的坑**，不知道这点会让你"改完重启又回来"反复抓狂几小时。

### 5.1 现象

你直接编辑 `/usr/local/x-ui/bin/config.json` 改完 outbounds / routing，`systemctl restart x-ui` 后，配置**自动还原**到改之前。

### 5.2 原因

3x-ui 启动时会从 SQLite 数据库 `/etc/x-ui/x-ui.db` 的 `settings` 表中读取 `xrayTemplateConfig`，**用它覆盖 `/usr/local/x-ui/bin/config.json`**。这是 3x-ui 的"模板优先"设计：

```
user 改 config.json → x-ui restart →
  3x-ui 读 db 里的 xrayTemplateConfig →
  写回 config.json（覆盖你的改动） →
  启动 xray
```

### 5.3 正确改法：直接改数据库

```bash
ssh root@<VPS_IP>
python3 <<'PY'
import json, sqlite3

con = sqlite3.connect("/etc/x-ui/x-ui.db")
cur = con.cursor()
cur.execute("SELECT value FROM settings WHERE key=?", ("xrayTemplateConfig",))
row = cur.fetchone()
tpl = json.loads(row[0])

# === 改 outbounds ===
tpl["outbounds"] = [
    { "tag": "direct",  "protocol": "freedom",   "settings": {} },
    { "tag": "warp",    "protocol": "wireguard", "settings": {...} },
    { "tag": "blocked", "protocol": "blackhole", "settings": {} },
]

# === 改 routing ===
tpl["routing"]["rules"] = [
    {"type": "field", "ip": ["<VPS_IP>/32"], "outboundTag": "direct"},
    {"type": "field", "domain": ["domain:gemini.google.com", ...], "outboundTag": "warp"},
    ...
]

cur.execute("UPDATE settings SET value=? WHERE key=?",
            (json.dumps(tpl), "xrayTemplateConfig"))
con.commit()
con.close()
print("✓ xrayTemplateConfig 已更新")
PY

systemctl restart x-ui
```

**改完才是真正持久化**。重启不会再回滚。

### 5.4 验证

```bash
# 看启动后实际生效的 config.json
python3 -c "
import json
c = json.load(open('/usr/local/x-ui/bin/config.json'))
print('outbounds:', [o['tag'] for o in c['outbounds']])
for r in c['routing']['rules']:
    print(' ', r.get('outboundTag'), '→', r.get('domain') or r.get('ip') or r.get('protocol'))
"
```

应该看到你期望的顺序，且**重启 x-ui 后再看依然是这个顺序**。

---

## 6. WARP 弃用流程（如果你装了又想拆）

既然判定 IP 没被封，WARP 没必要，可以拆掉：

```bash
ssh root@<VPS_IP> 'python3 <<"PYEOF"
import json, sqlite3, shutil

# 1. 改实时 config
p = "/usr/local/x-ui/bin/config.json"
shutil.copy(p, p + ".bak")
cfg = json.load(open(p))
cfg["outbounds"] = [o for o in cfg["outbounds"] if o.get("tag") != "warp"]
cfg["routing"]["rules"] = [r for r in cfg["routing"]["rules"]
                            if r.get("outboundTag") != "warp"]
json.dump(cfg, open(p, "w"), indent=2)
print("✓ config.json 清理")

# 2. 同步改数据库（防止重启回滚）
con = sqlite3.connect("/etc/x-ui/x-ui.db")
cur = con.cursor()
cur.execute("SELECT value FROM settings WHERE key=?", ("xrayTemplateConfig",))
row = cur.fetchone()
if row:
    tpl = json.loads(row[0])
    tpl["outbounds"] = [o for o in tpl["outbounds"] if o.get("tag") != "warp"]
    tpl["routing"]["rules"] = [r for r in tpl["routing"]["rules"]
                                if r.get("outboundTag") != "warp"]
    cur.execute("UPDATE settings SET value=? WHERE key=?",
                (json.dumps(tpl), "xrayTemplateConfig"))
    con.commit()
    print("✓ x-ui.db 清理")
con.close()
PYEOF

systemctl restart x-ui
sleep 3
echo "x-ui: $(systemctl is-active x-ui)"
'
```

WARP 接口本身可以留（不占资源），也可以彻底卸载：

```bash
# 彻底卸载 fscarmen warp（可选）
bash menu.sh u    # 用 fscarmen menu 卸载
# 或手动
systemctl disable --now wg-quick@warp.service 2>/dev/null
rm -rf /etc/wireguard/warp* /etc/wireguard/wgcf*
ip link delete warp 2>/dev/null
ip link delete wg0 2>/dev/null
```

---

## 7. 本次实战教训汇总

### 7.1 真正修了什么 ✅

这些是真 bug / 真有价值的改动：

1. **`scripts/lib/local_rules.py` 的空规则误清空 bug**：当 `local-rules.yaml` 为空时，`render_override_yaml` 会输出 `rules: []`，被 mihomo 的 deep-merge 解释为"清空所有规则"，导致 mac 上 mihomo 总规则变 0、Cursor 走 DIRECT。**已修**：空时不输出 `rules` 字段。

2. **TUN 模式 + 系统代理双开导致 Cursor reconnection**：mihomo 同时监听 7890 系统代理 + TUN 接管所有流量，对短连接 OK，但对 cursor 这种长 websocket 会路径冲突。**已修**：mac 上 `networksetup -setwebproxystate Wi-Fi off` + `setsecurewebproxystate Wi-Fi off`，只保留 TUN。

3. **xray outbounds 顺序错误导致 SSH 自指环路**：`outbounds[0] = warp` 时，VPS 自己访问自己的流量也被路由到 WARP 然后又回来，外部 SSH 进不来。**已修**：`outbounds[0] = direct`，并加自 IP 直连规则。

4. **3x-ui 数据库覆盖问题**：见第 5 节，**已修**：直接改 `xrayTemplateConfig`。

5. **`sub-converter.py` AI_DOMAINS 瘦身**：原本包含 cursor/openai/claude/anthropic，全部移除，只留 Google AI 7 项。这些站点的 IP 没被封，走 WARP 反而更慢。

### 7.2 事后看是过度的 ⚠️

1. **WARP 接入本身**：hosthatch JP 的 IP 没被 Google 封（第 2 节判定），完全不需要 WARP。但流程跑通了，作为备选方案沉淀在本文档。

2. **以为是 IP 被封"疯狂"加 warp 路由规则**：实际 Google 的 "isn't supported in your country" 提示来自**账号注册地区**，不是 IP 地区。WARP 改不了账号地区，所以即使加了 WARP 也救不了"账号 = 中国"的用户。

### 7.3 没改变的事

**国际链路速度受限于运营商出境质量**，跟 ace-vpn 配置无关。两个节点（hosthatch JP / vultr）在晚高峰都很慢（`SSL 握手 1-3s`），是运营商国际出口拥堵的物理表现。配置改不了，改善路径是：
- 凌晨 2-7 点测速对比
- 切手机 5G 热点对比
- 加一条 CN2 GIA 线路 VPS（不是再折腾 ace-vpn）

### 7.4 经验总结

| 教训 | 怎么避免 |
|------|----------|
| 看到 "isn't supported in your country" 直接判定 IP 被封 | **永远先用 curl 拉首页 + 看关键词词频判定**（第 2 节 SOP） |
| 改 xray config.json 后重启发现没生效 | 改 `/etc/x-ui/x-ui.db` 的 `xrayTemplateConfig`（第 5 节） |
| `fscarmen/warp` 装完发现 SSH 自指 | 装时选 **Non-global** 模式（`menu.sh 4`） |
| mihomo 加规则后 cursor reconnection | 检查 mac 系统代理是否双开（应只开 TUN） |
| 改完一处出现连环异常，分不清谁导致 | **先 rollback 到上一个稳定状态**（如 `bash scripts/rollback-overrides.sh --last`），再单点改、单点验 |

### 7.5 关键诊断脚本

| 场景 | 跑哪个 |
|------|--------|
| 想知道某 VPS 的 IP 是否被 Google 封 | 见本文 [第 2 节](#2-如何判定一个-ip-是否被-google-ai-封了) |
| 想知道当前节点对各类业务的延迟 / 带宽 | `bash scripts/speed-test.sh` 或 `--quick` |
| 想知道 mihomo 在跑什么、cursor 走什么 chain | `bash scripts/diagnose.sh` |
| 想知道某 URL 命中哪条规则 | `bash scripts/test-route.sh <url>` |
| 想知道当前出口 IP 在 Google / OpenAI 眼里是哪国 | `bash scripts/ip-check.sh` |

---

## 附：本次涉及的文件清单

VPS 端（hosthatch）：
- `/usr/local/x-ui/bin/config.json` - xray 实时配置（改完会被 db 覆盖，仅用于查看）
- `/etc/x-ui/x-ui.db` - **真正的配置源**，改 `xrayTemplateConfig` 才持久
- `/etc/wireguard/warp.conf` / `wgcf.conf` / `warp-account.conf` - WARP 配置
- `/etc/wireguard/NonGlobalUp.sh` - fscarmen 残留启动脚本（已禁用）
- `/opt/ace-vpn-sub/sub-converter.py` - 订阅生成器
- `/etc/ace-vpn/intranet.yaml` - 内网/海外规则（被 sub-converter 读取）

Mac 端：
- `~/Library/Application Support/mihomo-party/work/config.yaml` - 当前生效的 mihomo 配置
- `~/Library/Application Support/mihomo-party/override/ace-vpn-local.yaml` - 本地规则池渲染产物
- `~/workspace/publish/ace-vpn/private/local-rules.yaml` - 本地规则池源文件
- `~/workspace/publish/ace-vpn/private/intranet.yaml` - 推 VPS 用的内网/海外规则源文件
- `~/workspace/publish/ace-vpn/scripts/lib/local_rules.py` - **修了误清空 bug**

---

**结论**：今天最有价值的 deliverable 不是 WARP 接入（备选方案），而是**修了 5 个长期潜伏的 bug + 沉淀了"如何判定 IP 是否被封"的 SOP**。
