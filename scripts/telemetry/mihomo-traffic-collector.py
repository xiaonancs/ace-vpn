#!/usr/bin/env python3
"""Collect local Mihomo connection telemetry into SQLite.

This collector intentionally stores host-level metadata, not full HTTPS URLs.
It reads the local Mihomo external-controller API and records byte deltas per
connection, grouped later by source IP, app/process, host, rule, chain, and AI
classification.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


ROOT_DIR = Path(__file__).resolve().parents[2]
DEFAULT_CONTROLLER = os.environ.get("MIHOMO_CONTROLLER", "http://127.0.0.1:9090")
DEFAULT_SECRET = os.environ.get("MIHOMO_SECRET", "")
DEFAULT_DB = (
    Path.home()
    / "Library"
    / "Application Support"
    / "ace-vpn"
    / "mihomo-traffic.sqlite3"
)


def load_ai_suffixes() -> set[str]:
    path = ROOT_DIR / "scripts" / "server" / "sub-converter.py"
    spec = importlib.util.spec_from_file_location("_ace_sub_converter", path)
    if not spec or not spec.loader:
        return set()
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    suffixes = set()
    for name in ("AI_STREAMING_DOMAINS", "AI_DOMAINS"):
        for item in getattr(module, name, []) or []:
            if isinstance(item, str) and item.strip():
                suffixes.add(item.strip().lower().rstrip("."))
    return suffixes


def ensure_db(db: Path) -> sqlite3.Connection:
    db.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA busy_timeout=3000")
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS connection_totals (
          id TEXT PRIMARY KEY,
          first_seen INTEGER NOT NULL,
          last_seen INTEGER NOT NULL,
          host TEXT,
          dst_ip TEXT,
          dst_port INTEGER,
          network TEXT,
          source_ip TEXT,
          source_port INTEGER,
          process TEXT,
          process_path TEXT,
          rule TEXT,
          rule_payload TEXT,
          chains TEXT,
          is_ai INTEGER NOT NULL DEFAULT 0,
          upload_last INTEGER NOT NULL DEFAULT 0,
          download_last INTEGER NOT NULL DEFAULT 0,
          upload_total INTEGER NOT NULL DEFAULT 0,
          download_total INTEGER NOT NULL DEFAULT 0
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS traffic_samples (
          ts INTEGER NOT NULL,
          connection_id TEXT NOT NULL,
          host TEXT,
          dst_ip TEXT,
          dst_port INTEGER,
          source_ip TEXT,
          process TEXT,
          rule TEXT,
          rule_payload TEXT,
          chains TEXT,
          is_ai INTEGER NOT NULL DEFAULT 0,
          upload_delta INTEGER NOT NULL DEFAULT 0,
          download_delta INTEGER NOT NULL DEFAULT 0,
          duration_delta INTEGER NOT NULL DEFAULT 0
        )
        """
    )
    conn.execute("CREATE INDEX IF NOT EXISTS idx_samples_ts ON traffic_samples(ts)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_samples_host ON traffic_samples(host)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_samples_process ON traffic_samples(process)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_samples_ai ON traffic_samples(is_ai)")
    return conn


def request_connections(controller: str, secret: str, timeout: float) -> list[dict[str, Any]]:
    url = controller.rstrip("/") + "/connections"
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    if secret:
        req.add_header("Authorization", f"Bearer {secret}")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = json.loads(resp.read().decode("utf-8", errors="replace"))
    conns = data.get("connections", [])
    return conns if isinstance(conns, list) else []


def as_int(value: Any) -> int | None:
    if value is None or value == "":
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def basename(path: str) -> str:
    if not path:
        return ""
    return os.path.basename(path.replace("\\", "/"))


def suffix_match(host: str, suffixes: set[str]) -> bool:
    host = host.lower().rstrip(".")
    return any(host == sfx or host.endswith("." + sfx) for sfx in suffixes)


