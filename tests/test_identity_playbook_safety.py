import pathlib
import unittest

import yaml


ROOT_DIR = pathlib.Path(__file__).resolve().parents[1]
PLAYBOOK_DIR = ROOT_DIR / "ansible" / "playbooks"


def load_tasks(filename):
    plays = yaml.safe_load((PLAYBOOK_DIR / filename).read_text())
    return {
        task["name"]: task
        for play in plays
        for task in play.get("tasks", [])
        if "name" in task
    }


class IdentityPlaybookSafetyTests(unittest.TestCase):
    def test_ad_passwords_use_environment_and_samba_helper(self):
        tasks = load_tasks("ad-onboard-user.yml")
        for task_name in (
            "Create AD user",
            "Reset existing AD user password when requested",
        ):
            task = tasks[task_name]
            script = task["ansible.builtin.script"]
            self.assertNotIn("ad_user_password", script["cmd"])
            self.assertIn("samba_user_password.py", script["cmd"])
            self.assertIn("--must-change", script["cmd"])
            self.assertEqual(
                task["environment"]["AD_USER_PASSWORD"],
                "{{ ad_user_password }}",
            )
            self.assertTrue(task["no_log"])

        playbook = (PLAYBOOK_DIR / "ad-onboard-user.yml").read_text()
        self.assertNotIn("user setexpiry", playbook)

    def test_ad_enabled_state_converges_in_both_directions(self):
        tasks = load_tasks("ad-onboard-user.yml")
        for task_name in ("Enable AD user", "Disable AD user when requested"):
            with self.subTest(task=task_name):
                task = tasks[task_name]
                conditions = " ".join(task["when"])
                self.assertIn("ad_user_enabled", conditions)
                self.assertIn("ad_user_uac", conditions)
                self.assertNotIn("failed_when", task)

    def test_ad_lookup_only_tolerates_an_absent_user(self):
        task = load_tasks("ad-onboard-user.yml")[
            "Check whether AD user already exists"
        ]
        failure_rule = " ".join(task["failed_when"])
        self.assertIn("rc != 0", failure_rule)
        self.assertIn("unable to find user", failure_rule)

    def test_nextcloud_lookups_only_tolerate_an_absent_user(self):
        playbooks = (
            "employee-offboarding.yml",
            "employee-offboarding-verify.yml",
            "employee-offboarding-recovery.yml",
            "employee-offboarding-recovery-verify.yml",
        )
        for filename in playbooks:
            with self.subTest(playbook=filename):
                task = load_tasks(filename)["Read the matching Nextcloud user"]
                command = task["ansible.builtin.command"]
                self.assertIn("--output=json", command["argv"])
                failure_rule = " ".join(task["failed_when"])
                self.assertIn("rc != 0", failure_rule)
                self.assertIn("user not found", failure_rule)

    def test_nextcloud_state_checks_parse_json(self):
        cases = (
            ("employee-offboarding.yml", "Disable the matching Nextcloud user"),
            (
                "employee-offboarding-verify.yml",
                "Verify the matching Nextcloud user is disabled",
            ),
            (
                "employee-offboarding-recovery.yml",
                "Enable the matching Nextcloud user",
            ),
            (
                "employee-offboarding-recovery-verify.yml",
                "Verify the matching Nextcloud user is enabled",
            ),
        )
        for filename, task_name in cases:
            with self.subTest(playbook=filename, task=task_name):
                task = load_tasks(filename)[task_name]
                expressions = str(task.get("when", ""))
                expressions += str(
                    task.get("ansible.builtin.assert", {}).get("that", "")
                )
                self.assertIn("from_json", expressions)


if __name__ == "__main__":
    unittest.main()
