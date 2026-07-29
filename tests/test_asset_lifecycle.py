import json
import pathlib
import sqlite3
import subprocess
import sys
import tempfile
import unittest


ROOT_DIR = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT_DIR / "scripts" / "asset-lifecycle.py"


class AssetLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tempdir.name)
        self.db_path = self.root / "ops.sqlite"
        self.output_dir = self.root / "reports"
        with sqlite3.connect(self.db_path) as connection:
            connection.execute(
                """
                create table assets (
                  id integer primary key autoincrement,
                  name text not null unique,
                  kind text not null,
                  status text not null,
                  owner text,
                  metadata_json text not null,
                  updated_at text not null
                )
                """
            )
            connection.execute(
                """
                insert into assets(
                  name, kind, status, owner, metadata_json, updated_at
                ) values ('PC-DEMO01', 'endpoint', 'in_stock', null, '{}',
                          '2026-07-01T00:00:00+00:00')
                """
            )

    def tearDown(self):
        self.tempdir.cleanup()

    def run_script(self, *args):
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--db",
                str(self.db_path),
                "--output-dir",
                str(self.output_dir),
                *args,
            ],
            cwd=ROOT_DIR,
            text=True,
            capture_output=True,
            check=False,
        )

    def execute(self, action, expected_status, *, owner=None, evidence=None, at=None):
        args = [
            "--asset",
            "PC-DEMO01",
            "--action",
            action,
            "--ticket-ref",
            f"ASSET-{action}",
            "--reason",
            f"Fixture {action}",
            "--expected-status",
            expected_status,
            "--approved-by",
            "it.manager",
            "--confirm-asset",
            "PC-DEMO01",
            "--execute",
        ]
        if owner:
            args.extend(("--owner", owner))
        if evidence:
            args.extend(("--evidence-ref", evidence))
        if at:
            args.extend(("--at", at))
        return self.run_script(*args)

    def test_plan_records_intent_without_changing_asset(self):
        result = self.run_script(
            "--asset",
            "PC-DEMO01",
            "--action",
            "assign",
            "--owner",
            "demo.user",
            "--ticket-ref",
            "ASSET-PLAN-001",
            "--reason",
            "Planned assignment",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        with sqlite3.connect(self.db_path) as connection:
            asset = connection.execute(
                "select status, owner from assets where name = 'PC-DEMO01'"
            ).fetchone()
            operation = connection.execute(
                "select operation_type, status from operations order by id desc limit 1"
            ).fetchone()
            history_count = connection.execute(
                "select count(*) from asset_history"
            ).fetchone()[0]
        self.assertEqual(asset, ("in_stock", None))
        self.assertEqual(operation, ("asset_lifecycle_plan", "planned"))
        self.assertEqual(history_count, 0)

    def test_execute_requires_approval_confirmation_and_expected_state(self):
        result = self.run_script(
            "--asset",
            "PC-DEMO01",
            "--action",
            "assign",
            "--owner",
            "demo.user",
            "--ticket-ref",
            "ASSET-GATE-001",
            "--reason",
            "Missing approval",
            "--execute",
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("--approved-by is required", result.stderr)

    def test_full_assignment_transfer_return_wipe_retire_lifecycle(self):
        steps = (
            ("assign", "in_stock", "demo.user", None, "2026-07-01T01:00:00+00:00"),
            ("transfer", "assigned", "new.user", None, "2026-07-02T01:00:00+00:00"),
            ("return", "assigned", None, None, "2026-07-03T01:00:00+00:00"),
            ("start-wipe", "returned", None, None, "2026-07-04T01:00:00+00:00"),
            (
                "complete-wipe",
                "wipe_pending",
                None,
                "WIPE-LOG-001",
                "2026-07-05T01:00:00+00:00",
            ),
            (
                "retire",
                "wiped",
                None,
                "DISPOSAL-001",
                "2026-07-06T01:00:00+00:00",
            ),
        )
        for action, expected, owner, evidence, at in steps:
            result = self.execute(
                action,
                expected,
                owner=owner,
                evidence=evidence,
                at=at,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

        with sqlite3.connect(self.db_path) as connection:
            asset = connection.execute(
                "select status, owner, metadata_json from assets"
            ).fetchone()
            history = connection.execute(
                """
                select action, from_status, to_status, previous_owner, new_owner
                from asset_history order by id
                """
            ).fetchall()
        self.assertEqual(asset[0:2], ("retired", None))
        self.assertEqual(len(history), 6)
        self.assertEqual(
            history[1],
            ("transfer", "assigned", "assigned", "demo.user", "new.user"),
        )
        metadata = json.loads(asset[2])
        self.assertEqual(metadata["lifecycle"]["evidence_ref"], "DISPOSAL-001")

    def test_invalid_and_stale_transitions_are_rejected(self):
        invalid = self.execute(
            "retire",
            "in_stock",
            evidence="DISPOSAL-INVALID",
        )
        self.assertEqual(invalid.returncode, 2)
        self.assertIn("not allowed from in_stock", invalid.stderr)

        stale = self.execute(
            "assign",
            "returned",
            owner="demo.user",
        )
        self.assertEqual(stale.returncode, 2)
        self.assertIn("stale asset state", stale.stderr)

        with sqlite3.connect(self.db_path) as connection:
            asset = connection.execute(
                "select status, owner from assets"
            ).fetchone()
        self.assertEqual(asset, ("in_stock", None))

    def test_wipe_completion_requires_evidence(self):
        with sqlite3.connect(self.db_path) as connection:
            connection.execute(
                "update assets set status = 'wipe_pending' where name = 'PC-DEMO01'"
            )
        result = self.run_script(
            "--asset",
            "PC-DEMO01",
            "--action",
            "complete-wipe",
            "--ticket-ref",
            "ASSET-WIPE-001",
            "--reason",
            "Missing wipe log",
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("--evidence-ref is required", result.stderr)

    def test_non_endpoint_asset_is_rejected(self):
        with sqlite3.connect(self.db_path) as connection:
            connection.execute(
                """
                update assets
                set kind = 'server'
                where name = 'PC-DEMO01'
                """
            )
        result = self.run_script(
            "--asset",
            "PC-DEMO01",
            "--action",
            "assign",
            "--owner",
            "demo.user",
            "--ticket-ref",
            "ASSET-KIND-001",
            "--reason",
            "Invalid kind fixture",
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("only supports kind=endpoint", result.stderr)


if __name__ == "__main__":
    unittest.main()
