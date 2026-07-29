#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEMO_DIR="${DEMO_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/it-manager-demo.XXXXXX")}"
OPS_DB="$DEMO_DIR/ops.sqlite"

if [[ -e "$OPS_DB" ]]; then
  echo "Error: demo DB already exists: $OPS_DB" >&2
  exit 2
fi

mkdir -p "$DEMO_DIR"
export OPS_DB

"$ROOT_DIR/scripts/register-endpoint.sh" \
  --employee-id DEMO-001 \
  --username demo.user \
  --computer-name PC-DEMO01 \
  --status registered \
  --output-dir "$DEMO_DIR"

python3 "$ROOT_DIR/scripts/asset-lifecycle.py" \
  --asset PC-DEMO01 \
  --action stock \
  --ticket-ref ASSET-DEMO-STOCK \
  --reason "Receive demo endpoint into IT stock" \
  --expected-status registered \
  --approved-by it.manager \
  --confirm-asset PC-DEMO01 \
  --execute \
  --at 2026-07-29T00:00:00+00:00 \
  --output-dir "$DEMO_DIR"

python3 "$ROOT_DIR/scripts/asset-lifecycle.py" \
  --asset PC-DEMO01 \
  --action assign \
  --owner demo.user \
  --ticket-ref ASSET-DEMO-ASSIGN \
  --reason "Issue demo endpoint to test identity" \
  --expected-status in_stock \
  --approved-by it.manager \
  --confirm-asset PC-DEMO01 \
  --execute \
  --at 2026-07-29T00:05:00+00:00 \
  --output-dir "$DEMO_DIR"

python3 "$ROOT_DIR/scripts/helpdesk-ticket.py" --db "$OPS_DB" open \
  --ticket-ref HD-DEMO-001 \
  --actor demo.user \
  --priority p2 \
  --scenario sso \
  --target demo.user \
  --summary "SSO redirect returns to login" \
  --recurrence-key sso-login-loop \
  --at 2026-07-29T01:00:00+00:00 \
  --output-dir "$DEMO_DIR"

python3 "$ROOT_DIR/scripts/helpdesk-ticket.py" --db "$OPS_DB" respond \
  --ticket-ref HD-DEMO-001 \
  --actor helpdesk.agent \
  --note "Identity path triage started" \
  --at 2026-07-29T01:20:00+00:00 \
  --output-dir "$DEMO_DIR"

OPS_DB="$OPS_DB" "$ROOT_DIR/scripts/helpdesk-diagnose.sh" \
  --scenario sso \
  --username demo.user \
  --symptom "SSO redirect returns to login" \
  --network office-wifi \
  --occurred-at "2026-07-29 10:00 KST" \
  --output-dir "$DEMO_DIR"

python3 "$ROOT_DIR/scripts/helpdesk-ticket.py" --db "$OPS_DB" resolve \
  --ticket-ref HD-DEMO-001 \
  --actor helpdesk.agent \
  --resolution "Fixture triage completed without a live infrastructure change" \
  --at 2026-07-29T03:00:00+00:00 \
  --output-dir "$DEMO_DIR"

python3 "$ROOT_DIR/scripts/helpdesk-metrics.py" \
  --db "$OPS_DB" \
  --from 2026-07-01T00:00:00+00:00 \
  --to 2026-08-01T00:00:00+00:00 \
  --output-dir "$DEMO_DIR"

OPS_DB="$OPS_DB" "$ROOT_DIR/scripts/offboard-employee.sh" \
  --username demo.user \
  --ticket-ref OFF-DEMO-001 \
  --reason "Portfolio fixture" \
  --output-dir "$DEMO_DIR"

cat <<EOF

IT Manager demo completed.
Classification: simulation
Infrastructure changes: none
Demo directory: $DEMO_DIR
Operations DB: $OPS_DB
EOF
