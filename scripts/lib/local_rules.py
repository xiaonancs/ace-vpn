#!/usr/bin/env python3
"""ace-vpn 本地规则池工具库

供 add-rule.sh / list-rules.sh / apply-local-overrides.sh / promote-to-vps.sh 调用。

local-rules.yaml schema:
    rules:
      - host: foo.com
        target: IN | DIRECT | VPS         # IN=内网, DIRECT=普通直连, VPS=走 VPS 代理出去
        note: "..."
        added: "2026-04-21 16:00"

target 语义：
    IN      → 公司内网 DOMAIN-SUFFIX,host,DIRECT + nameserver-policy 走内网 DNS
    DIRECT  → DOMAIN-SUFFIX,host,DIRECT（普通直连，国内站误判修正用）
    VPS     → DOMAIN-SUFFIX,host,🚀 PROXY（走 VPS 代理出去；新 AI / 新海外站）

为兼容老数据，加载时会把 intranet→IN / cn→DIRECT / overseas→VPS 自动 normalize。

Mihomo Party override 渲染目标：
    ~/Library/Application Support/mihomo-party/override.yaml         # 注册表
    ~/Library/Application Support/mihomo-party/override/<id>.yaml    # 实际内容
"""
from __future__ import annotations

import datetime
import os
import sys
from pathlib import Path
from typing import Any

import yaml


# ─────────────────────────────────────────────────────────────────
# 路径常量
# ─────────────────────────────────────────────────────────────────

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
LOCAL_RULES_PATH = REPO_ROOT / "private" / "local-rules.yaml"
INTRANET_PATH = REPO_ROOT / "private" / "intranet.yaml"

MIHOMO_DIR = Path.home() / "Library" / "Application Support" / "mihomo-party"
OVERRIDE_REGISTRY = MIHOMO_DIR / "override.yaml"
OVERRIDE_DIR = MIHOMO_DIR / "override"
OVERRIDE_BAK_DIR = OVERRIDE_DIR / ".bak"
OVERRIDE_BAK_KEEP = 10  # 最多保留 10 个备份

PROFILE_REGISTRY = MIHOMO_DIR / "profile.yaml"
PROFILE_DIR = MIHOMO_DIR / "profiles"

OVERRIDE_ID = "ace-vpn-local"
OVERRIDE_NAME = "ace-vpn local rules (auto-generated)"
OVERRIDE_FILE = OVERRIDE_DIR / f"{OVERRIDE_ID}.yaml"

# Mihomo / Clash builtin rule targets，永远合法，不需要在 proxy-groups 里查找
BUILTIN_TARGETS = {"DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "GLOBAL"}

# 三种 target 对应的 proxy group 名（与 sub-converter.py 输出保持一致）
PROXY_GROUP_VPS = "🚀 PROXY"  # 必须与 sub-converter.py 输出的 group name 一致！

# 用户面向的 target 名（命令行 / yaml 字段值 / UI 输出 一律这三个）
TARGET_IN = "IN"          # 公司内网
TARGET_DIRECT = "DIRECT"  # 普通直连
TARGET_VPS = "VPS"        # 走 VPS 代理出去

VALID_TARGETS = {TARGET_IN, TARGET_DIRECT, TARGET_VPS}

# 兼容老数据 + 大小写无关。用户输入 / 老 yaml 文件全部归一化到大写
_TARGET_ALIASES = {
    "in": TARGET_IN, "intranet": TARGET_IN, "internal": TARGET_IN,
    "direct": TARGET_DIRECT, "cn": TARGET_DIRECT, "china": TARGET_DIRECT,
    "vps": TARGET_VPS, "overseas": TARGET_VPS, "proxy": TARGET_VPS, "oversea": TARGET_VPS,
}


def normalize_target(raw: str | None) -> str | None:
    """把用户输入 / 老 yaml 的 target 字符串归一到 IN/DIRECT/VPS。
    无法识别返回 None。"""
    if not raw:
        return None
    return _TARGET_ALIASES.get(str(raw).strip().lower())


# ─────────────────────────────────────────────────────────────────
# YAML helpers
# ─────────────────────────────────────────────────────────────────

def _yaml_dump(data: Any) -> str:
    return yaml.safe_dump(data, allow_unicode=True, sort_keys=False, default_flow_style=False)


def _load_yaml(path: Path, default: Any = None) -> Any:
    if not path.exists():
        return default
    with path.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f) or default


