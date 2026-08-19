# Mobile Domestic App Stability Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make iOS/Android rule mode reliably keep WeChat Moments, Douyin, Xiaohongshu, Quark/UC, domestic video, payment, and banking traffic on mainland direct routes so images/video/login flows do not stall after VPN is enabled.

**Architecture:** Keep overseas/AI traffic on the existing proxy groups, but harden the mainland mobile path as a first-class routing layer: categorized app-domain groups, explicit DIRECT routing, CN DNS policy for mainland app/CDN domains, generated mobile subscriptions, and regression tests. Add a lightweight diagnosis loop so newly observed mobile domains can be classified and promoted without guessing blindly.

**Tech Stack:** Python `scripts/server/sub-converter.py`, YAML subscriptions, Mihomo/Stash/Shadowrocket-compatible rules, Bash deploy scripts, route regression tests.

---

## Current Findings

- `scripts/server/sub-converter.py` already has a broad `CHINA_DIRECT` list covering Tencent/WeChat, ByteDance/Douyin, Xiaohongshu, Alibaba/UC, Bilibili, Meituan, JD/PDD/Kuaishou, and banks.
- `CHINA_DIRECT` is already rendered into `rules` as `DOMAIN-SUFFIX,<domain>,DIRECT`.
- `CHINA_DIRECT` is already rendered into `dns.fake-ip-filter`, which is good for mobile CDN/image domains.
- `CHINA_DIRECT` is not rendered into `dns.nameserver-policy`; only `intranet.domains`, `extra.cn`, `AI_STREAMING_DOMAINS`, and `extra.overseas` get explicit DNS policy.
- This leaves domestic mobile apps dependent on default DoH. In mobile clients and TUN-style rule mode, default DoH behavior can still cause bad CDN edge selection or slow fallback, especially for video/image-heavy apps.

## Non-Goals

- Do not route bank, payment, domestic video, WeChat, Douyin, Xiaohongshu, Quark, or domestic app-store traffic through the Japan VPS.
- Do not add user API keys, cookies, app accounts, or any sensitive traffic logs to git.
- Do not implement decrypted HTTPS inspection.
- Do not rely only on `GEOIP,CN`; app/CDN domains must have explicit suffix coverage.

---

### Task 1: Add Mainland Mobile Route Regression Coverage

**Files:**
- Modify: `/Users/hexiaonan/workspace/ace-vpn/scripts/test/route-regression.py`

**Step 1: Add failing route cases for the reported app families**

Add explicit `DIRECT` assertions for representative hosts that are likely to break images/video/login when misrouted:

```python
        # WeChat / Moments / Tencent media and payment
        ("szextshort.weixin.qq.com", "DIRECT"),
        ("res.wx.qq.com", "DIRECT"),
        ("mmsns.qpic.cn", "DIRECT"),
        ("wx.qlogo.cn", "DIRECT"),
        ("weixinc2c.qq.com", "DIRECT"),
        ("tenpay.com", "DIRECT"),

        # Douyin / ByteDance mobile video and images
        ("api5-normal-c-lf.amemv.com", "DIRECT"),
        ("v26-dy.ixigua.com", "DIRECT"),
        ("p3-sign.douyinpic.com", "DIRECT"),
        ("p3-pc.douyinpic.com", "DIRECT"),
        ("v3-web.douyinvod.com", "DIRECT"),

        # Xiaohongshu images/video/anti-abuse
        ("edith.xiaohongshu.com", "DIRECT"),
        ("sns-webpic-qc.xhscdn.com", "DIRECT"),
        ("sns-video-bd.xhscdn.com", "DIRECT"),
        ("ci.xiaohongshu.com", "DIRECT"),

        # Quark / UC / Alibaba browser and video stack
        ("quark.cn", "DIRECT"),
        ("myquark.cn", "DIRECT"),
        ("quark.sm.cn", "DIRECT"),
        ("uczzd.cn", "DIRECT"),
        ("ucweb.com", "DIRECT"),
        ("ykimg.com", "DIRECT"),

        # Banking / payment / domestic finance
        ("95516.com", "DIRECT"),
        ("abchina.com", "DIRECT"),
        ("ccb.com", "DIRECT"),
        ("icbc.com.cn", "DIRECT"),
        ("cmbchina.com", "DIRECT"),
        ("psbc.com", "DIRECT"),
```

