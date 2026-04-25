#!/usr/bin/env bash
# SSH SOCKS5 跳板隧道（常用于 Oracle Cloud 注册等需要「稳定海外出口 IP」的场景）
# 依赖：本机已能免密 ssh 登录跳板机（BatchMode=yes）。
#
# 用法（先 export 跳板 IP）：
#   export SG_VPS=<你的跳板机公网_IP>
#   bash scripts/common-tools/sg-tunnel.sh           # 前台（Ctrl+C 停）
#   bash scripts/common-tools/sg-tunnel.sh bg        # 后台
#   bash scripts/common-tools/sg-tunnel.sh stop      # 停后台
#   bash scripts/common-tools/sg-tunnel.sh status    # 状态
#
# 也可一行：SG_VPS=<IP> bash scripts/common-tools/sg-tunnel.sh bg

SG_VPS="${SG_VPS:-}"
SG_USER="${SG_USER:-root}"
LOCAL_PORT="${LOCAL_PORT:-1080}"
PID_FILE=/tmp/sg-tunnel.pid
LOG_FILE=/tmp/sg-tunnel.log

SSH_OPTS=(
  -D "$LOCAL_PORT"
  -C -N
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=3
  -o TCPKeepAlive=yes
  -o ExitOnForwardFailure=yes
  -o BatchMode=yes           # 失败直接退出，不卡在密码提示
)

_require_vps() {
  if [[ -z "$SG_VPS" ]]; then
    echo "未设置 SG_VPS。请先指定跳板机公网 IP，例如：" >&2
    echo "  export SG_VPS=203.0.113.1   # 仅为语法示例，请换成你的真实跳板 IP" >&2
    echo "  bash scripts/common-tools/sg-tunnel.sh bg" >&2
    exit 1
  fi
}

case "${1:-fg}" in
  fg|foreground)
    _require_vps
    echo "→ 前台启动 SOCKS5 :${LOCAL_PORT} → ${SG_USER}@${SG_VPS}"
    exec ssh "${SSH_OPTS[@]}" "${SG_USER}@${SG_VPS}"
    ;;
  bg|background)
    _require_vps
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      echo "✓ 已在后台运行，PID=$(cat "$PID_FILE")"
      exit 0
    fi
    nohup ssh "${SSH_OPTS[@]}" "${SG_USER}@${SG_VPS}" >"$LOG_FILE" 2>&1 &
    echo $! >"$PID_FILE"
    sleep 2
    if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      echo "✓ 隧道后台启动成功，PID=$(cat "$PID_FILE")"
      echo "  日志：tail -f $LOG_FILE"
      echo "  停止：$0 stop"
    else
      echo "✗ 启动失败，看日志：cat $LOG_FILE"
      exit 1
    fi
    ;;
  stop)
    if [[ -f "$PID_FILE" ]]; then
      kill "$(cat "$PID_FILE")" 2>/dev/null && echo "✓ 已停止"
      rm -f "$PID_FILE"
    else
      echo "未运行"
    fi
    ;;
  status)
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      echo "✓ 运行中 PID=$(cat "$PID_FILE")"
      netstat -an | grep LISTEN | grep -E "\.${LOCAL_PORT}\s" | head
    else
      echo "✗ 未运行"
    fi
    ;;
  *)
    echo "Usage: $0 [fg|bg|stop|status]"
    exit 1
    ;;
esac
