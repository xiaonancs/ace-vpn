#!/usr/bin/env python3
"""ace-vpn 订阅转换器：3x-ui base64 (vless://) → Clash Meta YAML

支持两种模式（环境变量）：

[A] 单 token 模式（兼容旧部署）：
    UPSTREAM_SUB    完整的 3x-ui 订阅 URL
    SUB_TOKEN       访问 token，客户端 URL：/<SUB_PATH_PREFIX>/$SUB_TOKEN

[B] 多 token 模式（推荐，一个实例服务全家）：
    UPSTREAM_BASE   3x-ui 订阅 URL 前缀（不含 SubId 那一段）
                    例：https://127.0.0.1:2096/sub_xxxxxxxx
    SUB_TOKENS      白名单，逗号分隔，每个 token = 3x-ui 里的一个 SubId
                    例：ace-main,ace-fork,dad-home
    客户端 URL：/<SUB_PATH_PREFIX>/<任意白名单里的 token>
    实际从 $UPSTREAM_BASE/<token> 拉上游

[C] 内联上游模式（3x-ui 原生订阅未启用时的稳妥回退）：
    UPSTREAM_INLINE  一行或多行 vless:// 分享链接
    SUB_TOKENS       白名单 token；每个 token 返回同一份内联节点

通用环境变量：
    LISTEN_PORT    监听端口，默认 25500
    SERVER_OVERRIDE 强制覆盖节点 server 字段（防 3x-ui 返回 127.0.0.1）
    COMPANY_CIDRS  公司内网 CIDR，逗号分隔（兼容旧部署，不推荐）
    COMPANY_SFX    公司域名后缀，逗号分隔（兼容旧部署，不推荐）

动态内网配置（推荐，每次 HTTP 请求热加载，改完无需重启服务）：
    INTRANET_FILE  内网规则 YAML 路径，默认 /etc/ace-vpn/intranet.yaml

    intranet.yaml 结构见 private/intranet.yaml.example；支持多 profile，
    每个 profile 带 enabled 开关，互相独立。本地编辑后 scp 到 VPS 即可。

固定路由策略（按规则顺序优先级从高到低）：
  - 公司内网（profile.cidrs / profile.domains）→ DIRECT，DNS 走 profile.dns_servers
  - extra.overseas（用户手加 / Mac 本地池 promote）→ 🚀 PROXY
  - extra.cn（用户手加 / Mac 本地池 promote）→ DIRECT
  - AI（OpenAI/Claude/Gemini/Cursor/GitHub Copilot，内置）→ 🤖 AI
  - 境外社交（Discord/X/Telegram/Facebook/Instagram/YouTube，内置）→ 🚀 PROXY
  - 境内常用（抖音/淘宝/B 站/微博/QQ/百度，内置）→ DIRECT
  - GEOIP CN → DIRECT
  - MATCH → 🐟 FINAL（默认代理，可手动切直连）

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DNS 层决策矩阵（source of truth）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

背景：enhanced-mode: fake-ip 是全局默认，**所有未进 fake-ip-filter
的域名都返回 198.18.x.x 假 IP**。这张表决定谁进 filter、谁用什么 DNS。

┌──────────────────────────┬──────────┬──────────────┬──────────────────────┐
│ 域名类别                 │ routing  │ fake-ip 策略 │ nameserver-policy    │
├──────────────────────────┼──────────┼──────────────┼──────────────────────┤
│ intranet.domains         │ DIRECT   │ ✅ 跳过      │ 公司内网 DNS (10.x)  │
│ extra.cn                 │ DIRECT   │ ✅ 跳过      │ CN_PUBLIC_DNS (UDP)  │
│ CHINA_DIRECT             │ DIRECT   │ ✅ 跳过      │ 无 (默认国内 DoH)    │
│ AI_STREAMING_DOMAINS     │ PROXY    │ ✅ 跳过*     │ OVERSEAS_DOH         │
│ extra.overseas           │ PROXY    │ ✅ 跳过*     │ OVERSEAS_DOH         │
│ SOCIAL_PROXY             │ PROXY    │ ❌ 保留      │ (无 policy，不需要)  │
│ MEDIA_PROXY              │ PROXY    │ ❌ 保留      │ (无 policy，不需要)  │
│ MATCH (fallback)         │ FINAL    │ ❌ 保留      │ -                    │
└──────────────────────────┴──────────┴──────────────┴──────────────────────┘

核心不变式（记 3 条就够）：
  1. 走 **DIRECT** 的域名 **必须** 跳过 fake-ip
     浏览器最终要本地直连，fake-IP 没法连，走 sniff 重解析链路偶发死锁
  2. 走 **PROXY** 的普通域名 **保留** fake-ip（Clash 默认就是这样用的）
     本地不解析，域名原样送 PROXY 节点，由节点所在地 DNS 解析
     → 规避国内 DoH 污染、规避 DoH 首包鸡生蛋、性能最优
  3. 走 **PROXY 但 CLI/agent 会用** 的域名 **例外跳过** fake-ip (*)
     Cursor/Claude Code/Codex 会把 DNS 结果缓存到磁盘，fake-IP 池洗牌
     后假 IP 指向别的域名 → agent 崩溃且不自愈
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""
import base64
import http.server
import ipaddress
import json
import os
import secrets
import socket
import socketserver
import ssl
import sys
import threading
import time
import urllib.parse
import urllib.request
import yaml
from typing import List, Dict, Any, Optional


# 模式 A：单 token
UPSTREAM_SUB = os.environ.get("UPSTREAM_SUB", "").strip()
UPSTREAM_INLINE = os.environ.get("UPSTREAM_INLINE", "").strip()
SUB_TOKEN = os.environ.get("SUB_TOKEN", "").strip() or secrets.token_urlsafe(12)

# 模式 B：多 token（推荐）
UPSTREAM_BASE = os.environ.get("UPSTREAM_BASE", "").strip().rstrip("/")
SUB_TOKENS = [t.strip() for t in os.environ.get("SUB_TOKENS", "").split(",") if t.strip()]

LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "25500"))
LISTEN_HOST = os.environ.get("LISTEN_HOST", "0.0.0.0").strip() or "0.0.0.0"
SUB_PATH_PREFIX = os.environ.get("SUB_PATH_PREFIX", "clash").strip().strip("/") or "clash"
SUB_ADMIN_TOKEN = os.environ.get("SUB_ADMIN_TOKEN", "").strip()
SUB_RATE_LIMIT_PER_MIN = int(os.environ.get("SUB_RATE_LIMIT_PER_MIN", "120"))
COMPANY_CIDRS = [c.strip() for c in os.environ.get("COMPANY_CIDRS", "").split(",") if c.strip()]
COMPANY_SFX = [c.strip() for c in os.environ.get("COMPANY_SFX", "").split(",") if c.strip()]
INTRANET_FILE = os.environ.get("INTRANET_FILE", "/etc/ace-vpn/intranet.yaml").strip()
# 保险丝：强制覆盖节点 server 字段（3x-ui 会根据 Host 头返回 127.0.0.1 等内网 IP，这里统一改成公网 IP）
SERVER_OVERRIDE = os.environ.get("SERVER_OVERRIDE", "").strip()

# 下发配置里 tun.enable 的默认值。
#   - 桌面端（macOS Mihomo Party）希望订阅自带 tun.enable=true，否则每次刷新订阅
#     都会把本地手开的 TUN 关掉 → 系统流量直连泄漏（见开发者日志 §6.16）。
#   - 移动端（iOS/Android）由 App 自身管理 VPN，订阅里强开 TUN 可能冲突，保持 false。
# 通过 ?tun=1 / ?tun=0 query 可按设备覆盖（见 do_GET）。
# TUN_TOKENS 可指定哪些 SubId 默认开启 TUN，例如 TUN_TOKENS=ace-main；
# 未命中的 token 使用 TUN_ENABLE 默认值。
TUN_ENABLE_DEFAULT = os.environ.get("TUN_ENABLE", "false").strip().lower() in ("1", "true", "yes", "on")
TUN_TOKENS = {t.strip() for t in os.environ.get("TUN_TOKENS", "").split(",") if t.strip()}
TUN_MTU = int(os.environ.get("TUN_MTU", "1420"))
FIND_PROCESS_MODE_DEFAULT = os.environ.get("FIND_PROCESS_MODE", "off").strip().lower() or "off"
MAIN_URL_TEST = os.environ.get("MAIN_URL_TEST", "https://www.gstatic.com/generate_204").strip()
AI_URL_TEST = os.environ.get("AI_URL_TEST", "https://chatgpt.com/cdn-cgi/trace").strip()

# extra.cn 域名强制使用的"国内公网 DNS"。
#
# 为什么必须强制？因为 Mihomo 默认 nameserver 是 DoH（doh.pub / dns.alidns.com），
# 当客户端开 TUN + 远端 PROXY 节点在海外（如新加坡 / 东京）时，DoH 流量会经过 PROXY，
# 远端解析返回的是站在海外节点视角的 IP（很多企业零信任网关 / 国内 SaaS 在海外有
# CDN 边缘节点，但这些节点对未授权请求静默丢包）—— 接着 DIRECT 直连那个海外 IP，
# TLS 通常被拒/卡死。
#
# 这里固定用 119.29.29.29 (DNSPod) 和 223.5.5.5 (AliDNS) UDP 53，
# Mihomo 把它们当成 DIRECT 直连解析（绕过 PROXY 节点），永远拿到国内视角的 IP。
CN_PUBLIC_DNS = ["119.29.29.29", "223.5.5.5"]

# AI / 境外流式域名强制使用的"境外 DoH"，对称于 CN_PUBLIC_DNS（见 §4.A.9）。
#
# 为什么必须强制？Mihomo 默认 nameserver 是国内 DoH（doh.pub / dns.alidns.com）。
# 解析境外 AI 域名（Cursor / Anthropic / OpenAI / Gemini 等）时：
#   1. 国内 DoH 有时命中污染记录 → getaddrinfo ENOTFOUND（今天 Cursor log 里的那种）
#   2. 或返回 CDN 边缘的国内节点 → 被 RST 注入 / TLS 握手卡死
#   3. fallback-filter 需要整轮 RT 才能纠正 → 首次连接多 100-500ms 延迟
# 境外域名直接用境外 DoH 解析，一次成、无污染、延迟稳定。
#
# DoH 走代理节点出去（mihomo 默认行为），跨境加密，不会被中间设备看到解析内容。
OVERSEAS_DOH = [
    "https://1.1.1.1/dns-query",
    "https://dns.google/dns-query",
    "https://dns.cloudflare.com/dns-query",
]

# proxy-server-nameserver 专用 DNS：解析 PROXY 节点的 server 字段（域名 → IP）。
#
# mihomo 强制要求：`dns.respect-rules: true` 开启时此字段必须非空，否则
# Clash Party 会报 "if respect-rules is turned on, proxy-server-nameserver
# cannot be empty" → 订阅 profile check failed。原因：开 respect-rules 后普通
# DNS 解析要经过 rules 分流，但 proxy server 自己的解析不能经过 rules（否则
# 鸡生蛋：要走 proxy 必须先解析它，但解析又要经过 rules，而 rules 最终又指向
# proxy），所以 mihomo 需要一个独立的 bootstrap nameserver。
#
# 特别约束：主机部分必须是 IP（不能是 dns.google / dns.cloudflare.com 这样的
# 域名，否则 bootstrap 阶段没法递归解析，会死锁）。这也是为什么不能直接复用
# OVERSEAS_DOH（它里面 2/3 是域名型 DoH）。
#
# 组合策略（按优先级）：
#   1. https://1.1.1.1/dns-query      境外加密，主机 IP 化，不被污染
#   2. https://8.8.8.8/dns-query      境外加密，主机 IP 化，备线路
#   3. 223.5.5.5                      国内明文 UDP，bootstrap 兜底（防境外 DoH
#                                     首包丢失时连不上 proxy）
#
# 对用 SERVER_OVERRIDE（IP 直连）的部署，这个字段只是满足校验，实际不被用到；
# 对 server 字段是域名的部署（动态 DDNS / 托管解析），这个字段是真正必要的。
PROXY_SERVER_DNS = [
    "https://1.1.1.1/dns-query",
    "https://8.8.8.8/dns-query",
    "223.5.5.5",
]

# AI 长流式响应域名白名单：路由到 🤖 AI，DNS 强制境外 DoH + 加入 fake-ip-filter。
# 这些域名的共同点是「agent/chat 模式的长连接流式输出」，对 DNS 污染和
# RST 注入最敏感；和普通海外网页分开，便于单独选择出口和测速目标。
#
# 按平台分类，便于后续增减：
AI_STREAMING_DOMAINS = [
    # Cursor
    "cursor.sh", "cursor.com", "cursorapi.com", "cursor-cdn.com",
    # Anthropic / Claude (Claude.ai / Claude Code CLI)
    "anthropic.com", "claude.ai", "claudeusercontent.com",
    # OpenAI (ChatGPT / Codex CLI / API)
    "openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com",
    "auth0.openai.com",
    # Google AI (Gemini / AI Studio)
    "gemini.google.com", "bard.google.com", "aistudio.google.com",
    "generativelanguage.googleapis.com", "makersuite.google.com",
    "notebooklm.google.com", "labs.google",
    # GitHub Copilot
    "githubcopilot.com", "copilot-proxy.githubusercontent.com",
    # xAI / Grok
    "x.ai", "grok.com",
    # Perplexity
    "perplexity.ai", "pplx.ai",
    # 开源 / 轻量 AI 平台
    "mistral.ai", "cohere.com", "cohere.ai",
    "huggingface.co", "hf.co",
    "replicate.com", "replicate.delivery",
    "groq.com",
    "together.ai", "together.xyz",
    "fireworks.ai",
    "deepseek.com",
    # OpenCode / 其他 AI 编码工具
    "opencode.ai",
]

_SSL_CONTEXT = ssl.create_default_context()
_SSL_CONTEXT.check_hostname = False
_SSL_CONTEXT.verify_mode = ssl.CERT_NONE

_INTRANET_CACHE_LOCK = threading.Lock()
_INTRANET_CACHE_KEY = None
_INTRANET_CACHE: Optional[Dict[str, Any]] = None
_RATE_LOCK = threading.Lock()
_RATE_BUCKETS: Dict[str, List[float]] = {}


def load_intranet_config() -> Dict[str, Any]:
    """按 intranet.yaml mtime/size 缓存配置，文件变化时自动热加载。"""
    global _INTRANET_CACHE_KEY, _INTRANET_CACHE

    try:
        stat = os.stat(INTRANET_FILE) if INTRANET_FILE else None
        cache_key = (
            INTRANET_FILE,
            stat.st_mtime_ns if stat else None,
            stat.st_size if stat else None,
            tuple(COMPANY_SFX),
            tuple(COMPANY_CIDRS),
        )
    except OSError:
        cache_key = (INTRANET_FILE, None, None, tuple(COMPANY_SFX), tuple(COMPANY_CIDRS))

    with _INTRANET_CACHE_LOCK:
        if _INTRANET_CACHE is not None and _INTRANET_CACHE_KEY == cache_key:
            return _INTRANET_CACHE

    parsed = _load_intranet_config_uncached()
    with _INTRANET_CACHE_LOCK:
        _INTRANET_CACHE_KEY = cache_key
        _INTRANET_CACHE = parsed
    return parsed


def _load_intranet_config_uncached() -> Dict[str, Any]:
    """热加载内网规则。每次 HTTP 请求调用一次，改 YAML 无需重启服务。

    合并来源（按顺序，去重保留顺序）：
      1. 环境变量 COMPANY_SFX / COMPANY_CIDRS（兼容旧部署）
      2. INTRANET_FILE 里 enabled=true 的各 profile

    返回：
      {
        "domains": ["app.corp-a.example", ...],   # 公司内网 → DIRECT
        "cidrs":   ["10.0.0.0/8", ...],
        "domain_dns": {                           # 域名 → 专属 DNS 服务器列表
            "app.corp-a.example": ["10.x.x.1", "10.x.x.2"],
            ...
        },
        "active_profiles": ["corp-a", ...],       # 仅用于日志
        "extra_overseas": ["claude-foo.example"], # 跨 profile 的额外代理域名
        "extra_cn":       ["misclassified.cn"],   # 跨 profile 的额外直连域名
      }

    关于 domain_dns：
      若 profile 配了 dns_servers（例如公司内网 DNS），该 profile 下所有 domain
      都会用这些 server 做解析，绕开系统 DNS（防 Mihomo / Clash Party GUI 强改
      系统 DNS 后拿不到内网 IP）。未配则回落到 "system"。

    关于 extra：
      顶层 `extra: {overseas: [...], cn: [...]}`，由 promote-to-vps.sh 把 Mac 本
      地池里 cn / overseas 类规则合并到这里。和 profiles 解耦——换公司不影响。
      在 build_rules 中 prepend 到 AI / SOCIAL_PROXY / CHINA_DIRECT 之前，
      让用户手加规则永远赢内置默认。
    """
    domains: List[str] = list(COMPANY_SFX)
    cidrs: List[str] = list(COMPANY_CIDRS)
    active: List[str] = []
    domain_dns: Dict[str, List[str]] = {}
    extra_overseas: List[str] = []
    extra_cn: List[str] = []

    if INTRANET_FILE and os.path.isfile(INTRANET_FILE):
        try:
            with open(INTRANET_FILE, "r", encoding="utf-8") as f:
                data = yaml.safe_load(f) or {}
            # 支持两种格式：
            # (a) 扁平：{domains: [...], cidrs: [...], dns_servers: [...]}
            # (b) 多 profile：{profiles: {name: {enabled, domains, cidrs, dns_servers}}}
            if isinstance(data.get("profiles"), dict):
                for name, prof in (data["profiles"] or {}).items():
                    if not isinstance(prof, dict):
                        continue
                    if not prof.get("enabled", False):
                        continue
                    active.append(name)
                    prof_dns = [
                        s.strip() for s in (prof.get("dns_servers") or [])
                        if isinstance(s, str) and s.strip()
                    ]
                    for d in (prof.get("domains") or []):
                        if isinstance(d, str) and d.strip():
                            d = d.strip()
                            domains.append(d)
                            if prof_dns:
                                domain_dns[d] = prof_dns
                    for c in (prof.get("cidrs") or []):
                        if isinstance(c, str) and c.strip():
                            cidrs.append(c.strip())
            else:
                flat_dns = [
                    s.strip() for s in (data.get("dns_servers") or [])
                    if isinstance(s, str) and s.strip()
                ]
                for d in (data.get("domains") or []):
                    if isinstance(d, str) and d.strip():
                        d = d.strip()
                        domains.append(d)
                        if flat_dns:
                            domain_dns[d] = flat_dns
                for c in (data.get("cidrs") or []):
                    if isinstance(c, str) and c.strip():
                        cidrs.append(c.strip())

            # 顶层 extra（profiles / 扁平格式都共享，不归任何 profile）
            extra = data.get("extra") or {}
            if isinstance(extra, dict):
                for d in (extra.get("overseas") or []):
                    if isinstance(d, str) and d.strip():
                        extra_overseas.append(d.strip())
                for d in (extra.get("cn") or []):
                    if isinstance(d, str) and d.strip():
                        extra_cn.append(d.strip())
        except Exception as e:  # noqa: BLE001
            sys.stderr.write(f"[intranet] failed to parse {INTRANET_FILE}: {e}\n")

    def _dedup(xs: List[str]) -> List[str]:
        seen = set()
        out = []
        for x in xs:
            key = x.strip().lower()
            if key and key not in seen:
                seen.add(key)
                out.append(x.strip())
        return out

    return {
        "domains": _dedup(domains),
        "cidrs": _dedup(cidrs),
        "domain_dns": domain_dns,
        "active_profiles": active,
        "extra_overseas": _dedup(extra_overseas),
        "extra_cn": _dedup(extra_cn),
    }


def resolve_upstream(token: str) -> Optional[str]:
    """按 token 解析上游 3x-ui 订阅 URL。None 表示 token 不在白名单。"""
    if UPSTREAM_INLINE:
        if SUB_TOKENS:
            return f"inline://{token}" if token in SUB_TOKENS else None
        if token == SUB_TOKEN:
            return f"inline://{token}"
        return None
    if UPSTREAM_BASE and SUB_TOKENS:
        if token in SUB_TOKENS:
            return f"{UPSTREAM_BASE}/{token}"
        return None
    if UPSTREAM_SUB:
        if token == SUB_TOKEN:
            return UPSTREAM_SUB
        return None
    return None


def fetch_sub(url: str) -> str:
    if url.startswith("inline://"):
        return UPSTREAM_INLINE
    req = urllib.request.Request(url, headers={"User-Agent": "ace-vpn/1.0"})
    with urllib.request.urlopen(req, context=_SSL_CONTEXT, timeout=10) as r:
        return r.read().decode("utf-8", errors="replace").strip()


def b64decode(s: str) -> str:
    s = s.strip().replace("\n", "").replace("\r", "")
    s += "=" * (-len(s) % 4)
    for dec in (base64.urlsafe_b64decode, base64.b64decode):
        try:
            return dec(s).decode("utf-8", errors="replace")
        except Exception:
            continue
    return s


def parse_vless(uri: str) -> Optional[Dict[str, Any]]:
    if not uri.startswith("vless://"):
        return None
    body = uri[len("vless://"):]
    name = ""
    if "#" in body:
        body, frag = body.rsplit("#", 1)
        name = urllib.parse.unquote(frag)
    query = ""
    if "?" in body:
        body, query = body.split("?", 1)
    if "@" not in body:
        return None
    uuid, hostport = body.rsplit("@", 1)
    if ":" not in hostport:
        return None
    host, port_s = hostport.rsplit(":", 1)
    try:
        port = int(port_s)
    except ValueError:
        return None
    params = dict(urllib.parse.parse_qsl(query))

    p: Dict[str, Any] = {
        "name": name or f"node-{uuid[:8]}",
        "type": "vless",
        "server": SERVER_OVERRIDE or host,
        "port": port,
        "uuid": uuid,
        "udp": True,
        "network": params.get("type", "tcp"),
        "client-fingerprint": params.get("fp", "chrome"),
        "skip-cert-verify": False,
    }

    sec = params.get("security", "")
    if sec in ("tls", "reality"):
        p["tls"] = True
    if params.get("sni"):
        p["servername"] = params["sni"]
    if params.get("flow"):
        p["flow"] = params["flow"]
    if sec == "reality":
        p["reality-opts"] = {
            "public-key": params.get("pbk", ""),
            "short-id": params.get("sid", ""),
        }
    if p["network"] == "ws":
        ws_opts: Dict[str, Any] = {}
        if params.get("path"):
            ws_opts["path"] = urllib.parse.unquote(params["path"])
        if params.get("host"):
            ws_opts["headers"] = {"Host": params["host"]}
        if ws_opts:
            p["ws-opts"] = ws_opts
    elif p["network"] == "grpc":
        if params.get("serviceName"):
            p["grpc-opts"] = {"grpc-service-name": urllib.parse.unquote(params["serviceName"])}

    return p


# 规则集（顺序即优先级）
#
# 🤖 AI group 专门承接 AI/agent/chat/API 流量；普通海外网页继续走 🚀 PROXY。
AI_DOMAINS = list(AI_STREAMING_DOMAINS)

PINTEREST_DOMAINS = [
    "pinimg.com",
    "pinterest.at", "pinterest.ca", "pinterest.ch", "pinterest.cl",
    "pinterest.co.kr", "pinterest.co.uk", "pinterest.com",
    "pinterest.com.au", "pinterest.com.mx", "pinterest.de",
    "pinterest.dk", "pinterest.es", "pinterest.fr", "pinterest.ie",
    "pinterest.it", "pinterest.jp", "pinterest.nl", "pinterest.nz",
    "pinterest.ph", "pinterest.pt", "pinterest.ru", "pinterest.se",
]

SOCIAL_PROXY = [
    # Discord
    "discord.com", "discordapp.com", "discordapp.net", "discord.gg", "discord.media",
    # X / Twitter
    "twitter.com", "x.com", "twimg.com", "t.co",
    # Meta
    "facebook.com", "fbcdn.net", "fb.com", "instagram.com", "cdninstagram.com", "whatsapp.com", "whatsapp.net",
    # Telegram
    "telegram.org", "t.me", "telegram.me", "tdesktop.com",
    # Overseas mobile apps / social / productivity
    *PINTEREST_DOMAINS,
    "tiktok.com", "tiktokv.com", "tiktokcdn.com", "tiktokcdn-us.com",
    "byteoversea.com", "ibyteimg.com", "ibytedtos.com", "muscdn.com", "musical.ly",
    "snapchat.com", "sc-cdn.net", "snapkit.com",
    "linkedin.com", "licdn.com",
    "threads.com", "threads.net",
    "slack.com", "slack-edge.com", "slack-imgs.com", "slackb.com",
    "notion.so", "notion.site",
    "dropbox.com", "dropboxusercontent.com",
    # Google（含搜索/邮件/Gmail 图片 CDN 等）
    "google.com", "gmail.com", "googlemail.com", "gstatic.com",
    "googleusercontent.com", "googleapis.com", "ggpht.com",
    # GitHub
    "github.com", "githubusercontent.com", "githubassets.com",
    # International news / publishers (app login and embedded webviews)
    "forbes.com", "forbesimg.com", "forbesmedia.com",
    "bloomberg.com", "bbci.co.uk", "bbc.com", "cnn.com", "edition.cnn.com",
    "reuters.com", "nytimes.com", "washingtonpost.com", "wsj.com",
    "ft.com", "economist.com", "theguardian.com",
    # 其他
    "wikipedia.org", "reddit.com", "medium.com", "stackexchange.com", "stackoverflow.com",
    "quora.com",
]

MEDIA_PROXY = [
    # YouTube
    "youtube.com", "youtu.be", "ytimg.com", "googlevideo.com", "ggpht.com",
    # Netflix
    "netflix.com", "nflximg.com", "nflxvideo.net", "nflxext.com",
    # Spotify / Apple / Disney
    "spotify.com", "scdn.co",
    "music.apple.com", "applemusic.com", "tv.apple.com",
    "disneyplus.com", "bamgrid.com", "disney-plus.net",
    # HBO / Prime
    "hbomax.com", "max.com", "primevideo.com",
]

def _dedupe_domains(*groups: List[str]) -> List[str]:
    seen: set[str] = set()
    result: List[str] = []
    for group in groups:
        for domain in group:
            key = str(domain).strip().lower()
            if not key or key in seen:
                continue
            seen.add(key)
            result.append(key)
    return result


CHINA_BYTEDANCE_DIRECT = [
    "douyin.com", "aweme.snssdk.com", "snssdk.com", "bytedance.com", "bytedancecdn.com",
    "douyincdn.com", "douyinpic.com", "douyinstatic.com", "douyinvod.com", "idouyinvod.com",
    "iesdouyin.com", "pstatp.com", "byteimg.com", "bytednsdoc.com", "zjcdn.com",
    "toutiao.com", "toutiaoimg.com", "toutiaocdn.com", "ixigua.com", "ixiguavideo.com",
    "amemv.com", "bdstatic.com",
]

CHINA_ALIBABA_DIRECT = [
    "taobao.com", "tmall.com", "alibaba.com", "alicdn.com", "aliyun.com",
    "alipay.com", "alipayobjects.com", "1688.com", "tanx.com", "mmstat.com",
    "tbcdn.cn", "taobaocdn.com", "tmall.hk",
    "ele.me", "ele.to", "eleme.com", "eleme.com.cn", "eleme.cn", "eleme.io",
    "elemecdn.com", "elemecdn.cn", "elenet.me", "fengniao.com",
    "fengniaopaotui.cn", "fengniaozhongbao.cn", "xingxuanwaimai.com", "xyzele.com", "youcaishop.cn",
    "goofish.com", "amap.com", "autonavi.com",
    "dingtalk.com", "dingtalkapps.com", "fliggy.com", "alitrip.com",
    "uc.cn", "ucweb.com", "quark.cn", "myquark.cn", "uczzd.cn", "sm.cn",
]

CHINA_TENCENT_DIRECT = [
    "qq.com", "qpic.cn", "qlogo.cn", "tencent.com", "tencent-cloud.com", "tencent-cloud.net",
    "weixin.qq.com", "weixin.com", "wechat.com", "wechatpay.com", "wechatlegal.net",
    "wechatos.net", "weixinbridge.com", "weixinsxy.com", "iot-tencent.com",
    "gtimg.com", "gtimg.cn", "tenpay.com",
    "myqcloud.com", "qcloud.com", "qcloudimg.com", "qcloudcdn.com",
    "servicewechat.com", "weapp.com", "wecom.work", "xy-asia.com", "weread.qq.com",
]

CHINA_SOCIAL_DIRECT = [
    "weibo.com", "weibo.cn", "weibocdn.com", "sinaimg.cn", "sina.com.cn", "sina.cn", "miaopai.com",
    "zhihu.com", "zhimg.com", "xiaohongshu.com", "xiaohongshu.net", "xhscdn.com",
    "xhscdn.net", "xhslink.com", "fengkongcloud.com",
    "douban.com", "doubanio.com",
]

CHINA_BAIDU_DIRECT = [
    "baidu.com", "bdimg.com", "bdstatic.com", "baidupcs.com", "baidubce.com", "bcebos.com",
]

CHINA_VIDEO_DIRECT = [
    "acg.tv", "acgvideo.com", "bilibili.com", "bilibili.cn", "bilibili.net", "bilibili.tv",
    "biliapi.com", "biliapi.net", "biliimg.com",
    "bilivideo.com", "bilivideo.cn", "bilivideo.net", "hdslb.com", "hdslb.net", "hdslb.org",
    "b23.tv", "bili22.cn", "bili23.cn", "bili2233.cn", "bili33.cn",
    "bilicdn1.com", "bilicdn2.com", "bilicdn3.com", "bilicdn4.com", "bilicdn5.com",
    "bilibiligame.cn", "bilibiligame.com", "bilibiligame.net", "bilicomics.com",
    "biligo.com", "maoercdn.com", "ourdvsss.com", "ksyungslb.com", "yfcdn.net", "smtcdns.net",
    "iqiyi.com", "iqiyipic.com",
    "youku.com", "ykimg.com",
    "mgtv.com", "hitv.com", "miguvideo.com", "cmvideo.cn", "pptv.com", "le.com",
]

CHINA_LOCAL_SERVICE_DIRECT = [
    "meituan.com", "meituan.net", "dianping.com", "sankuai.com",
    "mtyun.com", "maoyan.com", "neixin.cn", "dpfile.com",
    "58.com", "ganji.com", "anjuke.com", "ke.com", "lianjia.com", "beike.com",
    "didichuxing.com", "xiaojukeji.com", "didistatic.com",
    "ctrip.com", "trip.com", "tripcdn.com", "qunar.com", "12306.cn",
    "ly.com", "elong.com", "tuniu.com",
]

CHINA_MAP_DIRECT = [
    "amap.com", "autonavi.com", "baidu.com", "bdimg.com", "qq.com",
    "mapbar.com", "sogou.com",
]

CHINA_ECOMMERCE_DIRECT = [
    "jd.com", "360buy.com", "360buyimg.com", "3.cn", "jdstatic.com", "jdimg.com",
    "jdcloud.com", "jcloudcs.com", "jdpay.com",
    "vip.com", "suning.com", "smzdm.com", "dewu.com", "poizon.com",
    "pinduoduo.com", "yangkeduo.com", "pddpic.com", "pinduoduo.net",
]

CHINA_SHORT_VIDEO_DIRECT = [
    "kuaishou.com", "kwai.com", "kwaicdn.com", "kwaicdnx.com", "kwimgs.com",
    "ksapisrv.com", "gifshow.com", "yximgs.com",
]

CHINA_DEVICE_VENDOR_DIRECT = [
    "huawei.com", "hicloud.com", "vmall.com",
    "heytapmobi.com", "oppomobile.com", "vivo.com.cn", "honor.com", "lenovo.com.cn",
]

CHINA_BANKING_DIRECT = [
    "unionpay.com", "95516.com", "ccb.com", "icbc.com.cn", "abchina.com", "cmbchina.com",
    "cmbimg.com", "cmburl.cn", "bankcomm.com", "boc.cn", "cmbc.com.cn", "spdb.com.cn",
    "cib.com.cn", "cebbank.com", "psbc.com", "pingan.com", "citicbank.com",
    "hsbc.com.cn", "hsbc.com.hk",
]

CHINA_MISC_DIRECT = [
    "netease.com", "126.net", "163.com",
]

CHINA_DIRECT_TLD = ["cn", "hk", "tw"]

CHINA_DIRECT = _dedupe_domains(
    CHINA_BYTEDANCE_DIRECT,
    CHINA_ALIBABA_DIRECT,
    CHINA_TENCENT_DIRECT,
    CHINA_SOCIAL_DIRECT,
    CHINA_BAIDU_DIRECT,
    CHINA_VIDEO_DIRECT,
    CHINA_LOCAL_SERVICE_DIRECT,
    CHINA_MAP_DIRECT,
    CHINA_ECOMMERCE_DIRECT,
    CHINA_SHORT_VIDEO_DIRECT,
    CHINA_DEVICE_VENDOR_DIRECT,
    CHINA_BANKING_DIRECT,
    CHINA_MISC_DIRECT,
    CHINA_DIRECT_TLD,
)

CHINA_DIRECT_DNS_POLICY = _dedupe_domains(
    CHINA_BYTEDANCE_DIRECT,
    CHINA_ALIBABA_DIRECT,
    CHINA_TENCENT_DIRECT,
    CHINA_SOCIAL_DIRECT,
    CHINA_BAIDU_DIRECT,
    CHINA_VIDEO_DIRECT,
    CHINA_LOCAL_SERVICE_DIRECT,
    CHINA_MAP_DIRECT,
    CHINA_ECOMMERCE_DIRECT,
    CHINA_SHORT_VIDEO_DIRECT,
    CHINA_DEVICE_VENDOR_DIRECT,
    CHINA_BANKING_DIRECT,
    CHINA_MISC_DIRECT,
)


SHADOWROCKET_OVERSEAS_PROXY = _dedupe_domains(AI_DOMAINS, SOCIAL_PROXY, MEDIA_PROXY)
SHADOWROCKET_CHINA_DIRECT = _dedupe_domains(CHINA_DIRECT)
SHADOWROCKET_PINTEREST = list(PINTEREST_DOMAINS)


def build_shadowrocket_rule_list(name: str, domains: List[str]) -> str:
    lines = [
        f"# NAME: {name}",
        "# AUTHOR: ace-vpn",
        "# FORMAT: Shadowrocket Rule Set",
        f"# DOMAIN-SUFFIX: {len(domains)}",
    ]
    lines.extend(f"DOMAIN-SUFFIX,{domain}" for domain in domains)
    return "\n".join(lines) + "\n"


def build_shadowrocket_conf(name: str = "ace-vpn") -> str:
    """Build a full Shadowrocket config file.

    Shadowrocket users commonly import a 3x-ui base64 node subscription; that
    updates nodes only, not rules. A full config subscription lets iOS update
    routing rules in one place without rule-set UI support.
    """
    overseas = _dedupe_domains(SHADOWROCKET_PINTEREST, SHADOWROCKET_OVERSEAS_PROXY)
    china = _dedupe_domains(SHADOWROCKET_CHINA_DIRECT)
    lines = [
        "#!MANAGED-CONFIG https://github.com/xiaonancs/ace-vpn",
        f"# NAME: {name}",
        "# AUTHOR: ace-vpn",
        "# FORMAT: Shadowrocket Config",
        "",
        "[General]",
        "bypass-system = true",
        "skip-proxy = 127.0.0.1, localhost, *.local, *.lan",
        "dns-server = system, 119.29.29.29, 223.5.5.5",
        "ipv6 = false",
        "",
        "[Rule]",
        "# Overseas apps / AI / media / image CDN -> proxy",
    ]
    lines.extend(f"DOMAIN-SUFFIX,{domain},PROXY" for domain in overseas)
    lines.append("")
    lines.append("# Mainland China apps / CDN -> direct")
    lines.extend(f"DOMAIN-SUFFIX,{domain},DIRECT" for domain in china)
    lines.extend([
        "",
        "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
        "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
        "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
        "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
        "GEOIP,CN,DIRECT",
        "FINAL,DIRECT",
    ])
    return "\n".join(lines) + "\n"


def build_rules(proxy_names: List[str], intranet: Dict[str, Any]) -> List[str]:
    rules: List[str] = []
    seen_suffix: set[str] = set()

    def add_suffix_rule(domain: str, target: str) -> None:
        key = str(domain).strip().lower()
        if not key or key in seen_suffix:
            return
        seen_suffix.add(key)
        rules.append(f"DOMAIN-SUFFIX,{key},{target}")

    # 1. 公司内网最优先（CIDR + 域名）
    for cidr in intranet["cidrs"]:
        rules.append(f"IP-CIDR,{cidr},DIRECT,no-resolve")
    for sfx in intranet["domains"]:
        add_suffix_rule(sfx, "DIRECT")

    # 2. 私有网段兜底
    rules += [
        "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
        "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
        "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
        "IP-CIDR6,fc00::/7,DIRECT,no-resolve",
    ]

    # 3. extra.overseas（用户在 Mac 上 promote 上来的代理域名）
    #    放在 AI / SOCIAL_PROXY 之前，让用户手加规则赢内置默认
    for d in intranet.get("extra_overseas") or []:
        add_suffix_rule(d, "🚀 PROXY")

    # 4. extra.cn（用户 promote 上来的强制直连域名）
    #    放在 AI / SOCIAL_PROXY 之前，让"国内被误判"的修正生效
    for d in intranet.get("extra_cn") or []:
        add_suffix_rule(d, "DIRECT")

    # 5. AI（内置）
    for d in AI_DOMAINS:
        add_suffix_rule(d, "🤖 AI")

    # 6. 社交/工具（强制走代理，内置）
    for d in SOCIAL_PROXY:
        add_suffix_rule(d, "🚀 PROXY")

    # 7. 流媒体（内置）
    for d in MEDIA_PROXY:
        add_suffix_rule(d, "📺 MEDIA")

    # 8. 国内直连（抖音/淘宝/B 站等，内置）
    for d in CHINA_DIRECT:
        add_suffix_rule(d, "DIRECT")

    # 9. GEOIP 兜底
    rules += [
        "GEOIP,PRIVATE,DIRECT,no-resolve",
        "GEOIP,CN,DIRECT",
        "MATCH,🐟 FINAL",
    ]
    return rules


def build_clash_yaml(
    proxies: List[Dict[str, Any]],
    intranet: Dict[str, Any],
    tun_enable: Optional[bool] = None,
    find_process_mode: Optional[str] = None,
) -> str:
    if not proxies:
        return "# ERROR: No nodes parsed from upstream subscription.\n"
    if tun_enable is None:
        tun_enable = TUN_ENABLE_DEFAULT
    if find_process_mode is None:
        find_process_mode = FIND_PROCESS_MODE_DEFAULT
    if find_process_mode not in ("off", "strict", "always"):
        find_process_mode = "off"

    names = [p["name"] for p in proxies]

    config: Dict[str, Any] = {
        "mixed-port": 7890,
        "allow-lan": False,
        "mode": "rule",
        "log-level": "info",
        "external-controller": "127.0.0.1:9090",
        "find-process-mode": find_process_mode,
        "ipv6": False,
        "unified-delay": True,
        "tcp-concurrent": True,
        "geodata-mode": True,
        "geox-url": {
            "geoip": "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat",
            "geosite": "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat",
            "mmdb": "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb",
        },
        "dns": {
            "enable": True,
            "listen": "0.0.0.0:1053",
            "enhanced-mode": "fake-ip",
            "fake-ip-range": "198.18.0.1/16",
            # 让 DNS 解析遵从 rules 分流决策（和下面 sniffer 配合最精确）
            "respect-rules": True,
            # fake-ip-filter：列在这里的域名走真实 DNS，其他域名返回 198.18.x.x 假 IP。
            # 决策规则见本文件顶部"DNS 层决策矩阵"：走 DIRECT 必须跳过，走 PROXY 但被
            # CLI/agent 使用的域名例外跳过，其他走 PROXY 的默认保留 fake-ip。
            # *.lan / *.local 是 Mihomo 默认黑名单保留项；"+." 前缀 = 匹配该域名及所有子域。
            "fake-ip-filter": [
                # — 系统/局域网必需 —
                "*.lan",
                "*.local",
                "+.msftconnecttest.com",  # Windows 网络连通性检测（走系统默认 DNS）
                "+.msftncsi.com",          # 同上
                # — DIRECT 类（必须跳过，见不变式 #1） —
                *[f"+.{sfx}" for sfx in intranet["domains"]],          # 公司内网
                *[f"+.{sfx}" for sfx in (intranet.get("extra_cn") or [])],  # 用户 promote 强制直连
                *[f"+.{sfx}" for sfx in CHINA_DIRECT],                 # 国内大站 (baidu/taobao/...)
                # — PROXY 类例外（CLI 缓存坑，见不变式 #3） —
                *[f"+.{sfx}" for sfx in AI_STREAMING_DOMAINS],         # Cursor / Claude Code / Codex / Gemini 等
                *[f"+.{sfx}" for sfx in (intranet.get("extra_overseas") or [])],  # 用户 promote 走代理（多半也是 CLI）
                # — 其他走 PROXY 的域名（SOCIAL_PROXY / MEDIA_PROXY）不在这里 —
                #   保留 fake-ip 是 Clash 经典设计：本地不解析，域名原样送节点，
                #   由节点所在地 DNS 解析，规避国内 DoH 污染 + 规避 DoH 鸡生蛋。
            ],
            # 关键：内网域名用 profile 里配的 dns_servers（例如公司 VPN 下发的
            # 10.x.x.x 内网 DNS），回落到 "system"。用具体 DNS 能绕过 Mihomo /
            # Clash Party GUI 强改系统 DNS 后内网域名解不出的问题。
            # 用 list(...) 给每个 domain 独立副本，避免 PyYAML dump 出 &id001
            # 锚点语法（Mihomo 支持，但某些简易客户端/可读性不友好）。
            #
            # extra.cn 域名强制走 CN_PUBLIC_DNS（国内 UDP 公网 DNS）：
            # 见 CN_PUBLIC_DNS 注释，避免 default DoH 经 PROXY 拿到海外 IP。
            #
            # AI_STREAMING_DOMAINS + extra.overseas 强制走 OVERSEAS_DOH（境外 DoH）：
            # 见 OVERSEAS_DOH 注释（§4.A.9），避免国内 DoH 污染境外 AI 域名。
            "nameserver-policy": {
                **{
                    f"+.{sfx}": (
                        list(intranet["domain_dns"][sfx])
                        if sfx in intranet["domain_dns"]
                        else "system"
                    )
                    for sfx in intranet["domains"]
                },
                **{
                    f"+.{sfx}": list(CN_PUBLIC_DNS)
                    for sfx in (intranet.get("extra_cn") or [])
                },
                **{
                    f"+.{sfx}": list(CN_PUBLIC_DNS)
                    for sfx in CHINA_DIRECT_DNS_POLICY
                },
                **{
                    f"+.{sfx}": list(OVERSEAS_DOH)
                    for sfx in AI_STREAMING_DOMAINS
                },
                **{
                    f"+.{sfx}": list(OVERSEAS_DOH)
                    for sfx in (intranet.get("extra_overseas") or [])
                    if sfx not in AI_STREAMING_DOMAINS  # 去重，AI 内置优先
                },
            },
            "nameserver": [
                "https://doh.pub/dns-query",
                "https://dns.alidns.com/dns-query",
            ],
            "fallback": [
                "https://dns.cloudflare.com/dns-query",
                "https://dns.google/dns-query",
            ],
            "fallback-filter": {"geoip": True, "geoip-code": "CN"},
            # 解析 PROXY 节点 server 字段用的 bootstrap DNS，respect-rules:true
            # 必配（见 PROXY_SERVER_DNS 注释）。主机必须是 IP。
            "proxy-server-nameserver": list(PROXY_SERVER_DNS),
        },
        # sniffer：fake-ip 模式下嗅探 TLS SNI / HTTP Host / QUIC，拿到真实域名后
        # 按 nameserver-policy 重新选择 DNS 服务器。不开的话 AI 域名虽然有 policy
        # 也生效不了（因为流量进来时只有 fake-IP、没有域名信息）（见 §4.A.9）。
        #
        # override-destination: true 让 mihomo 用嗅探到的真实 SNI 作为目标域名
        # 重写连接目的地，修复 Cursor / Anthropic 长流偶发的 "SNI mismatch → RST"。
        "sniffer": {
            "enable": True,
            "parse-pure-ip": True,
            "force-dns-mapping": True,
            "override-destination": True,
            "sniff": {
                "HTTP": {
                    "ports": [80, 443, 8080, 8443],
                    "override-destination": True,
                },
                "TLS": {
                    "ports": [443, 8443],
                    "override-destination": True,
                },
                "QUIC": {
                    "ports": [443, 8443],
                    "override-destination": True,
                },
            },
        },
        # tun.enable 默认值由 TUN_ENABLE 环境变量 / ?tun= query 决定（见 TUN_ENABLE_DEFAULT）。
        # 桌面端下发 true，避免订阅刷新关掉本地 TUN 造成直连泄漏（开发者日志 §6.16）。
        "tun": {
            "enable": tun_enable,
            "stack": "mixed",
            "auto-route": True,
            "auto-redirect": False,
            "auto-detect-interface": True,
            "dns-hijack": ["any:53"],
            # 公司 VPN 常占用 1.0.0.0/8（utun6），Mihomo 再加同段路由会报
            # "add route: 1.0.0.0/8: file exists"，导致 TUN 整体启动失败。
            # 排除此段可让 TUN 与公司 VPN 共存；1/8 少量流量仍按系统/公司 VPN 路由走。
            "route-exclude-address": ["1.0.0.0/8"],
            "mtu": TUN_MTU,
        },
        "proxies": proxies,
        "proxy-groups": [
            {"name": "🚀 PROXY", "type": "select", "proxies": ["⚡ MAIN_AUTO", *names, "DIRECT"]},
            {
                "name": "⚡ MAIN_AUTO",
                "type": "url-test",
                "proxies": names,
                "url": MAIN_URL_TEST,
                "interval": 300,
                "tolerance": 50,
            },
            {
                "name": "🤖 AI_AUTO",
                "type": "url-test",
                "proxies": names,
                "url": AI_URL_TEST,
                "interval": 300,
                "tolerance": 50,
            },
            {"name": "🤖 AI", "type": "select", "proxies": ["🤖 AI_AUTO", "🚀 PROXY", "⚡ MAIN_AUTO", *names]},
            {"name": "📺 MEDIA", "type": "select", "proxies": ["🚀 PROXY", "⚡ MAIN_AUTO", *names]},
            {"name": "🐟 FINAL", "type": "select", "proxies": ["🚀 PROXY", "DIRECT"]},
        ],
        "rules": build_rules(names, intranet),
    }

    return yaml.safe_dump(
        config, sort_keys=False, allow_unicode=True, width=1000, default_flow_style=False
    )


def _parse_host(url_or_host: str) -> str:
    """接受 'https://x.com/path' 或 'x.com' 或 'x.com:8080/foo'，返回纯 host。"""
    s = url_or_host.strip()
    if "://" in s:
        p = urllib.parse.urlparse(s)
        return p.hostname or ""
    return s.split("/")[0].split(":")[0]


def _try_resolve(host: str) -> Optional[str]:
    """尽量解析一个 IP；失败或解析到 Clash fake-ip (198.18.0.0/16) 时返回 None。

    sub-converter 跑在 VPS 上时返回的是真实公网 DNS 结果；但开发/诊断时如果
    在本地 Mac（开启 Clash TUN）调用会返回 198.18.x.x 的假 IP，那是 Clash
    自己的 fake-ip 机制，不能当作真实解析结果用（会误命中 GEOIP,PRIVATE）。
    """
    try:
        ip = socket.gethostbyname(host)
    except Exception:  # noqa: BLE001
        return None
    try:
        if ipaddress.ip_address(ip) in ipaddress.ip_network("198.18.0.0/16"):
            return None
    except ValueError:
        return None
    return ip


def _suffix_match(host: str, sfx: str) -> bool:
    host = host.lower().rstrip(".")
    sfx = sfx.lower().rstrip(".")
    return host == sfx or host.endswith("." + sfx)


def match_rule(url_or_host: str, intranet: Dict[str, Any]) -> Dict[str, Any]:
    """把 build_rules 的规则按顺序跑一遍，返回第一条命中。

    GEOIP 规则当前不做在线查询（要第三方库或外部服务），视为"未检查"，
    如果前面规则都没命中就 fall through 到 MATCH。
    """
    host = _parse_host(url_or_host)
    resolved_ip = _try_resolve(host) if host else None
    rules = build_rules([], intranet)

    geoip_notes: List[str] = []

    for idx, rule in enumerate(rules, start=1):
        parts = [p.strip() for p in rule.split(",")]
        rtype = parts[0]
        hit = False

        if rtype == "MATCH":
            return _match_result(url_or_host, host, resolved_ip, idx, rule, parts[1], geoip_notes)

        if rtype == "DOMAIN-SUFFIX" and host and _suffix_match(host, parts[1]):
            hit = True
        elif rtype == "DOMAIN" and host and host.lower() == parts[1].lower():
            hit = True
        elif rtype == "DOMAIN-KEYWORD" and host and parts[1].lower() in host.lower():
            hit = True
        elif rtype in ("IP-CIDR", "IP-CIDR6"):
            # 忽略 no-resolve 标志——我们总是已经尝试过解析
            if resolved_ip:
                try:
                    if ipaddress.ip_address(resolved_ip) in ipaddress.ip_network(parts[1], strict=False):
                        hit = True
                except ValueError:
                    pass
        elif rtype == "GEOIP":
            code = parts[1].upper()
            if code == "PRIVATE" and resolved_ip:
                try:
                    if ipaddress.ip_address(resolved_ip).is_private:
                        hit = True
                except ValueError:
                    pass
            else:
                # 没有内置 GEOIP 数据，标记一下让调用方知道
                geoip_notes.append(f"GEOIP,{code} (skipped: no local db)")
                continue

        if hit:
            target = parts[2] if len(parts) >= 3 else parts[-1]
            return _match_result(url_or_host, host, resolved_ip, idx, rule, target, geoip_notes)

    return _match_result(url_or_host, host, resolved_ip, 0, "no match", "UNKNOWN", geoip_notes)


def _match_result(
    input_: str, host: str, ip: Optional[str], idx: int, rule: str, target: str, notes: List[str]
) -> Dict[str, Any]:
    return {
        "input": input_,
        "host": host,
        "resolved_ip": ip,
        "rule_index": idx,
        "rule": rule,
        "target": target,
        "notes": notes,
    }


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "server"
    sys_version = ""

    def do_GET(self):  # noqa: N802
        if self._rate_limited():
            self._reply(429, b"Too Many Requests\n", "text/plain")
            return

        parsed = urllib.parse.urlparse(self.path)
        # 期望 /<SUB_PATH_PREFIX>/<token>，不接受多级 path；/healthz 是简单自检
        request_path = parsed.path.rstrip("/")
        if request_path == "/healthz":
            if not self._admin_allowed():
                self._reply(404, b"Not Found\n", "text/plain")
                return
            intranet = load_intranet_config()
            body = (
                f"ok\n"
                f"active_profiles={','.join(intranet['active_profiles']) or '(none)'}\n"
                f"domains={len(intranet['domains'])}\n"
                f"cidrs={len(intranet['cidrs'])}\n"
                f"extra_overseas={len(intranet.get('extra_overseas') or [])}\n"
                f"extra_cn={len(intranet.get('extra_cn') or [])}\n"
            ).encode()
            self._reply(200, body, "text/plain; charset=utf-8")
            return

        # 诊断接口：GET /match?url=<...>  或  /match?host=<...>
        # 返回 JSON：命中哪条规则、目标组、解析到的 IP 等
        if request_path == "/match":
            if not self._admin_allowed():
                self._reply(404, b"Not Found\n", "text/plain")
                return
            try:
                qs = urllib.parse.urlparse(self.path).query
                params = dict(urllib.parse.parse_qsl(qs))
                target = params.get("url") or params.get("host")
                if not target:
                    self._reply(400,
                                b'{"error":"provide ?url=<URL> or ?host=<HOST>"}\n',
                                "application/json; charset=utf-8")
                    return
                intranet = load_intranet_config()
                result = match_rule(target, intranet)
                result["active_profiles"] = intranet["active_profiles"]
                body = json.dumps(result, ensure_ascii=False, indent=2).encode("utf-8")
                self._reply(200, body, "application/json; charset=utf-8")
            except Exception as e:  # noqa: BLE001
                self._reply(500, f'{{"error":"{e}"}}\n'.encode(), "application/json; charset=utf-8")
            return

        # Shadowrocket 用 3x-ui base64 节点订阅，服务端 Clash YAML rules 不会自动下发到
        # 手机本地配置。这里提供同源、无需翻墙的完整配置和规则集 URL，给 iOS 端配置模式订阅。
        config_base = f"/{SUB_PATH_PREFIX}/_configs"
        if request_path == f"{config_base}/shadowrocket.conf":
            body = build_shadowrocket_conf("ace-vpn shadowrocket").encode("utf-8")
            self._reply(200, body, "text/plain; charset=utf-8")
            return

        rule_base = f"/{SUB_PATH_PREFIX}/_rules"
        shadowrocket_rule_sets = {
            f"{rule_base}/shadowrocket-overseas-proxy.list": (
                "ace-vpn overseas proxy",
                SHADOWROCKET_OVERSEAS_PROXY,
            ),
            f"{rule_base}/shadowrocket-china-direct.list": (
                "ace-vpn china direct",
                SHADOWROCKET_CHINA_DIRECT,
            ),
            f"{rule_base}/shadowrocket-pinterest.list": (
                "ace-vpn pinterest",
                [
                    "pinimg.com",
                    "pinterest.at", "pinterest.ca", "pinterest.ch", "pinterest.cl",
                    "pinterest.co.kr", "pinterest.co.uk", "pinterest.com",
                    "pinterest.com.au", "pinterest.com.mx", "pinterest.de",
                    "pinterest.dk", "pinterest.es", "pinterest.fr", "pinterest.ie",
                    "pinterest.it", "pinterest.jp", "pinterest.nl", "pinterest.nz",
                    "pinterest.ph", "pinterest.pt", "pinterest.ru", "pinterest.se",
                ],
            ),
        }
        if request_path in shadowrocket_rule_sets:
            name, domains = shadowrocket_rule_sets[request_path]
            body = build_shadowrocket_rule_list(name, domains).encode("utf-8")
            self._reply(200, body, "text/plain; charset=utf-8")
            return

        # 拆掉 query 再解析 path；?tun=1/0 可按设备覆盖 tun.enable 默认值。
        # ?process=1/strict/always 可按设备打开进程归因，便于本地流量报表统计
        # "来源于哪个 app"；默认 off，避免日常使用付出额外开销。
        # 订阅路径由 SUB_PATH_PREFIX 控制，形如 /<long-random-prefix>/<token>，
        # 降低公网订阅端口被扫到后的可识别性。
        query = dict(urllib.parse.parse_qsl(parsed.query))
        tun_enable: Optional[bool] = None
        if "tun" in query:
            tun_enable = query["tun"].strip().lower() in ("1", "true", "yes", "on")
        find_process_mode: Optional[str] = None
        if "process" in query:
            process_value = query["process"].strip().lower()
            if process_value in ("1", "true", "yes", "on", "strict"):
                find_process_mode = "strict"
            elif process_value == "always":
                find_process_mode = "always"
            else:
                find_process_mode = "off"

        parts = parsed.path.rstrip("/").split("/")
        if len(parts) != 3 or parts[1] != SUB_PATH_PREFIX or not parts[2]:
            self._reply(404, b"Not Found\n", "text/plain")
            return
        token = parts[2]
        upstream = resolve_upstream(token)
        if not upstream:
            self._reply(404, b"Not Found\n", "text/plain")
            return
        if tun_enable is None and token in TUN_TOKENS:
            tun_enable = True
        try:
            intranet = load_intranet_config()  # 每次请求热加载 → 改 YAML 立即生效
            raw = fetch_sub(upstream)
            text = b64decode(raw) if "vless://" not in raw else raw
            proxies = []
            for line in text.splitlines():
                p = parse_vless(line.strip())
                if p:
                    proxies.append(p)
            body = build_clash_yaml(
                proxies,
                intranet,
                tun_enable=tun_enable,
                find_process_mode=find_process_mode,
            ).encode("utf-8")
            self._reply(
                200,
                body,
                "text/yaml; charset=utf-8",
                extra={"Profile-Update-Interval": "24"},
            )
        except Exception as e:  # noqa: BLE001
            sys.stderr.write(f"[error] subscription build failed from {self.client_address[0]}: {e}\n")
            self._reply(500, b"# Error: temporary subscription failure\n", "text/plain; charset=utf-8")

    def _is_local_client(self) -> bool:
        host = self.client_address[0]
        try:
            ip = ipaddress.ip_address(host)
            return ip.is_loopback
        except ValueError:
            return host in ("localhost",)

    def _admin_allowed(self) -> bool:
        if self._is_local_client():
            return True
        if not SUB_ADMIN_TOKEN:
            return False
        parsed = urllib.parse.urlparse(self.path)
        params = dict(urllib.parse.parse_qsl(parsed.query))
        supplied = params.get("admin_token") or params.get("token") or ""
        auth = self.headers.get("Authorization", "")
        if auth.lower().startswith("bearer "):
            supplied = auth[7:].strip()
        header_token = self.headers.get("X-Admin-Token", "")
        supplied = header_token.strip() or supplied
        return secrets.compare_digest(supplied, SUB_ADMIN_TOKEN)

    def _rate_limited(self) -> bool:
        if SUB_RATE_LIMIT_PER_MIN <= 0 or self._is_local_client():
            return False
        now = time.time()
        key = self.client_address[0]
        with _RATE_LOCK:
            bucket = [t for t in _RATE_BUCKETS.get(key, []) if now - t < 60]
            if len(bucket) >= SUB_RATE_LIMIT_PER_MIN:
                _RATE_BUCKETS[key] = bucket
                return True
            bucket.append(now)
            _RATE_BUCKETS[key] = bucket
        return False

    def _reply(self, code: int, body: bytes, ctype: str, extra: Optional[Dict[str, str]] = None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[{self.log_date_time_string()}] {self.address_string()} {fmt % args}\n")


class ReusableThreadingTCPServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main() -> int:
    if not UPSTREAM_BASE and not UPSTREAM_SUB and not UPSTREAM_INLINE:
        print("ERROR: Set UPSTREAM_INLINE, UPSTREAM_BASE+SUB_TOKENS (multi), or UPSTREAM_SUB+SUB_TOKEN (single)",
              file=sys.stderr)
        return 1
    if UPSTREAM_BASE and not SUB_TOKENS:
        print("ERROR: UPSTREAM_BASE set but SUB_TOKENS is empty; no tokens will be valid.",
              file=sys.stderr)
        return 1

    print(f"ace-vpn sub-converter listening on {LISTEN_HOST}:{LISTEN_PORT}", flush=True)
    if UPSTREAM_INLINE:
        print(f"  [Inline upstream mode]", flush=True)
        for t in (SUB_TOKENS or [SUB_TOKEN]):
            masked = f"{t[:4]}...{t[-4:]}" if len(t) > 10 else "***"
            print(f"    - http://<VPS-IP>:{LISTEN_PORT}/{SUB_PATH_PREFIX}/{masked}", flush=True)
    elif UPSTREAM_BASE:
        print(f"  [Multi-token mode]", flush=True)
        print(f"  Upstream base: {UPSTREAM_BASE}/<token>", flush=True)
        for t in SUB_TOKENS:
            masked = f"{t[:4]}...{t[-4:]}" if len(t) > 10 else "***"
            print(
                f"    - http://<VPS-IP>:{LISTEN_PORT}/{SUB_PATH_PREFIX}/{masked}",
                flush=True,
            )
    else:
        print(f"  [Single-token mode]", flush=True)
        print(f"  Upstream: {UPSTREAM_SUB}", flush=True)
        masked = f"{SUB_TOKEN[:4]}...{SUB_TOKEN[-4:]}" if len(SUB_TOKEN) > 10 else "***"
        print(f"  Clash URL: http://<VPS-IP>:{LISTEN_PORT}/{SUB_PATH_PREFIX}/{masked}", flush=True)

    _init = load_intranet_config()
    print(
        f"  Intranet file: {INTRANET_FILE} "
        f"(active: {','.join(_init['active_profiles']) or '(none)'}, "
        f"domains: {len(_init['domains'])}, cidrs: {len(_init['cidrs'])})",
        flush=True,
    )

    with ReusableThreadingTCPServer((LISTEN_HOST, LISTEN_PORT), Handler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