def _atomic_write(path: Path, content: str) -> None:
    """原子写入。

    ⚠ 关键：先 resolve() 跟随 symlink 到真实文件再做 rename，否则
       tmp.replace(symlink_path) 会把 symlink 本身替换成普通文件，
       破坏 ace-vpn/private/local-rules.yaml → ace-vpn-private/... 的链接。
    """
    target = path
    try:
        if path.is_symlink() or path.exists():
            target = path.resolve()
    except OSError:
        target = path
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(target.suffix + ".tmp")
    tmp.write_text(content, encoding="utf-8")
    tmp.replace(target)


# ─────────────────────────────────────────────────────────────────
# local-rules.yaml 操作
# ─────────────────────────────────────────────────────────────────

def load_pool() -> list[dict]:
    """读取本地池。同时把老的 target 字符串（intranet/cn/overseas）归一到 IN/DIRECT/VPS。"""
    data = _load_yaml(LOCAL_RULES_PATH, default={}) or {}
    rules = data.get("rules") or []
    out = []
    for r in rules:
        if not (isinstance(r, dict) and r.get("host")):
            continue
        norm = normalize_target(r.get("target"))
        if norm:
            r["target"] = norm
        out.append(r)
    return out


def save_pool(rules: list[dict]) -> None:
    """写回时保留文件头部注释（保留模板说明）。"""
    if not LOCAL_RULES_PATH.exists():
        body = {"rules": rules}
        _atomic_write(LOCAL_RULES_PATH, _yaml_dump(body))
        return

    raw = LOCAL_RULES_PATH.read_text(encoding="utf-8")
    # 保留首个 'rules:' 之前的所有文本（注释 + 空行）
    header_lines = []
    for line in raw.splitlines(keepends=True):
        if line.lstrip().startswith("rules:"):
            break
        header_lines.append(line)
    header = "".join(header_lines)

    if rules:
        rules_yaml = _yaml_dump({"rules": rules})
    else:
        rules_yaml = "rules: []\n"

    _atomic_write(LOCAL_RULES_PATH, header + rules_yaml)


def add_rule(host: str, target: str, note: str = "") -> tuple[bool, str]:
    """加一条规则到本地池。target 接受 IN/DIRECT/VPS（大小写无关，
    也接受老名 intranet/cn/overseas）。

    返回 (added, message)：
      - added=True 表示新增；False 表示已存在/被跳过
    """
    host = host.strip().lower().lstrip(".")
    if not host:
        return False, "host 为空"

    norm = normalize_target(target)
    if norm is None:
        return False, f"target 必须是 IN / DIRECT / VPS，给的是 '{target}'"
    target = norm

    pool = load_pool()

    for r in pool:
        if r.get("host", "").lower() == host:
            if r.get("target") == target:
                return False, f"已存在：{host} → {target}"
            old = r.get("target")
            r["target"] = target
            r["note"] = note or r.get("note", "")
            r["added"] = _now_str()
            save_pool(pool)
            return True, f"更新：{host}  {old} → {target}"

    pool.append({
        "host": host,
        "target": target,
        "note": note,
        "added": _now_str(),
    })
    save_pool(pool)
    return True, f"新增：{host} → {target}"


def _now_str() -> str:
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M")


# ─────────────────────────────────────────────────────────────────
# 内网 DNS 提取（用于 intranet target 生成 nameserver-policy）
# ─────────────────────────────────────────────────────────────────

