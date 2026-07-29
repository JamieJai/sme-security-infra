import json
import os
import pathlib
import sqlite3
import subprocess
import tempfile
import unittest


ROOT_DIR = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT_DIR / "scripts" / "register-endpoint.sh"


class RegisterEndpointTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tempdir.name)
        self.db_path = self.root / "ops.sqlite"
        self.output_dir = self.root / "reports"

    def tearDown(self):
        self.tempdir.cleanup()

    def run_script(self, *extra_args):
        env = os.environ.copy()
        env["OPS_DB"] = str(self.db_path)
        return subprocess.run(
            [
                str(SCRIPT),
                "--employee-id",
                "DEMO-001",
                "--username",
                "demo.user",
                "--computer-name",
                "PC-DEMO01",
                "--status",
                "registered",
                "--output-dir",
                str(self.output_dir),
                *extra_args,
            ],
            cwd=ROOT_DIR,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_registration_uses_overridden_db_and_records_initial_history(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.db_path.exists())

        with sqlite3.connect(self.db_path) as connection:
            asset = connection.execute(
                "select status, owner, metadata_json from assets"
            ).fetchone()
            history = connection.execute(
                """
                select action, from_status, to_status, new_owner
                from asset_history
                """
            ).fetchone()
        self.assertEqual(asset[0:2], ("registered", "demo.user"))
        self.assertEqual(json.loads(asset[2])["employee_id"], "DEMO-001")
        self.assertEqual(
            history,
            ("register", "untracked", "registered", "demo.user"),
        )

    def test_reregistration_cannot_overwrite_lifecycle_state_or_owner(self):
        self.assertEqual(self.run_script().returncode, 0)
        with sqlite3.connect(self.db_path) as connection:
            connection.execute(
                """
                update assets
                set status = 'assigned', owner = 'new.user'
                where name = 'PC-DEMO01'
                """
            )

        result = self.run_script()
        self.assertEqual(result.returncode, 1)
        self.assertIn("must use asset-lifecycle.py", result.stderr)

        with sqlite3.connect(self.db_path) as connection:
            asset = connection.execute(
                "select status, owner from assets"
            ).fetchone()
            history_count = connection.execute(
                "select count(*) from asset_history"
            ).fetchone()[0]
        self.assertEqual(asset, ("assigned", "new.user"))
        self.assertEqual(history_count, 1)


if __name__ == "__main__":
    unittest.main()