def classify_ai(host: str, rule: str, rule_payload: str, chains: list[str], suffixes: set[str]) -> int:
    text = " ".join([rule, rule_payload, *chains]).lower()
    if "ai" in text or "chatgpt" in text or "openai" in text or "claude" in text:
        return 1
    return 1 if host and suffix_match(host, suffixes) else 0


def normalize_connection(raw: dict[str, Any], ai_suffixes: set[str], include_process_path: bool) -> dict[str, Any]:
    meta = raw.get("metadata") or {}
    chains = raw.get("chains") or []
    if not isinstance(chains, list):
        chains = []

    host = str(meta.get("host") or "").strip().lower().rstrip(".")
    dst_ip = str(meta.get("destinationIP") or "").strip()
    dst_port = as_int(meta.get("destinationPort"))
    source_ip = str(meta.get("sourceIP") or "").strip()
    source_port = as_int(meta.get("sourcePort"))
    network = str(meta.get("network") or "").strip()
    process_path = str(meta.get("processPath") or "").strip()
    process = str(meta.get("process") or "").strip() or basename(process_path)
    rule = str(raw.get("rule") or "").strip()
    rule_payload = str(raw.get("rulePayload") or "").strip()
    chain_text = " > ".join(str(c) for c in chains if c)

    conn_id = str(raw.get("id") or "").strip()
    if not conn_id:
        material = json.dumps(
            [source_ip, source_port, host, dst_ip, dst_port, network, process, rule, chain_text],
            ensure_ascii=False,
            sort_keys=True,
        )
        conn_id = hashlib.sha1(material.encode("utf-8")).hexdigest()

    return {
        "id": conn_id,
        "host": host,
        "dst_ip": dst_ip,
        "dst_port": dst_port,
        "network": network,
        "source_ip": source_ip,
        "source_port": source_port,
        "process": process,
        "process_path": process_path if include_process_path else "",
        "rule": rule,
        "rule_payload": rule_payload,
        "chains": chain_text,
        "is_ai": classify_ai(host, rule, rule_payload, [str(c) for c in chains], ai_suffixes),
        "upload": max(0, int(raw.get("upload") or 0)),
        "download": max(0, int(raw.get("download") or 0)),
    }


