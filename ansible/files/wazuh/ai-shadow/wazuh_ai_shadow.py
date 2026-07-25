#!/usr/bin/env python3
"""Read-only Wazuh alert collector and deterministic shadow enrichment."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sqlite3
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

SAFE_DATA_KEYS = {"srcip", "dstip", "srcport", "dstport", "srcuser", "dstuser", "protocol", "action", "status"}
SECRET_KEY = re.compile(r"password|passwd|secret|token|cookie|authorization|body|credential", re.I)
EMAIL = re.compile(r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}", re.I)
MAX_TEXT = 512
NOTIFY_SEVERITIES = {"high", "critical"}



def text(value):
    value = EMAIL.sub("<redacted-email>", str(value))
    return value[:MAX_TEXT]


def normalize(raw):
    rule, agent, decoder = raw.get("rule", {}), raw.get("agent", {}), raw.get("decoder", {})
    data = {k: text(v) for k, v in raw.get("data", {}).items() if k in SAFE_DATA_KEYS and not SECRET_KEY.search(k)}
    return {
        "timestamp": text(raw.get("timestamp", "")),
        "rule": {
            "id": text(rule.get("id", "")),
            "level": int(rule.get("level", 0)),
            "description": text(rule.get("description", "")),
            "groups": [text(x) for x in rule.get("groups", [])[:20]],
        },
        "agent": {"id": text(agent.get("id", "")), "name": text(agent.get("name", ""))},
        "decoder": text(decoder.get("name", "")),
        "location": text(raw.get("location", "")),
        "data": data,
    }


def stable_hash(value):
    return hashlib.sha256(value.encode()).hexdigest()[:24]


def correlation_key(event):
    source = event["data"].get("srcip", "") or event["data"].get("srcuser", "")
    return ":".join((event["rule"]["id"], event["agent"]["id"], stable_hash(source) if source else "none"))


def connect(path):
    db = sqlite3.connect(path)
    db.execute("PRAGMA journal_mode=WAL")
    db.executescript("""
      CREATE TABLE IF NOT EXISTS state (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS events (
        id TEXT PRIMARY KEY, source_inode INTEGER NOT NULL, source_offset INTEGER NOT NULL,
        event_json TEXT NOT NULL, correlation_key TEXT NOT NULL, event_epoch INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending', enrichment_json TEXT, created_at INTEGER NOT NULL);
      CREATE INDEX IF NOT EXISTS events_pending ON events(status, created_at);
      CREATE INDEX IF NOT EXISTS events_correlation ON events(correlation_key, event_epoch);
      CREATE TABLE IF NOT EXISTS notifications (
        event_id TEXT PRIMARY KEY REFERENCES events(id), status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, sent_at INTEGER, last_error TEXT);
      CREATE INDEX IF NOT EXISTS notifications_status ON notifications(status, created_at);
    """)
    columns = {row[1] for row in db.execute("PRAGMA table_info(events)")}
    if "enriched_at" not in columns:
        db.execute("ALTER TABLE events ADD COLUMN enriched_at INTEGER")
    db.commit()
    return db


def state_get(db, key):
    row = db.execute("SELECT value FROM state WHERE key=?", (key,)).fetchone()
    return row[0] if row else None


def state_set(db, key, value):
    db.execute(
        "INSERT INTO state(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        (key, str(value)),
    )


def metric_add(db, key, value=1):
    current = int(state_get(db, f"metric.{key}") or 0)
    state_set(db, f"metric.{key}", current + value)


def metric_get(db, key):
    return int(state_get(db, f"metric.{key}") or 0)


def event_epoch(value):
    try:
        return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp())
    except (ValueError, TypeError):
        return int(time.time())


def collect_once(db, source, max_events=10000, start_at_end=True):
    source = Path(source)
    stat = source.stat()
    inode, size = stat.st_ino, stat.st_size
    old_inode = int(state_get(db, "inode") or 0)
    saved = state_get(db, "offset")
    if saved is None:
        offset = size if start_at_end else 0
    else:
        offset = int(saved)
    if old_inode != inode or offset > size:
        offset = 0
    pending = db.execute("SELECT count(*) FROM events WHERE status='pending'").fetchone()[0]
    if pending >= max_events:
        metric_add(db, "backpressure_skips")
        db.commit()
        return 0
    inserted = seen = duplicate = invalid = 0
    with source.open("rb") as stream:
        stream.seek(offset)
        while pending + inserted < max_events:
            begin = stream.tell()
            line = stream.readline()
            if not line or not line.endswith(b"\n"):
                break
            seen += 1
            try:
                event = normalize(json.loads(line))
            except (json.JSONDecodeError, UnicodeDecodeError, TypeError, ValueError):
                invalid += 1
                offset = stream.tell()
                continue
            canonical = json.dumps(event, sort_keys=True, separators=(",", ":"))
            event_id = hashlib.sha256(f"{inode}:{begin}:".encode() + canonical.encode()).hexdigest()
            cursor = db.execute(
                "INSERT OR IGNORE INTO events(id,source_inode,source_offset,event_json,correlation_key,event_epoch,created_at) VALUES(?,?,?,?,?,?,?)",
                (event_id, inode, begin, canonical, correlation_key(event), event_epoch(event["timestamp"]), int(time.time())),
            )
            inserted += cursor.rowcount
            duplicate += 1 - cursor.rowcount
            offset = stream.tell()
    state_set(db, "inode", inode)
    state_set(db, "offset", offset)
    metric_add(db, "seen", seen)
    metric_add(db, "inserted", inserted)
    metric_add(db, "duplicates", duplicate)
    metric_add(db, "invalid_json", invalid)
    db.commit()
    return inserted


def enrich_once(db, limit=500):
    rows = db.execute("SELECT id,event_json,correlation_key,event_epoch FROM events WHERE status='pending' ORDER BY created_at,id LIMIT ?", (limit,)).fetchall()
    now = int(time.time())
    for event_id, payload, key, epoch in rows:
        event = json.loads(payload)
        count = db.execute("SELECT count(*) FROM events WHERE correlation_key=? AND event_epoch BETWEEN ? AND ?", (key, epoch - 300, epoch)).fetchone()[0]
        level = event["rule"]["level"]
        severity = "critical" if level >= 12 else "high" if level >= 10 else "medium" if level >= 7 else "low"
        notification_candidate = severity in NOTIFY_SEVERITIES
        enrichment = {
            "mode": "shadow",
            "engine": "deterministic-v1",
            "severity": severity,
            "correlated_5m": count,
            "summary": f"rule={event['rule']['id']} agent={event['agent']['name']} count_5m={count}",
            "notification": False,
            "notification_candidate": notification_candidate,
            "automated_action": False,
        }
        db.execute(
            "UPDATE events SET status='enriched',enrichment_json=?,enriched_at=? WHERE id=?",
            (json.dumps(enrichment, sort_keys=True), now, event_id),
        )
        if notification_candidate:
            db.execute(
                "INSERT OR IGNORE INTO notifications(event_id,status,created_at) VALUES(?,?,?)",
                (event_id, "pending", now),
            )
    metric_add(db, "enriched", len(rows))
    db.commit()
    return len(rows)


def trim_spool(db, max_events):
    total = db.execute("SELECT count(*) FROM events").fetchone()[0]
    excess = max(0, total - max_events)
    if excess:
        db.execute("DELETE FROM events WHERE id IN (SELECT id FROM events WHERE status='enriched' ORDER BY created_at,id LIMIT ?)", (excess,))
        metric_add(db, "trimmed", excess)
        db.commit()


def percentile(values, pct):
    if not values:
        return None
    values = sorted(values)
    index = min(len(values) - 1, max(0, int(round((len(values) - 1) * pct))))
    return values[index]


def redaction_leak_count(db):
    leaks = 0
    for (payload,) in db.execute("SELECT event_json FROM events"):
        event = json.loads(payload)
        if any(SECRET_KEY.search(key) for key in event.get("data", {})):
            leaks += 1
            continue
        lowered = payload.lower()
        if any(secret in lowered for secret in ("authorization:", "password=", "passwd=", "cookie:")):
            leaks += 1
    return leaks


def load_env_file(path):
    values = {}
    if not path:
        return values
    env_path = Path(path)
    if not env_path.exists():
        return values
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('\"').strip("'")
    return values


def telegram_message(event, enrichment):
    fields = [
        "Wazuh alert candidate",
        f"severity={enrichment.get('severity', 'unknown')} rule={event['rule']['id']}",
        f"agent={event['agent']['name']} location={event.get('location', '')}",
        f"summary={enrichment.get('summary', '')}",
        f"description={event['rule'].get('description', '')}",
    ]
    data = event.get("data", {})
    if data:
        fields.append("data=" + json.dumps(data, sort_keys=True))
    return text("\n".join(fields))


def send_telegram_message(token, chat_id, message, timeout=10):
    encoded = urllib.parse.urlencode({"chat_id": chat_id, "text": message}).encode()
    request = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=encoded,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = response.read(4096)
    result = json.loads(body.decode("utf-8"))
    if not result.get("ok"):
        raise RuntimeError(result)


def process_notifications(db, token=None, chat_id=None, limit=20, dry_run=False):
    rows = db.execute(
        """
        SELECT n.event_id,e.event_json,e.enrichment_json
        FROM notifications n JOIN events e ON e.id=n.event_id
        WHERE n.status='pending'
        ORDER BY n.created_at,n.event_id LIMIT ?
        """,
        (limit,),
    ).fetchall()
    if not rows:
        return 0
    now = int(time.time())
    if not token or not chat_id:
        metric_add(db, "notification_config_missing")
        db.commit()
        return 0
    processed = 0
    for event_id, payload, enrichment_payload in rows:
        event = json.loads(payload)
        enrichment = json.loads(enrichment_payload or "{}")
        message = telegram_message(event, enrichment)
        try:
            if not dry_run:
                send_telegram_message(token, chat_id, message)
            status = "dry_run" if dry_run else "sent"
            db.execute(
                "UPDATE notifications SET status=?,attempts=attempts+1,sent_at=?,last_error=NULL WHERE event_id=?",
                (status, now, event_id),
            )
            processed += 1
        except Exception as exc:
            db.execute(
                "UPDATE notifications SET status='error',attempts=attempts+1,last_error=? WHERE event_id=?",
                (text(exc), event_id),
            )
    metric_add(db, "notifications_processed", processed)
    db.commit()
    return processed


def build_report(db):
    status_counts = dict(db.execute("SELECT status,count(*) FROM events GROUP BY status").fetchall())
    notification_counts = dict(db.execute("SELECT status,count(*) FROM notifications GROUP BY status").fetchall())
    total_events = sum(status_counts.values())
    latencies = [row[0] for row in db.execute("SELECT enriched_at-created_at FROM events WHERE enriched_at IS NOT NULL AND enriched_at >= created_at")]
    seen = metric_get(db, "seen")
    inserted = metric_get(db, "inserted")
    duplicates = metric_get(db, "duplicates")
    invalid_json = metric_get(db, "invalid_json")
    last_success = state_get(db, "last_success")
    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "last_success": last_success,
        "source_inode": int(state_get(db, "inode") or 0),
        "source_offset": int(state_get(db, "offset") or 0),
        "events_total": total_events,
        "events_pending": status_counts.get("pending", 0),
        "events_enriched": status_counts.get("enriched", 0),
        "seen_total": seen,
        "inserted_total": inserted,
        "duplicate_total": duplicates,
        "duplicate_rate": round(duplicates / seen, 6) if seen else 0.0,
        "invalid_json_total": invalid_json,
        "trimmed_total": metric_get(db, "trimmed"),
        "backpressure_skips_total": metric_get(db, "backpressure_skips"),
        "notification_pending": notification_counts.get("pending", 0),
        "notification_sent": notification_counts.get("sent", 0),
        "notification_error": notification_counts.get("error", 0),
        "notification_dry_run": notification_counts.get("dry_run", 0),
        "notification_config_missing_total": metric_get(db, "notification_config_missing"),
        "redaction_leak_count": redaction_leak_count(db),
        "latency_seconds_p50": percentile(latencies, 0.50),
        "latency_seconds_p95": percentile(latencies, 0.95),
    }
    report["event_loss_indicators"] = {
        "invalid_json_total": invalid_json,
        "trimmed_total": report["trimmed_total"],
        "backpressure_skips_total": report["backpressure_skips_total"],
    }
    return report


def write_report(db, output=None):
    payload = json.dumps(build_report(db), sort_keys=True, indent=2)
    if output:
        Path(output).write_text(payload + "\n", encoding="utf-8")
    else:
        print(payload)


def run(args):
    Path(args.database).parent.mkdir(parents=True, exist_ok=True)
    db = connect(args.database)
    if args.report:
        write_report(db, args.report_output)
        return
    if args.send_telegram_once:
        env = load_env_file(args.telegram_env_file)
        token = args.telegram_bot_token or os.environ.get("TELEGRAM_BOT_TOKEN") or env.get("TELEGRAM_BOT_TOKEN")
        chat_id = args.telegram_chat_id or os.environ.get("TELEGRAM_CHAT_ID") or env.get("TELEGRAM_CHAT_ID")
        process_notifications(db, token=token, chat_id=chat_id, limit=args.notification_limit, dry_run=args.telegram_dry_run)
        return
    while True:
        collect_once(db, args.source, args.max_events, args.start_at_end)
        enrich_once(db)
        trim_spool(db, args.max_events)
        state_set(db, "last_success", datetime.now(timezone.utc).isoformat())
        db.commit()
        if args.once:
            break
        time.sleep(args.interval)


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--source", default="/var/ossec/logs/alerts/alerts.json")
    p.add_argument("--database", default="/var/lib/wazuh-ai-shadow/spool.db")
    p.add_argument("--max-events", type=int, default=10000)
    p.add_argument("--interval", type=int, default=5)
    p.add_argument("--once", action="store_true")
    p.add_argument("--start-at-end", action=argparse.BooleanOptionalAction, default=True)
    p.add_argument("--report", action="store_true")
    p.add_argument("--report-output")
    p.add_argument("--send-telegram-once", action="store_true")
    p.add_argument("--telegram-env-file", default="/etc/wazuh-ai-shadow/telegram.env")
    p.add_argument("--telegram-bot-token")
    p.add_argument("--telegram-chat-id")
    p.add_argument("--telegram-dry-run", action="store_true")
    p.add_argument("--notification-limit", type=int, default=20)
    return p.parse_args()


if __name__ == "__main__":
    run(parse_args())
