import json
import os
import pathlib
import sqlite3
import subprocess
import tempfile
import unittest


ROOT_DIR = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT_DIR / "scripts" / "recover-offboarded-employee.sh"


class RecoverOffboardedEmployeeTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tempdir.name)
        self.db_path = self.root / "ops.sqlite"
        self.output_dir = self.root / "reports"
        metadata = {
            "asset_tag": "NB-RECOVERY01",
            "username": "recovery.pilot",
            "offboarding": {
                "ticket_ref": "OFF-2026-100",
                "previous_status": "assigned",
                "recovery_status": "pending",
            },
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
                    "PC-RECOVERY01",
                    "endpoint",
                    "recovery_pending",
                    "recovery.pilot",
                    json.dumps(metadata),
                    "2026-07-29T00:00:00+00:00",
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
        executable.write_text(f"#!/usr/bin/env bash\nexit {return_code}\n")
        executable.chmod(0o755)
        return f"{bin_dir}:{os.environ['PATH']}"

    def base_args(self):
        return (
            "--username",
            "recovery.pilot",
            "--ticket-ref",
            "REC-2026-100",
            "--reason",
            "Approved pilot recovery",
            "--group",
            "HR_Staff",
        )

    def read_asset(self):
        with sqlite3.connect(self.db_path) as conn:
            return conn.execute(
                "select status, owner, metadata_json from assets where name = ?",
                ("PC-RECOVERY01",),
            ).fetchone()

    def test_plan_records_recovery_without_changing_asset(self):
        result = self.run_script(*self.base_args())
        self.assertEqual(result.returncode, 0, result.stderr)
        asset = self.read_asset()
        self.assertEqual(asset[0:2], ("recovery_pending", "recovery.pilot"))
        self.assertNotIn("offboarding_recovery", json.loads(asset[2]))

        with sqlite3.connect(self.db_path) as conn:
            operation = conn.execute(
                """
                select operation_type, status
                from operations
                order by id desc
                limit 1
                """
            ).fetchone()
        self.assertEqual(
            operation,
            ("employee_offboarding_recovery_plan", "planned"),
        )

    def test_authorized_execute_restores_recorded_asset_status(self):
        result = self.run_script(
            *self.base_args(),
            "--approved-by",
            "it.manager",
            "--execute",
            "--confirm-username",
            "recovery.pilot",
            extra_env={"PATH": self.fake_ansible_path(0)},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        asset = self.read_asset()
        self.assertEqual(asset[0:2], ("assigned", "recovery.pilot"))
        metadata = json.loads(asset[2])
        self.assertEqual(
            metadata["offboarding"]["recovery_status"],
            "completed",
        )
        self.assertEqual(
            metadata["offboarding_recovery"]["restored_status"],
            "assigned",
        )
        with sqlite3.connect(self.db_path) as conn:
            history = conn.execute(
                """
                select action, from_status, to_status, previous_owner, new_owner
                from asset_history
                """
            ).fetchone()
        self.assertEqual(
            history,
            (
                "offboarding-recovery",
                "recovery_pending",
                "assigned",
                "recovery.pilot",
                "recovery.pilot",
            ),
        )

    def test_failed_recovery_keeps_asset_pending(self):
        result = self.run_script(
            *self.base_args(),
            "--approved-by",
            "it.manager",
            "--execute",
            "--confirm-username",
            "recovery.pilot",
            extra_env={"PATH": self.fake_ansible_path(1)},
        )
        self.assertEqual(result.returncode, 1)
        asset = self.read_asset()
        self.assertEqual(asset[0:2], ("recovery_pending", "recovery.pilot"))

    def test_execute_requires_approver(self):
        result = self.run_script(
            *self.base_args(),
            "--execute",
            "--confirm-username",
            "recovery.pilot",
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("--approved-by is required", result.stderr)

    def test_unmanaged_group_is_rejected(self):
        result = self.run_script(
            "--username",
            "recovery.pilot",
            "--ticket-ref",
            "REC-2026-101",
            "--reason",
            "Invalid group fixture",
            "--group",
            "Domain Admins",
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("unsupported managed group", result.stderr)


if __name__ == "__main__":
    unittest.main()
