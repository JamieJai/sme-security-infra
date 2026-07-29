#!/usr/bin/env python3
"""Build an honest Helpdesk KPI report from the local operations database."""

from __future__ import annotations

import argparse
import datetime as dt
import math
import os
import pathlib
import sqlite3
import sys
from collections import Counter

from ops_db import connect, parse_timestamp, record_operation, utc_now


ROOT_DIR = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_DB = ROOT_DIR / ".codex" / "mcp" / "homelab_ops.sqlite"
DEFAULT_OUTPUT = ROOT_DIR / "reports" / "helpdesk"
SLA_SECONDS = {
    "p1": {"response": 15 * 60, "resolution": 4 * 60 * 60},
    "p2": {"response": 60 * 60, "resolution": 8 * 60 * 60},
    "p3": {"response": 4 * 60 * 60, "resolution": 24 * 60 * 60},
    "p4": {"response": 8 * 60 * 60, "resolution": 72 * 60 * 60},
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate a Helpdesk KPI report.")
    parser.add_argument(
        "--db",
        type=pathlib.Path,
        default=pathlib.Path(os.environ.get("OPS_DB", str(DEFAULT_DB))),
    )
    parser.add_argument("--from", dest="start", help="ISO 8601 inclusive start")
    parser.add_argument("--to", dest="end", help="ISO 8601 exclusive end")
    parser.add_argument("--output-dir", type=pathlib.Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def as_datetime(value: str) -> dt.datetime:
    return dt.datetime.fromisoformat(value)


def duration_seconds(start: str, end: str | None) -> float | None:
    if not end:
        return None
    return (as_datetime(end) - as_datetime(start)).total_seconds()


def average(values: list[float]) -> float | None:
    return sum(values) / len(values) if values else None


def percentile_95(values: list[float]) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * 0.95) - 1)]


def format_duration(seconds: float | None) -> str:
    if seconds is None:
        return "n/a"
    minutes = seconds / 60
    if minutes < 60:
        return f"{minutes:.1f}m"
    return f"{minutes / 60:.1f}h"


def percentage(numerator: int, denominator: int) -> str:
    if denominator == 0:
        return "n/a"
    return f"{numerator / denominator * 100:.1f}%"


