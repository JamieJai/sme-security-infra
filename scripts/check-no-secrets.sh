#!/usr/bin/env bash
set -euo pipefail

tmp_files="$(mktemp)"
tmp_hits="$(mktemp)"
cleanup() {
  rm -f "$tmp_files" "$tmp_hits"
}
trap cleanup EXIT

git diff --cached --name-only -z \
  | grep -zv '^scripts/check-no-secrets\.sh$' \
  > "$tmp_files" || true

if [[ ! -s "$tmp_files" ]]; then
  exit 0
fi

patterns=(
  'hooks\.slack\.com/services/[A-Za-z0-9/_-]+'
  'xox[baprs]-[A-Za-z0-9-]+'
  'secret_[A-Za-z0-9]{20,}'
  'ntn_[A-Za-z0-9]{20,}'
  'github_pat_[A-Za-z0-9_]+'
  'ghp_[A-Za-z0-9]{20,}'
)

for pattern in "${patterns[@]}"; do
  if xargs -0 -r grep -nE "$pattern" -- < "$tmp_files" > "$tmp_hits" 2>/dev/null; then
    echo "Secret-like value detected in staged files:" >&2
    sed -E \
      -e 's#(hooks\.slack\.com/services/).*#\1<redacted>#' \
      -e 's#(xox[baprs]-)[A-Za-z0-9-]+#\1<redacted>#g' \
      -e 's#(secret_|ntn_|github_pat_|ghp_)[A-Za-z0-9_]+#\1<redacted>#g' \
      "$tmp_hits" >&2
    exit 1
  fi
done
