# 2026-05-14 corp-office TUN DNS 排障复盘

## 摘要

`llm.corp-office.cn` 和 `service.mify.corp-office.cn` 在关闭 Clash Party / Mihomo TUN 时可以访问，开启 TUN 后浏览器报 `DNS_PROBE_FINISHED_NXDOMAIN`。最终确认：这两个域名不是普通公网 DNS 可完整解析的公网入口；公网 DNS 只返回 `*.v.corp-gateway.com` CNAME，并且响应状态仍是 `NXDOMAIN`，没有最终 A 记录。真正可用的解析来自公司内网 DNS `<corp-dns-a>` / `<corp-dns-b>`，返回 `<internal-ip-a>` / `<internal-ip-b>`。

最终修复是：

- 将 `mify.corp-office.cn`、`llm.corp-office.cn` 归类为 `IN`，走 `<corp-dns>` 内网 DNS。
- 在本地 override 渲染中写入 `tun.dns-hijack: [any:53]`，确保 TUN 模式下浏览器、curl、系统 DNS 查询都进入 Mihomo DNS 引擎。
- 运行时通过 Mihomo Unix socket 临时 patch `dns-hijack: any:53`，因为 Clash Party GUI 会在运行态把 `dns-hijack` 清空。

验证结果：

```bash
dig +short llm.corp-office.cn
# llm.corp-office.cn.v.corp-gateway.com.
# cname-app-com.n.corp-gateway.srv.
# <internal-ip-a>
# <internal-ip-b>

curl --noproxy '*' -vk --max-time 8 https://llm.corp-office.cn/
# HTTP/2 302, remote_ip=<internal-ip-a>

curl --noproxy '*' -vk --max-time 8 \
  'https://service.mify.corp-office.cn/console/api/apps?page=1&limit=30&name='
# HTTP/2 302, remote_ip=<internal-ip-a>
```

`302` 跳转到 `cas.corp-office.cn` 是正常登录流程，不再是 DNS 或 TUN 问题。

## 现象

用户反馈：

- `https://service.mify.corp-office.cn/console/api/apps?page=1&limit=30&name=`：TUN 关闭可访问，TUN 打开不可访问。
- 后续 `https://llm.corp-office.cn`：浏览器报 `DNS_PROBE_FINISHED_NXDOMAIN`。
- 不需要连接公司 VPN，`netstat -rn -f inet | grep '^10/'` 无输出。
- `dig +short service.mify.corp-office.cn` 只看到：

```text
service.mify.corp-office.cn.v.corp-gateway.com.
```

表面上容易误判为“公网 corp-gateway 链，应该走 `extra.cn` / 国内公网 DNS”。

## 排障过程与误判

### 误判 1：以为 `mify.corp-office.cn` 是公网 extra.cn

最初看到公网 DNS 能返回 CNAME：

```bash
dig +short service.mify.corp-office.cn @dns.alidns.com
# service.mify.corp-office.cn.v.corp-gateway.com.
```

因此曾将 `mify.corp-office.cn` 从 `IN` 改为 `EXTRA_CN`，试图避免 `corp-office.cn` 父域的 `<corp-dns>` nameserver-policy 抢先命中。

问题：这个判断只看到了 CNAME，没检查最终 A/AAAA，也没看 DNS 响应状态。

完整响应其实是：

```bash
dig @dns.alidns.com service.mify.corp-office.cn A +noall +answer +comments
# status: NXDOMAIN
# ANSWER: CNAME service.mify.corp-office.cn.v.corp-gateway.com.

dig @dns.alidns.com service.mify.corp-office.cn.v.corp-gateway.com A +noall +answer +comments
# status: NXDOMAIN
# ANSWER: empty
```

也就是说公网 DNS 并没有给出可连接 IP，浏览器报 NXDOMAIN 是合理的。

### 误判 2：以为改 override 后 Mihomo Party 已经生效

`apply-local-overrides.sh` 写出了新的 `override/ace-vpn-local.yaml`，脚本提示：

```text
Mihomo Party GUI 监听 override 目录，秒级自动应用
```

但运行时 `work/config.yaml` 仍然保留旧配置：

```yaml
+.mify.corp-office.cn:
  - <corp-dns-a>
  - <corp-dns-b>
+.llm.corp-office.cn:
  - <corp-dns-a>
  - <corp-dns-b>
```

更关键的是，运行态 `/configs` 中：

```json
"tun": {
  "enable": true,
  "dns-hijack": []
}
```

