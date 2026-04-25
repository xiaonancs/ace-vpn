#!/usr/bin/env bash
# ace-vpn · 在每台 VPS 上对你关心的 URL 跑 curl 延迟（与 speed-test 同指标：code / total / tcp / ssl / ip）
#
# URL 来源（默认合并，去重）：
#   1. scripts/test/speed-test-endpoints.txt（与 speed-test.sh scenes() 一致，仓库内维护）
#   2. private/vps-watch-urls.txt（可选，额外监控地址）
#   环境变量 VPS_WATCH_INCLUDE_SPEED_TEST=0 可关闭合并 speed-test 列表；或命令行 --no-speed-merge
#
# 前置（免密）：
#   1. 两台 VPS 都装好本机公钥：ssh-copy-id -i ~/.ssh/id_rsa.pub root@<各机 IP>
#   2. 可选：private/env.sh 写 export VPS_SSH_KEY="$HOME/.ssh/id_rsa"（定时任务建议写上）
#      不写则依次试 id_rsa / id_ed25519 / id_ecdsa。
#
# 用法：
#   cd ~/workspace/publish/ace-vpn && source private/env.sh
#   bash scripts/test/vps-watch-urls.sh                    # 终端输出
#   bash scripts/test/vps-watch-urls.sh --log              # 追加到日志（默认 ~/Library/Logs/ace-vpn/vps-watch.log）
#   bash scripts/test/vps-watch-urls.sh --log --no-speed-merge   # 仅 private/vps-watch-urls.txt
#   VPS_WATCH_LOG_FILE=~/logs/vps.tsv bash ... --log  # 自定义单一日志文件
#
# 定时每 30 分钟：scripts/launchd/ace-vpn.vps-watch-urls.example.plist（带 --log）
#
# ── 怎么跑 ─────────────────────────────────────────────────
# 手跑（结果打终端）：
#   cd ~/workspace/publish/ace-vpn && source private/env.sh && bash scripts/test/vps-watch-urls.sh
# 手跑并追加到日志文件（默认 ~/Library/Logs/ace-vpn/vps-watch.log）：
#   bash scripts/test/vps-watch-urls.sh --log
# 自定义日志路径：
#   VPS_WATCH_LOG_FILE=~/Desktop/vps-watch.tsv bash scripts/test/vps-watch-urls.sh --log
# 定时：复制 scripts/launchd/ace-vpn.vps-watch-urls.example.plist 到 ~/Library/LaunchAgents/，
#       替换 __REPO_ROOT__ 后 launchctl load，详见 plist 内注释。
#
# ── 每行输出列（TSV，制表符分隔）────────────────────────────
#   列1  本机时间戳（跑脚本的那台 Mac 的 date）
#   列2  节点名（VPS_NODES 里冒号前，如 hosthatch / vultr）
#   列3  该 VPS 公网 IP
#   列4  HTTP 状态码（curl；000=超时或连不上）
#   列5  总耗时秒 time_total（从发起到收完响应头/体相关阶段，与 curl 文档一致）
#   列6  TCP 建连耗时秒 time_connect
#   列7  TLS/SSL 握手耗时秒 time_appconnect（纯 HTTP 站点可能接近 0）
#   列8  解析到的对端 IP（多为 CDN Anycast，可能是 IPv6）
#   列9  探测的完整 URL
# 说明：对 claude / chatgpt / anthropic / openai 等，未带登录态或 API Key 时 403/404/421 很常见，
#       这里测的是「从 VPS 出站能否较快拿到 HTTP 响应」，不是「账号能否用」；对比两台机请看列 5～7。
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)

USE_LOG=0
USE_SCP=1
NO_SPEED_MERGE=0
for a in "$@"; do
  case "$a" in
    --log) USE_LOG=1 ;;
    --no-scp) USE_SCP=0 ;;
    --no-speed-merge) NO_SPEED_MERGE=1 ;;
    -h|--help) sed -n '1,/^set/p' "$0" | grep '^#' | sed 's/^# \?//'; exit 0 ;;
  esac
