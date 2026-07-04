#!/usr/bin/env python3
"""Read-only Wazuh alert collector and deterministic shadow enrichment."""
from __future__ import annotations
import argparse, hashlib, json, os, re, sqlite3, time
from datetime import datetime, timezone
from pathlib import Path

SAFE_DATA_KEYS = {"srcip", "dstip", "srcport", "dstport", "srcuser", "dstuser", "protocol", "action", "status"}
SECRET_KEY = re.compile(r"password|passwd|secret|token|cookie|authorization|body|credential", re.I)
EMAIL = re.compile(r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}", re.I)
MAX_TEXT = 512


def text(value):
    value = EMAIL.sub("<redacted-email>", str(value))
    return value[:MAX_TEXT]


def normalize(raw):
    rule, agent, decoder = raw.get("rule", {}), raw.get("agent", {}), raw.get("decoder", {})
    data = {k: text(v) for k, v in raw.get("data", {}).items() if k in SAFE_DATA_KEYS and not SECRET_KEY.search(k)}
    return {
        "timestamp": text(raw.get("timestamp", "")),
        "rule": {"id": text(rule.get("id", "")), "level": int(rule.get("level", 0)), "description": text(rule.get("description", "")), "groups": [text(x) for x in rule.get("groups", [])[:20]]},
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
    """)
    return db


def state_get(db, key):
    row = db.execute("SELECT value FROM state WHERE key=?", (key,)).fetchone()
    return row[0] if row else None


def state_set(db, key, value):
    db.execute("INSERT INTO state(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, str(value)))


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
        return 0
    inserted = 0
    with source.open("rb") as stream:
        stream.seek(offset)
        while pending + inserted < max_events:
            begin = stream.tell()
            line = stream.readline()
            if not line or not line.endswith(b"\n"):
                break
            try:
                event = normalize(json.loads(line))
            except (json.JSONDecodeError, UnicodeDecodeError, TypeError, ValueError):
                offset = stream.tell()
                continue
            canonical = json.dumps(event, sort_keys=True, separators=(",", ":"))
            event_id = hashlib.sha256(f"{inode}:{begin}:".encode() + canonical.encode()).hexdigest()
            cursor = db.execute("INSERT OR IGNORE INTO events(id,source_inode,source_offset,event_json,correlation_key,event_epoch,created_at) VALUES(?,?,?,?,?,?,?)", (event_id, inode, begin, canonical, correlation_key(event), event_epoch(event["timestamp"]), int(time.time())))
            inserted += cursor.rowcount
            offset = stream.tell()
    state_set(db, "inode", inode)
    state_set(db, "offset", offset)
    db.commit()
    return inserted


def enrich_once(db, limit=500):
    rows = db.execute("SELECT id,event_json,correlation_key,event_epoch FROM events WHERE status='pending' ORDER BY created_at,id LIMIT ?", (limit,)).fetchall()
    for event_id, payload, key, epoch in rows:
        event = json.loads(payload)
        count = db.execute("SELECT count(*) FROM events WHERE correlation_key=? AND event_epoch BETWEEN ? AND ?", (key, epoch - 300, epoch)).fetchone()[0]
        level = event["rule"]["level"]
        severity = "critical" if level >= 12 else "high" if level >= 10 else "medium" if level >= 7 else "low"
        enrichment = {"mode": "shadow", "engine": "deterministic-v1", "severity": severity, "correlated_5m": count, "summary": f"rule={event['rule']['id']} agent={event['agent']['name']} count_5m={count}", "notification": False, "automated_action": False}
        db.execute("UPDATE events SET status='enriched',enrichment_json=? WHERE id=?", (json.dumps(enrichment, sort_keys=True), event_id))
    db.commit()
    return len(rows)


def trim_spool(db, max_events):
    total = db.execute("SELECT count(*) FROM events").fetchone()[0]
    excess = max(0, total - max_events)
    if excess:
        db.execute("DELETE FROM events WHERE id IN (SELECT id FROM events WHERE status='enriched' ORDER BY created_at,id LIMIT ?)", (excess,))
        db.commit()


def run(args):
    Path(args.database).parent.mkdir(parents=True, exist_ok=True)
    db = connect(args.database)
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
    return p.parse_args()

if __name__ == "__main__":
    run(parse_args())
