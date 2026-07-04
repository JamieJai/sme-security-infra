#!/usr/bin/env bash
set -euo pipefail
readonly base_url=http://127.0.0.1:19201
readonly state_dir=/var/lib/wazuh-restore-test-state
readonly repository=wazuh-offsite-restore-test
cleanup() {
  curl -fsS -X DELETE "${base_url}/restore-test-*" >/dev/null 2>&1 || true
  systemctl stop wazuh-restore-test-indexer.service >/dev/null 2>&1 || true
}
trap cleanup EXIT
systemctl start wazuh-restore-test-indexer.service
for _ in $(seq 1 90); do
  curl -fsS "${base_url}/_cluster/health" >/dev/null 2>&1 && break
  sleep 2
done
curl -fsS "${base_url}/_cluster/health" >/dev/null
curl -sS -X DELETE "${base_url}/restore-test-*" >/dev/null 2>&1 || true
curl -fsS -X PUT -H 'Content-Type: application/json' "${base_url}/_snapshot/${repository}" \
  --data '{"type":"fs","settings":{"location":"/mnt/wazuh-snapshot-replica","readonly":true}}' >/dev/null
snapshot=$(curl -fsS "${base_url}/_snapshot/${repository}/_all" | python3 -c 'import json,sys; s=[x for x in json.load(sys.stdin).get("snapshots",[]) if x.get("state")=="SUCCESS"]; assert s; print(sorted(s,key=lambda x:x.get("end_time_in_millis",0))[-1]["snapshot"])')
curl -fsS -X POST -H 'Content-Type: application/json' \
  "${base_url}/_snapshot/${repository}/${snapshot}/_restore?wait_for_completion=true" \
  --data '{"indices":"wazuh-alerts-4.x-*","ignore_unavailable":true,"include_global_state":false,"rename_pattern":"wazuh-alerts-4.x-(.+)","rename_replacement":"restore-test-$1"}' \
  | python3 -c 'import json,sys; j=json.load(sys.stdin); assert not j.get("error"), j; assert j.get("snapshot",{}).get("shards",{}).get("successful",0) > 0, j'
curl -fsS "${base_url}/_cluster/health/restore-test-*?wait_for_status=yellow&timeout=60s" >/dev/null
count=$(curl -fsS "${base_url}/restore-test-*/_count" | python3 -c 'import json,sys; j=json.load(sys.stdin); assert "count" in j, j; print(j["count"])')
install -d -o root -g root -m 0700 "${state_dir}"
printf '%s snapshot=%s documents=%s\n' "$(date -u +%FT%TZ)" "$snapshot" "$count" >"${state_dir}/last-success.tmp"
mv -f "${state_dir}/last-success.tmp" "${state_dir}/last-success"
