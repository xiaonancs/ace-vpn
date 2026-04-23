#!/usr/bin/env bash
# ace-vpn · 多 VPS 同步前置检查（只读，绝对不改任何东西）
#
# 用途：
#   在动手把 hosthatch 的设置同步到 vultr 之前，先确认两台机器的真实状态。
#   全程只读 / 只 ssh 拉信息，不改 VPS 任何文件。
#
# 用法：
#   bash scripts/preflight-multi-vps.sh
#
# 输出：
#   每台 VPS 的：
#     1. SSH 是否能进 + 哪种登录方式（key / password）
#     2. sub-converter 服务状态 + 监听端口
#     3. /etc/ace-vpn/intranet.yaml 是否存在 + 内容摘要
#     4. xray 当前 outbounds + routing rule 摘要（看是否有 warp）
#     5. 公网出口 IP
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
  YLW=$'\033[33m'; CYN=$'\033[36m'; RST=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; CYN=""; RST=""
fi

hdr()  { echo; echo "${BOLD}${CYN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"; echo "${BOLD}${CYN}  $*${RST}"; echo "${BOLD}${CYN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"; }
sub()  { echo; echo "${BOLD}▸ $*${RST}"; }
ok()   { echo "  ${GRN}✓${RST} $*"; }
no()   { echo "  ${RED}✗${RST} $*"; }
warn() { echo "  ${YLW}!${RST} $*"; }
kv()   { printf "  ${DIM}%-22s${RST} %s\n" "$1" "$2"; }

# 自动 source env
if [[ -f "$ROOT_DIR/private/env.sh" ]]; then
  source "$ROOT_DIR/private/env.sh"
fi

VPS_SSH_USER=${VPS_SSH_USER:-root}
SSH_KEY=${VPS_SSH_KEY:-}
SUB_PORT=${SUB_PORT_CLASH:-25500}

sub_health_token() {
  if [[ -n "${SUB_HEALTH_TOKEN:-}" ]]; then echo "$SUB_HEALTH_TOKEN"; return; fi
  if [[ -n "${SUB_TOKEN:-}" ]]; then echo "$SUB_TOKEN"; return; fi
  if [[ -n "${SUB_TOKENS:-}" ]]; then echo "${SUB_TOKENS%%,*}"; return; fi
  echo "sub-hxn"
}

# ────────────── 节点列表 ──────────────
# 只信 env.sh 里显式声明的节点；不再硬编码任何 hosthatch / vultr IP。
declare -a NODES=()
if [[ -n "${VPS_NODES:-}" ]]; then
  for entry in $VPS_NODES; do
    name="${entry%%:*}"
    ip="${entry##*:}"
    [[ -z "$name" || -z "$ip" || "$name" == "$ip" ]] && {
      echo "VPS_NODES 格式错误：$entry（应为 name:ip）" >&2
      exit 1
    }
    NODES+=("$name|$ip")
  done
elif [[ -n "${VPS_IP:-}" ]]; then
  NODES+=("primary|$VPS_IP")
else
  echo "既没有 VPS_NODES，也没有 VPS_IP；先 source private/env.sh" >&2
  exit 1
fi

