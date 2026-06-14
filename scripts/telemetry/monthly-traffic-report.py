#!/usr/bin/env python3
"""Generate monthly traffic reports from the local Mihomo telemetry DB."""

from __future__ import annotations

import argparse
import csv
import json
import sqlite3
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_DB = (
    Path.home()
    / "Library"
    / "Application Support"
    / "ace-vpn"
    / "mihomo-traffic.sqlite3"
)


def month_window(month: str | None) -> tuple[int, int, str]:
    if not month:
        month = datetime.now().strftime("%Y-%m")
    start_dt = datetime.strptime(month + "-01", "%Y-%m-%d").replace(tzinfo=timezone.utc)
    if start_dt.month == 12:
        end_dt = start_dt.replace(year=start_dt.year + 1, month=1)
    else:
        end_dt = start_dt.replace(month=start_dt.month + 1)
    return int(start_dt.timestamp()), int(end_dt.timestamp()), month


def human_bytes(n: int) -> str:
    value = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if value < 1024 or unit == "TB":
            return f"{value:.1f} {unit}" if unit != "B" else f"{int(value)} B"
        value /= 1024
    return f"{n} B"


def human_duration(seconds: int) -> str:
    seconds = max(0, int(seconds))
    hours, rem = divmod(seconds, 3600)
    minutes, secs = divmod(rem, 60)
    if hours:
        return f"{hours}h {minutes}m"
    if minutes:
        return f"{minutes}m {secs}s"
    return f"{secs}s"


def query_groups(conn: sqlite3.Connection, start: int, end: int, expr: str, limit: int) -> list[dict[str, Any]]:
    rows = conn.execute(
        f"""
        SELECT
          {expr} AS key,
          COUNT(DISTINCT connection_id) AS connections,
          SUM(upload_delta) AS upload,
          SUM(download_delta) AS download,
          SUM(upload_delta + download_delta) AS total,
          SUM(duration_delta) AS duration
        FROM traffic_samples
        WHERE ts >= ? AND ts < ?
        GROUP BY key
        ORDER BY total DESC, duration DESC
        LIMIT ?
        """,
        (start, end, limit),
    ).fetchall()
    return [
        {
            "key": row[0] or "(unknown)",
            "connections": int(row[1] or 0),
            "upload": int(row[2] or 0),
            "download": int(row[3] or 0),
            "total": int(row[4] or 0),
            "duration": int(row[5] or 0),
        }
        for row in rows
    ]


def detailed_rows(conn: sqlite3.Connection, start: int, end: int) -> list[dict[str, Any]]:
    rows = conn.execute(
        """
        SELECT
          COALESCE(NULLIF(source_ip, ''), '(unknown)') AS source_ip,
          COALESCE(NULLIF(process, ''), '(unknown)') AS process,
          COALESCE(NULLIF(host, ''), COALESCE(NULLIF(dst_ip, ''), '(unknown)')) AS host,
          COALESCE(NULLIF(rule, ''), '(unknown)') AS rule,
          COALESCE(NULLIF(rule_payload, ''), '') AS rule_payload,
          COALESCE(NULLIF(chains, ''), '(unknown)') AS chains,
          is_ai,
          COUNT(DISTINCT connection_id) AS connections,
          MIN(ts) AS first_seen,
          MAX(ts) AS last_seen,
          SUM(upload_delta) AS upload,
          SUM(download_delta) AS download,
          SUM(upload_delta + download_delta) AS total,
          SUM(duration_delta) AS duration
        FROM traffic_samples
        WHERE ts >= ? AND ts < ?
        GROUP BY source_ip, process, host, rule, rule_payload, chains, is_ai
        ORDER BY total DESC, duration DESC
        """,
        (start, end),
    ).fetchall()
    keys = [
        "source_ip",
        "process",
        "host",
        "rule",
        "rule_payload",
        "chains",
        "is_ai",
        "connections",
        "first_seen",
        "last_seen",
        "upload",
        "download",
        "total",
        "duration",
    ]
    out = []
    for row in rows:
        item = dict(zip(keys, row))
        for key in ("is_ai", "connections", "first_seen", "last_seen", "upload", "download", "total", "duration"):
            item[key] = int(item[key] or 0)
        out.append(item)
    return out