def get_active_intranet_dns() -> list[str]:
    """从 intranet.yaml 第一个 enabled profile 抽 dns_servers。"""
    data = _load_yaml(INTRANET_PATH, default={}) or {}
    profs = data.get("profiles") or {}
    if not isinstance(profs, dict):
        return []
    for _, prof in profs.items():
        if not isinstance(prof, dict) or not prof.get("enabled"):
            continue
        servers = prof.get("dns_servers") or []
        if servers:
            return [s for s in servers if isinstance(s, str)]
    return []


# ─────────────────────────────────────────────────────────────────
# Mihomo Party override 渲染
# ─────────────────────────────────────────────────────────────────

def render_override_yaml(pool: list[dict]) -> str:
    """把本地池渲染成 Mihomo Party 覆写 yaml（深度合并语法）。

    所有规则 prepend 到 rules 数组最前（最高优先级）：
      +rules:
        - DOMAIN-SUFFIX,foo.com,DIRECT

    target=IN 额外加：
      dns:
        +fake-ip-filter:           ← 跳过 fake-ip
          - "+.foo.com"
        nameserver-policy:
          <+.foo.com>:             ← 强制走内网 DNS
            - 10.x.x.x
    """
    in_hosts = []
    other_rules = []

    for r in pool:
        host = r["host"]
        target = normalize_target(r.get("target"))
        note = r.get("note", "")
        comment = f"  # {note}" if note else ""

        if target == TARGET_IN:
            other_rules.append(f"DOMAIN-SUFFIX,{host},DIRECT{comment}")
            in_hosts.append(host)
        elif target == TARGET_DIRECT:
            other_rules.append(f"DOMAIN-SUFFIX,{host},DIRECT{comment}")
        elif target == TARGET_VPS:
            other_rules.append(f"DOMAIN-SUFFIX,{host},{PROXY_GROUP_VPS}{comment}")
        # 未知 target 静默跳过

    lines: list[str] = [
        "# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
        f"# Auto-generated by ace-vpn/scripts/apply-local-overrides.sh",
        f"# Source: {LOCAL_RULES_PATH}",
        f"# Updated: {_now_str()}",
        "#",
        "# 不要手编辑这个文件。改 local-rules.yaml 然后 add-rule.sh 自动重渲染。",
        "# Mihomo Party 会在订阅加载后用这里的规则做深度合并：",
        "#   +rules:           prepend 到原 rules 最前（最高优先级）",
        "#   +fake-ip-filter:  prepend 到 dns.fake-ip-filter（防 fake-IP）",
        "#   <+.host>:         强制覆盖 dns.nameserver-policy 的 +.host 项",
        "# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
        "",
    ]

    if not other_rules:
        # ⚠ 本地池为空时，整个 override 必须**完全不含 rules / +rules / dns**
        #   等任何顶层字段，否则 Mihomo Party 的 deep merge 会把那个字段当成
        #   "用户指定要覆盖" → 用空 list 替换掉订阅里原本的规则集 → 全网瘫痪。
        #   历史曾错误地写过 `rules: []`（注释自称"占位"），实测会直接清空订阅
        #   rules 让 mihomo total rules=0，所有流量 fall through 到 DIRECT。
        #   现在保险做法：只留头部注释，不输出任何 yaml key。
        lines.append("# 本地池为空 —— 不输出任何字段，避免 deep merge 把订阅 rules 替换成空")
        return "\n".join(lines) + "\n"

    lines.append("+rules:")
    for r in other_rules:
        lines.append(f"  - {r}")

    if in_hosts:
        dns_servers = get_active_intranet_dns()
        lines.append("")
        lines.append("dns:")
        lines.append("  +fake-ip-filter:")
        for h in in_hosts:
            lines.append(f'    - "+.{h}"')

        if dns_servers:
            lines.append("  nameserver-policy:")
            for h in in_hosts:
                # key 含 + 号，必须用 <> 包裹（Mihomo Party 语法）
                lines.append(f'    "<+.{h}>":')
                for s in dns_servers:
                    lines.append(f"      - {s}")
        else:
            lines.append("  # ⚠ intranet.yaml 当前 enabled profile 没配 dns_servers")
            lines.append("  # IN 类规则只 prepend 了 fake-ip-filter，DNS 仍走系统")

    return "\n".join(lines) + "\n"