也就是说 TUN 虽然开着，但 DNS 查询没有被 hijack 到 Mihomo DNS；系统仍在问 `<cn-public-dns-b>`。

### 误判 3：只看 `dig +short`，没有看 A 记录和 status

`dig +short` 对 CNAME-only / NXDOMAIN-with-CNAME 的输出很容易误导。它会打印 CNAME，但不告诉你最终没有 A 记录。

以后要用：

```bash
dig @dns.alidns.com example.com A +noall +answer +comments
dig @<corp-dns-a> example.com A +noall +answer +comments
```

必须同时看：

- `status`
- `ANSWER SECTION`
- CNAME 目标是否继续有 A/AAAA

## 真正原因

这个问题由三层因素叠加：

### 1. `llm/mify` 必须走公司内网 DNS

公网 DNS：

```bash
dig @<cn-public-dns-b> llm.corp-office.cn A +short
# llm.corp-office.cn.v.corp-gateway.com.
# 没有 A 记录
```

内网 DNS：

```bash
dig @<corp-dns-a> llm.corp-office.cn A +short
# llm.corp-office.cn.v.corp-gateway.com.
# cname-app-com.n.corp-gateway.srv.
# <internal-ip-b>
# <internal-ip-a>

dig @<corp-dns-a> service.mify.corp-office.cn A +short
# service.mify.corp-office.cn.v.corp-gateway.com.
# cname-app-com.n.corp-gateway.srv.
# <internal-ip-a>
# <internal-ip-b>
```

所以这两个域名应归类为 `IN`，不是 `extra.cn`。

### 2. TUN 开启但 `dns-hijack` 被 Clash Party 清空

`work/config.yaml` 文件里可以有：

```yaml
tun:
  enable: true
  dns-hijack:
    - any:53
```

但 Mihomo 运行态 `/configs` 里可能仍然是：

```json
"dns-hijack": []
```

这种情况下，浏览器和普通 `curl` 走系统 DNS，不会使用 Mihomo 的 `nameserver-policy`。

### 3. fake-ip / 系统缓存会制造二次干扰

一度出现：

```text
curl resolved llm.corp-office.cn -> 198.18.x.x
```

这是旧 fake-ip 或系统缓存残留。需要在 DNS hijack 修好后清缓存，或重启 Mihomo core / 浏览器。

## 最终解决方案

### 规则归类

`private/intranet.yaml`：

```yaml
profiles:
  corp:
    dns_servers:
      - <corp-dns-a>
      - <corp-dns-b>
    domains:
      - corp.srv
      - corp-office.cn
      - mify.corp-office.cn
      - llm.corp-office.cn
      - ai.corp.com
      - n.corp.com
      - api.corp.net
```

`private/local-rules.yaml`：

```yaml
- host: mify.corp-office.cn
  target: IN
  note: corp-gateway 链需 <corp-dns> 才返回 <internal-ip-ranges> A 记录

- host: llm.corp-office.cn
  target: IN
  note: corp-gateway 链需 <corp-dns> 才返回 <internal-ip-ranges> A 记录
```

### 本地 override 渲染

`scripts/lib/local_rules.py` 在有 `IN` / `EXTRA_CN` 规则时渲染：

```yaml
tun:
  dns-hijack:
    - any:53

dns:
  +fake-ip-filter:
    - "+.mify.corp-office.cn"
    - "+.llm.corp-office.cn"
  nameserver-policy:
    "<+.mify.corp-office.cn>":
      - <corp-dns-a>
      - <corp-dns-b>
    "<+.llm.corp-office.cn>":
      - <corp-dns-a>
      - <corp-dns-b>
```

同时将更具体的子域规则排到父域前面，避免 order-sensitive 客户端中 `corp-office.cn` 先命中：

```text
DOMAIN-SUFFIX,mify.corp-office.cn,DIRECT
DOMAIN-SUFFIX,llm.corp-office.cn,DIRECT
DOMAIN-SUFFIX,corp-office.cn,DIRECT
```

### 运行时 patch

Clash Party GUI 会在某些情况下把运行态 `tun.dns-hijack` 清空。可通过 Mihomo Unix socket 检查：

```bash
python3 - <<'PY'
import socket, json
sock = "/tmp/mihomo-party-501-65622.sock"
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock)
s.sendall(b"GET /configs HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
data = b""
while True:
    c = s.recv(8192)
    if not c:
        break
    data += c
body = data.split(b"\r\n\r\n", 1)[1]
print(json.loads(body)["tun"]["dns-hijack"])
PY
```

