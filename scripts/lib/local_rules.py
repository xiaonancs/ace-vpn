#!/usr/bin/env python3
"""ace-vpn 本地规则池工具库

供 add-rule.sh / list-rules.sh / apply-local-overrides.sh / promote-to-vps.sh 调用。

local-rules.yaml schema:
    rules:
      - host: foo.com
        target: intranet | cn | overseas
        note: "..."
        added: "2026-04-21 16:00"

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

OVERRIDE_ID = "ace-vpn-local"
OVERRIDE_NAME = "ace-vpn local rules (auto-generated)"
OVERRIDE_FILE = OVERRIDE_DIR / f"{OVERRIDE_ID}.yaml"

# 三种 target 对应的 proxy group 名（与 sub-converter.py 输出保持一致）
PROXY_GROUP_OVERSEAS = "🚀 节点选择"

VALID_TARGETS = {"intranet", "cn", "overseas"}


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
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(content, encoding="utf-8")
    tmp.replace(path)


# ─────────────────────────────────────────────────────────────────
# local-rules.yaml 操作
# ─────────────────────────────────────────────────────────────────

def load_pool() -> list[dict]:
    data = _load_yaml(LOCAL_RULES_PATH, default={}) or {}
    rules = data.get("rules") or []
    return [r for r in rules if isinstance(r, dict) and r.get("host")]


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
    """加一条规则到本地池。

    返回 (added, message)：
      - added=True 表示新增；False 表示已存在/被跳过
    """
    host = host.strip().lower().lstrip(".")
    if not host:
        return False, "host 为空"
    if target not in VALID_TARGETS:
        return False, f"target 必须是 {VALID_TARGETS}，给的是 {target}"

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

    intranet target 额外加：
      dns:
        +fake-ip-filter:           ← 跳过 fake-ip
          - "+.foo.com"
        nameserver-policy:
          <+.foo.com>:             ← 强制走内网 DNS
            - 10.x.x.x
    """
    intranet_hosts = []
    other_rules = []

    for r in pool:
        host = r["host"]
        target = r.get("target")
        note = r.get("note", "")
        comment = f"  # {note}" if note else ""

        if target == "intranet":
            other_rules.append(f"DOMAIN-SUFFIX,{host},DIRECT{comment}")
            intranet_hosts.append(host)
        elif target == "cn":
            other_rules.append(f"DOMAIN-SUFFIX,{host},DIRECT{comment}")
        elif target == "overseas":
            other_rules.append(f"DOMAIN-SUFFIX,{host},{PROXY_GROUP_OVERSEAS}{comment}")
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
        lines.append("# 本地池为空")
        lines.append("rules: []  # 占位（不实际覆盖订阅 rules）")
        # 用占位 rules 而不是 +rules，避免清空订阅原有规则
        return "\n".join(lines) + "\n"

    lines.append("+rules:")
    for r in other_rules:
        lines.append(f"  - {r}")

    if intranet_hosts:
        dns_servers = get_active_intranet_dns()
        lines.append("")
        lines.append("dns:")
        lines.append("  +fake-ip-filter:")
        for h in intranet_hosts:
            lines.append(f'    - "+.{h}"')

        if dns_servers:
            lines.append("  nameserver-policy:")
            for h in intranet_hosts:
                # key 含 + 号，必须用 <> 包裹（Mihomo Party 语法）
                lines.append(f'    "<+.{h}>":')
                for s in dns_servers:
                    lines.append(f"      - {s}")
        else:
            lines.append("  # ⚠ intranet.yaml 当前 enabled profile 没配 dns_servers")
            lines.append("  # intranet 类规则只 prepend 了 fake-ip-filter，DNS 仍走系统")

    return "\n".join(lines) + "\n"


def render_and_install() -> dict:
    """渲染本地池 → 写到 Mihomo override 子文件 + 注册到 override.yaml。

    返回统计字典。
    """
    pool = load_pool()
    content = render_override_yaml(pool)

    if not MIHOMO_DIR.exists():
        raise FileNotFoundError(
            f"Mihomo Party 目录不存在：{MIHOMO_DIR}\n"
            f"请先安装并启动一次 Mihomo Party / Clash Party"
        )

    OVERRIDE_DIR.mkdir(parents=True, exist_ok=True)
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

    - intranet target → 加到当前第一个 enabled profile 的 domains
    - overseas target → 加到顶层 extra.overseas（跨 profile 共享）
    - cn target       → 加到顶层 extra.cn（跨 profile 共享）

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
    existing_domains = set((d or "").lower() for d in (active.get("domains") or []))

    extra = intra.get("extra") or {}
    existing_overseas = set((d or "").lower() for d in (extra.get("overseas") or []))
    existing_cn = set((d or "").lower() for d in (extra.get("cn") or []))

    plan = {
        "active_profile": active_name,
        "intranet_to_add": [],
        "intranet_skipped_dup": [],
        "overseas_to_add": [],
        "overseas_skipped_dup": [],
        "cn_to_add": [],
        "cn_skipped_dup": [],
        "unknown": [],
    }

    for r in pool:
        host = (r.get("host") or "").lower()
        target = r.get("target")
        if not host:
            continue
        if target == "intranet":
            if host in existing_domains:
                plan["intranet_skipped_dup"].append(host)
            else:
                plan["intranet_to_add"].append(host)
        elif target == "overseas":
            if host in existing_overseas:
                plan["overseas_skipped_dup"].append(host)
            else:
                plan["overseas_to_add"].append(host)
        elif target == "cn":
            if host in existing_cn:
                plan["cn_skipped_dup"].append(host)
            else:
                plan["cn_to_add"].append(host)
        else:
            plan["unknown"].append((host, target))

    return plan


def apply_promote(plan: dict) -> None:
    """根据 plan 实际改 intranet.yaml：
       - intranet → profiles[active].domains 追加
       - overseas → 顶层 extra.overseas 追加
       - cn       → 顶层 extra.cn 追加
    """
    if not (plan["intranet_to_add"] or plan["overseas_to_add"] or plan["cn_to_add"]):
        return

    raw = INTRANET_PATH.read_text(encoding="utf-8")
    intra = yaml.safe_load(raw) or {}

    # intranet → profile.domains
    if plan["intranet_to_add"]:
        active_name = plan["active_profile"]
        active = intra["profiles"][active_name]
        domains = list(active.get("domains") or [])
        for h in plan["intranet_to_add"]:
            if h not in domains:
                domains.append(h)
        active["domains"] = domains

    # overseas / cn → 顶层 extra（不存在则建）
    if plan["overseas_to_add"] or plan["cn_to_add"]:
        extra = intra.get("extra")
        if not isinstance(extra, dict):
            extra = {}
            intra["extra"] = extra

        if plan["overseas_to_add"]:
            cur = list(extra.get("overseas") or [])
            for h in plan["overseas_to_add"]:
                if h not in cur:
                    cur.append(h)
            extra["overseas"] = cur

        if plan["cn_to_add"]:
            cur = list(extra.get("cn") or [])
            for h in plan["cn_to_add"]:
                if h not in cur:
                    cur.append(h)
            extra["cn"] = cur

    INTRANET_PATH.write_text(_yaml_dump(intra), encoding="utf-8")


def all_promoted_hosts(plan: dict) -> list[str]:
    """plan 里所有"将被 promote"的 host 集合（用于 promote 后从本地池剔除）。

    跳过的（已存在 / unknown）不算——它们留在本地池让用户决定。
    """
    return list(plan["intranet_to_add"]) \
         + list(plan["overseas_to_add"]) \
         + list(plan["cn_to_add"])


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
