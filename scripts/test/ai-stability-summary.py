#!/usr/bin/env python3
"""Summarize ace-vpn AI stability probe TSV logs.

Input rows are produced by scripts/test/ai-stability-probe.sh:
  ts node ip round service url method curl_exit http_code expected_ok slow block_hint total connect tls ttfb remote_ip size
"""

from __future__ import annotations

import argparse
import datetime as dt
import statistics
from collections import defaultdict
from pathlib import Path

DEFAULT_LOG = Path.home() / "Library" / "Logs" / "ace-vpn" / "ai-stability-probe.log"


def parse_float(value: str) -> float | None:
    if value in {"", "na", "-"}:
        return None
    try:
        return float(value)
    except ValueError:
        return None


def parse_ts(value: str) -> dt.datetime | None:
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M:%S %z"):
        try:
            return dt.datetime.strptime(value, fmt).replace(tzinfo=None)
        except ValueError:
            pass
    return None


def percentile(values: list[float], pct: float) -> float | None:
    if not values:
        return None
    values = sorted(values)
    if len(values) == 1:
        return values[0]
    idx = (len(values) - 1) * pct
    low = int(idx)
    high = min(low + 1, len(values) - 1)
    weight = idx - low
    return values[low] * (1 - weight) + values[high] * weight


def fmt_sec(value: float | None) -> str:
    if value is None:
        return "-"
    return f"{value * 1000:.0f}ms" if value < 1 else f"{value:.2f}s"


def fmt_pct(value: float | None) -> str:
    if value is None:
        return "-"
    return f"{value * 100:.1f}%"


def is_data_line(line: str) -> bool:
    return bool(line and "\t" in line and not line.startswith("#") and not line.startswith("========") and not line.startswith("----"))


def read_rows(path: Path, since: dt.datetime | None) -> list[dict[str, object]]:
    if not path.exists():
        raise SystemExit(f"日志不存在：{path}")
    rows: list[dict[str, object]] = []
    for raw in path.read_text().splitlines():
        line = raw.rstrip("\n")
        if not is_data_line(line):
            continue
        parts = line.split("\t")
        if len(parts) != 18:
            continue
        (
            ts_s,
            node,
            ip,
            round_s,
            service,
            url,
            method,
            curl_exit,
            code,
            expected_ok,
            slow,
            block_hint,
            total,
            connect,
            tls,
            ttfb,
            remote_ip,
            size,
        ) = parts
        ts = parse_ts(ts_s)
        if ts is None:
            continue
        if since and ts < since:
            continue
        rows.append(
            {
                "ts": ts,
                "node": node,
                "ip": ip,
                "round": int(round_s),
                "service": service,
                "url": url,
                "method": method,
                "curl_exit": int(curl_exit),
                "code": code,
                "expected_ok": expected_ok == "1",
                "slow": slow == "1",
                "block_hint": block_hint,
                "total": parse_float(total),
                "connect": parse_float(connect),
                "tls": parse_float(tls),
                "ttfb": parse_float(ttfb),
                "remote_ip": remote_ip,
                "size": int(size) if size.isdigit() else 0,
            }
        )
    return rows


def is_bad(row: dict[str, object]) -> bool:
    return bool(row["curl_exit"] != 0 or not row["expected_ok"] or row["slow"] or row["block_hint"] != "-")


def max_consecutive_bad(rows: list[dict[str, object]]) -> int:
    max_seen = 0
    current = 0
    for row in sorted(rows, key=lambda r: (int(r["round"]), str(r["service"]))):
        if is_bad(row):
            current += 1
            max_seen = max(max_seen, current)
        else:
            current = 0
    return max_seen


def score_node(rows: list[dict[str, object]]) -> float:
    """Lower is better. Heavily weight failures and block hints over latency."""
    n = len(rows) or 1
    failures = sum(1 for r in rows if r["curl_exit"] != 0 or not r["expected_ok"])
    blocks = sum(1 for r in rows if r["block_hint"] != "-")
    slow = sum(1 for r in rows if r["slow"])
    totals = [r["total"] for r in rows if isinstance(r["total"], float) and r["curl_exit"] == 0]
    p95 = percentile(totals, 0.95) or 0
    return failures / n * 100 + blocks / n * 100 + slow / n * 20 + p95