**Step 2: Run the regression test and confirm current gaps**

Run:

```bash
python3 scripts/test/route-regression.py
```

Expected:

- Some cases may already pass.
- Missing domains such as `quark.cn`, `myquark.cn`, `uczzd.cn`, or WeChat subdomains should fail until Task 2 is implemented.

**Step 3: Commit only if this task is kept separate**

```bash
git add scripts/test/route-regression.py
git commit -m "test: cover mainland mobile app routing"
```

---

### Task 2: Split `CHINA_DIRECT` Into Categorized Mobile App Groups

**Files:**
- Modify: `/Users/hexiaonan/workspace/ace-vpn/scripts/server/sub-converter.py`

**Step 1: Create explicit domain groups above `CHINA_DIRECT`**

Introduce named lists so future fixes are not hidden inside one long list:

```python
CHINA_BYTEDANCE_DIRECT = [
    "douyin.com", "aweme.snssdk.com", "snssdk.com", "bytedance.com", "bytedancecdn.com",
    "douyincdn.com", "douyinpic.com", "douyinstatic.com", "douyinvod.com", "idouyinvod.com",
    "iesdouyin.com", "pstatp.com", "byteimg.com", "bytednsdoc.com", "zjcdn.com",
    "toutiao.com", "toutiaoimg.com", "toutiaocdn.com", "ixigua.com", "ixiguavideo.com",
    "amemv.com",
]

CHINA_TENCENT_DIRECT = [
    "qq.com", "qpic.cn", "qlogo.cn", "tencent.com", "tencent-cloud.com", "tencent-cloud.net",
    "weixin.qq.com", "weixin.com", "wechat.com", "wechatpay.com", "wechatlegal.net",
    "wechatos.net", "weixinbridge.com", "weixinsxy.com", "iot-tencent.com",
    "gtimg.com", "gtimg.cn", "tenpay.com",
    "myqcloud.com", "qcloud.com", "qcloudimg.com", "qcloudcdn.com",
    "servicewechat.com", "weapp.com", "wecom.work", "xy-asia.com",
]

CHINA_XHS_DIRECT = [
    "xiaohongshu.com", "xiaohongshu.net", "xhscdn.com", "xhscdn.net",
    "xhslink.com", "fengkongcloud.com",
]

CHINA_ALIBABA_DIRECT = [
    "taobao.com", "tmall.com", "alibaba.com", "alicdn.com", "aliyun.com",
    "alipay.com", "alipayobjects.com", "1688.com", "tanx.com", "mmstat.com",
    "tbcdn.cn", "taobaocdn.com",
    "ele.me", "ele.to", "eleme.com", "eleme.com.cn", "eleme.cn", "eleme.io",
    "elemecdn.com", "elemecdn.cn", "elenet.me", "fengniao.com",
    "fengniaopaotui.cn", "fengniaozhongbao.cn", "xingxuanwaimai.com", "xyzele.com", "youcaishop.cn",
    "goofish.com", "amap.com", "autonavi.com",
    "dingtalk.com", "dingtalkapps.com", "fliggy.com", "alitrip.com",
    "uc.cn", "ucweb.com", "quark.cn", "myquark.cn", "uczzd.cn", "sm.cn",
]

CHINA_BANKING_DIRECT = [
    "unionpay.com", "95516.com", "ccb.com", "icbc.com.cn", "abchina.com", "cmbchina.com",
    "bankcomm.com", "boc.cn", "cmbc.com.cn", "spdb.com.cn", "cib.com.cn",
    "cebbank.com", "psbc.com", "pingan.com", "citicbank.com",
]
```

**Step 2: Rebuild `CHINA_DIRECT` from the groups**

Replace the current one-piece list with:

```python
CHINA_DIRECT = _dedupe_domains(
    CHINA_BYTEDANCE_DIRECT,
    CHINA_ALIBABA_DIRECT,
    CHINA_TENCENT_DIRECT,
    CHINA_XHS_DIRECT,
    CHINA_BAIDU_DIRECT,
    CHINA_VIDEO_DIRECT,
    CHINA_LOCAL_SERVICE_DIRECT,
    CHINA_ECOMMERCE_DIRECT,
    CHINA_SHORT_VIDEO_DIRECT,
    CHINA_DEVICE_VENDOR_DIRECT,
    CHINA_BANKING_DIRECT,
    CHINA_MISC_DIRECT,
    ["cn", "hk", "tw"],
)
```

