import importlib.util, json, sqlite3, tempfile, unittest
from pathlib import Path
HERE = Path(__file__).parent
spec = importlib.util.spec_from_file_location("shadow", HERE / "wazuh_ai_shadow.py")
shadow = importlib.util.module_from_spec(spec); spec.loader.exec_module(shadow)

class ShadowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); root = Path(self.tmp.name)
        self.source, self.dbpath = root / "alerts.json", root / "spool.db"
        self.db = shadow.connect(self.dbpath)
    def tearDown(self): self.db.close(); self.tmp.cleanup()
    def write(self, events):
        with self.source.open("a") as f:
            for event in events: f.write(json.dumps(event) + "\n")
    def event(self, suffix="1"):
        return {"timestamp":"2026-07-04T10:00:00Z","rule":{"id":"10010"+suffix,"level":10,"description":"Login a@corp.test","groups":["auth"]},"agent":{"id":"001","name":"mail01"},"decoder":{"name":"json"},"location":"journald","data":{"srcip":"192.0.2.5","password":"never-store"},"full_log":"Authorization: secret"}
    def test_redaction_offset_dedup_and_enrichment(self):
        self.write([self.event(), self.event()])
        self.assertEqual(shadow.collect_once(self.db,self.source,100,False),2)
        self.assertEqual(shadow.collect_once(self.db,self.source,100,False),0)
        rows=self.db.execute("select event_json from events").fetchall()
        self.assertTrue(all("never-store" not in x[0] and "Authorization" not in x[0] and "<redacted-email>" in x[0] for x in rows))
        self.assertEqual(shadow.enrich_once(self.db),2)
        result=json.loads(self.db.execute("select enrichment_json from events limit 1").fetchone()[0])
        self.assertEqual(result["correlated_5m"],2); self.assertFalse(result["notification"]); self.assertFalse(result["automated_action"])
    def test_rotation_and_bounded_pending_spool(self):
        self.write([self.event("1"),self.event("2"),self.event("3")])
        self.assertEqual(shadow.collect_once(self.db,self.source,2,False),2)
        self.assertEqual(shadow.collect_once(self.db,self.source,2,False),0)
        self.source.unlink(); self.write([self.event("4")])
        shadow.enrich_once(self.db); shadow.trim_spool(self.db,1)
        self.assertEqual(self.db.execute("select count(*) from events").fetchone()[0],1)

    def test_metrics_report(self):
        self.write([self.event(), self.event(), {"not": "wazuh"}])
        with self.source.open("a") as f:
            f.write("{bad json\n")
        self.assertEqual(shadow.collect_once(self.db,self.source,100,False),3)
        self.assertEqual(shadow.enrich_once(self.db),3)
        report = shadow.build_report(self.db)
        self.assertEqual(report["events_enriched"],3)
        self.assertEqual(report["events_pending"],0)
        self.assertEqual(report["seen_total"],4)
        self.assertEqual(report["invalid_json_total"],1)
        self.assertEqual(report["redaction_leak_count"],0)
        self.assertIsNotNone(report["latency_seconds_p95"])
        self.assertIn("event_loss_indicators", report)

if __name__ == "__main__": unittest.main()
