import json
import os
import pathlib
import sqlite3
import subprocess
import tempfile
import unittest


ROOT_DIR = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT_DIR / "scripts" / "offboard-employee.sh"


class OffboardEmployeePlanTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tempdir.name)
        self.db_path = self.root / "ops.sqlite"
        self.output_dir = self.root / "reports"
        now = "2026-07-29T00:00:00+00:00"
        metadata = {
            "asset_tag": "NB-DEMO01",
            "employee_id": "DEMO-001",
            "username": "demo.user",
        }
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                """create table assets (
                  id integer primary key autoincrement,
                  name text not null unique,
                  kind text not null,
                  status text not null,
                  owner text,
                  metadata_json text not null,
                  updated_at text not null
                )"""
            )
            conn.execute(
                """
                insert into assets(
                  name, kind, status, owner, metadata_json, updated_at
                ) values (?, ?, ?, ?, ?, ?)
                """,
                (
                    "PC-DEMO01",
                    "endpoint",
                    "assigned",
                    "demo.user",
                    json.dumps(metadata),
                    now,
                ),
            )

    def tearDown(self):
        self.tempdir.cleanup()

    def run_script(self, *args, extra_env=None):
        env = os.environ.copy()
        env["OPS_DB"] = str(self.db_path)
        env.update(extra_env or {})
        return subprocess.run(
            [str(SCRIPT), *args, "--output-dir", str(self.output_dir)],
            cwd=ROOT_DIR,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def fake_ansible_path(self, return_code):
        bin_dir = self.root / f"fake-bin-{return_code}"
        bin_dir.mkdir()
        executable = bin_dir / "ansible-playbook"
        executable.write_text(
            f"#!/usr/bin/env bash\nexit {return_code}\n",
        )
        executable.chmod(0o755)
        return f"{bin_dir}:{os.environ['PATH']}"

    def test_plan_records_evidence_without_changing_asset(self):
        result = self.run_script(
            "--username",
            "demo.user",
            "--ticket-ref",
            "OFF-2026-001",
            "--reason",
            "Fixture test",
        )
        self.assertEqual(result.returncode, 0, result.stderr)

        with sqlite3.connect(self.db_path) as conn:
            asset = conn.execute(
                "select status, owner, metadata_json from assets where name = ?",
                ("PC-DEMO01",),
            ).fetchone()
            operation = conn.execute(
                """
                select operation_type, target, status, details_json
                from operations
                order by id desc
                limit 1
                """
            ).fetchone()

        self.assertEqual(asset[0:2], ("assigned", "demo.user"))
        self.assertNotIn("offboarding", json.loads(asset[2]))
        self.assertEqual(
            operation[0:3],
            ("employee_offboarding_plan", "demo.user", "planned"),
        )
        details = json.loads(operation[3])
        self.assertEqual(details["assigned_assets"][0]["name"], "PC-DEMO01")
        self.assertEqual(details["destructive_actions"], [])

        reports = list(self.output_dir.glob("*-demo.user-plan.md"))
        self.assertEqual(len(reports), 1)
        report = reports[0].read_text()
        self.assertIn("No account, mailbox, home directory", report)
        self.assertIn("`PC-DEMO01`", report)
        self.assertIn("not run in plan mode", report)

    def test_execute_requires_exact_confirmation_and_approver(self):
        result = self.run_script(
            "--username",
            "demo.user",
            "--ticket-ref",
            "OFF-2026-002",
            "--reason",
            "Fixture guard test",
            "--execute",
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("--approved-by is required", result.stderr)

        with sqlite3.connect(self.db_path) as conn:
            has_operations = conn.execute(
                "select 1 from sqlite_master where type='table' and name='operations'"
            ).fetchone()
        self.assertIsNone(has_operations)

    def test_protected_identity_is_rejected(self):
        result = self.run_script(
            "--username",
            "administrator",
            "--ticket-ref",
            "OFF-2026-003",
            "--reason",
            "Fixture guard test",
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("protected account", result.stderr)

    def test_authorized_execute_transitions_asset_and_preserves_owner(self):
        result = self.run_script(
            "--username",
            "demo.user",
            "--ticket-ref",
            "OFF-2026-004",
            "--reason",
            "Fixture execute test",
            "--approved-by",
            "it.manager",
            "--execute",
            "--confirm-username",
            "demo.user",
            extra_env={"PATH": self.fake_ansible_path(0)},
        )
        self.assertEqual(result.returncode, 0, result.stderr)

        with sqlite3.connect(self.db_path) as conn:
            asset = conn.execute(
                "select status, owner, metadata_json from assets where name = ?",
                ("PC-DEMO01",),
            ).fetchone()
            operation = conn.execute(
                """
                select operation_type, status, details_json
                from operations
                order by id desc
                limit 1
                """
            ).fetchone()
            history = conn.execute(
                """
                select action, from_status, to_status, previous_owner, new_owner
                from asset_history
                """
            ).fetchone()

        self.assertEqual(asset[0:2], ("recovery_pending", "demo.user"))
        metadata = json.loads(asset[2])
        self.assertEqual(
            metadata["offboarding"]["previous_status"],
            "assigned",
        )
        self.assertEqual(metadata["offboarding"]["recovery_status"], "pending")
        self.assertEqual(operation[0:2], ("employee_offboarding", "success"))
        details = json.loads(operation[2])
        self.assertEqual(details["apply_return_code"], 0)
        self.assertEqual(details["verify_return_code"], 0)
        self.assertEqual(
            history,
            (
                "offboard-recovery-queue",
                "assigned",
                "recovery_pending",
                "demo.user",
                "demo.user",
            ),
        )

    def test_failed_apply_still_queues_physical_asset_recovery(self):
        result = self.run_script(
            "--username",
            "demo.user",
            "--ticket-ref",
            "OFF-2026-005",
            "--reason",
            "Fixture partial test",
            "--approved-by",
            "it.manager",
            "--execute",
            "--confirm-username",
            "demo.user",
            extra_env={"PATH": self.fake_ansible_path(1)},
        )
        self.assertEqual(result.returncode, 1)

        with sqlite3.connect(self.db_path) as conn:
            asset = conn.execute(
                "select status, owner from assets where name = ?",
                ("PC-DEMO01",),
            ).fetchone()
            operation = conn.execute(
                """
                select operation_type, status, details_json
                from operations
                order by id desc
                limit 1
                """
            ).fetchone()

        self.assertEqual(asset, ("recovery_pending", "demo.user"))
        self.assertEqual(operation[0:2], ("employee_offboarding", "partial"))
        details = json.loads(operation[2])
        self.assertEqual(details["apply_return_code"], 1)
        self.assertEqual(details["verify_return_code"], 125)

    def test_execute_retry_preserves_original_asset_status(self):
        first = self.run_script(
            "--username",
            "demo.user",
            "--ticket-ref",
            "OFF-2026-006",
            "--reason",
            "Fixture first attempt",
            "--approved-by",
            "it.manager",
            "--execute",
            "--confirm-username",
            "demo.user",
            extra_env={"PATH": self.fake_ansible_path(1)},
        )
        self.assertEqual(first.returncode, 1)

        second = self.run_script(
            "--username",
            "demo.user",
            "--ticket-ref",
            "OFF-2026-006",
            "--reason",
            "Fixture retry",
            "--approved-by",
            "it.manager",
            "--execute",
            "--confirm-username",
            "demo.user",
            extra_env={"PATH": self.fake_ansible_path(0)},
        )
        self.assertEqual(second.returncode, 0, second.stderr)

        with sqlite3.connect(self.db_path) as conn:
            metadata_raw = conn.execute(
                "select metadata_json from assets where name = ?",
                ("PC-DEMO01",),
            ).fetchone()[0]
        metadata = json.loads(metadata_raw)
        self.assertEqual(
            metadata["offboarding"]["previous_status"],
            "assigned",
        )


if __name__ == "__main__":
    unittest.main()
