#!/usr/bin/env bash
set -euo pipefail

base_url=https://127.0.0.1:9200
repository=wazuh-alerts
cert=/etc/wazuh-indexer/certs/admin.pem
key=/etc/wazuh-indexer/certs/admin-key.pem
ca=/etc/wazuh-indexer/certs/root-ca.pem
snapshot="wazuh-alerts-$(date -u +%Y%m%d)"

curl_args=(--silent --show-error --fail --cert "$cert" --key "$key" --cacert "$ca")

if ! curl "${curl_args[@]}" "${base_url}/_snapshot/${repository}/${snapshot}" >/dev/null 2>&1; then
  curl "${curl_args[@]}" -X PUT -H 'Content-Type: application/json' "${base_url}/_snapshot/${repository}/${snapshot}?wait_for_completion=true" --data '{"indices":"wazuh-alerts-4.x-*","ignore_unavailable":true,"include_global_state":false}' >/dev/null
fi

cutoff=$(date -u -d '90 days ago' +%Y%m%d)
while IFS= read -r expired; do
  test -n "$expired" || continue
  curl "${curl_args[@]}" -X DELETE "${base_url}/_snapshot/${repository}/${expired}" >/dev/null
done < <(
  curl "${curl_args[@]}" "${base_url}/_snapshot/${repository}/_all" |
  python3 -c 'import json,re,sys; cutoff=sys.argv[1]; print("\n".join(item["snapshot"] for item in json.load(sys.stdin).get("snapshots", []) if re.fullmatch(r"wazuh-alerts-(\d{8})", item.get("snapshot", "")) and item["snapshot"].rsplit("-",1)[1] < cutoff))' "$cutoff"
)
