#!/usr/bin/env python3
"""ace-vpn 订阅转换器：3x-ui base64 (vless://) → Clash Meta YAML

用法（环境变量）：
  UPSTREAM_SUB    3x-ui 订阅 URL（支持 http/https，自动跳过证书校验）
  LISTEN_PORT    监听端口，默认 25500
  SUB_TOKEN      访问 token，访问路径 /clash/$SUB_TOKEN，默认随机
  COMPANY_CIDRS  公司内网 CIDR，逗号分隔，例："10.0.0.0/8,172.16.0.0/12"
  COMPANY_SFX    公司域名后缀，逗号分隔，例："corp.example.com,internal.example.com"

固定路由策略：
  - 公司内网（CIDR / 域名后缀）→ DIRECT
  - AI（OpenAI/Claude/Gemini/Cursor/GitHub Copilot）→ 🤖 AI（默认走代理）
  - 境外社交（Discord/X/Telegram/Facebook/Instagram/YouTube）→ 🚀 PROXY
  - 境内常用（抖音/淘宝/B 站/微博/QQ/百度）→ DIRECT
  - GEOIP CN → DIRECT
  - MATCH → 🐟 FINAL（默认代理，可手动切直连）
"""
import base64
import http.server
import os
import secrets
import socketserver
import ssl
import sys
import urllib.parse
import urllib.request
import yaml
from typing import List, Dict, Any, Optional


UPSTREAM_SUB = os.environ.get("UPSTREAM_SUB", "").strip()
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "25500"))
SUB_TOKEN = os.environ.get("SUB_TOKEN", "").strip() or secrets.token_urlsafe(12)
COMPANY_CIDRS = [c.strip() for c in os.environ.get("COMPANY_CIDRS", "").split(",") if c.strip()]
COMPANY_SFX = [c.strip() for c in os.environ.get("COMPANY_SFX", "").split(",") if c.strip()]
# 保险丝：强制覆盖节点 server 字段（3x-ui 会根据 Host 头返回 127.0.0.1 等内网 IP，这里统一改成公网 IP）
SERVER_OVERRIDE = os.environ.get("SERVER_OVERRIDE", "").strip()


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
AI_DOMAINS = [
    "openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com",
    "anthropic.com", "claude.ai",
    "gemini.google.com", "bard.google.com", "generativelanguage.googleapis.com",
    "cursor.sh", "cursor.com",
    "copilot.microsoft.com", "githubcopilot.com",
    "perplexity.ai",
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


def build_rules(proxy_names: List[str]) -> List[str]:
    rules: List[str] = []

    # 1. 公司内网最优先（CIDR + 域名）
    for cidr in COMPANY_CIDRS:
        rules.append(f"IP-CIDR,{cidr},DIRECT,no-resolve")
    for sfx in COMPANY_SFX:
        rules.append(f"DOMAIN-SUFFIX,{sfx},DIRECT")

    # 2. 私有网段兜底
    rules += [
        "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
        "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
        "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
        "IP-CIDR6,fc00::/7,DIRECT,no-resolve",
    ]

    # 3. AI
    for d in AI_DOMAINS:
        rules.append(f"DOMAIN-SUFFIX,{d},🤖 AI")

    # 4. 社交/工具（强制走代理）
    for d in SOCIAL_PROXY:
        rules.append(f"DOMAIN-SUFFIX,{d},🚀 PROXY")

    # 5. 流媒体
    for d in MEDIA_PROXY:
        rules.append(f"DOMAIN-SUFFIX,{d},📺 MEDIA")

    # 6. 国内直连（抖音/淘宝/B 站等）
    for d in CHINA_DIRECT:
        if len(d) <= 2:
            rules.append(f"DOMAIN-SUFFIX,{d},DIRECT")
        else:
            rules.append(f"DOMAIN-SUFFIX,{d},DIRECT")

    # 7. GEOIP 兜底
    rules += [
        "GEOIP,PRIVATE,DIRECT,no-resolve",
        "GEOIP,CN,DIRECT",
        "MATCH,🐟 FINAL",
    ]
    return rules


def build_clash_yaml(proxies: List[Dict[str, Any]]) -> str:
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
            "nameserver-policy": {sfx: "system" for sfx in COMPANY_SFX},
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
        "rules": build_rules(names),
    }

    return yaml.safe_dump(
        config, sort_keys=False, allow_unicode=True, width=1000, default_flow_style=False
    )


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "ace-vpn/1.0"

    def do_GET(self):  # noqa: N802
        expected_prefix = f"/clash/{SUB_TOKEN}"
        if self.path.rstrip("/") != expected_prefix:
            self._reply(404, b"Not Found\n", "text/plain")
            return
        try:
            raw = fetch_sub(UPSTREAM_SUB)
            text = b64decode(raw) if "vless://" not in raw else raw
            proxies = []
            for line in text.splitlines():
                p = parse_vless(line.strip())
                if p:
                    proxies.append(p)
            body = build_clash_yaml(proxies).encode("utf-8")
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
    if not UPSTREAM_SUB:
        print("ERROR: Set UPSTREAM_SUB env var to your 3x-ui subscription URL", file=sys.stderr)
        return 1
    print(f"ace-vpn sub-converter listening on 0.0.0.0:{LISTEN_PORT}", flush=True)
    print(f"  Upstream: {UPSTREAM_SUB}", flush=True)
    print(f"  Clash URL: http://<VPS-IP>:{LISTEN_PORT}/clash/{SUB_TOKEN}", flush=True)
    print(f"  SUB_TOKEN: {SUB_TOKEN}", flush=True)
    with socketserver.ThreadingTCPServer(("0.0.0.0", LISTEN_PORT), Handler) as httpd:
        httpd.allow_reuse_address = True
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