def main() -> int:
    args = parse_args()
    try:
        start = parse_timestamp(args.start) if args.start else None
        end = parse_timestamp(args.end) if args.end else None
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2
    if start and end and start >= end:
        print("Error: --from must be earlier than --to", file=sys.stderr)
        return 2

    try:
        args.output_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2
    created_at = utc_now()
    filename_time = (
        created_at.replace("+00:00", "Z").replace("-", "").replace(":", "")
    )
    report_path = args.output_dir / f"{filename_time}-helpdesk-kpi.md"

    where = []
    params: list[str] = []
    if start:
        where.append("opened_at >= ?")
        params.append(start)
    if end:
        where.append("opened_at < ?")
        params.append(end)
    query = "select * from helpdesk_tickets"
    if where:
        query += " where " + " and ".join(where)
    query += " order by opened_at, ticket_ref"

    try:
        with connect(args.db) as connection:
            rows = connection.execute(query, params).fetchall()
            response_values = [
                value
                for row in rows
                if (value := duration_seconds(row["opened_at"], row["first_response_at"]))
                is not None
            ]
            resolution_values = [
                value
                for row in rows
                if (value := duration_seconds(row["opened_at"], row["resolved_at"]))
                is not None
            ]
            priority_counts = Counter(row["priority"] for row in rows)
            status_counts = Counter(row["status"] for row in rows)
            classification_counts = Counter(row["data_classification"] for row in rows)
            recurrence_counts = Counter(
                row["recurrence_key"] for row in rows if row["recurrence_key"]
            )
            repeated_keys = {
                key: count for key, count in recurrence_counts.items() if count > 1
            }
            response_sla_eligible = [
                row for row in rows if row["first_response_at"] is not None
            ]
            resolution_sla_eligible = [
                row for row in rows if row["resolved_at"] is not None
            ]
            response_sla_met = sum(
                duration_seconds(row["opened_at"], row["first_response_at"])
                <= SLA_SECONDS[row["priority"]]["response"]
                for row in response_sla_eligible
            )
            resolution_sla_met = sum(
                duration_seconds(row["opened_at"], row["resolved_at"])
                <= SLA_SECONDS[row["priority"]]["resolution"]
                for row in resolution_sla_eligible
            )
            reopened_tickets = sum(row["reopen_count"] > 0 for row in rows)

    except sqlite3.Error as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    lines = [
        "# Helpdesk KPI Report",
        "",
        "## Scope",
        "",
        f"- Generated: `{created_at}`",
        f"- Period start: `{start or 'unbounded'}`",
        f"- Period end: `{end or 'unbounded'}`",
        f"- Tickets opened in period: `{len(rows)}`",
        f"- Simulation tickets: `{classification_counts['simulation']}`",
        f"- Live tickets: `{classification_counts['live']}`",
        "",
        "Simulation data validates the workflow only and is not real-user SLA evidence.",
        "",
        "## Service Metrics",
        "",
        f"- First response average: `{format_duration(average(response_values))}`",
        f"- First response p95: `{format_duration(percentile_95(response_values))}`",
        f"- Resolution average: `{format_duration(average(resolution_values))}`",
        f"- Resolution p95: `{format_duration(percentile_95(resolution_values))}`",
        (
            f"- Response SLA attainment: "
            f"`{percentage(response_sla_met, len(response_sla_eligible))}` "
            f"({response_sla_met}/{len(response_sla_eligible)})"
        ),
        (
            f"- Resolution SLA attainment: "
            f"`{percentage(resolution_sla_met, len(resolution_sla_eligible))}` "
            f"({resolution_sla_met}/{len(resolution_sla_eligible)})"
        ),
        (
            f"- Tickets reopened at least once: `{reopened_tickets}` "
            f"({percentage(reopened_tickets, len(rows))})"
        ),
        f"- Recurrence keys affecting multiple tickets: `{len(repeated_keys)}`",
        "",
        "## Priority",
        "",
    ]
    for priority in ("p1", "p2", "p3", "p4"):
        lines.append(f"- `{priority}`: `{priority_counts[priority]}`")
    lines.extend(["", "## Current Status", ""])
    for status in ("open", "in_progress", "reopened", "resolved"):
        lines.append(f"- `{status}`: `{status_counts[status]}`")
    lines.extend(["", "## Recurrence", ""])
    if repeated_keys:
        for key, count in sorted(repeated_keys.items()):
            lines.append(f"- `{key}`: `{count}` tickets")
    else:
        lines.append("- No repeated recurrence key in this period.")
    lines.extend(
        [
            "",
            "## SLA Targets",
            "",
            "| Priority | First response | Resolution |",
            "|---|---:|---:|",
            "| P1 | 15m | 4h |",
            "| P2 | 1h | 8h |",
            "| P3 | 4h | 24h |",
            "| P4 | 8h | 72h |",
            "",
            "These are portfolio workflow targets, not a production commitment.",
            "",
        ]
    )
    try:
        report_path.write_text("\n".join(lines), encoding="utf-8")
        relative_report = (
            str(report_path.relative_to(ROOT_DIR))
            if report_path.is_relative_to(ROOT_DIR)
            else str(report_path)
        )
        with connect(args.db) as connection:
            record_operation(
                connection,
                operation_type="helpdesk_metrics",
                target="helpdesk",
                status="success",
                summary=f"Helpdesk KPI report generated for {len(rows)} tickets",
                details={
                    "ticket_count": len(rows),
                    "simulation_count": classification_counts["simulation"],
                    "live_count": classification_counts["live"],
                    "report_path": relative_report,
                    "period_start": start,
                    "period_end": end,
                },
                created_at=created_at,
            )
    except (OSError, sqlite3.Error) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    print(f"Tickets: {len(rows)}")
    print(f"Response SLA: {percentage(response_sla_met, len(response_sla_eligible))}")
    print(f"Resolution SLA: {percentage(resolution_sla_met, len(resolution_sla_eligible))}")
    print(f"Report: {report_path}")
    print("SQLite: recorded")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
