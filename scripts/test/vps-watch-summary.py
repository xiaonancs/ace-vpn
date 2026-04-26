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
SLOW_SECONDS = 2.0
LATENCY_BUCKETS = (
    ("lt_100ms", 0.1),
    ("100_300ms", 0.3),
    ("300_800ms", 0.8),
    ("800ms_2s", 2.0),
    ("ge_2s", None),
)


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


def fmt_pct(value: float | None) -> str:
    if value is None:
        return "-"
    return f"{value * 100:.1f}%"


def fmt_ratio(value: float | None) -> str:
    if value is None:
        return "-"
    return f"{value:.1f}x"


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


def compare_by_url(summary: list[dict[str, object]]) -> list[dict[str, object]]:
    by_url: dict[str, list[dict[str, object]]] = defaultdict(list)
    for s in summary:
        by_url[str(s["url"])].append(s)

    comparisons: list[dict[str, object]] = []
    for url, items in sorted(by_url.items()):
        valid = [i for i in items if isinstance(i["median"], float)]
        if not valid:
            comparisons.append(
                {
                    "url": url,
                    "winner": "-",
                    "best_median": None,
                    "second_median": None,
                    "delta": None,
                    "ok_winner": "-",
                    "ok_winner_rate": None,
                }
            )
            continue
        valid.sort(key=lambda i: (float(i["median"]), -float(i["ok_rate"])))
        best = valid[0]
        second = valid[1] if len(valid) > 1 else None
        best_ok_rate = max(float(i["ok_rate"]) for i in items)
        ok_best_nodes = sorted(str(i["node"]) for i in items if float(i["ok_rate"]) == best_ok_rate)
        ok_winner = ok_best_nodes[0] if len(ok_best_nodes) == 1 else "tie:" + ",".join(ok_best_nodes)
        delta = None
        if second and isinstance(second["median"], float):
            delta = float(second["median"]) - float(best["median"])
        comparisons.append(
            {
                "url": url,
                "winner": str(best["node"]),
                "best_median": best["median"],
                "second_median": second["median"] if second else None,
                "delta": delta,
                "ok_winner": ok_winner,
                "ok_winner_rate": best_ok_rate,
            }
        )
    return comparisons


def latency_bucket_name(value: float) -> str:
    floor = 0.0
    for name, upper in LATENCY_BUCKETS:
        if upper is None or floor <= value < upper:
            return name
        floor = upper
    return LATENCY_BUCKETS[-1][0]


def node_overview(rows: list[dict[str, object]], comparisons: list[dict[str, object]]) -> list[dict[str, object]]:
    nodes = sorted({str(r["node"]) for r in rows})
    wins = {node: 0 for node in nodes}
    losses = {node: 0 for node in nodes}
    no_winner = 0

    for cmp in comparisons:
        winner = str(cmp["winner"])
        if winner == "-":
            no_winner += 1
            continue
        for node in nodes:
            if node == winner:
                wins[node] += 1
            else:
                losses[node] += 1

    grouped: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        grouped[str(row["node"])].append(row)

    overview: list[dict[str, object]] = []
    for node in nodes:
        items = grouped[node]
        totals = [r["total"] for r in items if isinstance(r["total"], float) and str(r["code"]) != "000"]
        timeouts = sum(1 for r in items if str(r["code"]) == "000")
        slow = sum(1 for total in totals if total >= SLOW_SECONDS)
        median = statistics.median(totals) if totals else None
        p99 = percentile(totals, 0.99)
        p99_median_ratio = p99 / median if isinstance(p99, float) and isinstance(median, float) and median > 0 else None
        overview.append(
            {
                "node": node,
                "records": len(items),
                "ok": len(totals),
                "ok_rate": len(totals) / len(items) if items else 0,
                "timeouts": timeouts,
                "timeout_rate": timeouts / len(items) if items else 0,
                "slow_ge_2s": slow,
                "slow_rate": slow / len(items) if items else 0,
                "pain_events": timeouts + slow,
                "pain_rate": (timeouts + slow) / len(items) if items else 0,
                "avg": statistics.mean(totals) if totals else None,
                "median": median,
                "p90": percentile(totals, 0.90),
                "p95": percentile(totals, 0.95),
                "p99": p99,
                "p99_median_ratio": p99_median_ratio,
                "best": min(totals) if totals else None,
                "worst": max(totals) if totals else None,
                "wins": wins[node],
                "losses": losses[node],
                "no_winner": no_winner,
            }
        )
    return overview


