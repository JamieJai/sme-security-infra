#!/usr/bin/env bash
set -euo pipefail

readonly ALLOWED_TARGET="192.168.0.77"
readonly ALLOWED_NAME="ODJ-VERIFY01"
readonly EXECUTION_ACK="${ALLOWED_NAME}:${ALLOWED_TARGET}"
readonly INITIAL_PORTS="22,445,3389,5985,5986"

target=""
execute=false
output_dir=""

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/kali-purple-team-scan.sh --target 192.168.0.77 [--execute] [--output-dir DIR]

The default mode prints the exact single-target nmap command without running it.
Live execution requires:

  PURPLE_TEAM_ACK=ODJ-VERIFY01:192.168.0.77 \
    ./scripts/kali-purple-team-scan.sh --target 192.168.0.77 --execute

CIDR ranges, hostnames, alternate IPs, nmap scripts, service detection, and
credential attacks are intentionally outside this initial validation wrapper.
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || die "--target requires a value"
      target="$2"
      shift 2
      ;;
    --execute)
      execute=true
      shift
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || die "--output-dir requires a value"
      output_dir="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$target" ]] || die "--target is required"
[[ "$target" == "$ALLOWED_TARGET" ]] || die "target must be exactly $ALLOWED_TARGET ($ALLOWED_NAME)"
[[ "$target" != */* ]] || die "CIDR targets are not allowed"

scan_command=(
  nmap
  -Pn
  -sT
  -n
  --max-retries
  2
  --host-timeout
  2m
  -p
  "$INITIAL_PORTS"
  "$target"
)

if [[ "$execute" != "true" ]]; then
  printf 'Dry run only. Approved command:'
  printf ' %q' "${scan_command[@]}"
  printf '\n'
  exit 0
fi

[[ "${PURPLE_TEAM_ACK:-}" == "$EXECUTION_ACK" ]] || {
  die "set PURPLE_TEAM_ACK=$EXECUTION_ACK for live execution"
}
command -v nmap >/dev/null 2>&1 || die "nmap is required"

if [[ -z "$output_dir" ]]; then
  script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  output_dir="$script_root/artifacts/kali-validation"
fi

mkdir -p "$output_dir"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output_base="$output_dir/${timestamp}-odj-verify01-initial-ports"

printf 'Scope: %s / %s\n' "$ALLOWED_NAME" "$ALLOWED_TARGET"
printf 'UTC start: %s\n' "$timestamp"
printf 'Evidence base: %s\n' "$output_base"

"${scan_command[@]}" -oA "$output_base"

printf 'Completed single-target scan. Evidence: %s.{nmap,gnmap,xml}\n' "$output_base"