done

if [[ -f "$ROOT_DIR/private/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/private/env.sh"
fi

VPS_SSH_USER=${VPS_SSH_USER:-root}
URL_FILE=${VPS_WATCH_URL_FILE:-"$ROOT_DIR/private/vps-watch-urls.txt"}
SPEED_LIST="${VPS_SPEED_TEST_ENDPOINTS:-$SCRIPT_DIR/speed-test-endpoints.txt}"
REMOTE_LIST=/tmp/ace-vpn-watch-urls.txt
LOG_FILE="${VPS_WATCH_LOG_FILE:-${VPS_WATCH_LOG_DIR:-$HOME/Library/Logs/ace-vpn}/vps-watch.log}"

# 用第一台可达的 IP 做「免密探测」（与 vps-watch 实际遍历的节点一致）
first_probe_ip() {
  if [[ -n "${VPS_IP:-}" ]]; then
    echo "$VPS_IP"
    return
  fi
  local entry
  for entry in ${VPS_NODES:-}; do
    echo "${entry##*:}"
    return
  done
  echo ""
}

resolve_ssh_key() {
  SSH_OPTS=( -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new )
  local ip=$1 k cand

  if [[ -n "${VPS_SSH_KEY:-}" ]]; then
    k="${VPS_SSH_KEY/#~/$HOME}"
    if [[ ! -f "$k" ]]; then
      echo "ERROR: VPS_SSH_KEY=${VPS_SSH_KEY} 文件不存在" >&2
      exit 1
    fi
    if ! ssh "${SSH_OPTS[@]}" -i "$k" "${VPS_SSH_USER}@${ip}" 'echo OK' >/dev/null 2>&1; then
      echo "ERROR: 用 ${k} 无法免密登录 ${ip}（请对该机执行 ssh-copy-id）" >&2
      exit 1
    fi
    SSH_OPTS+=( -i "$k" )
    echo "→ 使用 VPS_SSH_KEY: ${k}" >&2
    return
  fi

  for cand in "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ecdsa"; do
    [[ -f "$cand" ]] || continue
    if ssh "${SSH_OPTS[@]}" -i "$cand" "${VPS_SSH_USER}@${ip}" 'echo OK' >/dev/null 2>&1; then
      SSH_OPTS+=( -i "$cand" )
      echo "→ 自动选用免密私钥: ${cand}（定时任务建议在 private/env.sh 写 VPS_SSH_KEY）" >&2
      return
    fi
  done

  echo "ERROR: 未配置 VPS_SSH_KEY，且 ~/.ssh 下 id_rsa/id_ed25519/id_ecdsa 均无法免密登录 ${ip}。" >&2
  echo "  请执行: ssh-copy-id -i ~/.ssh/id_rsa.pub root@${ip}（\$VPS_NODES 里每台都要）" >&2
  echo "  或在 private/env.sh: export VPS_SSH_KEY=\"\$HOME/.ssh/id_rsa\"" >&2
  exit 1
}

build_nodes() {
  NODES=()
  if [[ -n "${VPS_NODES:-}" ]]; then
    for e in $VPS_NODES; do
      NODES+=( "$e" )
    done
  elif [[ -n "${VPS_IP:-}" ]]; then
    NODES+=( "primary:${VPS_IP}" )
  else
    echo "ERROR: 未设置 VPS_NODES 或 VPS_IP" >&2
    exit 1
  fi
}

build_nodes
probe_ip=$(first_probe_ip)
[[ -n "$probe_ip" ]] || { echo "ERROR: 需要 VPS_IP 或 VPS_NODES" >&2; exit 1; }
resolve_ssh_key "$probe_ip"

merge_watch_urls() {
  local out=$1
  : > "$out"
  local inc=${VPS_WATCH_INCLUDE_SPEED_TEST:-1}
  if [[ "${inc}" == "1" && "${NO_SPEED_MERGE}" == "0" && -f "${SPEED_LIST}" ]]; then
    grep -vE '^\s*(#|$)' "${SPEED_LIST}" | sed 's/[[:space:]]*#.*//' | sed '/^\s*$/d' >> "$out"
  fi
  if [[ -f "${URL_FILE}" ]]; then
    grep -vE '^\s*(#|$)' "${URL_FILE}" | sed 's/[[:space:]]*#.*//' | sed '/^\s*$/d' >> "$out"
  fi
  [[ -s "${out}" ]] || return 1
  awk 'NF && $0 ~ /^https?:\/\// { if (!seen[$0]++) print }' "${out}" > "${out}.u" && mv "${out}.u" "${out}"
  return 0
}

MERGED=$(mktemp /tmp/ace-vpn-watch-merged.XXXXXX)
trap 'rm -f "${MERGED}"' EXIT
if ! merge_watch_urls "${MERGED}"; then
  echo "ERROR: 合并后无可用 URL。请检查：" >&2
  echo "  - ${SPEED_LIST}（speed-test 默认列表）是否存在，或设 VPS_WATCH_INCLUDE_SPEED_TEST=0 并创建 ${URL_FILE}" >&2
  exit 1
fi

run_remote_probe() {
  local ip=$1
  ssh "${SSH_OPTS[@]}" "${VPS_SSH_USER}@${ip}" 'bash -s' <<'EOS'
set -euo pipefail
f=/tmp/ace-vpn-watch-urls.txt
[[ -f "$f" ]] || { echo "missing $f"; exit 1; }
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
while IFS= read -r raw || [[ -n "$raw" ]]; do
  line="${raw%%#*}"
  line=$(echo "$line" | xargs)
  [[ -z "$line" ]] && continue
  case "$line" in
    http://*|https://*) ;;
    *) continue ;;
  esac
  # 与 speed-test.sh ep() 相同 write-out 字段（超时 25s）
  out=$(curl -gLsS --max-time 25 -o /dev/null -A "$UA" \
    -w '%{http_code}\t%{time_total}\t%{time_connect}\t%{time_appconnect}\t%{remote_ip}' \
    "$line" 2>/dev/null || echo "000	na	na	na	-")
  printf '%s\t%s\n' "$out" "$line"
done < "$f"
EOS
}

if [[ $USE_LOG -eq 1 ]]; then
  mkdir -p "$(dirname "${LOG_FILE}")"
  exec > >(tee -a "${LOG_FILE}") 2>&1
fi

echo "======== $(date '+%Y-%m-%d %H:%M:%S %z') ========"
echo "合并 URL 数: $(wc -l < "${MERGED}" | xargs)（speed-test 列表 + 可选 ${URL_FILE}）"
echo "日志文件（--log 时）: ${LOG_FILE}"

for entry in "${NODES[@]}"; do
  name="${entry%%:*}"
  ip="${entry##*:}"
  echo ""
  echo "---- ${name} (${ip}) ----"
  if [[ $USE_SCP -eq 1 ]]; then
    scp "${SSH_OPTS[@]}" "${MERGED}" "${VPS_SSH_USER}@${ip}:${REMOTE_LIST}" >/dev/null
  else
    ssh "${SSH_OPTS[@]}" "${VPS_SSH_USER}@${ip}" "cat > ${REMOTE_LIST}" < "${MERGED}"
  fi
  # 每行：ts  node  ip  http_code  total  tcp  ssl  remote_ip  url（制表符，便于 awk/TSV）
  run_remote_probe "$ip" | while IFS= read -r row; do
    echo "$(date '+%Y-%m-%d %H:%M:%S')	${name}	${ip}	${row}"
  done
done

echo ""
echo "完成。"
