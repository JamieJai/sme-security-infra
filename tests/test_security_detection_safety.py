import json
import pathlib
import unittest
import xml.etree.ElementTree as ET

import yaml


ROOT_DIR = pathlib.Path(__file__).resolve().parents[1]
RULES = ROOT_DIR / "ansible" / "files" / "wazuh" / "rules" / "sme_rules.xml"
FIXTURES = ROOT_DIR / "ansible" / "files" / "wazuh" / "fixtures"
RUNNER = ROOT_DIR / "ansible" / "files" / "wazuh" / "test-detections.sh"
WINDOWS_PLAYBOOK = ROOT_DIR / "ansible" / "playbooks" / "wazuh-agent-windows.yml"


class SecurityDetectionSafetyTests(unittest.TestCase):
    def test_wfp_block_and_burst_rules_are_scoped(self):
        root = ET.parse(RULES).getroot()
        rules = {rule.attrib["id"]: rule for rule in root.findall("rule")}

        blocked = rules["100506"]
        self.assertEqual(blocked.attrib["level"], "7")
        fields = {
            field.attrib["name"]: field.text for field in blocked.findall("field")
        }
        self.assertEqual(fields["win.system.eventID"], "^5157$")
        self.assertEqual(fields["win.system.channel"], "^Security$")
        self.assertEqual(blocked.findtext("mitre/id"), "T1046")

        burst = rules["100507"]
        self.assertEqual(burst.attrib["frequency"], "5")
        self.assertEqual(burst.attrib["timeframe"], "60")
        self.assertEqual(burst.findtext("if_matched_sid"), "100506")
        self.assertEqual(
            burst.findtext("same_field"), "win.eventdata.sourceAddress"
        )

    def test_wfp_fixtures_pin_the_lab_scope_and_negative_case(self):
        blocked = json.loads(
            (FIXTURES / "windows-5157-blocked-connection.log").read_text()
        )
        allowed = json.loads(
            (FIXTURES / "windows-5156-allowed-connection.log").read_text()
        )
        self.assertEqual(blocked["win"]["system"]["eventID"], "5157")
        self.assertEqual(
            blocked["win"]["eventdata"]["sourceAddress"], "192.168.0.37"
        )
        self.assertEqual(
            blocked["win"]["eventdata"]["destAddress"], "192.168.0.77"
        )
        self.assertEqual(allowed["win"]["system"]["eventID"], "5156")

        runner = RUNNER.read_text()
        self.assertIn("windows-5157-blocked-connection 100506", runner)
        self.assertIn("windows-5157-blocked-connection 100507 6", runner)
        self.assertIn("windows-5156-allowed-connection 100506", runner)

    def test_wfp_audit_policy_defaults_to_observe_and_pilot_targets(self):
        source = WINDOWS_PLAYBOOK.read_text()
        plays = yaml.safe_load(source)
        endpoint_play = plays[1]
        self.assertEqual(
            endpoint_play["vars"]["wazuh_windows_filtering_platform_audit_state"],
            "observe",
        )
        self.assertEqual(
            endpoint_play["vars"]["wazuh_windows_filtering_platform_audit_targets"],
            [],
        )
        self.assertEqual(
            endpoint_play["vars"]["wazuh_windows_filtering_platform_audit_baseline"],
            "unconfirmed",
        )
        self.assertIn(
            "/subcategory:{0CCE9226-69AE-11D9-BED3-505054503030}",
            source,
        )
        self.assertNotIn('/subcategory:"Filtering Platform Connection"', source)
        self.assertIn("difference(groups['windows_endpoint_pilot'])", source)
        self.assertIn("/success:disable /failure:enable", source)
        self.assertIn("/success:disable /failure:disable", source)
        self.assertIn("Refusing to replace an existing", source)
        self.assertLess(
            source.index("Require a safe audit baseline or the desired idempotent state"),
            source.index("Enable failed Filtering Platform Connection"),
        )


if __name__ == "__main__":
    unittest.main()
