#!/usr/bin/env python3
"""ace-vpn 订阅转换器：3x-ui base64 (vless://) → Clash Meta YAML

支持两种模式（环境变量）：

[A] 单 token 模式（兼容旧部署）：
    UPSTREAM_SUB    完整的 3x-ui 订阅 URL
    SUB_TOKEN       访问 token，客户端 URL：/clash/$SUB_TOKEN

[B] 多 token 模式（推荐，一个实例服务全家）：
    UPSTREAM_BASE   3x-ui 订阅 URL 前缀（不含 SubId 那一段）
                    例：https://127.0.0.1:2096/sub_xxxxxxxx
    SUB_TOKENS      白名单，逗号分隔，每个 token = 3x-ui 里的一个 SubId
                    例：sub-hxn,sub-hxn01,dad-home
    客户端 URL：/clash/<任意白名单里的 token>
    实际从 $UPSTREAM_BASE/<token> 拉上游

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
import urllib.parse
import urllib.request
import yaml
from typing import List, Dict, Any, Optional


# 模式 A：单 token
UPSTREAM_SUB = os.environ.get("UPSTREAM_SUB", "").strip()
SUB_TOKEN = os.environ.get("SUB_TOKEN", "").strip() or secrets.token_urlsafe(12)

# 模式 B：多 token（推荐）
UPSTREAM_BASE = os.environ.get("UPSTREAM_BASE", "").strip().rstrip("/")
SUB_TOKENS = [t.strip() for t in os.environ.get("SUB_TOKENS", "").split(",") if t.strip()]

LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "25500"))
COMPANY_CIDRS = [c.strip() for c in os.environ.get("COMPANY_CIDRS", "").split(",") if c.strip()]
COMPANY_SFX = [c.strip() for c in os.environ.get("COMPANY_SFX", "").split(",") if c.strip()]
INTRANET_FILE = os.environ.get("INTRANET_FILE", "/etc/ace-vpn/intranet.yaml").strip()
# 保险丝：强制覆盖节点 server 字段（3x-ui 会根据 Host 头返回 127.0.0.1 等内网 IP，这里统一改成公网 IP）
SERVER_OVERRIDE = os.environ.get("SERVER_OVERRIDE", "").strip()

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


def load_intranet_config() -> Dict[str, Any]:
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
            if x not in seen:
                seen.add(x)
                out.append(x)
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
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(url, headers={"User-Agent": "ace-vpn/1.0"})
    with urllib.request.urlopen(req, context=ctx, timeout=10) as r:
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
# 🤖 AI group 现在专门用来"标记需要走特殊出口（例如 VPS 上 xray 的 wireguard
# outbound 把 Google AI 转 WARP）的域名"。其他 AI 站（OpenAI / Claude / Cursor 等）
# 在 VPS 那边能直出干净 IP，留在默认 🚀 PROXY 即可，没必要进 🤖 AI；进了反而让
# mac 端 group 显示混乱、并误导 VPS 端 routing 加多余规则。
#
# 👉 想"专属出口"的域名才往这里加；只是"想代理"的请让它走 🚀 PROXY。
AI_DOMAINS = [
    "gemini.google.com",
    "bard.google.com",
    "aistudio.google.com",
    "generativelanguage.googleapis.com",
    "makersuite.google.com",
    "notebooklm.google.com",
    "labs.google",
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
    # Google（含搜索/邮件等）
    "google.com", "gstatic.com", "googleusercontent.com", "googleapis.com", "ggpht.com",
    # GitHub
    "github.com", "githubusercontent.com", "githubassets.com",
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

CHINA_DIRECT = [
    # ByteDance / Douyin
    "douyin.com", "aweme.snssdk.com", "snssdk.com", "bytedance.com", "bytedancecdn.com",
    "douyincdn.com", "douyinpic.com", "douyinvod.com", "iesdouyin.com", "pstatp.com",
    "toutiao.com", "toutiaoimg.com", "toutiaocdn.com", "bdstatic.com",
    # Alibaba
    "taobao.com", "tmall.com", "alibaba.com", "alicdn.com", "aliyun.com",
    "alipay.com", "alipayobjects.com", "1688.com", "tanx.com", "mmstat.com",
    # Tencent
    "qq.com", "qpic.cn", "tencent.com", "tencent-cloud.com", "weixin.qq.com",
    "gtimg.com", "gtimg.cn", "tenpay.com",
    # Social 国内
    "weibo.com", "weibo.cn", "sinaimg.cn", "sina.com.cn", "sina.cn", "miaopai.com",
    "zhihu.com", "zhimg.com", "xiaohongshu.com", "xhscdn.com",
    "douban.com", "doubanio.com",
    # Baidu
    "baidu.com", "bdimg.com", "bdstatic.com", "baidupcs.com",
    # 视频
    "bilibili.com", "biliapi.net", "bilivideo.com", "hdslb.com",
    "iqiyi.com", "iqiyipic.com",
    "youku.com", "ykimg.com",
    # Misc
    "jd.com", "360buyimg.com", "meituan.net", "meituan.com",
    "netease.com", "126.net", "163.com",
    "cn", "hk", "tw",  # TLD 兜底
]


def build_rules(proxy_names: List[str], intranet: Dict[str, Any]) -> List[str]:
    rules: List[str] = []

    # 1. 公司内网最优先（CIDR + 域名）
    for cidr in intranet["cidrs"]:
        rules.append(f"IP-CIDR,{cidr},DIRECT,no-resolve")
    for sfx in intranet["domains"]:
        rules.append(f"DOMAIN-SUFFIX,{sfx},DIRECT")

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
        rules.append(f"DOMAIN-SUFFIX,{d},🚀 PROXY")

    # 4. extra.cn（用户 promote 上来的强制直连域名）
    #    放在 AI / SOCIAL_PROXY 之前，让"国内被误判"的修正生效
    for d in intranet.get("extra_cn") or []:
        rules.append(f"DOMAIN-SUFFIX,{d},DIRECT")

    # 5. AI（内置）
    for d in AI_DOMAINS:
        rules.append(f"DOMAIN-SUFFIX,{d},🤖 AI")

    # 6. 社交/工具（强制走代理，内置）
    for d in SOCIAL_PROXY:
        rules.append(f"DOMAIN-SUFFIX,{d},🚀 PROXY")

    # 7. 流媒体（内置）
    for d in MEDIA_PROXY:
        rules.append(f"DOMAIN-SUFFIX,{d},📺 MEDIA")

    # 8. 国内直连（抖音/淘宝/B 站等，内置）
    for d in CHINA_DIRECT:
        if len(d) <= 2:
            rules.append(f"DOMAIN-SUFFIX,{d},DIRECT")
        else:
            rules.append(f"DOMAIN-SUFFIX,{d},DIRECT")

    # 9. GEOIP 兜底
    rules += [
        "GEOIP,PRIVATE,DIRECT,no-resolve",
        "GEOIP,CN,DIRECT",
        "MATCH,🐟 FINAL",
    ]
    return rules


def build_clash_yaml(proxies: List[Dict[str, Any]], intranet: Dict[str, Any]) -> str:
    if not proxies:
        return "# ERROR: No nodes parsed from upstream subscription.\n"

    names = [p["name"] for p in proxies]

    config: Dict[str, Any] = {
        "mixed-port": 7890,
        "allow-lan": False,
        "mode": "rule",
        "log-level": "info",
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
            # 关键：内网域名必须跳过 fake-ip，否则 Clash 会给它们发 198.18.x.x 假 IP，
            # 导致 DIRECT 规则命中后拿不到真实 IP，连接被 RST。
            # *.lan / *.local 是默认黑名单，+ 开头表示匹配该域名及其所有子域
            "fake-ip-filter": [
                "*.lan",
                "*.local",
                "+.msftconnecttest.com",
                "+.msftncsi.com",
                *[f"+.{sfx}" for sfx in intranet["domains"]],
                # extra.cn 也跳过 fake-ip：避免 Mihomo fake-ip 反查路径上某些客户端
                # 实现把 nameserver-policy 绕过去，导致 DIRECT 真实解析仍走默认 DoH
                *[f"+.{sfx}" for sfx in (intranet.get("extra_cn") or [])],
            ],
            # 关键：内网域名用 profile 里配的 dns_servers（例如公司 VPN 下发的
            # 10.x.x.x 内网 DNS），回落到 "system"。用具体 DNS 能绕过 Mihomo /
            # Clash Party GUI 强改系统 DNS 后内网域名解不出的问题。
            # 用 list(...) 给每个 domain 独立副本，避免 PyYAML dump 出 &id001
            # 锚点语法（Mihomo 支持，但某些简易客户端/可读性不友好）。
            #
            # extra.cn 域名强制走 CN_PUBLIC_DNS（国内 UDP 公网 DNS）：
            # 见 CN_PUBLIC_DNS 注释，避免 default DoH 经 PROXY 拿到海外 IP。
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
        },
        "tun": {
            "enable": False,
            "stack": "mixed",
            "auto-route": True,
            "auto-detect-interface": True,
            "dns-hijack": ["any:53"],
        },
        "proxies": proxies,
        "proxy-groups": [
            {"name": "🚀 PROXY", "type": "select", "proxies": ["⚡ AUTO", *names, "DIRECT"]},
            {
                "name": "⚡ AUTO",
                "type": "url-test",
                "proxies": names,
                "url": "https://www.gstatic.com/generate_204",
                "interval": 300,
                "tolerance": 50,
            },
            {"name": "🤖 AI", "type": "select", "proxies": ["🚀 PROXY", "⚡ AUTO", *names]},
            {"name": "📺 MEDIA", "type": "select", "proxies": ["🚀 PROXY", "⚡ AUTO", *names]},
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
    server_version = "ace-vpn/1.0"

    def do_GET(self):  # noqa: N802
        # 期望 /clash/<token>，不接受多级 path；/healthz 是简单自检
        if self.path.rstrip("/") == "/healthz":
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
        if self.path.split("?")[0].rstrip("/") == "/match":
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

        parts = self.path.rstrip("/").split("/")
        if len(parts) != 3 or parts[1] != "clash" or not parts[2]:
            self._reply(404, b"Not Found\n", "text/plain")
            return
        token = parts[2]
        upstream = resolve_upstream(token)
        if not upstream:
            self._reply(404, b"Not Found\n", "text/plain")
            return
        try:
            intranet = load_intranet_config()  # 每次请求热加载 → 改 YAML 立即生效
            raw = fetch_sub(upstream)
            text = b64decode(raw) if "vless://" not in raw else raw
            proxies = []
            for line in text.splitlines():
                p = parse_vless(line.strip())
                if p:
                    proxies.append(p)
            body = build_clash_yaml(proxies, intranet).encode("utf-8")
            self._reply(
                200,
                body,
                "text/yaml; charset=utf-8",
                extra={"Profile-Update-Interval": "24"},
            )
        except Exception as e:  # noqa: BLE001
            self._reply(500, f"# Error: {e}\n".encode(), "text/plain; charset=utf-8")

    def _reply(self, code: int, body: bytes, ctype: str, extra: Optional[Dict[str, str]] = None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[{self.log_date_time_string()}] {self.address_string()} {fmt % args}\n")


def main() -> int:
    if not UPSTREAM_BASE and not UPSTREAM_SUB:
        print("ERROR: Set either UPSTREAM_BASE+SUB_TOKENS (multi) or UPSTREAM_SUB+SUB_TOKEN (single)",
              file=sys.stderr)
        return 1
    if UPSTREAM_BASE and not SUB_TOKENS:
        print("ERROR: UPSTREAM_BASE set but SUB_TOKENS is empty; no tokens will be valid.",
              file=sys.stderr)
        return 1

    print(f"ace-vpn sub-converter listening on 0.0.0.0:{LISTEN_PORT}", flush=True)
    if UPSTREAM_BASE:
        print(f"  [Multi-token mode]", flush=True)
        print(f"  Upstream base: {UPSTREAM_BASE}/<token>", flush=True)
        for t in SUB_TOKENS:
            print(f"    - http://<VPS-IP>:{LISTEN_PORT}/clash/{t}  (-> {UPSTREAM_BASE}/{t})", flush=True)
    else:
        print(f"  [Single-token mode]", flush=True)
        print(f"  Upstream: {UPSTREAM_SUB}", flush=True)
        print(f"  Clash URL: http://<VPS-IP>:{LISTEN_PORT}/clash/{SUB_TOKEN}", flush=True)

    _init = load_intranet_config()
    print(
        f"  Intranet file: {INTRANET_FILE} "
        f"(active: {','.join(_init['active_profiles']) or '(none)'}, "
        f"domains: {len(_init['domains'])}, cidrs: {len(_init['cidrs'])})",
        flush=True,
    )

    with socketserver.ThreadingTCPServer(("0.0.0.0", LISTEN_PORT), Handler) as httpd:
        httpd.allow_reuse_address = True
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