如果输出是 `[]`，临时 patch：

```bash
python3 - <<'PY'
import json, socket
sock = "/tmp/mihomo-party-501-65622.sock"
body = json.dumps({"tun": {"enable": True, "dns-hijack": ["any:53"]}}).encode()
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock)
s.sendall(
    b"PATCH /configs HTTP/1.1\r\n"
    b"Host: localhost\r\n"
    b"Connection: close\r\n"
    b"Content-Type: application/json\r\n"
    + f"Content-Length: {len(body)}\r\n\r\n".encode()
    + body
)
print(s.recv(1024).decode("utf-8", "ignore"))
PY
```

## 验证 checklist

### 1. 公网 DNS 与内网 DNS 对比

```bash
dig @<cn-public-dns-b> llm.corp-office.cn A +noall +answer +comments
dig @<corp-dns-a> llm.corp-office.cn A +noall +answer +comments
```

判定：

- 公网只有 CNAME 且 `status: NXDOMAIN`：不能归 `extra.cn`。
- `<corp-dns>` 返回 `<internal-ip-ranges>`：应归 `IN`。

### 2. Mihomo DNS 是否正确

```bash
dig @127.0.0.1 -p 1053 +short llm.corp-office.cn
dig @127.0.0.1 -p 1053 +short service.mify.corp-office.cn
```

期望：

```text
cname-app-com.n.corp-gateway.srv.
<internal-ip-a>
<internal-ip-b>
```

### 3. 系统 DNS 是否被 TUN hijack

```bash
dig +short llm.corp-office.cn
dig +short service.mify.corp-office.cn
```

期望同样有 `<internal-ip-ranges>`。如果只有 `*.v.corp-gateway.com` CNAME，说明浏览器大概率也会失败。

### 4. HTTPS 是否通

```bash
HTTPS_PROXY= HTTP_PROXY= ALL_PROXY= \
https_proxy= http_proxy= all_proxy= \
curl --noproxy '*' -vk --max-time 8 https://llm.corp-office.cn/
```

期望：

```text
HTTP/2 302
location: https://cas.corp-office.cn/login...
```

## 下次遇到同类问题怎么办

### 快速判定流程

1. 先看现象：
   - TUN 关可访问，TUN 开不可访问：优先怀疑 DNS hijack / fake-ip / nameserver-policy。
   - 浏览器 `DNS_PROBE_FINISHED_NXDOMAIN`：不要只看 `dig +short`。

2. 对比公网与内网 DNS：

```bash
host=xxx.corp-office.cn
dig @<cn-public-dns-b> "$host" A +noall +answer +comments
dig @<corp-dns-a> "$host" A +noall +answer +comments
```

3. 分类：
   - 公网 DNS 返回真实 A 记录：可考虑 `extra.cn` / DIRECT。
   - 公网 DNS 只有 CNAME 或 NXDOMAIN，但 `<corp-dns>` 返回 A 记录：必须放 `IN`。
   - 两边都没有 A：可能是域名写错、服务未发布、或需要特定环境。

4. 检查运行态：

```bash
dig @127.0.0.1 -p 1053 +short "$host"
dig +short "$host"
```

如果前者对、后者错，说明 TUN DNS hijack 没有真正生效。

5. 检查 Mihomo 运行态：

```bash
# 通过 /tmp/mihomo-party-501-*.sock 查询 /configs
# 关注 tun.dns-hijack 是否为 ["any:53"]
```

6. 修复后清缓存：

```bash
dscacheutil -flushcache 2>/dev/null || true
killall -HUP mDNSResponder 2>/dev/null || true
```

Chrome 还要清：

```text
chrome://net-internals/#dns
```

点 `Clear host cache`。

## 持久化与同步

本机立即生效：

```bash
bash scripts/rules/apply-local-overrides.sh
```

同步 `intranet.yaml` 到 VPS：

```bash
bash scripts/rules/sync-intranet.sh
```

如果 `sub-converter.py` 的逻辑也变更：

```bash
bash scripts/rules/sync-subconverter.sh
```

注意：VPS 同步只会影响订阅生成；本机 Clash Party 的 GUI 运行态仍可能覆盖 `tun.dns-hijack`。如果重启 Clash Party 后复发，优先确认 GUI 的 TUN/DNS 设置是否将 DNS hijack 固定为 `any:53`，或重新通过 runtime socket patch。

