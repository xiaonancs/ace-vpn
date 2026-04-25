#!/usr/bin/env bash
# ace-vpn · 离线诊断采集器
#
# 使用方法（关键：切到 ace-vpn 状态再跑，不要与其他全量 VPN 叠用）：
#   1. 关掉其他 VPN（避免双 VPN 抢路由）
#   2. mihomo 切到 ace-vpn 任一节点
#   3. 复现 cursor reconnection（让 cursor 在前台尝试连接）
#   4. 跑：bash scripts/test/diagnose.sh
#   5. 跑完把生成的 /tmp/ace-vpn-diag-*.txt 内容发给我
#   6. 需要时再切回你平时的网络环境
#
# 这个脚本不需要联外网（除了几个 5s 内 fail-fast 的 curl 探测），
# 即使 ace-vpn 完全不通也能把数据采下来。
set +e

OUT="/tmp/ace-vpn-diag-$(date +%Y%m%d-%H%M%S).txt"
SOCK=$(ls /tmp/mihomo-party-*.sock 2>/dev/null | head -1)

# 所有输出同时进文件和 stdout
exec > >(tee "$OUT") 2>&1

sec() { echo; echo "════════════════════════════════════════════════"; echo "▶ $*"; echo "════════════════════════════════════════════════"; }

sec "0. 基本环境"
date
sw_vers 2>/dev/null | head -3
echo "mihomo socket: $SOCK"
[[ -z "$SOCK" ]] && { echo "❌ 没找到 mihomo unix socket，Clash Party 没开？"; exit 1; }

api() { curl -sS --max-time 5 --unix-socket "$SOCK" "http://localhost$1"; }

sec "1. mihomo 当前 active proxy（PROXY group）"
api "/proxies/%F0%9F%9A%80%20PROXY" | python3 -c "
import json,sys
d = json.load(sys.stdin)
print('PROXY now:', d.get('now'))
print('PROXY all:', d.get('all'))"

sec "2. 关键 group 都选了什么"
for g in "🤖%20AI" "🐟%20FINAL" "📺%20MEDIA" "⚡%20AUTO"; do
  api "/proxies/$g" 2>/dev/null | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(f'  {d.get(\"name\",\"?\"):15s} now={d.get(\"now\")}')
except: pass"
done

sec "3. mihomo rules 总数 + AI / cursor 相关规则"
api "/rules" | python3 -c "
import json,sys
rules = json.load(sys.stdin).get('rules',[])
print('total rules:', len(rules))
print()
print('AI / cursor / anthropic / openai 相关:')
for r in rules:
    p = r.get('payload','').lower()
    if any(k in p for k in ['cursor','anthropic','openai','claude','chatgpt','gemini','google','ai']):
        print(f'  {r.get(\"type\"):14s} {r.get(\"payload\"):40s} -> {r.get(\"proxy\")}')"

sec "4. mihomo 当前所有 active connection（看 cursor 实际走什么 chain）"
api "/connections" | python3 -c "
import json,sys
conns = json.load(sys.stdin).get('connections',[])
print(f'total connections: {len(conns)}')
print()
print('--- cursor / anthropic 相关连接 ---')
for c in conns:
    md = c.get('metadata',{})
    h  = md.get('host','') or md.get('destinationIP','')
    if any(k in h.lower() for k in ['cursor','anthropic','openai','claude']):
        net = md.get('network','?')
        chain = '/'.join(c.get('chains',[]))
        upload = c.get('upload',0)
        download = c.get('download',0)
        start = c.get('start','')
        print(f'  {h:45s} {net:4s} ↑{upload:>7} ↓{download:>7}')
        print(f'    chain: {chain}')
        print(f'    start: {start}')"

sec "5. 测 mihomo 出口（ace-vpn 节点的实际出口IP）"
echo "走 mihomo http proxy 7890:"
curl -sS --proxy http://127.0.0.1:7890 --max-time 8 https://api.ipify.org 2>&1
echo
curl -sS --proxy http://127.0.0.1:7890 --max-time 8 https://www.cloudflare.com/cdn-cgi/trace 2>&1 | head -10
echo
echo "TUN 模式（系统直出）:"
curl -sS --max-time 8 https://api.ipify.org 2>&1
echo
curl -sS --max-time 8 https://www.cloudflare.com/cdn-cgi/trace 2>&1 | head -10

