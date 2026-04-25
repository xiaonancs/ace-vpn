#!/usr/bin/env bash
# ============================================================
# ace-vpn - 3x-ui 自动化配置（通过 HTTP API）
# ============================================================
# 完成：
#   1. 登录 3x-ui 面板
#   2. 生成 Reality 密钥对 + UUID
#   3. 创建 VLESS+Reality 入站（TCP）
#   4. 创建 Hysteria2 入站（UDP）
#   5. 输出 vless:// 和 hysteria2:// 分享链接
#   6. 凭据写入 /root/ace-vpn-credentials.txt（chmod 600）
#
# 依赖：python3（Ubuntu 22.04+ 默认有）、curl、xray
#
# 环境变量：
#   XUI_USER=admin          面板用户名（默认 admin）
#   XUI_PASS=admin          面板密码（默认 admin）
#   XUI_PANEL_PORT=2053     面板端口
#   XUI_PANEL_PATH=""       面板路径（若改过，如 "/xyz123"）
#   TCP_PORT=443            VLESS+Reality 端口
#   UDP_PORT=443            Hysteria2 端口
#   REALITY_DEST=www.cloudflare.com:443
#   REALITY_SNI=www.cloudflare.com
#   CLIENT_EMAIL=self-main  客户端备注
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "${ROOT_DIR}/scripts/lib/common.sh"

require_root

# ---------- 参数 ----------
XUI_USER="${XUI_USER:-admin}"
XUI_PASS="${XUI_PASS:-admin}"
XUI_PANEL_PORT="${PANEL_PORT:-${XUI_PANEL_PORT:-2053}}"
XUI_PANEL_PATH="${XUI_PANEL_PATH:-}"
XUI_PANEL_SCHEME="${XUI_PANEL_SCHEME:-auto}"  # auto / http / https
TCP_PORT="${TCP_PORT:-443}"
# 3x-ui 检查端口占用时不区分 TCP/UDP，因此 Hy2 必须使用不同端口
UDP_PORT="${UDP_PORT:-8443}"
REALITY_DEST="${REALITY_DEST:-www.cloudflare.com:443}"
REALITY_SNI="${REALITY_SNI:-www.cloudflare.com}"
CLIENT_EMAIL="${CLIENT_EMAIL:-self-main}"

COOKIE_JAR="$(mktemp)"
CREDS_FILE="/root/ace-vpn-credentials.txt"
trap 'rm -f "${COOKIE_JAR}"' EXIT

# ---------- 依赖检查 ----------
for cmd in curl python3 openssl; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    log_error "缺少命令：${cmd}"
    exit 1
  fi
done

# ---------- 1. 自动探测 HTTP / HTTPS + 等待面板起来 ----------
log_step "等待 3x-ui 面板响应并探测协议"

detect_scheme() {
  local scheme
  for scheme in https http; do
    if curl -sk --max-time 3 -o /dev/null \
       "${scheme}://127.0.0.1:${XUI_PANEL_PORT}${XUI_PANEL_PATH}/"; then
      echo "${scheme}"
      return 0
    fi
  done
  return 1
}

ATTEMPTS=0
MAX_ATTEMPTS=30
DETECTED_SCHEME=""

if [[ "${XUI_PANEL_SCHEME}" == "auto" ]]; then
  until DETECTED_SCHEME=$(detect_scheme); do
    ATTEMPTS=$((ATTEMPTS + 1))
    if (( ATTEMPTS >= MAX_ATTEMPTS )); then
      log_error "面板端口 ${XUI_PANEL_PORT} 无响应"
      log_error "请确认 3x-ui 已启动：systemctl status x-ui"
      log_error "或检查 PANEL_PORT / XUI_PANEL_PATH 是否正确"
      exit 1
    fi
    sleep 1
  done
else
  DETECTED_SCHEME="${XUI_PANEL_SCHEME}"
fi

PANEL_URL="${DETECTED_SCHEME}://127.0.0.1:${XUI_PANEL_PORT}${XUI_PANEL_PATH}"
# 3x-ui v2：入站 API 在 /panel/api/inbounds/（复数 inbounds），不是 /panel/inbound/
API_INBOUNDS="${PANEL_URL}/panel/api/inbounds"
# 对 https + 给 IP 签的 Let's Encrypt 证书，curl 校验 CN=IP 时可能不匹配，放宽
CURL_OPTS="-sk --max-time 10"
log_ok "面板响应正常：${PANEL_URL}"

