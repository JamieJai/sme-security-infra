#!/usr/bin/env python3
"""Plan or execute an approved endpoint asset lifecycle transition."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sqlite3
import sys

from ops_db import connect, json_text, parse_timestamp, record_operation


ROOT_DIR = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_DB = ROOT_DIR / ".codex" / "mcp" / "homelab_ops.sqlite"
DEFAULT_OUTPUT = ROOT_DIR / "artifacts" / "asset-lifecycle"
SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.@-]{0,127}$")
TRANSITIONS = {
    "stock": {
        "from": {
            "registered",
            "odj_package_issued",
            "ad_join_package_issued",
            "returned",
            "repaired",
            "wiped",
        },
        "to": "in_stock",
        "owner": "clear",
    },
    "assign": {"from": {"in_stock", "wiped"}, "to": "assigned", "owner": "required"},
    "transfer": {"from": {"assigned"}, "to": "assigned", "owner": "required"},
    "send-repair": {
        "from": {"assigned", "in_stock", "returned"},
        "to": "repair",
        "owner": "clear",
    },
    "complete-repair": {
        "from": {"repair"},
        "to": "repaired",
        "owner": "clear",
    },
    "return": {
        "from": {"assigned", "recovery_pending", "repair"},
        "to": "returned",
        "owner": "clear",
    },
    "start-wipe": {
        "from": {"returned"},
        "to": "wipe_pending",
        "owner": "clear",
    },
    "complete-wipe": {
        "from": {"wipe_pending"},
        "to": "wiped",
        "owner": "clear",
        "evidence": True,
    },
    "retire": {
        "from": {"wiped"},
        "to": "retired",
        "owner": "clear",
        "evidence": True,
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Plan or execute an endpoint asset lifecycle transition."
    )
    parser.add_argument("--asset", required=True)
    parser.add_argument("--action", required=True, choices=tuple(TRANSITIONS))
    parser.add_argument("--owner")
    parser.add_argument("--ticket-ref", required=True)
    parser.add_argument("--reason", required=True)
    parser.add_argument("--evidence-ref")
    parser.add_argument("--expected-status")
    parser.add_argument("--approved-by")
    parser.add_argument("--confirm-asset")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--at", help="ISO 8601 timestamp with timezone")
    parser.add_argument(
        "--db",
        type=pathlib.Path,
        default=pathlib.Path(os.environ.get("OPS_DB", str(DEFAULT_DB))),
    )
    parser.add_argument("--output-dir", type=pathlib.Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def validate(args: argparse.Namespace) -> None:
    for label in ("asset", "ticket_ref"):
        if not SAFE_ID.fullmatch(getattr(args, label)):
            raise ValueError(f"{label.replace('_', '-')} contains unsupported characters")
    if args.owner and not SAFE_ID.fullmatch(args.owner):
        raise ValueError("owner contains unsupported characters")
    for label in ("reason", "evidence_ref"):
        value = getattr(args, label)
        if value and ("\n" in value or "\r" in value):
            raise ValueError(f"{label.replace('_', '-')} must be single-line")
    transition = TRANSITIONS[args.action]
    if transition["owner"] == "required" and not args.owner:
        raise ValueError(f"--owner is required for {args.action}")
    if transition["owner"] == "clear" and args.owner:
        raise ValueError(f"--owner is not accepted for {args.action}")
    if transition.get("evidence") and not args.evidence_ref:
        raise ValueError(f"--evidence-ref is required for {args.action}")
    if args.execute:
        if not args.approved_by:
            raise ValueError("--approved-by is required with --execute")
        if not SAFE_ID.fullmatch(args.approved_by):
            raise ValueError("approved-by contains unsupported characters")
        if args.confirm_asset != args.asset:
            raise ValueError("--confirm-asset must exactly match --asset")
        if not args.expected_status:
            raise ValueError("--expected-status is required with --execute")


def owner_after(args: argparse.Namespace) -> str | None:
    return args.owner if TRANSITIONS[args.action]["owner"] == "required" else None


def report_text(
    *,
    args: argparse.Namespace,
    current_status: str,
    current_owner: str | None,
    new_status: str,
    new_owner: str | None,
    changed_at: str,
    mode: str,
) -> str:
    return "\n".join(
        [
            "# Endpoint Asset Lifecycle Report",
            "",
            "## Summary",
            "",
            f"- Mode: `{mode}`",
            f"- Asset: `{args.asset}`",
            f"- Action: `{args.action}`",
            f"- Current status: `{current_status}`",
            f"- Target status: `{new_status}`",
            f"- Previous owner: `{current_owner or 'unassigned'}`",
            f"- New owner: `{new_owner or 'unassigned'}`",
            f"- Ticket: `{args.ticket_ref}`",
            f"- Approved by: `{args.approved_by or 'not required in plan'}`",
            f"- Event time: `{changed_at}`",
            f"- Evidence: `{args.evidence_ref or 'not provided'}`",
            "",
            "## Reason",
            "",
            args.reason,
            "",
            "## Safety",
            "",
            (
                "- Plan mode does not change the asset record."
                if mode == "plan"
                else "- The expected current status and exact asset confirmation were verified."
            ),
            "- Wipe completion records evidence but does not perform a disk wipe itself.",
            "- Retire is only allowed after the asset reaches `wiped`.",
            "",
        ]
    )


def main() -> int:
    args = parse_args()
    try:
        validate(args)
        changed_at = parse_timestamp(args.at)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    try:
        args.output_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2
    mode = "execute" if args.execute else "plan"
    timestamp = changed_at.replace("+00:00", "Z").replace("-", "").replace(":", "")
    report_path = args.output_dir / f"{timestamp}-{args.asset.lower()}-{mode}.md"

    try:
        with connect(args.db) as connection:
            connection.execute("begin immediate")
            asset = connection.execute(
                "select * from assets where name = ?", (args.asset,)
            ).fetchone()
            if asset is None:
                raise ValueError("asset does not exist; register it first")
            if asset["kind"] != "endpoint":
                raise ValueError("asset lifecycle only supports kind=endpoint")
            transition = TRANSITIONS[args.action]
            current_status = asset["status"]
            current_owner = asset["owner"]
            if current_status not in transition["from"]:
                allowed = ", ".join(sorted(transition["from"]))
                raise ValueError(
                    f"{args.action} is not allowed from {current_status}; expected: {allowed}"
                )
            new_status = transition["to"]
            new_owner = owner_after(args)
            if args.action == "transfer" and new_owner == current_owner:
                raise ValueError("transfer owner must differ from the current owner")
            if args.execute and args.expected_status != current_status:
                raise ValueError(
                    f"stale asset state: expected {args.expected_status}, found {current_status}"
                )

            relative_report = (
                str(report_path.relative_to(ROOT_DIR))
                if report_path.is_relative_to(ROOT_DIR)
                else str(report_path)
            )
            details = {
                "action": args.action,
                "from_status": current_status,
                "to_status": new_status,
                "previous_owner": current_owner,
                "new_owner": new_owner,
                "ticket_ref": args.ticket_ref,
                "approved_by": args.approved_by,
                "reason": args.reason,
                "evidence_ref": args.evidence_ref,
                "report_path": relative_report,
            }
            if args.execute:
                try:
                    metadata = json.loads(asset["metadata_json"] or "{}")
                except json.JSONDecodeError as exc:
                    raise ValueError("asset metadata_json is invalid") from exc
                metadata["lifecycle"] = {
                    "last_action": args.action,
                    "previous_status": current_status,
                    "previous_owner": current_owner,
                    "ticket_ref": args.ticket_ref,
                    "approved_by": args.approved_by,
                    "evidence_ref": args.evidence_ref,
                    "changed_at": changed_at,
                }
                connection.execute(
                    """
                    update assets
                    set status = ?, owner = ?, metadata_json = ?, updated_at = ?
                    where name = ?
                    """,
                    (
                        new_status,
                        new_owner,
                        json_text(metadata),
                        changed_at,
                        args.asset,
                    ),
                )
                connection.execute(
                    """
                    insert into asset_history(
                      asset_name, action, from_status, to_status, previous_owner,
                      new_owner, ticket_ref, approved_by, reason, evidence_ref,
                      changed_at, metadata_json
                    ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        args.asset,
                        args.action,
                        current_status,
                        new_status,
                        current_owner,
                        new_owner,
                        args.ticket_ref,
                        args.approved_by,
                        args.reason,
                        args.evidence_ref,
                        changed_at,
                        "{}",
                    ),
                )
            record_operation(
                connection,
                operation_type=f"asset_lifecycle_{mode}",
                target=args.asset,
                status="success" if args.execute else "planned",
                summary=f"Asset {args.action} {mode} recorded",
                details=details,
                created_at=changed_at,
            )
            report_path.write_text(
                report_text(
                    args=args,
                    current_status=current_status,
                    current_owner=current_owner,
                    new_status=new_status,
                    new_owner=new_owner,
                    changed_at=changed_at,
                    mode=mode,
                ),
                encoding="utf-8",
            )
            connection.commit()
    except (OSError, sqlite3.Error, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    print(f"Asset: {args.asset}")
    print(f"Mode: {mode}")
    print(f"Transition: {current_status} -> {new_status}")
    print(f"Report: {report_path}")
    print("SQLite: recorded")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
