#!/usr/bin/env bash
# ace-vpn · 从本机探测 3x-ui 面板 URL 是否还能连上（不登录，只看 TLS/TCP）
#
# 典型症状：浏览器打不开 https://IP:PORT/path/panel/
#
# 常见原因（按出现频率）：
#   1. 面板端口 / webBasePath 在「设置」里改过 → URL 与当前不一致
#   2. x-ui 未运行：ssh 上 systemctl status x-ui
#   3. UFW 未放行该 TCP 端口：sudo ufw status | grep PORT
#   4. 你在国内网络直连境外 VPS 443/2053 被 QoS 或间歇阻断 → 换网络或先 SSH 再 curl 本机
#   5. 证书是自签 IP 证书：浏览器会拦截，需「继续访问」或用 curl -k 看 HTTP 层
#
# 用法：
#   bash scripts/check-xui-panel.sh 'https://<VPS_IP>:<面板端口>/<webBasePath>/panel/'
#   source private/env.sh && bash scripts/check-xui-panel.sh "$PANEL_URL"   # 若 env 里有 PANEL_URL
set +e

URL="${1:-${PANEL_URL:-}}"
if [[ -z "$URL" ]]; then
  echo "用法: bash scripts/check-xui-panel.sh 'https://IP:PORT/随机path/panel/'" >&2
  exit 1
fi

echo "探测: $URL"
echo "---- curl -vk（看 TLS、HTTP 状态、是否 connection refused）----"
curl -vk --max-time 15 -o /dev/null "$URL" 2>&1 | tail -40

echo ""
echo "---- 若上面是 connection refused：SSH 上执行 ----"
echo "  systemctl is-active x-ui; ss -lntp | grep x-ui"
echo "  sudo ufw status verbose"
