#!/usr/bin/env python3
"""mihomo Clash YAML 语义校验器（独立，无外部依赖）。

为什么需要它：
  python3 -c 'yaml.safe_load(...)' 只能发现语法错误，发现不了"语义级联动"问题，
  例如今天踩的坑（见 docs/开发者日志.md §4.A.10）：
      dns.respect-rules: true
      dns.proxy-server-nameserver: []     ← 空
  YAML 语法完全正确，但 mihomo 的校验器会直接拒绝这种组合，导致客户端 profile
  check failed → 订阅全线不可用。

本脚本在 sync-subconverter.sh 里本地推前 + 远端推后各跑一次，把"能生成、
mihomo 拒收"的 YAML 拦在真正拉订阅之前。

用法：
  python3 validate-config.py <yaml-file>            # 校验一份文件
  curl http://vps:25500/<SUB_PATH_PREFIX>/$tok | python3 validate-config.py -   # 校验 stdin

退出码：
  0    通过
  1    致命错误（必然被 mihomo 拒绝）
  2    警告（非致命，但可能导致不可预期行为；默认不视作失败，除非 --strict）
"""

from __future__ import annotations

import argparse
import sys
from typing import Any, List, Tuple

try:
    import yaml
except ImportError:
    print("ERROR: 需要 PyYAML (pip3 install pyyaml)", file=sys.stderr)
    sys.exit(1)


class Issue:
    def __init__(self, level: str, path: str, msg: str):
        self.level = level  # "error" | "warn"
        self.path = path
        self.msg = msg

    def render(self) -> str:
        tag = {"error": "\033[31mERROR\033[0m", "warn": "\033[33mWARN \033[0m"}[self.level]
        return f"  {tag}  {self.path}: {self.msg}"


# ───────────────────────── 校验规则 ──────────────────────────


def check_dns(cfg: dict) -> List[Issue]:
    """DNS 块校验。今天主要的坑都在这里。"""
    issues: List[Issue] = []
    dns = cfg.get("dns") or {}
    if not dns:
        issues.append(Issue("warn", "dns", "缺失整个 dns 段（mihomo 会用默认值）"))
        return issues

    respect = dns.get("respect-rules", False)
    psn = dns.get("proxy-server-nameserver") or []
    # 核心联动 1：respect-rules 必须配 proxy-server-nameserver
    if respect and not psn:
        issues.append(
            Issue(
                "error",
                "dns.proxy-server-nameserver",
                "dns.respect-rules=true 时必须非空（mihomo 硬校验，见 §4.A.10）",
            )
        )
    # 核心联动 2：proxy-server-nameserver 里主机必须是 IP（不能递归解析域名型 DoH）
    for idx, ns in enumerate(psn):
        if not isinstance(ns, str):
            issues.append(Issue("error", f"dns.proxy-server-nameserver[{idx}]", f"必须是字符串，实为 {type(ns).__name__}"))
            continue
        host = _extract_host(ns)
        if host and not _is_ip(host):
            issues.append(
                Issue(
                    "error",
                    f"dns.proxy-server-nameserver[{idx}]",
                    f"主机 {host!r} 是域名，bootstrap 阶段会死锁；必须用 IP 型 DoH（如 https://1.1.1.1/dns-query）",
                )
            )

    # 核心联动 3：enhanced-mode=fake-ip 需要 fake-ip-range
    if dns.get("enhanced-mode") == "fake-ip" and not dns.get("fake-ip-range"):
        issues.append(Issue("error", "dns.fake-ip-range", "enhanced-mode=fake-ip 时必须提供 fake-ip-range"))

    # 软性检查：nameserver 不能为空
    if not (dns.get("nameserver") or []):
        issues.append(Issue("error", "dns.nameserver", "不能为空"))

    # 软性检查：nameserver-policy 每条 value 必须是 list 或 "system"
    pol = dns.get("nameserver-policy") or {}
    for k, v in pol.items():
        if isinstance(v, str):
            if v != "system":
                issues.append(Issue("warn", f"dns.nameserver-policy[{k!r}]", f"字符串值只支持 'system'，实为 {v!r}"))
        elif not isinstance(v, list):
            issues.append(Issue("error", f"dns.nameserver-policy[{k!r}]", f"必须是 list 或 'system'，实为 {type(v).__name__}"))

    # 软性检查：default-nameserver（如果存在）必须是 IP（它是 bootstrap）
    for idx, ns in enumerate(dns.get("default-nameserver") or []):
        if isinstance(ns, str):
            host = _extract_host(ns)
            if host and not _is_ip(host):
                issues.append(
                    Issue(
                        "error",
                        f"dns.default-nameserver[{idx}]",
                        f"主机 {host!r} 必须是 IP（default-nameserver 是 bootstrap DNS）",
                    )
                )

    return issues