# ---------- 2. 登录 ----------
log_step "登录 3x-ui（用户：${XUI_USER}）"
# shellcheck disable=SC2086
LOGIN_RESP=$(curl ${CURL_OPTS} -c "${COOKIE_JAR}" \
  -d "username=${XUI_USER}&password=${XUI_PASS}" \
  "${PANEL_URL}/login")

if ! echo "${LOGIN_RESP}" | grep -q '"success":true'; then
  log_error "登录失败：${LOGIN_RESP}"
  log_error ""
  log_error "请检查："
  log_error "  1. 用户名/密码是否正确（默认 admin/admin，修改过则指定 XUI_USER/XUI_PASS）"
  log_error "  2. 面板端口/路径（默认 2053，修改过则指定 XUI_PANEL_PORT/XUI_PANEL_PATH）"
  log_error "  3. 运行 'x-ui settings' 查看当前配置"
  exit 1
fi
log_ok "登录成功"

# ---------- 3. 生成 Reality 密钥 + UUID ----------
log_step "生成 Reality 密钥对 和 UUID"

XRAY_BIN=""
for p in /usr/local/x-ui/bin/xray-linux-* /usr/local/bin/xray /usr/bin/xray; do
  if [[ -x "${p}" ]]; then
    XRAY_BIN="${p}"
    break
  fi
done
if [[ -z "${XRAY_BIN}" ]]; then
  XRAY_BIN=$(find /usr/local/x-ui /usr/local /usr/bin -maxdepth 4 -name 'xray*' -executable -type f 2>/dev/null | head -1)
fi
if [[ -z "${XRAY_BIN}" ]]; then
  log_error "找不到 xray 二进制，Reality 密钥无法生成"
  exit 1
fi
log_info "使用 xray: ${XRAY_BIN}"

X25519_OUT=$("${XRAY_BIN}" x25519 2>/dev/null || true)

# xray 不同版本输出字段名不一致：
#   PrivateKey: / Private key:
#   PublicKey: / Public key:
#   少数构建用 Password: 表示公钥（与 PrivateKey 配对）
#
# 注意：脚本开头有 set -o pipefail。grep 无匹配时返回 1，若写在
# VAR=$(echo … | grep … | sed) 里会导致整条命令替换失败 → set -e 直接退出，
# 永远走不到下面的 Password: 回退。因此必须用 ( pipeline ) || true 包住。
x25519_extract_line() {
  local out="$1" pattern="$2"
  ( echo "${out}" | grep -iE "${pattern}" | head -1 | sed -E 's/^[^:]*:[[:space:]]*//;s/[[:space:]]*$//' ) 2>/dev/null || true
}

parse_x25519() {
  local out="$1"
  PBK_SOURCE=""
  PRIVATE_KEY=$(x25519_extract_line "${out}" '^PrivateKey:|^Private key:')
  PUBLIC_KEY=$(x25519_extract_line "${out}" '^PublicKey:|^Public key:')
  if [[ -n "${PUBLIC_KEY}" ]]; then
    PBK_SOURCE="PublicKey"
  else
    # 部分 xray 构建第二行名为 Password:，实为 X25519 公钥（客户端 vless 参数 pbk）
    PUBLIC_KEY=$(x25519_extract_line "${out}" '^Password:')
    if [[ -n "${PUBLIC_KEY}" ]]; then
      PBK_SOURCE="Password-as-publicKey"
    fi
  fi
}
parse_x25519 "${X25519_OUT}"

if [[ -z "${PRIVATE_KEY}" || -z "${PUBLIC_KEY}" ]]; then
  log_error "无法解析 xray x25519 输出，请把下面内容反馈给维护者："
  echo "${X25519_OUT}" | sed 's/^/[x25519] /'
  exit 1
fi

SHORT_ID=$(openssl rand -hex 8)
UUID_MAIN=$(cat /proc/sys/kernel/random/uuid)
HY2_PASSWORD=$(openssl rand -hex 16)
HY2_OBFS_PASSWORD=$(openssl rand -hex 16)
SUB_ID=$(openssl rand -hex 8)

log_ok "Reality 密钥与 UUID 已生成（pbk 来源=${PBK_SOURCE:-?}，公钥长度 ${#PUBLIC_KEY}）"

# ---------- 4. 构造 VLESS+Reality 入站 JSON ----------
log_step "构造入站配置"