def collect_once(
    conn: sqlite3.Connection,
    controller: str,
    secret: str,
    timeout: float,
    ai_suffixes: set[str],
    include_process_path: bool,
) -> tuple[int, int, int]:
    now = int(time.time())
    raw_connections = request_connections(controller, secret, timeout)
    upload_delta_total = 0
    download_delta_total = 0

    with conn:
        for raw in raw_connections:
            if not isinstance(raw, dict):
                continue
            item = normalize_connection(raw, ai_suffixes, include_process_path)
            prev = conn.execute(
                "SELECT first_seen, last_seen, upload_last, download_last FROM connection_totals WHERE id = ?",
                (item["id"],),
            ).fetchone()
            if prev:
                first_seen, last_seen, prev_upload, prev_download = prev
                upload_delta = item["upload"] - prev_upload if item["upload"] >= prev_upload else item["upload"]
                download_delta = (
                    item["download"] - prev_download if item["download"] >= prev_download else item["download"]
                )
                duration_delta = max(0, now - int(last_seen))
            else:
                first_seen = now
                upload_delta = item["upload"]
                download_delta = item["download"]
                duration_delta = 0

            upload_delta_total += upload_delta
            download_delta_total += download_delta

            conn.execute(
                """
                INSERT INTO connection_totals (
                  id, first_seen, last_seen, host, dst_ip, dst_port, network, source_ip,
                  source_port, process, process_path, rule, rule_payload, chains, is_ai,
                  upload_last, download_last, upload_total, download_total
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  last_seen = excluded.last_seen,
                  host = excluded.host,
                  dst_ip = excluded.dst_ip,
                  dst_port = excluded.dst_port,
                  network = excluded.network,
                  source_ip = excluded.source_ip,
                  source_port = excluded.source_port,
                  process = excluded.process,
                  process_path = excluded.process_path,
                  rule = excluded.rule,
                  rule_payload = excluded.rule_payload,
                  chains = excluded.chains,
                  is_ai = excluded.is_ai,
                  upload_last = excluded.upload_last,
                  download_last = excluded.download_last,
                  upload_total = connection_totals.upload_total + ?,
                  download_total = connection_totals.download_total + ?
                """,
                (
                    item["id"],
                    first_seen,
                    now,
                    item["host"],
                    item["dst_ip"],
                    item["dst_port"],
                    item["network"],
                    item["source_ip"],
                    item["source_port"],
                    item["process"],
                    item["process_path"],
                    item["rule"],
                    item["rule_payload"],
                    item["chains"],
                    item["is_ai"],
                    item["upload"],
                    item["download"],
                    upload_delta,
                    download_delta,
                    upload_delta,
                    download_delta,
                ),
            )
            conn.execute(
                """
                INSERT INTO traffic_samples (
                  ts, connection_id, host, dst_ip, dst_port, source_ip, process, rule,
                  rule_payload, chains, is_ai, upload_delta, download_delta, duration_delta
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    now,
                    item["id"],
                    item["host"],
                    item["dst_ip"],
                    item["dst_port"],
                    item["source_ip"],
                    item["process"],
                    item["rule"],
                    item["rule_payload"],
                    item["chains"],
                    item["is_ai"],
                    upload_delta,
                    download_delta,
                    duration_delta,
                ),
            )
    return len(raw_connections), upload_delta_total, download_delta_total


def prune_old(conn: sqlite3.Connection, retention_days: int) -> None:
    if retention_days <= 0:
        return
    cutoff = int(time.time()) - retention_days * 86400
    with conn:
        conn.execute("DELETE FROM traffic_samples WHERE ts < ?", (cutoff,))
        conn.execute("DELETE FROM connection_totals WHERE last_seen < ?", (cutoff,))


def main() -> int:
    parser = argparse.ArgumentParser(description="Collect Mihomo connection telemetry into SQLite.")
    parser.add_argument("--controller", default=DEFAULT_CONTROLLER)
    parser.add_argument("--secret", default=DEFAULT_SECRET)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--interval", type=float, default=30.0)
    parser.add_argument("--timeout", type=float, default=3.0)
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--retention-days", type=int, default=400)
    parser.add_argument("--include-process-path", action="store_true")
    args = parser.parse_args()

    ai_suffixes = load_ai_suffixes()
    conn = ensure_db(args.db)

    try:
        while True:
            try:
                count, up, down = collect_once(
                    conn,
                    args.controller,
                    args.secret,
                    args.timeout,
                    ai_suffixes,
                    args.include_process_path,
                )
                prune_old(conn, args.retention_days)
                print(
                    f"connections={count} upload_delta={up} download_delta={down} db={args.db}",
                    flush=True,
                )
            except urllib.error.HTTPError as exc:
                if exc.code == 401:
                    print(
                        "ERROR: Mihomo controller requires a secret; set MIHOMO_SECRET or pass --secret",
                        file=sys.stderr,
                        flush=True,
                    )
                else:
                    print(f"ERROR: Mihomo controller HTTP {exc.code}: {exc.reason}", file=sys.stderr, flush=True)
                if args.once:
                    return 2
            except urllib.error.URLError as exc:
                print(f"ERROR: cannot reach Mihomo controller: {exc}", file=sys.stderr, flush=True)
                if args.once:
                    return 2
            except Exception as exc:  # noqa: BLE001
                print(f"ERROR: collector failed: {exc}", file=sys.stderr, flush=True)
                if args.once:
                    return 1

            if args.once:
                return 0
            time.sleep(max(1.0, args.interval))
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
