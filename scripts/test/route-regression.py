#!/usr/bin/env python3
"""Regression checks for ace-vpn built-in routing decisions."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
SUB_CONVERTER = ROOT_DIR / "scripts" / "server" / "sub-converter.py"


def load_module():
    spec = importlib.util.spec_from_file_location("_ace_sub_converter", SUB_CONVERTER)
    if not spec or not spec.loader:
        raise RuntimeError(f"cannot import {SUB_CONVERTER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    module = load_module()
    intranet = {
        "cidrs": ["10.0.0.0/8"],
        "domains": ["corp.example.com"],
        "domain_dns": {},
        "active_profiles": ["test"],
        "extra_overseas": ["new-ai.example"],
        "extra_cn": ["cn-saas.example"],
    }
    cases = [
        ("gmail.com", "🚀 PROXY"),
        ("mail.google.com", "🚀 PROXY"),
        ("ci3.googleusercontent.com", "🚀 PROXY"),
        ("googlemail.com", "🚀 PROXY"),
        ("chatgpt.com", "🤖 AI"),
        ("api.openai.com", "🤖 AI"),
        ("claude.ai", "🤖 AI"),
        ("gemini.google.com", "🤖 AI"),
        ("youtube.com", "📺 MEDIA"),
        ("googlevideo.com", "📺 MEDIA"),
        ("douyin.com", "DIRECT"),
        ("bilibili.com", "DIRECT"),
        ("portal.corp.example.com", "DIRECT"),
        ("new-ai.example", "🚀 PROXY"),
        ("cn-saas.example", "DIRECT"),
    ]

    failed = 0
    for host, expected in cases:
        result = module.match_rule(host, intranet)
        actual = result.get("target")
        rule = result.get("rule")
        if actual != expected:
            failed += 1
            print(f"FAIL {host}: expected={expected!r} actual={actual!r} rule={rule!r}")
        else:
            print(f"OK   {host}: {actual} via {rule}")

    if failed:
        print(f"\n{failed} route regression(s) failed", file=sys.stderr)
        return 1
    print("\nroute regressions passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