# 用 Python 构造 JSON，避免 bash 转义噩梦
VLESS_PAYLOAD=$(python3 <<PYEOF
import json

settings = {
    "clients": [{
        "id": "${UUID_MAIN}",
        "flow": "xtls-rprx-vision",
        "email": "${CLIENT_EMAIL}",
        "limitIp": 0,
        "totalGB": 0,
        "expiryTime": 0,
        "enable": True,
        "tgId": "",
        "subId": "${SUB_ID}",
        "reset": 0
    }],
    "decryption": "none",
    "fallbacks": []
}

stream_settings = {
    "network": "tcp",
    "security": "reality",
    "externalProxy": [],
    "realitySettings": {
        "show": False,
        "xver": 0,
        "dest": "${REALITY_DEST}",
        "serverNames": ["${REALITY_SNI}"],
        "privateKey": "${PRIVATE_KEY}",
        "minClient": "",
        "maxClient": "",
        "maxTimediff": 0,
        "shortIds": ["${SHORT_ID}"],
        "settings": {
            "publicKey": "${PUBLIC_KEY}",
            "fingerprint": "chrome",
            "serverName": "",
            "spiderX": "/"
        }
    },
    "tcpSettings": {
        "acceptProxyProtocol": False,
        "header": {"type": "none"}
    }
}

sniffing = {
    "enabled": True,
    "destOverride": ["http", "tls", "quic", "fakedns"],
    "metadataOnly": False,
    "routeOnly": False
}

inbound = {
    "up": 0, "down": 0, "total": 0,
    "remark": "ace-vpn-reality",
    "enable": True,
    "expiryTime": 0,
    "listen": "",
    "port": ${TCP_PORT},
    "protocol": "vless",
    "settings": json.dumps(settings),
    "streamSettings": json.dumps(stream_settings),
    "tag": "inbound-${TCP_PORT}",
    "sniffing": json.dumps(sniffing),
    "allocate": json.dumps({"strategy": "always", "refresh": 5, "concurrency": 3}),
}
print(json.dumps(inbound))
PYEOF
)

HY2_PAYLOAD=$(python3 <<PYEOF
import json

# 3x-ui 校验：非 trojan/shadowsocks 协议要求 client.id 非空（即使 hy2 实际用 password 认证）
settings = {
    "clients": [{
        "id": "${UUID_MAIN}",
        "password": "${HY2_PASSWORD}",
        "email": "${CLIENT_EMAIL}-hy2",
        "limitIp": 0,
        "totalGB": 0,
        "expiryTime": 0,
        "enable": True,
        "tgId": "",
        "subId": "${SUB_ID}",
        "reset": 0
    }]
}

# Hysteria2 需要 TLS 自签证书（或申请证书）
# 这里用自签，客户端 sni + insecure=0 + skip-cert-verify=true 就能跑
import subprocess, os, tempfile

cert_dir = "/etc/x-ui/cert"
cert_file = f"{cert_dir}/hy2-self.crt"
key_file = f"{cert_dir}/hy2-self.key"

os.makedirs(cert_dir, exist_ok=True)
if not os.path.exists(cert_file):
    subprocess.run([
        "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", key_file, "-out", cert_file,
        "-days", "3650",
        "-subj", "/CN=${REALITY_SNI}"
    ], check=True, capture_output=True)
    os.chmod(key_file, 0o600)

stream_settings = {
    "network": "tcp",
    "security": "tls",
    "externalProxy": [],
    "tlsSettings": {
        "serverName": "${REALITY_SNI}",
        "minVersion": "1.3",
        "maxVersion": "1.3",
        "cipherSuites": "",
        "rejectUnknownSni": False,
        "disableSystemRoot": False,
        "enableSessionResumption": False,
        "certificates": [{
            "certificateFile": cert_file,
            "keyFile": key_file,
            "ocspStapling": 3600,
            "oneTimeLoading": False,
            "usage": "encipherment",
            "buildChain": False
        }],
        "alpn": ["h3"],
        "settings": {"allowInsecure": False, "fingerprint": ""}
    }
}

# 注意：3x-ui 对 hysteria2 的 streamSettings 有自己的结构
# 实际走的是 hysteria2 原生协议层
inbound = {
    "up": 0, "down": 0, "total": 0,
    "remark": "ace-vpn-hy2",
    "enable": True,
    "expiryTime": 0,
    "listen": "",
    "port": ${UDP_PORT},
    "protocol": "hysteria2",
    "settings": json.dumps({
        "clients": settings["clients"],
        "obfs": {"type": "salamander", "password": "${HY2_OBFS_PASSWORD}"},
        "ignoreClientBandwidth": False,
        "masquerade": ""
    }),
    "streamSettings": json.dumps(stream_settings),
    "tag": "inbound-hy2-${UDP_PORT}",
    "sniffing": json.dumps({
        "enabled": True,
        "destOverride": ["http", "tls", "quic", "fakedns"],
        "metadataOnly": False,
        "routeOnly": False
    }),
    "allocate": json.dumps({"strategy": "always", "refresh": 5, "concurrency": 3}),
}
print(json.dumps(inbound))
PYEOF
)

