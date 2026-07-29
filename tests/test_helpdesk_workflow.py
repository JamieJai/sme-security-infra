import json
import pathlib
import sqlite3
import subprocess
import sys
import tempfile
import unittest


ROOT_DIR = pathlib.Path(__file__).resolve().parents[1]
TICKET_SCRIPT = ROOT_DIR / "scripts" / "helpdesk-ticket.py"
METRICS_SCRIPT = ROOT_DIR / "scripts" / "helpdesk-metrics.py"


class HelpdeskWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tempdir.name)
        self.db_path = self.root / "ops.sqlite"
        self.output_dir = self.root / "reports"

    def tearDown(self):
        self.tempdir.cleanup()

    def run_ticket(self, command, *args):
        return subprocess.run(
            [
                sys.executable,
                str(TICKET_SCRIPT),
                "--db",
                str(self.db_path),
                command,
                *args,
                "--output-dir",
                str(self.output_dir),
            ],
            cwd=ROOT_DIR,
            text=True,
            capture_output=True,
            check=False,
        )

    def run_metrics(self, *args):
        return subprocess.run(
            [
                sys.executable,
                str(METRICS_SCRIPT),
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

    def open_ticket(
        self,
        ticket_ref,
        *,
        priority="p2",
        opened_at="2026-07-01T00:00:00+00:00",
        recurrence_key="sso-login-loop",
    ):
        return self.run_ticket(
            "open",
            "--ticket-ref",
            ticket_ref,
            "--actor",
            "helpdesk.agent",
            "--priority",
            priority,
            "--scenario",
            "sso",
            "--target",
            "demo.user",
            "--summary",
            "SSO login loop",
            "--recurrence-key",
            recurrence_key,
            "--at",
            opened_at,
        )

    def test_ticket_requires_response_before_resolution(self):
        opened = self.open_ticket("HD-001")
        self.assertEqual(opened.returncode, 0, opened.stderr)

        resolved = self.run_ticket(
            "resolve",
            "--ticket-ref",
            "HD-001",
            "--actor",
            "helpdesk.agent",
            "--resolution",
            "Reset stale browser session",
            "--at",
            "2026-07-01T01:00:00+00:00",
        )
        self.assertEqual(resolved.returncode, 2)
        self.assertIn("must have a response", resolved.stderr)

        with sqlite3.connect(self.db_path) as connection:
            ticket = connection.execute(
                "select status, resolved_at from helpdesk_tickets"
            ).fetchone()
        self.assertEqual(ticket, ("open", None))

    def test_lifecycle_records_first_response_and_reopen(self):
        self.assertEqual(self.open_ticket("HD-002").returncode, 0)
        first_response = self.run_ticket(
            "respond",
            "--ticket-ref",
            "HD-002",
            "--actor",
            "helpdesk.agent",
            "--note",
            "Investigating identity path",
            "--at",
            "2026-07-01T00:30:00+00:00",
        )
        self.assertEqual(first_response.returncode, 0, first_response.stderr)
        second_response = self.run_ticket(
            "respond",
            "--ticket-ref",
            "HD-002",
            "--actor",
            "helpdesk.agent",
            "--note",
            "Keycloak path is healthy",
            "--at",
            "2026-07-01T00:45:00+00:00",
        )
        self.assertEqual(second_response.returncode, 0, second_response.stderr)
        self.assertEqual(
            self.run_ticket(
                "resolve",
                "--ticket-ref",
                "HD-002",
                "--actor",
                "helpdesk.agent",
                "--resolution",
                "Cleared stale browser session",
                "--at",
                "2026-07-01T02:00:00+00:00",
            ).returncode,
            0,
        )
        self.assertEqual(
            self.run_ticket(
                "reopen",
                "--ticket-ref",
                "HD-002",
                "--actor",
                "demo.user",
                "--reason",
                "Issue recurred",
                "--at",
                "2026-07-01T03:00:00+00:00",
            ).returncode,
            0,
        )

        with sqlite3.connect(self.db_path) as connection:
            ticket = connection.execute(
                """
                select status, first_response_at, resolved_at, reopen_count,
                       data_classification
                from helpdesk_tickets where ticket_ref = 'HD-002'
                """
            ).fetchone()
            first_response_events = connection.execute(
                """
                select metadata_json from helpdesk_events
                where ticket_ref = 'HD-002' and event_type = 'respond'
                order by id
                """
            ).fetchall()
        self.assertEqual(
            ticket,
            (
                "reopened",
                "2026-07-01T00:30:00+00:00",
                None,
                1,
                "simulation",
            ),
        )
        self.assertTrue(json.loads(first_response_events[0][0])["is_first_response"])
        self.assertFalse(json.loads(first_response_events[1][0])["is_first_response"])

    def test_metrics_calculate_sla_and_recurrence(self):
        fixtures = (
            (
                "HD-101",
                "p2",
                "2026-07-01T00:00:00+00:00",
                "2026-07-01T00:30:00+00:00",
                "2026-07-01T05:00:00+00:00",
            ),
            (
                "HD-102",
                "p3",
                "2026-07-02T00:00:00+00:00",
                "2026-07-02T05:00:00+00:00",
                "2026-07-03T06:00:00+00:00",
            ),
        )
        for ticket_ref, priority, opened_at, responded_at, resolved_at in fixtures:
            opened = self.open_ticket(
                ticket_ref, priority=priority, opened_at=opened_at
            )
            self.assertEqual(opened.returncode, 0, opened.stderr)
            responded = self.run_ticket(
                "respond",
                "--ticket-ref",
                ticket_ref,
                "--actor",
                "helpdesk.agent",
                "--note",
                "Initial response",
                "--at",
                responded_at,
            )
            self.assertEqual(responded.returncode, 0, responded.stderr)
            resolved = self.run_ticket(
                "resolve",
                "--ticket-ref",
                ticket_ref,
                "--actor",
                "helpdesk.agent",
                "--resolution",
                "Fixture resolution",
                "--at",
                resolved_at,
            )
            self.assertEqual(resolved.returncode, 0, resolved.stderr)

        metrics = self.run_metrics(
            "--from",
            "2026-07-01T00:00:00+00:00",
            "--to",
            "2026-08-01T00:00:00+00:00",
        )
        self.assertEqual(metrics.returncode, 0, metrics.stderr)
        report = next(self.output_dir.glob("*-helpdesk-kpi.md")).read_text()
        self.assertIn("Response SLA attainment: `50.0%` (1/2)", report)
        self.assertIn("Resolution SLA attainment: `50.0%` (1/2)", report)
        self.assertIn("`sso-login-loop`: `2` tickets", report)
        self.assertIn("Simulation data validates the workflow only", report)

        with sqlite3.connect(self.db_path) as connection:
            operation = connection.execute(
                """
                select status, details_json from operations
                where operation_type = 'helpdesk_metrics'
                order by id desc limit 1
                """
            ).fetchone()
        self.assertEqual(operation[0], "success")
        self.assertEqual(json.loads(operation[1])["ticket_count"], 2)

    def test_event_timestamps_cannot_move_backwards(self):
        self.assertEqual(self.open_ticket("HD-201").returncode, 0)
        result = self.run_ticket(
            "respond",
            "--ticket-ref",
            "HD-201",
            "--actor",
            "helpdesk.agent",
            "--note",
            "Invalid earlier response",
            "--at",
            "2026-06-30T23:59:00+00:00",
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("earlier than the latest", result.stderr)


if __name__ == "__main__":
    unittest.main()