def get_active_profile_id() -> str | None:
    """从 Mihomo Party profile.yaml 注册表里取第一个 enabled 的 profile id。

    profile.yaml 结构（用户切换 profile 后这个会自动改）：
        items:
          - id: 19da8c4f699
            name: ...
            ...
          - id: ...
    Mihomo Party 用 items[0]（注册表是顺序敏感的，第 1 个就是 current）。
    """
    if not PROFILE_REGISTRY.exists():
        return None
    try:
        data = _load_yaml(PROFILE_REGISTRY, default={}) or {}
    except Exception:
        return None
    items = data.get("items") or []
    if not items:
        return None
    first = items[0]
    if isinstance(first, dict) and first.get("id"):
        return str(first["id"])
    return None


def get_available_proxy_groups(profile_id: str | None = None) -> set[str]:
    """读 active profile 拿所有 proxy / proxy-group 的合法名集合 + builtin。

    用于 pre-flight check：本地池里所有 target 必须在这个集合里，否则
    写到 override 后 Mihomo Party 加载 profile 会整体失败 → 用户连不上网。
    """
    pid = profile_id or get_active_profile_id()
    if not pid:
        return set()
    pf = PROFILE_DIR / f"{pid}.yaml"
    if not pf.exists():
        return set()
    try:
        data = _load_yaml(pf, default={}) or {}
    except Exception:
        return set()
    names: set[str] = set(BUILTIN_TARGETS)
    for g in (data.get("proxy-groups") or []):
        if isinstance(g, dict) and g.get("name"):
            names.add(str(g["name"]))
    for p in (data.get("proxies") or []):
        if isinstance(p, dict) and p.get("name"):
            names.add(str(p["name"]))
    return names


def validate_pool(pool: list[dict]) -> tuple[bool, list[str], set[str]]:
    """pre-flight 校验本地池里每条规则引用的 target proxy 是否存在于 active profile。

    返回 (ok, errors, available_groups)：
      - ok=False 时 errors 列出哪些规则坏了
      - available_groups 用于在错误信息里告诉用户当前 profile 有哪些可选
    """
    available = get_available_proxy_groups()
    if not available:
        # 拿不到可用 group 集合（profile 文件不存在 / 解析失败 / GUI 未启动）
        # 不卡用户：返回 ok=True 让流程继续，但 errors 里给一条 warning
        return True, ["⚠ 无法读取当前 profile，跳过 proxy group 校验（GUI 未启动？）"], set()

    errors = []
    for r in pool:
        host = r.get("host", "?")
        target = normalize_target(r.get("target"))
        if target == TARGET_VPS:
            wanted = PROXY_GROUP_VPS
            if wanted not in available:
                errors.append(
                    f"VPS 类规则 host={host} 引用 proxy '{wanted}'，但当前 profile 里没有这个 group"
                )
        # IN / DIRECT 都用 builtin DIRECT，永远合法

    return (len(errors) == 0), errors, available


def _backup_override_file() -> Path | None:
    """写新 override 前备份当前 override 文件到 override/.bak/<file>.<timestamp>。

    返回备份路径；若当前没有 override 文件则返回 None。同时清理超出
    OVERRIDE_BAK_KEEP 数量的旧备份。
    """
    if not OVERRIDE_FILE.exists() and not OVERRIDE_FILE.is_symlink():
        return None
    OVERRIDE_BAK_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    bak = OVERRIDE_BAK_DIR / f"{OVERRIDE_FILE.name}.{ts}.bak"
    bak.write_bytes(OVERRIDE_FILE.read_bytes())

    # GC 旧备份：保留 OVERRIDE_BAK_KEEP 个最新
    baks = sorted(OVERRIDE_BAK_DIR.glob(f"{OVERRIDE_FILE.name}.*.bak"))
    for old in baks[:-OVERRIDE_BAK_KEEP]:
        try:
            old.unlink()
        except OSError:
            pass
    return bak