# ---------- 5. 调 API 创建入站 ----------
add_inbound() {
  local name="$1"
  local payload="$2"
  local resp
  # shellcheck disable=SC2086
  resp=$(curl ${CURL_OPTS} -b "${COOKIE_JAR}" \
    -H "Content-Type: application/json" \
    -H "X-Requested-With: XMLHttpRequest" \
    -d "${payload}" \
    "${API_INBOUNDS}/add")

  if echo "${resp}" | grep -qE '"success"[[:space:]]*:[[:space:]]*true'; then
    log_ok "${name} 入站创建成功"
    return 0
  else
    log_warn "${name} 入站创建失败（前 400 字符）："
    echo "${resp}" | head -c 400 | sed 's/^/[api] /' >&2
    return 1
  fi
}

log_step "创建 VLESS+Reality 入站（TCP ${TCP_PORT}）"
VLESS_ADD_OK=0
add_inbound "VLESS+Reality" "${VLESS_PAYLOAD}" && VLESS_ADD_OK=1 || true

if [[ "${VLESS_ADD_OK}" != "1" ]]; then
  log_warn "VLESS 入站未新建成功，尝试从面板读取端口 ${TCP_PORT} 上已有 VLESS+Reality…"
  FETCH_OUT=$(COOKIE_JAR="${COOKIE_JAR}" PANEL_URL="${PANEL_URL}" TCP_PORT="${TCP_PORT}" XRAY_BIN="${XRAY_BIN}" python3 <<'PYFETCH'
import json, os, re, shlex, subprocess, sys

def curl_get_inbounds_list():
    """3x-ui v2：GET …/panel/api/inbounds/list"""
    url = os.environ["PANEL_URL"] + "/panel/api/inbounds/list"
    cmd = [
        "curl", "-sk", "-b", os.environ["COOKIE_JAR"],
        "-H", "X-Requested-With: XMLHttpRequest",
        url,
    ]
    return subprocess.check_output(cmd, text=True)


def x25519_pubkey_from_private(priv: str) -> str:
    xray = os.environ.get("XRAY_BIN") or "/usr/local/x-ui/bin/xray-linux-amd64"
    out = subprocess.check_output([xray, "x25519", "-i", priv.strip()], text=True)
    for line in out.splitlines():
        line = line.strip()
        m = re.match(r"(?i)^(PublicKey|Public key|Password)\s*:\s*(.+)$", line)
        if m:
            return m.group(2).strip()
    return ""


port = int(os.environ.get("TCP_PORT", "443"))
try:
    data = json.loads(curl_get_inbounds_list())
except Exception:
    print("FETCH_OK=0")
    sys.exit(0)
if not data.get("success"):
    print("FETCH_OK=0")
    sys.exit(0)
obj = data.get("obj")
if not isinstance(obj, list):
    print("FETCH_OK=0")
    sys.exit(0)
for ib in obj:
    if (ib.get("protocol") or "").lower() != "vless":
        continue
    if int(ib.get("port") or 0) != port:
        continue
    ss = ib.get("streamSettings")
    ss = json.loads(ss) if isinstance(ss, str) else (ss or {})
    if (ss.get("security") or "").lower() != "reality":
        continue
    rs = ss.get("realitySettings") or {}
    st = ib.get("settings")
    settings = json.loads(st) if isinstance(st, str) else (st or {})
    clients = settings.get("clients") or []
    uuid = (clients[0] or {}).get("id", "") if clients else ""
    pbk = ((rs.get("settings") or {}).get("publicKey")) or ""
    sids = rs.get("shortIds") or []
    sid = sids[0] if sids else ""
    priv = rs.get("privateKey") or ""
    if not pbk and priv:
        pbk = x25519_pubkey_from_private(priv)
    sns = rs.get("serverNames") or [""]
    sni = sns[0] or ""
    dest = rs.get("dest") or ""
    print("FETCH_OK=1")
    print(f"UUID_MAIN={shlex.quote(uuid)}")
    print(f"PUBLIC_KEY={shlex.quote(pbk)}")
    print(f"SHORT_ID={shlex.quote(sid)}")
    print(f"PRIVATE_KEY={shlex.quote(priv)}")
    if sni:
        print(f"REALITY_SNI={shlex.quote(sni)}")
    if dest:
        print(f"REALITY_DEST={shlex.quote(dest)}")
    sys.exit(0)
print("FETCH_OK=0")
PYFETCH
)
  # shellcheck disable=SC1090
  eval "${FETCH_OUT}"
  if [[ "${FETCH_OK:-0}" == "1" ]]; then
    log_ok "已从面板同步 VLESS+Reality 参数（与现有入站一致）"
  else
    log_error "无法创建也无法读取 VLESS 入站。"
    log_error "请在 3x-ui 面板删除占用端口 ${TCP_PORT} 的旧入站（或改 TCP_PORT），然后重新运行："
    log_error "  sudo bash scripts/deploy/configure-3xui.sh"
    exit 1
  fi
