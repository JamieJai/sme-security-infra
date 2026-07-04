#!/usr/bin/env bash
set -euo pipefail

logtest=/var/ossec/bin/wazuh-logtest
fixture_dir=${1:-/var/ossec/tmp/sme-detection-fixtures}

run_test() {
  local fixture=$1
  local expected_rule=$2
  local repeat=${3:-1}
  local output

  output=$(for ((i = 0; i < repeat; i++)); do
    cat "${fixture_dir}/${fixture}.log"
  done | "${logtest}" 2>&1)

  if ! grep -Fq "id: '${expected_rule}'" <<<"${output}"; then
    printf 'FAIL fixture=%s expected_rule=%s\n' "${fixture}" "${expected_rule}" >&2
    printf '%s\n' "${output}" >&2
    return 1
  fi

  printf 'PASS fixture=%s rule=%s\n' "${fixture}" "${expected_rule}"
}

run_test keycloak-login-error 100201
run_test keycloak-login-error 100202 6
run_test nextcloud-login-error 100101
run_test nextcloud-login-error 100102 6
run_test dovecot-login-error 9705
run_test dovecot-login-error 100301 6
run_test samba-replication-auth-error 100401