def list_override_backups() -> list[Path]:
    """按时间倒序（新→旧）列出所有 override 备份。"""
    if not OVERRIDE_BAK_DIR.exists():
        return []
    return sorted(OVERRIDE_BAK_DIR.glob(f"{OVERRIDE_FILE.name}.*.bak"), reverse=True)


def restore_override_backup(bak: Path) -> None:
    """把 bak 文件恢复成当前 override（不删 bak，方便反复）。"""
    if not bak.exists():
        raise FileNotFoundError(f"备份不存在：{bak}")
    OVERRIDE_DIR.mkdir(parents=True, exist_ok=True)
    _atomic_write(OVERRIDE_FILE, bak.read_text(encoding="utf-8"))


def disable_override_in_registry() -> bool:
    """把 override.yaml 注册表里 ace-vpn-local 那条 enabled 改成 false（应急用）。

    返回 True 表示改成功，False 表示注册表里没找到这条。
    """
    if not OVERRIDE_REGISTRY.exists():
        return False
    registry = _load_yaml(OVERRIDE_REGISTRY, default={"items": []}) or {"items": []}
    items = registry.get("items") or []
    found = False
    for item in items:
        if isinstance(item, dict) and item.get("id") == OVERRIDE_ID:
            item["enabled"] = False
            item["updated"] = int(datetime.datetime.now().timestamp() * 1000)
            found = True
            break
    if found:
        _atomic_write(OVERRIDE_REGISTRY, _yaml_dump(registry))
    return found


def render_and_install(*, validate: bool = True) -> dict:
    """渲染本地池 → 写到 Mihomo override 子文件 + 注册到 override.yaml。

    流程（带安全网）：
      1. pre-flight 校验：本地池里所有 VPS 类规则引用的 proxy group 都
         必须在当前 active profile 里存在。任意一个不在 → 拒绝写入，
         保留旧 override 不动（用户网络不会因为新加的坏规则断掉）
      2. 备份当前 override 文件到 override/.bak/<file>.<ts>.bak
      3. 原子写入新 override
      4. 同步 override 注册表
    返回统计字典；validate 失败时 raise ValueError。
    """
    pool = load_pool()

    if not MIHOMO_DIR.exists():
        raise FileNotFoundError(
            f"Mihomo Party 目录不存在：{MIHOMO_DIR}\n"
            f"请先安装并启动一次 Mihomo Party / Clash Party"
        )

    if validate:
        ok, errors, available = validate_pool(pool)
        if not ok:
            msg_lines = ["pre-flight 校验失败，未写入 override（你的网络不受影响）：", ""]
            msg_lines.extend(f"  ✗ {e}" for e in errors)
            if available:
                vps_like = sorted(g for g in available if g not in BUILTIN_TARGETS)
                msg_lines.extend([
                    "",
                    f"当前 profile 里可用的 proxy group：",
                    "    " + ", ".join(vps_like[:20]) + (" ..." if len(vps_like) > 20 else ""),
                    "",
                    f"修法：编辑 {LOCAL_RULES_PATH} 修正/删除上面那些坏规则，",
                    f"     再跑一次 bash scripts/apply-local-overrides.sh",
                ])
            raise ValueError("\n".join(msg_lines))
        # warning 也展示
        for w in errors:
            print(f"  {w}")

    content = render_override_yaml(pool)

    OVERRIDE_DIR.mkdir(parents=True, exist_ok=True)
    bak = _backup_override_file()
    _atomic_write(OVERRIDE_FILE, content)

    # 注册到 override.yaml（如果还没注册过）
    registry = _load_yaml(OVERRIDE_REGISTRY, default={"items": []}) or {"items": []}
    items = registry.get("items") or []
    found = False
    for item in items:
        if isinstance(item, dict) and item.get("id") == OVERRIDE_ID:
            item["name"] = OVERRIDE_NAME
            item["type"] = "local"
            item["ext"] = "yaml"
            item["enabled"] = True
            item["global"] = True
            item["updated"] = int(datetime.datetime.now().timestamp() * 1000)
            found = True
            break

    if not found:
        items.append({
            "id": OVERRIDE_ID,
            "name": OVERRIDE_NAME,
            "type": "local",
            "ext": "yaml",
            "enabled": True,
            "global": True,
            "updated": int(datetime.datetime.now().timestamp() * 1000),
        })
        registry["items"] = items

    _atomic_write(OVERRIDE_REGISTRY, _yaml_dump(registry))

    by_target = {}
    for r in pool:
        by_target[r.get("target", "?")] = by_target.get(r.get("target", "?"), 0) + 1

    return {
        "rules_total": len(pool),
        "by_target": by_target,
        "override_file": str(OVERRIDE_FILE),
        "registered": not found,  # True 表示这次新注册的
    }