def check_proxies(cfg: dict) -> List[Issue]:
    issues: List[Issue] = []
    proxies = cfg.get("proxies") or []
    if not proxies:
        issues.append(Issue("error", "proxies", "节点列表为空，订阅不可用"))
        return issues
    names = set()
    for i, p in enumerate(proxies):
        if not isinstance(p, dict):
            issues.append(Issue("error", f"proxies[{i}]", f"必须是 mapping，实为 {type(p).__name__}"))
            continue
        n = p.get("name")
        if not n:
            issues.append(Issue("error", f"proxies[{i}]", "缺 name 字段"))
        elif n in names:
            issues.append(Issue("error", f"proxies[{i}]", f"节点名重复：{n!r}"))
        else:
            names.add(n)
        if not p.get("server"):
            issues.append(Issue("error", f"proxies[{i}].server", "缺失"))
        if not p.get("port"):
            issues.append(Issue("error", f"proxies[{i}].port", "缺失"))
    return issues


def check_proxy_groups(cfg: dict) -> List[Issue]:
    issues: List[Issue] = []
    groups = cfg.get("proxy-groups") or []
    group_names = {g.get("name") for g in groups if isinstance(g, dict)}
    proxy_names = {p.get("name") for p in (cfg.get("proxies") or []) if isinstance(p, dict)}
    all_names = group_names | proxy_names | {"DIRECT", "REJECT", "PASS"}

    for i, g in enumerate(groups):
        if not isinstance(g, dict):
            issues.append(Issue("error", f"proxy-groups[{i}]", f"必须是 mapping，实为 {type(g).__name__}"))
            continue
        name = g.get("name") or f"#{i}"
        for j, ref in enumerate(g.get("proxies") or []):
            if ref not in all_names:
                issues.append(
                    Issue(
                        "error",
                        f"proxy-groups[{name!r}].proxies[{j}]",
                        f"引用不存在的节点/组：{ref!r}",
                    )
                )
    return issues


def check_rules(cfg: dict) -> List[Issue]:
    issues: List[Issue] = []
    rules = cfg.get("rules") or []
    if not rules:
        issues.append(Issue("error", "rules", "规则列表为空"))
        return issues
    group_names = {g.get("name") for g in (cfg.get("proxy-groups") or []) if isinstance(g, dict)}
    proxy_names = {p.get("name") for p in (cfg.get("proxies") or []) if isinstance(p, dict)}
    builtin = {"DIRECT", "REJECT", "REJECT-DROP", "PASS"}
    all_targets = group_names | proxy_names | builtin

    last = rules[-1] if rules else ""
    if not isinstance(last, str) or not last.startswith("MATCH,"):
        issues.append(Issue("warn", f"rules[-1]", f"最后一条建议是 MATCH 兜底，实为 {last!r}"))

    for i, r in enumerate(rules):
        if not isinstance(r, str):
            issues.append(Issue("error", f"rules[{i}]", f"必须是字符串，实为 {type(r).__name__}"))
            continue
        parts = r.split(",")
        if len(parts) < 2:
            issues.append(Issue("error", f"rules[{i}]", f"格式错：{r!r}（至少 TYPE,VALUE,TARGET）"))
            continue
        rtype = parts[0].strip()
        # MATCH,TARGET 只有 2 段；其他至少 3 段
        if rtype == "MATCH":
            target = parts[1].strip()
        else:
            if len(parts) < 3:
                issues.append(Issue("error", f"rules[{i}]", f"非 MATCH 规则至少 3 段：{r!r}"))
                continue
            target = parts[2].strip()
        if target not in all_targets:
            issues.append(Issue("error", f"rules[{i}]", f"target {target!r} 不存在（规则：{r!r}）"))
    return issues