sec "6. ace-vpn 下访问 cursor 后端是否真的通"
for url in \
  "https://api2.cursor.sh/" \
  "https://api3.cursor.sh/" \
  "https://repo42.cursor.sh/" \
  "https://cursor.com/" \
  "https://api.anthropic.com/" \
  "https://gemini.google.com/" \
  "https://www.youtube.com/"; do
  out=$(curl -sS --max-time 10 -o /dev/null \
    -w 'http=%{http_code} time=%{time_total}s connect=%{time_connect}s remote=%{remote_ip}' \
    "$url" 2>&1 || echo "FAIL")
  printf "  %-32s %s\n" "$url" "$out"
done

sec "7. 测 cursor IDE 真正用的 wss / api（websocket 探测）"
# cursor IDE 用 websocket 长连接，我们模拟一次 upgrade 看能否成功
for host in api2.cursor.sh api3.cursor.sh; do
  echo "--- WebSocket upgrade test: $host ---"
  curl -sS --max-time 8 -o /dev/null \
    -w 'http=%{http_code} time=%{time_total}s\n' \
    -H "Connection: Upgrade" \
    -H "Upgrade: websocket" \
    -H "Sec-WebSocket-Version: 13" \
    -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
    "https://$host/" 2>&1
done

sec "8. 看 mihomo 进程日志最后 80 行（找 cursor 相关错误）"
LOG_DIR="$HOME/Library/Application Support/mihomo-party/work/logs"
LATEST_LOG=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
if [[ -n "$LATEST_LOG" ]]; then
  echo "log file: $LATEST_LOG"
  tail -200 "$LATEST_LOG" | grep -iE 'cursor|anthropic|reset|timeout|reject|drop|reconnect|err' | tail -80
else
  echo "no mihomo log"
fi

sec "9. cursor IDE 自己的网络日志最后 60 行"
CURSOR_LOG_DIR="$HOME/Library/Application Support/Cursor/logs"
LATEST_CURSOR_LOG=$(ls -t "$CURSOR_LOG_DIR" 2>/dev/null | head -1)
if [[ -n "$LATEST_CURSOR_LOG" ]]; then
  echo "log dir: $CURSOR_LOG_DIR/$LATEST_CURSOR_LOG"
  for f in "$CURSOR_LOG_DIR/$LATEST_CURSOR_LOG"/*.log; do
    [[ -f "$f" ]] || continue
    name=$(basename "$f")
    echo "--- $name ---"
    grep -iE 'reconnect|econnreset|websocket.*err|abort|proxy|tunnel|enotfound|etimedout|fetch.*fail' "$f" 2>/dev/null | tail -20
  done
fi

sec "10. cursor IDE 进程网络配置"
pgrep -f "Cursor.app" | head -3 | while read pid; do
  echo "pid=$pid"
  ps -o command= -p "$pid" 2>/dev/null | head -1 | cut -c1-180
done
echo
echo "cursor 进程有没有自己设了 HTTPS_PROXY:"
ps -E -p "$(pgrep -f 'Cursor.app' | head -1)" 2>/dev/null | tr ' ' '\n' | grep -iE 'proxy|http' | head -10

sec "11. mac 系统代理 / DNS"
networksetup -getwebproxy Wi-Fi 2>/dev/null
networksetup -getsecurewebproxy Wi-Fi 2>/dev/null
networksetup -getsocksproxy Wi-Fi 2>/dev/null
echo
echo "DNS resolver:"
scutil --dns 2>/dev/null | grep -E 'nameserver\[0\]|search domain\[0\]' | head -6

sec "12. utun 网卡（TUN 模式时谁是默认路由）"
ifconfig | grep -E '^utun|status:' | head -20
echo
echo "默认路由:"
route -n get default 2>/dev/null | head -10

sec "完成"
echo "诊断报告保存到: $OUT"
echo
echo "下一步: 把本报告发给协助排查的人（直接 cat $OUT 拷贝粘贴）"