# ─────────────────────────────────────────────────────────────────
# 触发 Mihomo Party reload（curl localhost API）
# ─────────────────────────────────────────────────────────────────

def trigger_mihomo_reload() -> tuple[bool, str]:
    """触发 Mihomo Party 重新加载配置。

    策略（按可靠性排序）：

    1. 改 override 文件的 mtime（已经写入时改了）→ Mihomo Party GUI 默认监听
       override 目录，会自动 reload。这是最常见情况。

    2. 如果 work/config.yaml 里 external-controller 配置了 host:port，
       走标准 RESTful API：PUT /configs?force=true（带 secret）。
       多数用户没开这个（Mihomo Party 默认空），所以是 fallback。

    3. 都失败：返回 False + 提示语，让用户在 GUI 里手动点一下"重新加载"。
    """
    work_cfg = MIHOMO_DIR / "work" / "config.yaml"

    # 路径 1：Mihomo Party 自动监听 override（GUI 跑着就秒级生效）
    # 我们已经原子写了 override 文件，watcher 会触发——这里只能"乐观假设成功"
    auto_msg = "Mihomo Party GUI 监听 override 目录，秒级自动应用（前提 GUI 在跑）"

    if not work_cfg.exists():
        return True, f"{auto_msg}（GUI 未启动则下次开 GUI 时生效）"

    try:
        cfg = yaml.safe_load(work_cfg.read_text(encoding="utf-8")) or {}
    except Exception:
        return True, auto_msg

    ctrl = (cfg.get("external-controller") or "").strip()
    if not ctrl or ctrl in ("0.0.0.0:0", ":0"):
        return True, auto_msg

    secret = cfg.get("secret", "")

    import urllib.request
    import urllib.error
    import json

    if "://" not in ctrl:
        ctrl = "http://" + ctrl
    url = ctrl.rstrip("/") + "/configs?force=true"
    body = json.dumps({"path": str(work_cfg)}).encode()
    req = urllib.request.Request(url, data=body, method="PUT")
    req.add_header("Content-Type", "application/json")
    if secret:
        req.add_header("Authorization", f"Bearer {secret}")

    try:
        with urllib.request.urlopen(req, timeout=3) as resp:
            return True, f"通过 controller {ctrl} reload 成功（HTTP {resp.status}）"
    except Exception as e:
        return True, f"{auto_msg}（controller {ctrl} 调用失败：{type(e).__name__}）"


# ─────────────────────────────────────────────────────────────────
# promote：本地池 → intranet.yaml 合并 + 清空
# ─────────────────────────────────────────────────────────────────

