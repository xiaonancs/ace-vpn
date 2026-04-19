#!/usr/bin/env bash
# ============================================================
# ace-vpn - Mac 终端代理开关
# ============================================================
# 用途：Claude Code / curl / git / npm / pip 等命令行工具走代理
# 安装：把这段追加到 ~/.zshrc（或 ~/.bashrc）
#   echo "source $(pwd)/clients/shell-proxy.sh" >> ~/.zshrc
#   source ~/.zshrc
# 使用：
#   proxy_on      # 打开代理
#   proxy_off     # 关闭代理
#   proxy_status  # 查看当前状态
# ============================================================

# Clash / Mihomo 默认混合端口（按你客户端实际端口改）
# Mihomo Party 默认 7890，Clash Verge Rev 默认 7897
export ACE_VPN_PROXY_PORT="${ACE_VPN_PROXY_PORT:-7890}"

# 公司内网域名 / CIDR（走直连，不经代理）
# TODO: 按你司实际补全
export ACE_VPN_NO_PROXY="localhost,127.0.0.1,::1,\
.corp.example.com,\
.internal.example,\
10.0.0.0/8,\
172.16.0.0/12,\
192.168.0.0/16"

proxy_on() {
  export HTTP_PROXY="http://127.0.0.1:${ACE_VPN_PROXY_PORT}"
  export HTTPS_PROXY="http://127.0.0.1:${ACE_VPN_PROXY_PORT}"
  export ALL_PROXY="socks5://127.0.0.1:${ACE_VPN_PROXY_PORT}"
  export http_proxy="$HTTP_PROXY"
  export https_proxy="$HTTPS_PROXY"
  export all_proxy="$ALL_PROXY"
  export NO_PROXY="$ACE_VPN_NO_PROXY"
  export no_proxy="$NO_PROXY"
  echo "[ace-vpn] proxy ON  -> 127.0.0.1:${ACE_VPN_PROXY_PORT}"
  echo "[ace-vpn] NO_PROXY  -> ${NO_PROXY}"
}

proxy_off() {
  unset HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY
  unset http_proxy https_proxy all_proxy no_proxy
  echo "[ace-vpn] proxy OFF"
}

proxy_status() {
  if [[ -n "$HTTP_PROXY" ]]; then
    echo "[ace-vpn] proxy: ON  ($HTTP_PROXY)"
    echo "[ace-vpn] NO_PROXY: $NO_PROXY"
    echo "[ace-vpn] exit IP (via proxy): $(curl -s --max-time 5 https://api.ipify.org || echo 'unreachable')"
  else
    echo "[ace-vpn] proxy: OFF"
    echo "[ace-vpn] exit IP (direct): $(curl -s --max-time 5 https://api.ipify.org || echo 'unreachable')"
  fi
}

# 可选：终端默认就打开（Clash TUN 模式下可以不开，TUN 会全局接管）
# proxy_on
