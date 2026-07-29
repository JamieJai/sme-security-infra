#!/usr/bin/env python3
"""Shared SQLite helpers for local IT operations workflows."""

from __future__ import annotations

import datetime as dt
import json
import pathlib
import sqlite3


CORE_SCHEMA = """
create table if not exists assets (
  id integer primary key autoincrement,
  name text not null unique,
  kind text not null,
  status text not null default 'unknown',
  owner text,
  metadata_json text not null default '{}',
  updated_at text not null
);
create table if not exists operations (
  id integer primary key autoincrement,
  created_at text not null,
  operation_type text not null,
  target text not null,
  status text not null,
  summary text not null,
  details_json text not null default '{}'
);
create table if not exists helpdesk_tickets (
  id integer primary key autoincrement,
  ticket_ref text not null unique,
  opened_at text not null,
  priority text not null,
  scenario text not null,
  requester text,
  target text not null,
  status text not null,
  first_response_at text,
  resolved_at text,
  recurrence_key text,
  summary text not null,
  resolution text,
  data_classification text not null default 'simulation',
  reopen_count integer not null default 0,
  updated_at text not null
);
create table if not exists helpdesk_events (
  id integer primary key autoincrement,
  ticket_ref text not null,
  event_type text not null,
  event_at text not null,
  actor text not null,
  note text not null,
  metadata_json text not null default '{}',
  foreign key(ticket_ref) references helpdesk_tickets(ticket_ref)
);
create index if not exists helpdesk_events_ticket_time
  on helpdesk_events(ticket_ref, event_at, id);
create table if not exists asset_history (
  id integer primary key autoincrement,
  asset_name text not null,
  action text not null,
  from_status text not null,
  to_status text not null,
  previous_owner text,
  new_owner text,
  ticket_ref text not null,
  approved_by text not null,
  reason text not null,
  evidence_ref text,
  changed_at text not null,
  metadata_json text not null default '{}',
  foreign key(asset_name) references assets(name)
);
create index if not exists asset_history_asset_time
  on asset_history(asset_name, changed_at, id);
"""


def connect(path: pathlib.Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path)
    connection.row_factory = sqlite3.Row
    connection.execute("pragma foreign_keys = on")
    connection.executescript(CORE_SCHEMA)
    return connection


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def parse_timestamp(value: str | None) -> str:
    if not value:
        return utc_now()
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = dt.datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise ValueError("timestamp must be ISO 8601") from exc
    if parsed.tzinfo is None:
        raise ValueError("timestamp must include a timezone")
    return parsed.astimezone(dt.timezone.utc).isoformat()


def json_text(value: object) -> str:
    return json.dumps(value, ensure_ascii=True, sort_keys=True)


def record_operation(
    connection: sqlite3.Connection,
    *,
    operation_type: str,
    target: str,
    status: str,
    summary: str,
    details: dict[str, object],
    created_at: str,
) -> None:
    connection.execute(
        """
        insert into operations(
          created_at, operation_type, target, status, summary, details_json
        ) values (?, ?, ?, ?, ?, ?)
        """,
        (
            created_at,
            operation_type,
            target,
            status,
            summary,
            json_text(details),
        ),
    )