def promote_to_intranet() -> dict:
    """把本地池里的规则按 target 合并到 intranet.yaml。

    映射（用户 target → intranet.yaml 字段）：
      IN     → profiles[active].domains            （随当前 enabled profile）
      VPS    → 顶层 extra.overseas                  （跨 profile 共享）
      DIRECT → 顶层 extra.cn                        （跨 profile 共享）

    注：intranet.yaml 顶层 extra 字段名（overseas/cn）保持不变，
       因为 sub-converter 已经按这套 schema 部署在 VPS 上。
       用户层面只看到 IN/DIRECT/VPS，schema 命名是内部细节。

    返回 plan dict（不真改文件），由 apply_promote() 落地。
    """
    pool = load_pool()
    intra = _load_yaml(INTRANET_PATH, default={}) or {}
    profs = intra.get("profiles") or {}
    if not isinstance(profs, dict):
        raise ValueError(f"{INTRANET_PATH} 不是 profiles 结构")

    active_name = None
    for name, prof in profs.items():
        if isinstance(prof, dict) and prof.get("enabled"):
            active_name = name
            break

    if not active_name:
        raise ValueError(f"{INTRANET_PATH} 没有任何 enabled profile")

    active = profs[active_name]
    existing_in = set((d or "").lower() for d in (active.get("domains") or []))

    extra = intra.get("extra") or {}
    existing_vps = set((d or "").lower() for d in (extra.get("overseas") or []))
    existing_direct = set((d or "").lower() for d in (extra.get("cn") or []))

    plan = {
        "active_profile": active_name,
        "in_to_add": [], "in_skipped_dup": [],
        "vps_to_add": [], "vps_skipped_dup": [],
        "direct_to_add": [], "direct_skipped_dup": [],
        "unknown": [],
    }

    for r in pool:
        host = (r.get("host") or "").lower()
        target = normalize_target(r.get("target"))
        if not host:
            continue
        if target == TARGET_IN:
            (plan["in_skipped_dup"] if host in existing_in else plan["in_to_add"]).append(host)
        elif target == TARGET_VPS:
            (plan["vps_skipped_dup"] if host in existing_vps else plan["vps_to_add"]).append(host)
        elif target == TARGET_DIRECT:
            (plan["direct_skipped_dup"] if host in existing_direct else plan["direct_to_add"]).append(host)
        else:
            plan["unknown"].append((host, r.get("target")))

    return plan


def apply_promote(plan: dict) -> None:
    """根据 plan 实际改 intranet.yaml：
       - IN     → profiles[active].domains 追加
       - VPS    → 顶层 extra.overseas 追加
       - DIRECT → 顶层 extra.cn 追加
    """
    if not (plan["in_to_add"] or plan["vps_to_add"] or plan["direct_to_add"]):
        return

    raw = INTRANET_PATH.read_text(encoding="utf-8")
    intra = yaml.safe_load(raw) or {}

    # IN → profile.domains
    if plan["in_to_add"]:
        active_name = plan["active_profile"]
        active = intra["profiles"][active_name]
        domains = list(active.get("domains") or [])
        for h in plan["in_to_add"]:
            if h not in domains:
                domains.append(h)
        active["domains"] = domains

    # VPS / DIRECT → 顶层 extra（不存在则建）
    if plan["vps_to_add"] or plan["direct_to_add"]:
        extra = intra.get("extra")
        if not isinstance(extra, dict):
            extra = {}
            intra["extra"] = extra

        if plan["vps_to_add"]:
            cur = list(extra.get("overseas") or [])
            for h in plan["vps_to_add"]:
                if h not in cur:
                    cur.append(h)
            extra["overseas"] = cur

        if plan["direct_to_add"]:
            cur = list(extra.get("cn") or [])
            for h in plan["direct_to_add"]:
                if h not in cur:
                    cur.append(h)
            extra["cn"] = cur

    INTRANET_PATH.write_text(_yaml_dump(intra), encoding="utf-8")


def all_promoted_hosts(plan: dict) -> list[str]:
    """plan 里所有"将被 promote"的 host 集合（用于 promote 后从本地池剔除）。

    跳过的（已存在 / unknown）不算——它们留在本地池让用户决定。
    """
    return list(plan["in_to_add"]) \
         + list(plan["vps_to_add"]) \
         + list(plan["direct_to_add"])


def remove_from_pool(hosts: list[str]) -> int:
    """从本地池删掉指定 host 的规则，返回删除数量。"""
    if not hosts:
        return 0
    pool = load_pool()
    keep = []
    removed = 0
    targets_set = set(h.lower() for h in hosts)
    for r in pool:
        if r.get("host", "").lower() in targets_set:
            removed += 1
        else:
            keep.append(r)
    save_pool(keep)
    return removed