If the existing `_dedupe_domains()` definition is currently below `CHINA_DIRECT`, move `_dedupe_domains()` above the grouped constants before using it.

**Step 3: Run tests**

```bash
python3 scripts/test/route-regression.py
```

Expected:

- All route cases pass.
- The noisy local `hashlib blake2b/blake2s` warnings may appear on this machine; the test should still exit `0`.

**Step 4: Commit**

```bash
git add scripts/server/sub-converter.py scripts/test/route-regression.py
git commit -m "fix: harden mainland mobile app direct routing"
```

---

### Task 3: Add CN DNS Policy for Mainland Direct App Domains

**Files:**
- Modify: `/Users/hexiaonan/workspace/ace-vpn/scripts/server/sub-converter.py`
- Modify: `/Users/hexiaonan/workspace/ace-vpn/scripts/test/route-regression.py`

**Step 1: Render `CHINA_DIRECT` into `dns.nameserver-policy`**

In `build_clash_yaml()`, add `CHINA_DIRECT` to the `nameserver-policy` map with `CN_PUBLIC_DNS`.

Add this block after the `extra.cn` policy block and before AI/overseas policy blocks:

```python
                **{
                    f"+.{sfx}": list(CN_PUBLIC_DNS)
                    for sfx in CHINA_DIRECT
                },
```

Important ordering:

- `intranet["domains"]` must stay first so company domains keep profile DNS.
- `extra.cn` may stay before `CHINA_DIRECT` so user overrides are visibly first.
- AI/overseas policy must stay after direct policy and target `OVERSEAS_DOH`.

**Step 2: Add config-level regression checks**

In `scripts/test/route-regression.py`, after `shadowrocket_conf` checks, generate a full Clash YAML and assert DNS policy exists:

```python
    clash_yaml = module.build_clash_yaml(
        [{"name": "test-node", "type": "ss", "server": "127.0.0.1", "port": 8388, "cipher": "aes-128-gcm", "password": "x"}],
        intranet,
    )
    for needle in [
        "+.weixin.com:",
        "+.douyin.com:",
        "+.xhscdn.com:",
        "+.quark.cn:",
        "+.95516.com:",
    ]:
        if needle not in clash_yaml:
            print(f"FAIL clash config missing DNS policy {needle}", file=sys.stderr)
            return 1
        print(f"OK   clash config contains DNS policy {needle}")
```

If the test proxy shape fails validation, use the existing test helper pattern or import `yaml.safe_load()` and inspect only `config["dns"]["nameserver-policy"]` from `build_clash_yaml()`.

**Step 3: Validate generated subscription**

```bash
python3 scripts/test/route-regression.py
INTRANET_FILE=private/intranet.yaml python3 scripts/server/sub-converter.py --help >/dev/null || true
bash scripts/rules/sync-subconverter.sh --dry-run
```

Expected:

- Route regression passes.
- Dry-run validates local generated YAML.

**Step 4: Commit**

```bash
git add scripts/server/sub-converter.py scripts/test/route-regression.py
git commit -m "fix: resolve mainland mobile apps with cn dns"
```

---

### Task 4: Add a Mobile App Probe List and Batch Match Tool

**Files:**
- Create: `/Users/hexiaonan/workspace/ace-vpn/scripts/test/mobile-direct-hosts.txt`
- Create: `/Users/hexiaonan/workspace/ace-vpn/scripts/test/check-mobile-direct.sh`
- Modify: `/Users/hexiaonan/workspace/ace-vpn/scripts/README.md`

**Step 1: Create the host list**

Create `scripts/test/mobile-direct-hosts.txt`:

