#!/usr/bin/env bash
set -euo pipefail
readonly source_path=/var/backups/wazuh-indexer
readonly replica_path=/mnt/wazuh-snapshot-replica
readonly state_path=/var/lib/wazuh-snapshot-replica
readonly marker="${replica_path}/.last-success"
exec 9>"${state_path}/lock"
flock -n 9 || exit 0
mountpoint -q "${replica_path}"
test -f "${source_path}/index.latest"
rsync --recursive --links --times --delete --no-owner --no-group --chmod=Du=rwx,Dg=rx,Do=,Fu=rw,Fg=r,Fo= "${source_path}/" "${replica_path}/"
date -u +%FT%TZ >"${marker}.tmp"
mv -f "${marker}.tmp" "${marker}"
sync -f "${replica_path}"
