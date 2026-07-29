#!/usr/bin/env python3
"""Record a test or live Helpdesk ticket lifecycle with auditable timestamps."""

from __future__ import annotations

import argparse
import os
import pathlib
import re
import sqlite3
import sys

from ops_db import connect, json_text, parse_timestamp, record_operation


ROOT_DIR = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_DB = ROOT_DIR / ".codex" / "mcp" / "homelab_ops.sqlite"
DEFAULT_OUTPUT = ROOT_DIR / "artifacts" / "helpdesk-tickets"
REF_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{1,63}$")
SAFE_VALUE_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.@-]{0,127}$")


def single_line(value: str, label: str) -> str:
    if "\n" in value or "\r" in value:
        raise argparse.ArgumentTypeError(f"{label} must be single-line")
    return value


def add_common_event_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--ticket-ref", required=True)
    parser.add_argument("--actor", required=True)
    parser.add_argument("--at", help="ISO 8601 timestamp with timezone")
    parser.add_argument("--output-dir", type=pathlib.Path, default=DEFAULT_OUTPUT)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Record Helpdesk ticket lifecycle events in the operations DB."
    )
    parser.add_argument(
        "--db",
        type=pathlib.Path,
        default=pathlib.Path(os.environ.get("OPS_DB", str(DEFAULT_DB))),
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    opened = subparsers.add_parser("open", help="Open a new ticket.")
    add_common_event_arguments(opened)
    opened.add_argument("--priority", required=True, choices=("p1", "p2", "p3", "p4"))
    opened.add_argument("--scenario", required=True)
    opened.add_argument("--target", required=True)
    opened.add_argument("--summary", required=True)
    opened.add_argument("--requester")
    opened.add_argument("--recurrence-key")
    opened.add_argument(
        "--data-classification",
        choices=("simulation", "live"),
        default="simulation",
    )

    responded = subparsers.add_parser("respond", help="Record the first response.")
    add_common_event_arguments(responded)
    responded.add_argument("--note", required=True)

    resolved = subparsers.add_parser("resolve", help="Resolve a ticket.")
    add_common_event_arguments(resolved)
    resolved.add_argument("--resolution", required=True)

    reopened = subparsers.add_parser("reopen", help="Reopen a resolved ticket.")
    add_common_event_arguments(reopened)
    reopened.add_argument("--reason", required=True)
    return parser


def validate_args(args: argparse.Namespace) -> None:
    if not REF_PATTERN.fullmatch(args.ticket_ref):
        raise ValueError("ticket reference contains unsupported characters")
    if not SAFE_VALUE_PATTERN.fullmatch(args.actor):
        raise ValueError("actor contains unsupported characters")
    for field in ("scenario", "target", "requester", "recurrence_key"):
        value = getattr(args, field, None)
        if value and not SAFE_VALUE_PATTERN.fullmatch(value):
            raise ValueError(f"{field.replace('_', '-')} contains unsupported characters")
    for field in (
        "summary",
        "note",
        "resolution",
        "reason",
    ):
        value = getattr(args, field, None)
        if value:
            single_line(value, field.replace("_", "-"))


def event_note(args: argparse.Namespace) -> str:
    if args.command == "open":
        return args.summary
    if args.command == "respond":
        return args.note
    if args.command == "resolve":
        return args.resolution
    return args.reason


def write_report(
    args: argparse.Namespace,
    ticket: sqlite3.Row,
    event_at: str,
    report_path: pathlib.Path,
) -> None:
    lines = [
        "# Helpdesk Ticket Event",
        "",
        "## Summary",
        "",
        f"- Ticket: `{ticket['ticket_ref']}`",
        f"- Event: `{args.command}`",
        f"- Event time: `{event_at}`",
        f"- Actor: `{args.actor}`",
        f"- Status: `{ticket['status']}`",
        f"- Priority: `{ticket['priority']}`",
        f"- Scenario: `{ticket['scenario']}`",
        f"- Target: `{ticket['target']}`",
        f"- Data classification: `{ticket['data_classification']}`",
        f"- Reopen count: `{ticket['reopen_count']}`",
        "",
        "## Event Note",
        "",
        event_note(args),
        "",
        "## Evidence Boundary",
        "",
        "- Do not store passwords, OTP values, tokens, webhook URLs, or raw sensitive logs.",
        "- `simulation` tickets are workflow evidence and must not be represented as real user SLA.",
        "",
    ]
    report_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    args = build_parser().parse_args()
    try:
        validate_args(args)
        event_at = parse_timestamp(args.at)
    except (ValueError, argparse.ArgumentTypeError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    try:
        args.output_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2
    timestamp = event_at.replace("+00:00", "Z").replace("-", "").replace(":", "")
    report_path = args.output_dir / f"{timestamp}-{args.ticket_ref}-{args.command}.md"

    try:
        with connect(args.db) as connection:
            connection.execute("begin immediate")
            ticket = connection.execute(
                "select * from helpdesk_tickets where ticket_ref = ?",
                (args.ticket_ref,),
            ).fetchone()

            if args.command == "open":
                if ticket is not None:
                    raise ValueError("ticket already exists")
                connection.execute(
                    """
                    insert into helpdesk_tickets(
                      ticket_ref, opened_at, priority, scenario, requester, target,
                      status, recurrence_key, summary, data_classification, updated_at
                    ) values (?, ?, ?, ?, ?, ?, 'open', ?, ?, ?, ?)
                    """,
                    (
                        args.ticket_ref,
                        event_at,
                        args.priority,
                        args.scenario,
                        args.requester,
                        args.target,
                        args.recurrence_key,
                        args.summary,
                        args.data_classification,
                        event_at,
                    ),
                )
                metadata = {
                    "priority": args.priority,
                    "scenario": args.scenario,
                    "data_classification": args.data_classification,
                }
            else:
                if ticket is None:
                    raise ValueError("ticket does not exist")
                latest_event = connection.execute(
                    """
                    select event_at from helpdesk_events
                    where ticket_ref = ? order by event_at desc, id desc limit 1
                    """,
                    (args.ticket_ref,),
                ).fetchone()
                if latest_event and event_at < latest_event["event_at"]:
                    raise ValueError("event timestamp is earlier than the latest ticket event")

                if args.command == "respond":
                    if ticket["status"] not in ("open", "in_progress", "reopened"):
                        raise ValueError("only an active ticket can receive a response")
                    first_response = ticket["first_response_at"] or event_at
                    connection.execute(
                        """
                        update helpdesk_tickets
                        set status = 'in_progress', first_response_at = ?, updated_at = ?
                        where ticket_ref = ?
                        """,
                        (first_response, event_at, args.ticket_ref),
                    )
                    metadata = {"is_first_response": ticket["first_response_at"] is None}
                elif args.command == "resolve":
                    if ticket["status"] not in ("in_progress", "reopened"):
                        raise ValueError("ticket must have a response before resolution")
                    connection.execute(
                        """
                        update helpdesk_tickets
                        set status = 'resolved', resolved_at = ?, resolution = ?,
                            updated_at = ?
                        where ticket_ref = ?
                        """,
                        (event_at, args.resolution, event_at, args.ticket_ref),
                    )
                    metadata = {}
                else:
                    if ticket["status"] != "resolved":
                        raise ValueError("only a resolved ticket can be reopened")
                    connection.execute(
                        """
                        update helpdesk_tickets
                        set status = 'reopened', resolved_at = null, resolution = null,
                            reopen_count = reopen_count + 1, updated_at = ?
                        where ticket_ref = ?
                        """,
                        (event_at, args.ticket_ref),
                    )
                    metadata = {}

            connection.execute(
                """
                insert into helpdesk_events(
                  ticket_ref, event_type, event_at, actor, note, metadata_json
                ) values (?, ?, ?, ?, ?, ?)
                """,
                (
                    args.ticket_ref,
                    args.command,
                    event_at,
                    args.actor,
                    event_note(args),
                    json_text(metadata),
                ),
            )
            relative_report = (
                str(report_path.relative_to(ROOT_DIR))
                if report_path.is_relative_to(ROOT_DIR)
                else str(report_path)
            )
            record_operation(
                connection,
                operation_type=f"helpdesk_ticket_{args.command}",
                target=args.ticket_ref,
                status="success",
                summary=f"Helpdesk ticket {args.command} recorded",
                details={
                    "actor": args.actor,
                    "event_at": event_at,
                    "report_path": relative_report,
                },
                created_at=event_at,
            )
            ticket = connection.execute(
                "select * from helpdesk_tickets where ticket_ref = ?",
                (args.ticket_ref,),
            ).fetchone()
            write_report(args, ticket, event_at, report_path)
            connection.commit()
    except (OSError, sqlite3.Error, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    print(f"Ticket: {args.ticket_ref}")
    print(f"Event: {args.command}")
    print(f"Status: {ticket['status']}")
    print(f"Report: {report_path}")
    print("SQLite: recorded")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