```text
# WeChat / Tencent
mmsns.qpic.cn
mmbiz.qpic.cn
wx.qlogo.cn
thirdwx.qlogo.cn
res.wx.qq.com
szextshort.weixin.qq.com
weixinc2c.qq.com
tenpay.com

# Douyin / ByteDance
douyin.com
api5-normal-c-lf.amemv.com
p3-sign.douyinpic.com
v3-web.douyinvod.com
byteimg.com
bytednsdoc.com
zjcdn.com

# Xiaohongshu
edith.xiaohongshu.com
sns-img-qc.xhscdn.net
sns-webpic-qc.xhscdn.com
sns-video-bd.xhscdn.com
ci.xiaohongshu.com

# Alibaba / Quark / UC / Youku
quark.cn
myquark.cn
quark.sm.cn
uczzd.cn
ucweb.com
alicdn.com
ykimg.com
youku.com

# Banking / payment
95516.com
ccb.com
icbc.com.cn
abchina.com
cmbchina.com
bankcomm.com
boc.cn
psbc.com
```

**Step 2: Create the checker script**

Create `scripts/test/check-mobile-direct.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
HOST_FILE=${1:-"$ROOT_DIR/scripts/test/mobile-direct-hosts.txt"}
MATCH_URL=${MATCH_URL:-"http://207.148.102.103:25500/match?host="}

failed=0
while IFS= read -r host; do
  host=${host%%#*}
  host=$(echo "$host" | xargs)
  [[ -z "$host" ]] && continue
  json=$(curl -fsS --max-time 8 "${MATCH_URL}${host}" || true)
  target=$(python3 -c 'import json,sys; print((json.load(sys.stdin) or {}).get("target",""))' <<<"$json" 2>/dev/null || true)
  rule=$(python3 -c 'import json,sys; print((json.load(sys.stdin) or {}).get("rule",""))' <<<"$json" 2>/dev/null || true)
  if [[ "$target" != "DIRECT" ]]; then
    echo "FAIL $host target=$target rule=$rule"
    failed=$((failed + 1))
  else
    echo "OK   $host target=$target rule=$rule"
  fi
done < "$HOST_FILE"

if [[ $failed -gt 0 ]]; then
  echo "$failed mobile direct host(s) failed" >&2
  exit 1
fi
```

**Step 3: Make it executable and run**

```bash
chmod +x scripts/test/check-mobile-direct.sh
scripts/test/check-mobile-direct.sh
```

Expected:

- Every listed host reports `target=DIRECT`.

**Step 4: Document the tool**

Add a short row to `scripts/README.md`:

```markdown
| [`test/check-mobile-direct.sh`](test/check-mobile-direct.sh) | Batch-check reported mobile app/CDN hosts against `/match` and require `DIRECT` | WeChat/Douyin/XHS/bank/Quark mobile troubleshooting |
```

**Step 5: Commit**

```bash
git add scripts/test/mobile-direct-hosts.txt scripts/test/check-mobile-direct.sh scripts/README.md
git commit -m "test: add mobile direct route probe"
```

---

### Task 5: Deploy Safely to VPS and Verify Both Subscriptions

**Files:**
- No source edits unless validation fails.

**Step 1: Push sub-converter to VPS**

```bash
bash scripts/rules/sync-subconverter.sh
```

Expected:

- Local build/validation passes.
- Remote `/healthz` returns `ok`.
- Remote generated config validates.

**Step 2: Pull `ace-main` and `ace-fork`**

```bash
curl -sS -o /tmp/ace-main-mobile.yaml -w "main %{http_code} %{content_type} %{size_download}\n" --max-time 10 \
  "http://207.148.102.103:25500/clash-decb18b14f2817da2361d18eaa6f61a3/ace-main"
curl -sS -o /tmp/ace-fork-mobile.yaml -w "fork %{http_code} %{content_type} %{size_download}\n" --max-time 10 \
  "http://207.148.102.103:25500/clash-decb18b14f2817da2361d18eaa6f61a3/ace-fork"
python3 scripts/server/validate-config.py /tmp/ace-main-mobile.yaml
python3 scripts/server/validate-config.py /tmp/ace-fork-mobile.yaml
```

Expected:

- Both subscriptions return `200`.
- Both YAML files validate.

**Step 3: Check representative live matches**

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=15 root@207.148.102.103 \
  "curl -sS 'http://127.0.0.1:25500/match?host=mmsns.qpic.cn'; echo; \
   curl -sS 'http://127.0.0.1:25500/match?host=p3-sign.douyinpic.com'; echo; \
   curl -sS 'http://127.0.0.1:25500/match?host=sns-webpic-qc.xhscdn.com'; echo; \
   curl -sS 'http://127.0.0.1:25500/match?host=quark.cn'; echo; \
   curl -sS 'http://127.0.0.1:25500/match?host=95516.com'; echo"
