#!/usr/bin/env python3
"""Summarize ace-vpn vps-watch TSV logs.

Input rows are produced by scripts/test/vps-watch-urls.sh:
  ts node ip http_code total tcp ssl remote_ip url
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import statistics
import sys
from collections import defaultdict
from pathlib import Path


DEFAULT_LOG = Path.home() / "Library" / "Logs" / "ace-vpn" / "vps-watch.log"


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
    if value < 1:
        return f"{value * 1000:.0f}ms"
    return f"{value:.2f}s"


def read_rows(path: Path, since: dt.datetime | None) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    if not path.exists():
        raise SystemExit(f"日志不存在：{path}")

    with path.open() as f:
        for raw in f:
            line = raw.rstrip("\n")
            if not line or line.startswith("========") or line.startswith("----") or "\t" not in line:
                continue
            parts = line.split("\t")
            if len(parts) != 9:
                continue
            ts_s, node, ip, code, total, tcp, ssl, remote_ip, url = parts
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
                    "code": code,
                    "total": parse_float(total),
                    "tcp": parse_float(tcp),
                    "ssl": parse_float(ssl),
                    "remote_ip": remote_ip,
                    "url": url,
                }
            )
    return rows


def summarize(rows: list[dict[str, object]]) -> list[dict[str, object]]:
    grouped: dict[tuple[str, str], list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        grouped[(str(row["node"]), str(row["url"]))].append(row)

    summary: list[dict[str, object]] = []
    for (node, url), items in sorted(grouped.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        totals = [r["total"] for r in items if isinstance(r["total"], float) and str(r["code"]) != "000"]
        codes = [str(r["code"]) for r in items]
        ok = sum(1 for c in codes if c != "000")
        summary.append(
            {
                "node": node,
                "url": url,
                "count": len(items),
                "ok": ok,
                "ok_rate": ok / len(items) if items else 0,
                "timeouts": len(items) - ok,
                "median": statistics.median(totals) if totals else None,
                "p95": percentile(totals, 0.95),
                "avg": statistics.mean(totals) if totals else None,
                "best": min(totals) if totals else None,
                "worst": max(totals) if totals else None,
                "codes": ",".join(f"{c}:{codes.count(c)}" for c in sorted(set(codes))),
            }
        )
    return summary


def print_records(rows: list[dict[str, object]]) -> None:
    print("# records")
    print("ts\tnode\tip\tcode\ttotal\ttcp\tssl\tremote_ip\turl")
    for r in rows:
        print(
            "\t".join(
                [
                    r["ts"].strftime("%Y-%m-%d %H:%M:%S"),  # type: ignore[union-attr]
                    str(r["node"]),
                    str(r["ip"]),
                    str(r["code"]),
                    fmt_sec(r["total"] if isinstance(r["total"], float) else None),
                    fmt_sec(r["tcp"] if isinstance(r["tcp"], float) else None),
                    fmt_sec(r["ssl"] if isinstance(r["ssl"], float) else None),
                    str(r["remote_ip"]),
                    str(r["url"]),
                ]
            )
        )
    print()


def print_summary(rows: list[dict[str, object]], summary: list[dict[str, object]]) -> None:
    if not rows:
        print("没有可汇总记录。")
        return

    first = min(r["ts"] for r in rows)  # type: ignore[type-var]
    last = max(r["ts"] for r in rows)  # type: ignore[type-var]
    nodes = sorted({str(r["node"]) for r in rows})
    urls = sorted({str(r["url"]) for r in rows})
    print("# summary")
    print(f"range: {first}  ->  {last}")
    print(f"nodes: {', '.join(nodes)}")
    print(f"urls: {len(urls)}")
    print(f"records: {len(rows)}")
    print()

    print("node\turl\tcount\tok_rate\ttimeouts\tmedian\tp95\tavg\tbest\tworst\tcodes")
    for s in summary:
        print(
            "\t".join(
                [
                    str(s["node"]),
                    str(s["url"]),
                    str(s["count"]),
                    f"{float(s['ok_rate']) * 100:.1f}%",
                    str(s["timeouts"]),
                    fmt_sec(s["median"] if isinstance(s["median"], float) else None),
                    fmt_sec(s["p95"] if isinstance(s["p95"], float) else None),
                    fmt_sec(s["avg"] if isinstance(s["avg"], float) else None),
                    fmt_sec(s["best"] if isinstance(s["best"], float) else None),
                    fmt_sec(s["worst"] if isinstance(s["worst"], float) else None),
                    str(s["codes"]),
                ]
            )
        )


def print_comparison(summary: list[dict[str, object]]) -> None:
    by_url: dict[str, list[dict[str, object]]] = defaultdict(list)
    for s in summary:
        by_url[str(s["url"])].append(s)

    print()
    print("# comparison_by_url")
    print("url\twinner_by_median\tbest_median\tsecond_median\tdelta\twinner_by_ok_rate")
    for url, items in sorted(by_url.items()):
        valid = [i for i in items if isinstance(i["median"], float)]
        if not valid:
            print(f"{url}\t-\t-\t-\t-\t-")
            continue
        valid.sort(key=lambda i: (float(i["median"]), -float(i["ok_rate"])))
        best = valid[0]
        second = valid[1] if len(valid) > 1 else None
        ok_best = max(items, key=lambda i: float(i["ok_rate"]))
        delta = None
        if second and isinstance(second["median"], float):
            delta = float(second["median"]) - float(best["median"])
        print(
            "\t".join(
                [
                    url,
                    str(best["node"]),
                    fmt_sec(best["median"] if isinstance(best["median"], float) else None),
                    fmt_sec(second["median"] if second and isinstance(second["median"], float) else None),
                    fmt_sec(delta),
                    f"{ok_best['node']} ({float(ok_best['ok_rate']) * 100:.1f}%)",
                ]
            )
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarize ace-vpn VPS watch logs.")
    parser.add_argument("--log", default=os.environ.get("VPS_WATCH_LOG_FILE", str(DEFAULT_LOG)))
    parser.add_argument("--days", type=int, default=20, help="Only include records from the last N days.")
    parser.add_argument("--all", action="store_true", help="Include all records, ignoring --days.")
    parser.add_argument("--records", action="store_true", help="Print all matching raw records before summaries.")
    args = parser.parse_args()

    since = None if args.all else dt.datetime.now() - dt.timedelta(days=args.days)
    rows = read_rows(Path(args.log).expanduser(), since)
    if args.records:
        print_records(rows)
    summary = summarize(rows)
    print_summary(rows, summary)
    print_comparison(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