SSH_OPTS=(-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
SSH_KEY_LABEL="ssh 默认链路"
if [[ -n "$SSH_KEY" ]]; then
  SSH_KEY="${SSH_KEY/#~/$HOME}"
  if [[ -f "$SSH_KEY" ]]; then
    SSH_OPTS+=(-i "$SSH_KEY")
    SSH_KEY_LABEL="$SSH_KEY"
  else
    echo "WARN: VPS_SSH_KEY=$SSH_KEY 不存在，改用 ssh 默认链路 / agent / 密码" >&2
    SSH_KEY=""
  fi
fi

probe_ssh() {
  local ip=$1
  # 先用 BatchMode（key only），看能不能进
  local out
  if out=$(ssh "${SSH_OPTS[@]}" -o BatchMode=yes "$VPS_SSH_USER@$ip" 'echo OK' 2>&1); then
    if [[ "$out" == "OK" ]]; then
      echo "key:$SSH_KEY_LABEL"
      return 0
    fi
  fi
  echo "fail:$out"
  return 1
}

run_remote() {
  local ip=$1
  local cmd=$2
  ssh "${SSH_OPTS[@]}" "$VPS_SSH_USER@$ip" "$cmd" 2>&1
}

REPORT_FILE=/tmp/ace-vpn-preflight-$(date +%Y%m%d-%H%M%S).txt
exec > >(tee "$REPORT_FILE") 2>&1

echo
echo "${BOLD}ace-vpn · 多 VPS 同步前置检查${RST}"
echo "${DIM}时间：$(date)${RST}"
echo "${DIM}报告：$REPORT_FILE${RST}"
echo "${DIM}SSH：$SSH_KEY_LABEL${RST}"

# 用普通数组累总结（macOS 自带 bash 3.2 不支持关联数组 declare -A）
SUMMARY_LINES=()

for entry in "${NODES[@]}"; do
  name="${entry%%|*}"
  ip="${entry##*|}"

  hdr "节点 [${name}] ${ip}"

  sub "1. SSH 可达性"
  ssh_ok=0
  if probe_result=$(probe_ssh "${ip}"); then
    ok "SSH 可达（key 登录）"
    ssh_ok=1
  else
    no "key 登录不通；尝试用密码进一次（你需要手动输密码）"
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
        "${VPS_SSH_USER}@${ip}" 'echo OK' 2>&1 | tail -1 | grep -q '^OK$'; then
      if [[ -n "$SSH_KEY" && -f "${SSH_KEY}.pub" ]]; then
        ok "密码登录通了（如需免密：ssh-copy-id -i ${SSH_KEY}.pub ${VPS_SSH_USER}@${ip}）"
      else
        ok "密码登录通了（当前未指定可用公钥文件，不提示 ssh-copy-id）"
      fi
      ssh_ok=2     # 通了但要密码
    else
      no "SSH 完全不通：${probe_result#fail:}"
      SUMMARY_LINES+=("${RED}✗${RST} [${name}] ${ip} — SSH 不通")
      continue
    fi
  fi

  sub "2. sub-converter 服务状态"
  svc=$(run_remote "${ip}" 'systemctl is-active ace-vpn-sub 2>/dev/null || echo missing')
  port_listen=$(run_remote "${ip}" "ss -lntp 2>/dev/null | grep -c ':${SUB_PORT} '" || echo 0)
  sub_state="✗"
  if [[ "${svc}" == "active" ]]; then
    ok "ace-vpn-sub.service: active"
    sub_state="✓"
  else
    no "ace-vpn-sub.service: ${svc}"
  fi
  kv "端口 ${SUB_PORT} 监听" "${port_listen}"

  health=$(curl -fsS --max-time 5 "http://${ip}:${SUB_PORT}/healthz" 2>/dev/null || echo "")
  if [[ -n "${health}" ]]; then
    ok "/healthz: ${health}"
  else
    tok=$(sub_health_token)
    clash_code=$(curl -sS --max-time 15 -o /dev/null -w "%{http_code}" "http://${ip}:${SUB_PORT}/clash/${tok}" 2>/dev/null || echo 000)
    if [[ "${clash_code}" == "200" ]]; then
      ok "/clash/${tok} 返回 200（旧版 sub-converter 无 /healthz，订阅与热加载仍正常）"
    else
      warn "/healthz 不通且 /clash/${tok} 返回 ${clash_code}（可能防火墙或服务异常）"
      sub_state="✗"
    fi
  fi

  sub "3. /etc/ace-vpn/intranet.yaml"
  intranet_info=$(run_remote "${ip}" 'if [ -f /etc/ace-vpn/intranet.yaml ]; then
    echo "EXISTS"
    ls -l /etc/ace-vpn/intranet.yaml
    echo "---SHA256---"
    sha256sum /etc/ace-vpn/intranet.yaml | awk "{print \$1}"
    echo "---SUMMARY---"
    python3 -c "
import yaml
d = yaml.safe_load(open(\"/etc/ace-vpn/intranet.yaml\")) or {}
profs = d.get(\"profiles\") or {}
if isinstance(profs, dict):
    for n, p in profs.items():
        if not isinstance(p, dict): continue
        en = p.get(\"enabled\")
        nd = len(p.get(\"domains\") or [])
        nc = len(p.get(\"cidrs\") or [])
        print(f\"  profile={n} enabled={en} domains={nd} cidrs={nc}\")
extra = d.get(\"extra\") or {}
if isinstance(extra, dict):
    for k, v in extra.items():
        if isinstance(v, list):
            print(f\"  extra.{k}: {len(v)} 项\")
"
  else
    echo "MISSING"
  fi')
  intranet_state="✗"
  if echo "${intranet_info}" | grep -q EXISTS; then
    ok "存在"
    intranet_state="✓"
    echo "${intranet_info}" | grep -E '^  ' | sed 's/^/    /'
    sha=$(echo "${intranet_info}" | awk '/---SHA256---/{f=1;next} /---SUMMARY---/{f=0} f' | tr -d ' ')
    kv "SHA256" "${sha}"
  else
    no "MISSING（首次同步会创建）"
  fi

  sub "4. xray outbounds + routing 摘要（看是否有 warp）"
  xray_info=$(run_remote "${ip}" 'python3 -c "
import json, os
p = \"/usr/local/x-ui/bin/config.json\"
if not os.path.exists(p):
    print(\"MISSING\")
else:
    c = json.load(open(p))
    obs = c.get(\"outbounds\", [])
    print(\"outbounds:\", \",\".join([o.get(\"tag\",\"?\")+\"(\"+o.get(\"protocol\",\"?\")+\")\" for o in obs]))
    rules = (c.get(\"routing\") or {}).get(\"rules\", [])
    print(\"rules ({}):\".format(len(rules)))
    for i, r in enumerate(rules[:8]):
        d = r.get(\"domain\", [])
        ip_ = r.get(\"ip\", [])
        proto = r.get(\"protocol\", [])
        ib = r.get(\"inboundTag\", [])
        what = []
        if d: what.append(\"domain[\"+str(len(d))+\"]\")
        if ip_: what.append(\"ip[\"+str(len(ip_))+\"]\")
        if proto: what.append(\"proto:\"+\",\".join(proto))
        if ib: what.append(\"inboundTag\")
        print(f\"  #{i} -> {r.get(\\\"outboundTag\\\",\\\"?\\\")}  {\\\" \\\".join(what)}\")
"')
  echo "${xray_info}" | sed 's/^/    /'
  warp_state="无"
  if echo "${xray_info}" | grep -qiE 'warp|wireguard'; then
    warn "此节点配置里有 warp/wireguard outbound（同步规则时不会动它）"
    warp_state="⚠warp"
  else
    ok "此节点没有 warp outbound（干净）"
  fi

  sub "5. 公网出口 IP"
  exit_ip=$(run_remote "${ip}" 'curl -sS --max-time 8 -4 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -E "^ip=" | head -1')
  if [[ -n "${exit_ip}" ]]; then
    kv "Cloudflare 看到" "${exit_ip}"
  else
    warn "Cloudflare trace 取不到（节点出网可能有问题）"
  fi

  ssh_label="key"; [[ ${ssh_ok} == 2 ]] && ssh_label="pwd"
  SUMMARY_LINES+=("${GRN}✓${RST} [${name}] ${ip} — ssh:${ssh_label}｜sub-converter:${sub_state}｜intranet.yaml:${intranet_state}｜${warp_state}")

done

# ────────────── 总结 ──────────────
hdr "总结 / 同步建议"
echo
for line in "${SUMMARY_LINES[@]}"; do
  echo "  ${line}"
done

echo
echo "${BOLD}下一步（按出现的状况）${RST}：" 
echo
echo "${CYN}如果两台都 SSH 通 + sub-converter 健康：${RST}"
echo "  ✅ 可以放心同步规则（intranet.yaml）"
echo "  → 跑：bash scripts/sync-intranet.sh --all-vps"
echo "    （此命令会先 dry-run 列表，再让你确认，再 scp 推送）"
echo
echo "${CYN}如果某台 sub-converter 没装：${RST}"
echo "  ⚠ 那台不能用规则同步，需要先在它上面装："
echo "  → 见 scripts/install-sub-converter.sh 用法"
echo
echo "${CYN}关于 warp outbound：${RST}"
echo "  规则同步只动 /etc/ace-vpn/intranet.yaml，"
echo "  不会动 xray 的 outbounds/routing 配置，"
echo "  所以一台有 warp 一台没有，互不影响。"
echo
echo "${DIM}完整报告已保存到：$REPORT_FILE${RST}"
echo
