#!/usr/bin/env bash
# ace-vpn · 网速 / 延迟测试（纯 curl 版本，不依赖 mihomo API）
#
# 不需要 mihomo 控制面，只看你"当前网络栈"实际表现。
# 在不同节点对比时：手动在 GUI 切换节点，再跑一次。
#
# 用法：
#   bash scripts/test/speed-test.sh             # 完整测试（含带宽）
#   bash scripts/test/speed-test.sh --quick     # 只测延迟，跳过带宽
#   bash scripts/test/speed-test.sh --bw        # 只测带宽
#   bash scripts/test/speed-test.sh --mtr       # 加跑 mtr 路由质量诊断（需 brew install mtr）
set +e

QUICK=0; BWONLY=0; MTR=0
for a in "$@"; do
  case "$a" in
    --quick) QUICK=1 ;;
    --bw)    BWONLY=1 ;;
    --mtr)   MTR=1 ;;
    -h|--help) sed -n '1,/^set/p' "$0" | grep '^#' | sed 's/^# \?//'; exit 0 ;;
  esac
done

g=$'\033[32m'; y=$'\033[33m'; c=$'\033[36m'; r=$'\033[31m'; o=$'\033[0m'

# ─── 出口/链路信息（不依赖 mihomo）─────────────────────────
identity() {
  echo "${c}━━ 出口与链路 ━━${o}"
  ip4=$(curl -sS --max-time 5 -4 https://api.ipify.org 2>/dev/null)
  echo "  公网出口 IPv4 : ${g}${ip4:-?}${o}"
  trace=$(curl -sS --max-time 5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)
  if [ -n "$trace" ]; then
    echo "  cloudflare    : $(echo "$trace" | grep -E '^(loc|colo|ip|warp)=' | tr '\n' ' ')"
  fi
  if [ -n "$ip4" ]; then
    org=$(curl -sS --max-time 5 "https://ipinfo.io/${ip4}/json" 2>/dev/null \
      | python3 -c "import json,sys
try:
  d=json.load(sys.stdin)
  print(f\"  ASN/ISP       : {d.get('org','?')}\")
  print(f\"  地理位置      : {d.get('city','?')}, {d.get('region','?')}, {d.get('country','?')}\")
except: pass" 2>/dev/null)
    [ -n "$org" ] && echo "$org"
  fi
}

# ─── 单点 endpoint 测试 ───────────────────────────────────
fmt_t() { python3 -c "
t=float('$1' or 0)
if t<=0 or t>=99: print(' --- ')
elif t<1: print(f'{int(t*1000):>4d}ms')
else:    print(f'{t:>5.2f}s')"; }

ep() {
  local label="$1" url="$2" timeout="${3:-10}"
  out=$(curl -sS --max-time "$timeout" -o /dev/null \
    -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
    -w '%{http_code}|%{time_total}|%{time_connect}|%{time_appconnect}|%{remote_ip}' \
    "$url" 2>/dev/null)
  [ -z "$out" ] && out="000|${timeout}|0|0|-"
  IFS='|' read -r code total connect ssl ip <<<"$out"
  local color=$g
  case "$code" in
    000)        color=$r ;;
    [45]??)     color=$y ;;
    [23]??)     color=$g ;;
  esac
  printf "  %s%-22s%s  %s  total=%s  tcp=%s  ssl=%s  ip=%s\n" \
    "$color" "$label" "$o" "$code" \
    "$(fmt_t $total)" "$(fmt_t $connect)" "$(fmt_t $ssl)" "$ip"
}

# 下列 URL 与 scripts/test/speed-test-endpoints.txt 保持同步（供 vps-watch-urls 定时合并）
scenes() {
  echo
  echo "${c}━━ AI 服务（看你最关心的）━━${o}"
  ep "gemini.google.com"     "https://gemini.google.com/"           12
  ep "aistudio.google.com"   "https://aistudio.google.com/"         12
  ep "claude.ai"             "https://claude.ai/"                   12
  ep "chatgpt.com"           "https://chatgpt.com/"                 12
  ep "api.anthropic.com"     "https://api.anthropic.com/"           12
  ep "api.openai.com"        "https://api.openai.com/"              12

  echo
  echo "${c}━━ Cursor IDE 实际后端 ━━${o}"
  ep "api2.cursor.sh"        "https://api2.cursor.sh/"              10
  ep "api3.cursor.sh"        "https://api3.cursor.sh/"              10
  ep "repo42.cursor.sh"      "https://repo42.cursor.sh/"            10
  ep "cursor.com"            "https://cursor.com/"                  10

  echo
  echo "${c}━━ 媒体 / 通用 ━━${o}"
  ep "youtube.com"           "https://www.youtube.com/"             12
  ep "github.com"            "https://github.com/"                  10
  ep "google.com"            "https://www.google.com/"              10

  echo
  echo "${c}━━ 国内对照（应该很快，验证本机网络没崩）━━${o}"
  ep "baidu.com"             "https://www.baidu.com/"               5
  ep "qq.com"                "https://www.qq.com/"                  5
}

bandwidth() {
  echo
  echo "${c}━━ 下载带宽（cloudflare 10MB）━━${o}"
  out=$(curl -sS --max-time 30 -o /dev/null \
    -w '%{speed_download}|%{size_download}|%{time_total}|%{time_connect}|%{remote_ip}' \
    'https://speed.cloudflare.com/__down?bytes=10000000' 2>/dev/null || echo "0|0|30|0|-")
  IFS='|' read -r speed size t connect ip <<<"$out"
  mbps=$(python3 -c "print(f'{float($speed)*8/1024/1024:.2f}')" 2>/dev/null)
  mb=$(python3 -c   "print(f'{float($size)/1024/1024:.2f}')" 2>/dev/null)
  echo "  下行 : ${g}${mbps:-?} Mbps${o}   下载 ${mb:-?} MB / ${t}s   连接经过 $ip"

  echo
  echo "${c}━━ Google 域内带宽（gstatic 大文件）━━${o}"
  out=$(curl -sS --max-time 30 -o /dev/null \
    -w '%{speed_download}|%{size_download}|%{time_total}' \
    'https://www.gstatic.com/generate_204' 2>/dev/null)
  IFS='|' read -r speed size t <<<"$out"
  echo "  gstatic 探测点 : size=$size time=${t}s"
}

mtr_check() {
  echo
  echo "${c}━━ MTR 路由质量（10s）━━${o}"
  if ! command -v mtr >/dev/null 2>&1; then
    echo "  ${y}未安装 mtr，跳过${o}（要装：brew install mtr）"
    return
  fi
  for h in google.com api2.cursor.sh; do
    echo
    echo "  → $h"
    sudo mtr -rwzbc 10 "$h" 2>/dev/null | tail -20 | sed 's/^/    /'
  done
}

# ─── 主流程 ─────────────────────────────────────────────────
date '+%Y-%m-%d %H:%M:%S'
echo
identity

if [ $BWONLY -eq 1 ]; then
  bandwidth
elif [ $QUICK -eq 1 ]; then
  scenes
else
  scenes
  bandwidth
fi

if [ $MTR -eq 1 ]; then
  mtr_check
fi

echo
echo "${c}━━ 完成 ━━${o}"
echo "提示："
echo "  - 切换节点：在 Clash Party GUI 里切，再重跑此脚本对比"
echo "  - 路由诊断：bash $0 --mtr （需 brew install mtr）"
echo "  - 只测带宽：bash $0 --bw"