def check_sniffer(cfg: dict) -> List[Issue]:
    issues: List[Issue] = []
    sn = cfg.get("sniffer") or {}
    if sn.get("enable") and not (sn.get("sniff") or {}):
        issues.append(Issue("warn", "sniffer.sniff", "enable=true 但 sniff 为空，等于关闭"))
    return issues


CHECKS = [check_dns, check_proxies, check_proxy_groups, check_rules, check_sniffer]


# ───────────────────────── 工具函数 ──────────────────────────


def _extract_host(ns: str) -> str:
    """从 DNS 字符串里抽出 host 部分。

    支持：
      - '223.5.5.5'                     → '223.5.5.5'
      - 'tls://8.8.8.8:853'              → '8.8.8.8'
      - 'https://1.1.1.1/dns-query'     → '1.1.1.1'
      - 'https://dns.google/dns-query'  → 'dns.google'
      - 'system'                         → ''（不校验）
    """
    s = ns.strip()
    if s in ("system",):
        return ""
    # 去 scheme
    if "://" in s:
        s = s.split("://", 1)[1]
    # 去 path
    if "/" in s:
        s = s.split("/", 1)[0]
    # 去 port
    if s.startswith("["):  # IPv6
        if "]" in s:
            return s.split("]", 1)[0].lstrip("[")
        return s
    if ":" in s:
        s = s.rsplit(":", 1)[0]
    return s


def _is_ip(host: str) -> bool:
    import ipaddress

    try:
        ipaddress.ip_address(host)
        return True
    except ValueError:
        return False


# ───────────────────────── 主流程 ──────────────────────────


def validate(cfg: dict) -> Tuple[List[Issue], List[Issue]]:
    errors: List[Issue] = []
    warns: List[Issue] = []
    for fn in CHECKS:
        for iss in fn(cfg):
            (errors if iss.level == "error" else warns).append(iss)
    return errors, warns


def main() -> int:
    ap = argparse.ArgumentParser(
        description="mihomo Clash YAML 语义校验器（拦 respect-rules / proxy-group / rules 引用等联动问题）"
    )
    ap.add_argument("file", help="YAML 文件路径；'-' 表示从 stdin 读")
    ap.add_argument("--strict", action="store_true", help="warn 也视为失败")
    ap.add_argument("--quiet", action="store_true", help="成功时不输出")
    args = ap.parse_args()

    if args.file == "-":
        raw = sys.stdin.read()
    else:
        with open(args.file, "r", encoding="utf-8") as f:
            raw = f.read()

    try:
        cfg = yaml.safe_load(raw) or {}
    except yaml.YAMLError as e:
        print(f"\033[31mYAML 语法错误：\033[0m{e}", file=sys.stderr)
        return 1
    if not isinstance(cfg, dict):
        print(f"\033[31mYAML 顶层必须是 mapping，实为 {type(cfg).__name__}\033[0m", file=sys.stderr)
        return 1

    errors, warns = validate(cfg)

    if args.quiet and not errors and not (args.strict and warns):
        return 0

    if errors:
        print(f"\033[31m✗\033[0m 发现 {len(errors)} 个致命错误：", file=sys.stderr)
        for e in errors:
            print(e.render(), file=sys.stderr)
    if warns:
        tag = "\033[33m!\033[0m" if not args.strict else "\033[31m✗\033[0m"
        print(f"{tag}  {len(warns)} 个警告：", file=sys.stderr)
        for w in warns:
            print(w.render(), file=sys.stderr)

    if errors or (args.strict and warns):
        return 1

    if not args.quiet:
        ok_count = (
            len(cfg.get("proxies") or []),
            len(cfg.get("proxy-groups") or []),
            len(cfg.get("rules") or []),
        )
        print(f"\033[32m✓\033[0m 校验通过 · proxies={ok_count[0]} proxy-groups={ok_count[1]} rules={ok_count[2]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