fi

log_step "创建 Hysteria2 入站（UDP ${UDP_PORT}）"
add_inbound "Hysteria2" "${HY2_PAYLOAD}" || log_warn "Hysteria2 入站可能已存在或版本不兼容（可只在面板里手动添加）"

# ---------- 6. 校验 VLESS 分享链接必要字段 ----------
if [[ -z "${PUBLIC_KEY}" || -z "${UUID_MAIN}" ]]; then
  log_error "PUBLIC_KEY 或 UUID 仍为空，不会写入错误的 vless 链接。请检查面板或重跑脚本。"
  exit 1
fi

# ---------- 7. 获取公网 IP ----------
PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
            curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
            echo "YOUR_VPS_IP")

# ---------- 8. 生成分享链接 ----------
VLESS_URL="vless://${UUID_MAIN}@${PUBLIC_IP}:${TCP_PORT}?type=tcp&security=reality&pbk=${PUBLIC_KEY}&fp=chrome&sni=${REALITY_SNI}&sid=${SHORT_ID}&flow=xtls-rprx-vision#ace-vpn-reality"

HY2_URL="hysteria2://${HY2_PASSWORD}@${PUBLIC_IP}:${UDP_PORT}?sni=${REALITY_SNI}&insecure=1&obfs=salamander&obfs-password=${HY2_OBFS_PASSWORD}#ace-vpn-hy2"

# ---------- 9. 写凭据文件 ----------
cat > "${CREDS_FILE}" <<EOF
===========================================================
 ace-vpn 部署凭据 - $(date)
===========================================================

【公网 IP】 ${PUBLIC_IP}

【VLESS + Reality（TCP ${TCP_PORT}）】
  UUID       : ${UUID_MAIN}
  Flow       : xtls-rprx-vision
  SNI        : ${REALITY_SNI}
  Public Key : ${PUBLIC_KEY}
  Private Key: ${PRIVATE_KEY}
  Short ID   : ${SHORT_ID}
  Dest       : ${REALITY_DEST}

【Hysteria2（UDP ${UDP_PORT}）】
  Password       : ${HY2_PASSWORD}
  Obfs(salamander): ${HY2_OBFS_PASSWORD}
  SNI            : ${REALITY_SNI}
  allowInsecure  : true（自签证书）

【分享链接（直接导入客户端）】

${VLESS_URL}

${HY2_URL}

【3x-ui 面板】
  URL     : ${DETECTED_SCHEME}://${PUBLIC_IP}:${XUI_PANEL_PORT}${XUI_PANEL_PATH}
  User    : ${XUI_USER}
  Password: ${XUI_PASS}

  ⚠️ 立即登录面板改：用户名、密码、面板路径！

===========================================================
EOF
chmod 600 "${CREDS_FILE}"

# ---------- 10. 打印结果 ----------
cat <<EOF

${COLOR_GREEN}============================================================${COLOR_RESET}
${COLOR_GREEN} 3x-ui 自动化配置完成 ✓${COLOR_RESET}
${COLOR_GREEN}============================================================${COLOR_RESET}

 凭据文件已保存至：${CREDS_FILE}
 （chmod 600，只有 root 可读）

${COLOR_YELLOW}■ 分享链接（复制到客户端即可）${COLOR_RESET}

${COLOR_CYAN}${VLESS_URL}${COLOR_RESET}

${COLOR_CYAN}${HY2_URL}${COLOR_RESET}

${COLOR_YELLOW}■ 查看完整凭据${COLOR_RESET}

  cat ${CREDS_FILE}

${COLOR_YELLOW}■ 安全提醒${COLOR_RESET}

  1. 立即登录面板 ${DETECTED_SCHEME}://${PUBLIC_IP}:${XUI_PANEL_PORT} 改默认账号密码
  2. 面板路径改成随机字符串后重启
  3. 凭据文件不要 scp 到公开位置

EOF