def node_latency_distribution(rows: list[dict[str, object]]) -> list[dict[str, object]]:
    grouped: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        grouped[str(row["node"])].append(row)

    distributions: list[dict[str, object]] = []
    for node, items in sorted(grouped.items()):
        counts = {name: 0 for name, _ in LATENCY_BUCKETS}
        timeouts = 0
        total_ok = 0
        for row in items:
            total = row["total"]
            if str(row["code"]) == "000" or not isinstance(total, float):
                timeouts += 1
                continue
            total_ok += 1
            counts[latency_bucket_name(total)] += 1
        distributions.append(
            {
                "node": node,
                "ok": total_ok,
                "timeouts": timeouts,
                **counts,
            }
        )
    return distributions


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


def print_node_overview(overview: list[dict[str, object]]) -> None:
    print("# node_overview")
    print(
        "node\trecords\tok_rate\ttimeouts\ttimeout_rate\tslow_ge_2s\tpain_rate\tavg\tmedian\tp90\tp95\tp99\tp99/median\tbest\tworst\twin_loss"
    )
    for item in overview:
        print(
            "\t".join(
                [
                    str(item["node"]),
                    str(item["records"]),
                    fmt_pct(float(item["ok_rate"])),
                    str(item["timeouts"]),
                    fmt_pct(float(item["timeout_rate"])),
                    str(item["slow_ge_2s"]),
                    fmt_pct(float(item["pain_rate"])),
                    fmt_sec(item["avg"] if isinstance(item["avg"], float) else None),
                    fmt_sec(item["median"] if isinstance(item["median"], float) else None),
                    fmt_sec(item["p90"] if isinstance(item["p90"], float) else None),
                    fmt_sec(item["p95"] if isinstance(item["p95"], float) else None),
                    fmt_sec(item["p99"] if isinstance(item["p99"], float) else None),
                    fmt_ratio(item["p99_median_ratio"] if isinstance(item["p99_median_ratio"], float) else None),
                    fmt_sec(item["best"] if isinstance(item["best"], float) else None),
                    fmt_sec(item["worst"] if isinstance(item["worst"], float) else None),
                    f"{item['wins']}:{item['losses']}",
                ]
            )
        )
    print()


def print_latency_distribution(distributions: list[dict[str, object]]) -> None:
    bucket_names = [name for name, _ in LATENCY_BUCKETS]
    print("# node_latency_distribution")
    print("\t".join(["node", "ok", "timeouts", *bucket_names]))
    for item in distributions:
        total_ok = int(item["ok"])
        values = []
        for name in bucket_names:
            count = int(item[name])
            pct = count / total_ok if total_ok else 0
            values.append(f"{count} ({fmt_pct(pct)})")
        print(
            "\t".join(
                [
                    str(item["node"]),
                    str(item["ok"]),
                    str(item["timeouts"]),
                    *values,
                ]
            )
        )
    print()


def print_url_summary(summary: list[dict[str, object]]) -> None:
    print("# url_summary")
    print("node\turl\tcount\tok_rate\ttimeouts\tmedian\tp95\tavg\tbest\tworst\tcodes")
    for s in summary:
        print(
            "\t".join(
                [
                    str(s["node"]),
                    str(s["url"]),
                    str(s["count"]),
                    fmt_pct(float(s["ok_rate"])),
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
    print()


def print_comparison(comparisons: list[dict[str, object]]) -> None:
    print("# comparison_by_url")
    print("url\twinner_by_median\tbest_median\tsecond_median\tdelta\twinner_by_ok_rate")
    for cmp in comparisons:
        ok_rate = cmp["ok_winner_rate"]
        ok_winner = str(cmp["ok_winner"])
        ok_text = "-" if ok_rate is None else f"{ok_winner} ({fmt_pct(float(ok_rate))})"
        print(
            "\t".join(
                [
                    str(cmp["url"]),
                    str(cmp["winner"]),
                    fmt_sec(cmp["best_median"] if isinstance(cmp["best_median"], float) else None),
                    fmt_sec(cmp["second_median"] if isinstance(cmp["second_median"], float) else None),
                    fmt_sec(cmp["delta"] if isinstance(cmp["delta"], float) else None),
                    ok_text,
                ]
            )
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarize ace-vpn VPS watch logs.")
    parser.add_argument("--log", default=os.environ.get("VPS_WATCH_LOG_FILE", str(DEFAULT_LOG)))
    parser.add_argument("--days", type=int, default=30, help="Only include records from the last N days.")
    parser.add_argument("--all", action="store_true", help="Include all records, ignoring --days.")
    parser.add_argument("--records", action="store_true", help="Print all matching raw records before summaries.")
    args = parser.parse_args()

    since = None if args.all else dt.datetime.now() - dt.timedelta(days=args.days)
    rows = read_rows(Path(args.log).expanduser(), since)
    if args.records:
        print_records(rows)
    summary = summarize(rows)
    comparisons = compare_by_url(summary)
    print_summary(rows, summary)
    print_node_overview(node_overview(rows, comparisons))
    print_latency_distribution(node_latency_distribution(rows))
    print_url_summary(summary)
    print_comparison(comparisons)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