def summarize(rows: list[dict[str, object]]) -> None:
    print("# ai_stability_summary")
    if not rows:
        print("no records")
        return

    print(f"range: {min(r['ts'] for r in rows)} -> {max(r['ts'] for r in rows)}")
    print(f"nodes: {', '.join(sorted({str(r['node']) for r in rows}))}")
    print(f"services: {len({str(r['service']) for r in rows})}")
    print(f"records: {len(rows)}")
    print()

    by_node: dict[str, list[dict[str, object]]] = defaultdict(list)
    by_pair: dict[tuple[str, str], list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        by_node[str(row["node"])].append(row)
        by_pair[(str(row["node"]), str(row["service"]))].append(row)

    print("# node_decision")
    print("node\trecords\tbad_rate\tfail_or_unexpected_rate\tblock_rate\tslow_rate\tmedian\tp95\tp99\tmax_consecutive_bad\tstability_score")
    node_scores: dict[str, float] = {}
    for node, items in sorted(by_node.items()):
        totals = [r["total"] for r in items if isinstance(r["total"], float) and r["curl_exit"] == 0]
        fail = [r for r in items if r["curl_exit"] != 0 or not r["expected_ok"]]
        block = [r for r in items if r["block_hint"] != "-"]
        slow = [r for r in items if r["slow"]]
        bad = [r for r in items if is_bad(r)]
        score = score_node(items)
        node_scores[node] = score
        print(
            "\t".join(
                [
                    node,
                    str(len(items)),
                    fmt_pct(len(bad) / len(items)),
                    fmt_pct(len(fail) / len(items)),
                    fmt_pct(len(block) / len(items)),
                    fmt_pct(len(slow) / len(items)),
                    fmt_sec(statistics.median(totals) if totals else None),
                    fmt_sec(percentile(totals, 0.95)),
                    fmt_sec(percentile(totals, 0.99)),
                    str(max_consecutive_bad(items)),
                    f"{score:.2f}",
                ]
            )
        )

    print()
    if node_scores:
        winner = sorted(node_scores.items(), key=lambda kv: kv[1])[0][0]
        print(f"recommendation: {winner} (lowest stability_score)")
        print()

    print("# service_detail")
    print("node\tservice\trecords\tbad\tfail_or_unexpected\tblock_hints\tslow\tmedian\tp95\tworst\tcodes\thints")
    for (node, service), items in sorted(by_pair.items()):
        totals = [r["total"] for r in items if isinstance(r["total"], float) and r["curl_exit"] == 0]
        codes: dict[str, int] = defaultdict(int)
        hints: dict[str, int] = defaultdict(int)
        for row in items:
            codes[str(row["code"])] += 1
            if row["block_hint"] != "-":
                hints[str(row["block_hint"])] += 1
        print(
            "\t".join(
                [
                    node,
                    service,
                    str(len(items)),
                    str(sum(1 for r in items if is_bad(r))),
                    str(sum(1 for r in items if r["curl_exit"] != 0 or not r["expected_ok"])),
                    str(sum(1 for r in items if r["block_hint"] != "-")),
                    str(sum(1 for r in items if r["slow"])),
                    fmt_sec(statistics.median(totals) if totals else None),
                    fmt_sec(percentile(totals, 0.95)),
                    fmt_sec(max(totals) if totals else None),
                    ",".join(f"{k}:{v}" for k, v in sorted(codes.items())),
                    ",".join(f"{k}:{v}" for k, v in sorted(hints.items())) or "-",
                ]
            )
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, default=DEFAULT_LOG)
    parser.add_argument("--since-hours", type=float, default=None)
    parser.add_argument("--slow-sec", type=float, default=5.0)
    args = parser.parse_args()

    since = None
    if args.since_hours is not None:
        since = dt.datetime.now() - dt.timedelta(hours=args.since_hours)
    rows = read_rows(args.log, since)
    summarize(rows)


if __name__ == "__main__":
    main()
