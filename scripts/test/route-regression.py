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
        ("forbes.com", "🚀 PROXY"),
        ("www.forbes.com", "🚀 PROXY"),
        ("image.forbesimg.com", "🚀 PROXY"),
        ("bloomberg.com", "🚀 PROXY"),
        ("reuters.com", "🚀 PROXY"),
        ("pinterest.com", "🚀 PROXY"),
        ("i.pinimg.com", "🚀 PROXY"),
        ("pinterest.ca", "🚀 PROXY"),
        ("tiktok.com", "🚀 PROXY"),
        ("snapchat.com", "🚀 PROXY"),
        ("linkedin.com", "🚀 PROXY"),
        ("slack.com", "🚀 PROXY"),
        ("notion.so", "🚀 PROXY"),
        ("chatgpt.com", "🤖 AI"),
        ("api.openai.com", "🤖 AI"),
        ("claude.ai", "🤖 AI"),
        ("gemini.google.com", "🤖 AI"),
        ("youtube.com", "📺 MEDIA"),
        ("googlevideo.com", "📺 MEDIA"),
        ("douyin.com", "DIRECT"),
        ("douyinstatic.com", "DIRECT"),
        ("p3-dy.byteimg.com", "DIRECT"),
        ("lf3-static.bytednsdoc.com", "DIRECT"),
        ("v5-dy-o-abtest.zjcdn.com", "DIRECT"),
        ("ixigua.com", "DIRECT"),
        ("bilibili.com", "DIRECT"),
        ("i0.hdslb.com", "DIRECT"),
        ("biliimg.com", "DIRECT"),
        ("acgvideo.com", "DIRECT"),
        ("upos-sz-mirrorcos.bilivideo.net", "DIRECT"),
        ("upos-sz-mirrorcos.bilivideo.cn", "DIRECT"),
        ("uposdash-302-bilivideo.yfcdn.net", "DIRECT"),
        ("1gr5dgmttgha1hcj38yzdncb3.ourdvsss.com", "DIRECT"),
        ("sns-img-qc.xhscdn.net", "DIRECT"),
        ("fe-video-qc.xhscdn.net", "DIRECT"),
        ("sns-img-qc.xhscdn.com", "DIRECT"),
        ("weibocdn.com", "DIRECT"),
        ("mmbiz.qpic.cn", "DIRECT"),
        ("thirdwx.qlogo.cn", "DIRECT"),
        ("apd-pcdnwxlogin.teg.tencent-cloud.net", "DIRECT"),
        ("wechatpay.com", "DIRECT"),
        ("weixin.com", "DIRECT"),
        ("wechatos.net", "DIRECT"),
        ("wechatlegal.net", "DIRECT"),
        ("weixinsxy.com", "DIRECT"),
        ("iot-tencent.com", "DIRECT"),
        ("qcloudimg.com", "DIRECT"),
        ("qcloudcdn.com", "DIRECT"),
        ("waimai.meituan.com", "DIRECT"),
        ("p1.meituan.net", "DIRECT"),
        ("api.sankuai.com", "DIRECT"),
        ("dianping.com", "DIRECT"),
        ("servicewechat.com", "DIRECT"),
        ("dingtalk.com", "DIRECT"),
        ("elemecdn.com", "DIRECT"),
        ("elemecdn.cn", "DIRECT"),
        ("ele.to", "DIRECT"),
        ("elenet.me", "DIRECT"),
        ("amap.com", "DIRECT"),
        ("didichuxing.com", "DIRECT"),
        ("ctrip.com", "DIRECT"),
        ("mgtv.com", "DIRECT"),
        ("vip.com", "DIRECT"),
        ("wecom.work", "DIRECT"),
        ("bankcomm.com", "DIRECT"),
        ("pinduoduo.com", "DIRECT"),
        ("pddpic.com", "DIRECT"),
        ("kuaishou.com", "DIRECT"),
        ("kwimgs.com", "DIRECT"),
        ("yximgs.com", "DIRECT"),
        ("360buyimg.com", "DIRECT"),
        ("img10.jdstatic.com", "DIRECT"),
        ("jcloudcs.com", "DIRECT"),
        ("gw.taobaocdn.com", "DIRECT"),
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

    shadowrocket_overseas = module.build_shadowrocket_rule_list(
        "test overseas",
        module.SHADOWROCKET_OVERSEAS_PROXY,
    )
    shadowrocket_china = module.build_shadowrocket_rule_list(
        "test china",
        module.SHADOWROCKET_CHINA_DIRECT,
    )
    for needle, content in [
        ("DOMAIN-SUFFIX,pinimg.com", shadowrocket_overseas),
        ("DOMAIN-SUFFIX,pinterest.com", shadowrocket_overseas),
        ("DOMAIN-SUFFIX,xhscdn.net", shadowrocket_china),
        ("DOMAIN-SUFFIX,weixin.com", shadowrocket_china),
        ("DOMAIN-SUFFIX,tencent-cloud.net", shadowrocket_china),
        ("DOMAIN-SUFFIX,qcloudimg.com", shadowrocket_china),
        ("DOMAIN-SUFFIX,byteimg.com", shadowrocket_china),
        ("DOMAIN-SUFFIX,bytednsdoc.com", shadowrocket_china),
        ("DOMAIN-SUFFIX,zjcdn.com", shadowrocket_china),
        ("DOMAIN-SUFFIX,biliimg.com", shadowrocket_china),
        ("DOMAIN-SUFFIX,acgvideo.com", shadowrocket_china),
        ("DOMAIN-SUFFIX,taobaocdn.com", shadowrocket_china),
        ("DOMAIN-SUFFIX,jcloudcs.com", shadowrocket_china),
        ("DOMAIN-SUFFIX,servicewechat.com", shadowrocket_china),
    ]:
        if needle not in content:
            print(f"FAIL shadowrocket rule list missing {needle}", file=sys.stderr)
            return 1
        print(f"OK   shadowrocket list contains {needle}")

    shadowrocket_conf = module.build_shadowrocket_conf("test")
    for needle in [
        "[Rule]",
        "DOMAIN-SUFFIX,pinimg.com,PROXY",
        "DOMAIN-SUFFIX,pinterest.com,PROXY",
        "DOMAIN-SUFFIX,xhscdn.net,DIRECT",
        "DOMAIN-SUFFIX,weixin.com,DIRECT",
        "DOMAIN-SUFFIX,tencent-cloud.net,DIRECT",
        "DOMAIN-SUFFIX,qcloudimg.com,DIRECT",
        "DOMAIN-SUFFIX,byteimg.com,DIRECT",
        "DOMAIN-SUFFIX,bytednsdoc.com,DIRECT",
        "DOMAIN-SUFFIX,zjcdn.com,DIRECT",
        "DOMAIN-SUFFIX,biliimg.com,DIRECT",
        "DOMAIN-SUFFIX,acgvideo.com,DIRECT",
        "DOMAIN-SUFFIX,taobaocdn.com,DIRECT",
        "DOMAIN-SUFFIX,jcloudcs.com,DIRECT",
        "DOMAIN-SUFFIX,servicewechat.com,DIRECT",
        "FINAL,DIRECT",
    ]:
        if needle not in shadowrocket_conf:
            print(f"FAIL shadowrocket config missing {needle}", file=sys.stderr)
            return 1
        print(f"OK   shadowrocket config contains {needle}")

    print("\nroute regressions passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
