#!/usr/bin/env bash
set -euo pipefail

# Minimal smoke test for the Story 1.5 backup/restore scripts: syntax checks
# plus the "fail fast on missing config" guards, since these scripts touch
# backups/restores and a silent wrong-path failure is expensive to debug.
# Run manually: ./deploy/test-backup-scripts.sh

cd "$(dirname "$0")"
fail=0

check() {
  local desc="$1"; shift
  if "$@"; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc"
    fail=1
  fi
}

for script in backup-remote.sh backup.sh restore.sh; do
  check "$script has valid bash syntax" bash -n "$script"
done

check "backup.sh rejects a missing env file" \
  bash -c '! ./backup.sh /nonexistent-env-file 2>/dev/null'

check "restore.sh rejects a missing env file" \
  bash -c '! ./restore.sh /nonexistent-env-file 2>/dev/null'

if [ "$fail" -ne 0 ]; then
  echo "One or more checks failed."
  exit 1
fi
echo "All backup/restore script checks passed."