def build_report(conn: sqlite3.Connection, start: int, end: int, limit: int) -> dict[str, Any]:
    total = conn.execute(
        """
        SELECT
          COUNT(DISTINCT connection_id),
          SUM(upload_delta),
          SUM(download_delta),
          SUM(upload_delta + download_delta),
          SUM(duration_delta)
        FROM traffic_samples
        WHERE ts >= ? AND ts < ?
        """,
        (start, end),
    ).fetchone()
    return {
        "generated_at": int(time.time()),
        "summary": {
            "connections": int(total[0] or 0),
            "upload": int(total[1] or 0),
            "download": int(total[2] or 0),
            "total": int(total[3] or 0),
            "duration": int(total[4] or 0),
        },
        "ai_vs_non_ai": query_groups(
            conn,
            start,
            end,
            "CASE is_ai WHEN 1 THEN 'AI' ELSE 'non-AI' END",
            limit,
        ),
        "by_app": query_groups(conn, start, end, "COALESCE(NULLIF(process, ''), '(unknown)')", limit),
        "by_source_ip": query_groups(conn, start, end, "COALESCE(NULLIF(source_ip, ''), '(unknown)')", limit),
        "by_chain": query_groups(conn, start, end, "COALESCE(NULLIF(chains, ''), '(unknown)')", limit),
        "top_hosts": query_groups(
            conn,
            start,
            end,
            "COALESCE(NULLIF(host, ''), COALESCE(NULLIF(dst_ip, ''), '(unknown)'))",
            limit,
        ),
    }


def print_table(title: str, rows: list[dict[str, Any]]) -> None:
    print(f"\n{title}")
    print("-" * len(title))
    if not rows:
        print("(no data)")
        return
    print(f"{'key':42} {'total':>12} {'up':>12} {'down':>12} {'time':>10} {'conn':>6}")
    for row in rows:
        key = str(row["key"])[:42]
        print(
            f"{key:42} {human_bytes(row['total']):>12} "
            f"{human_bytes(row['upload']):>12} {human_bytes(row['download']):>12} "
            f"{human_duration(row['duration']):>10} {row['connections']:>6}"
        )


def write_details_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()) if rows else [])
        if rows:
            writer.writeheader()
            writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate monthly ace-vpn traffic reports.")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--month", help="YYYY-MM, default current UTC month")
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--details-csv", type=Path)
    args = parser.parse_args()

    if not args.db.exists():
        print(f"ERROR: telemetry DB not found: {args.db}", flush=True)
        return 2

    start, end, month = month_window(args.month)
    conn = sqlite3.connect(args.db)
    report = build_report(conn, start, end, args.limit)
    details = detailed_rows(conn, start, end)
    report["month"] = month
    report["detail_groups"] = len(details)

    if args.details_csv:
        write_details_csv(args.details_csv, details)
        report["details_csv"] = str(args.details_csv)

    if args.format == "json":
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0

    summary = report["summary"]
    print(f"ace-vpn monthly traffic report: {month}")
    print(f"db: {args.db}")
    print(
        "total: "
        f"{human_bytes(summary['total'])} "
        f"(up {human_bytes(summary['upload'])}, down {human_bytes(summary['download'])}) · "
        f"observed time {human_duration(summary['duration'])} · "
        f"connections {summary['connections']} · detail groups {len(details)}"
    )
    if args.details_csv:
        print(f"details_csv: {args.details_csv}")

    print_table("AI vs non-AI", report["ai_vs_non_ai"])
    print_table("By app/process", report["by_app"])
    print_table("By source IP", report["by_source_ip"])
    print_table("By route chain", report["by_chain"])
    print_table("Top hosts", report["top_hosts"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