```

Expected:

- Every response has `"target": "DIRECT"`.

**Step 4: Commit deploy docs if changed, then push**

```bash
git status --short --branch
git push
```

---

### Task 6: Add User-Facing Mobile Troubleshooting Notes

**Files:**
- Modify: `/Users/hexiaonan/workspace/ace-vpn/docs/用户手册 user-guide.md`
- Modify: `/Users/hexiaonan/workspace/ace-vpn/docs/开发者日志.md`

**Step 1: Add a mobile symptom checklist**

Add a section under mobile usage:

```markdown
### 国内 App 图片/视频卡顿排查

如果微信朋友圈、抖音、小红书、夸克、银行 App 在规则模式下图片/视频不加载：

1. 先刷新订阅并断开重连 VPN。
2. 确认不是全局代理模式；国内 App 应命中 DIRECT。
3. 用管理员机器跑：
   `scripts/test/check-mobile-direct.sh`
4. 如果某个新域名没命中 DIRECT，用：
   `bash scripts/rules/add-rule.sh https://example.cn/ DIRECT`
   先本机生效。
5. 验证稳定后执行：
   `bash scripts/rules/promote-to-vps.sh`
   同步到 iOS/Android/家人设备。
```

**Step 2: Add the technical changelog**

In `docs/开发者日志.md`, add a dated entry:

```markdown
### [2026-08-19] 移动端国内 App DIRECT 与 CN DNS 加固

- 将国内移动 App 域名按微信/腾讯、抖音/字节、小红书、阿里/夸克、视频、银行等分组维护。
- `CHINA_DIRECT` 同时进入 rules、fake-ip-filter、nameserver-policy。
- 国内 App/CDN 使用国内公网 DNS，避免 VPN 开启后拿到错误海外 CDN 边缘。
- 新增 `scripts/test/check-mobile-direct.sh` 批量检查移动端关键域名。
```

**Step 3: Commit**

```bash
git add "docs/用户手册 user-guide.md" docs/开发者日志.md
git commit -m "docs: add mobile app routing troubleshooting"
```

---

## Acceptance Criteria

- WeChat Moments image hosts such as `mmsns.qpic.cn` and `mmbiz.qpic.cn` are `DIRECT`.
- Douyin video/image hosts such as `douyinpic.com`, `douyinvod.com`, `amemv.com`, and `byteimg.com` are `DIRECT`.
- Xiaohongshu app/API/CDN hosts such as `xiaohongshu.com`, `xhscdn.com`, `xhscdn.net`, and `fengkongcloud.com` are `DIRECT`.
- Quark/UC hosts such as `quark.cn`, `myquark.cn`, `uczzd.cn`, `uc.cn`, `ucweb.com`, and `sm.cn` are `DIRECT`.
- Major bank/payment hosts stay `DIRECT`.
- `CHINA_DIRECT` domains appear in `fake-ip-filter`.
- `CHINA_DIRECT` domains appear in `nameserver-policy` and use `CN_PUBLIC_DNS`.
- `ace-main` and `ace-fork` both validate and include the new DNS/routing behavior.
- iOS/Android only need subscription refresh and VPN reconnect; no manual per-device rule edits are required.

## Rollback Plan

1. If generated YAML fails validation, do not run `sync-subconverter.sh`; revert the local commit.
2. If remote deploy succeeds but mobile clients fail to load profiles, restore the previous remote `sub-converter.py` backup from `/opt/ace-vpn-sub/backups/` or rerun `sync-subconverter.sh` from the previous git commit.
3. If only a domain classification is wrong, add a higher-priority `extra.cn` or `extra.overseas` override via `add-rule.sh`, verify locally, then promote.
4. Keep `ace-vpn-private` untouched unless new private/local override evidence is needed.

## Suggested Execution Order

1. Task 1 and Task 2 together, because route tests and grouped constants should land as one behavior change.
2. Task 3 next, because DNS policy is the likely missing piece for mobile CDN/video stability.
3. Task 4 to make future mobile misses easy to diagnose.
4. Task 5 deploy and verify.
5. Task 6 document the workflow.
