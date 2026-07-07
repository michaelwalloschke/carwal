#!/usr/bin/env bash
set -euo pipefail

# Runs on the operator's Mac. Restores the latest restic snapshot onto a
# scratch target (fresh Docker project, no existing carwal state) — never
# the live VPS. See Story 1.5 AC2 and deploy/RESTORE.md for the rehearsal
# record.
#
# Scratch target modes:
#   SCRATCH_HOST unset/empty  -> local scratch: a separate docker compose
#                                project (-p carwal-scratch) in $SCRATCH_DIR
#                                on this Mac, so it never touches your normal
#                                dev stack.
#   SCRATCH_HOST=user@host    -> remote scratch: ssh/scp/rsync to that host's
#                                ~/carwal/, same as deploy.sh's target style.
#
# Caddy is intentionally not started here: the rehearsal only needs to prove
# the app boots against restored data (AC2), not TLS/routing, so we talk to
# the app container directly via `docker compose exec`.
#
# Env contract (see deploy/README.md):
#   RESTIC_REPOSITORY   restic repo location (local path, sftp:, or rest:)
#   RESTIC_PASSWORD     restic repo password
# Loaded from a chmod 600 env file, path given as $1 (default: ~/.carwal-backup.env).

ENV_FILE="${1:-$HOME/.carwal-backup.env}"
SCRATCH_HOST="${SCRATCH_HOST:-}"
SCRATCH_DIR="${SCRATCH_DIR:-$HOME/.carwal-scratch}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: backup env file not found at $ENV_FILE (see deploy/README.md)."
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

if [ -z "${RESTIC_REPOSITORY:-}" ] || [ -z "${RESTIC_PASSWORD:-}" ]; then
  echo "Error: RESTIC_REPOSITORY and RESTIC_PASSWORD must both be set in $ENV_FILE."
  exit 1
fi
export RESTIC_REPOSITORY RESTIC_PASSWORD

# --- scratch-target helpers (local docker project vs. remote ssh host) -----

remote_run() {
  if [ -n "$SCRATCH_HOST" ]; then
    ssh "$SCRATCH_HOST" "set -euo pipefail; cd ~/carwal && $1"
  else
    bash -c "set -euo pipefail; cd \"$SCRATCH_DIR\" && $1"
  fi
}

remote_mkdir() {
  if [ -n "$SCRATCH_HOST" ]; then
    ssh "$SCRATCH_HOST" "mkdir -p ~/carwal/$1"
  else
    mkdir -p "$SCRATCH_DIR/$1"
  fi
}

copy_file() {
  # copy_file <local-src> <relative-dst-under-carwal>
  if [ -n "$SCRATCH_HOST" ]; then
    scp "$1" "$SCRATCH_HOST":~/carwal/"$2"
  else
    cp "$1" "$SCRATCH_DIR/$2"
  fi
}

copy_dir() {
  # copy_dir <local-src-dir> <relative-dst-under-carwal>
  if [ -n "$SCRATCH_HOST" ]; then
    rsync -az -e ssh "$1"/ "$SCRATCH_HOST":~/carwal/"$2"/
  else
    rsync -az "$1"/ "$SCRATCH_DIR/$2"/
  fi
}

if [ -n "$SCRATCH_HOST" ]; then
  echo "Scratch target: remote ($SCRATCH_HOST:~/carwal/)"
else
  echo "Scratch target: local docker project at $SCRATCH_DIR (compose -p carwal-scratch)"
fi

RESTORE_STAGING="${CARWAL_RESTORE_STAGING:-$HOME/.carwal-restore-staging}"
rm -rf "$RESTORE_STAGING"
mkdir -p "$RESTORE_STAGING"

echo "Restoring latest restic snapshot into $RESTORE_STAGING..."
restic restore latest --target "$RESTORE_STAGING"

DUMP_FILE=$(find "$RESTORE_STAGING" -name 'carwal-*.sql.gz' | sort | tail -n1)
if [ -z "$DUMP_FILE" ]; then
  echo "Error: no carwal-*.sql.gz dump found in the restored snapshot."
  exit 1
fi
MEDIA_DIR=$(find "$RESTORE_STAGING" -type d -name media | head -n1)
if [ -z "$MEDIA_DIR" ]; then
  echo "Warning: no media directory found in restored snapshot — skipping media restore."
fi

# Resolve repo root so relative copy_file/copy_dir source paths work from any CWD.
cd "$(dirname "$0")/.."

echo "Setting up scratch carwal directory..."
remote_mkdir ""
copy_file deploy/compose.yml compose.yml

echo "Copying restored media..."
remote_mkdir media
if [ -n "$MEDIA_DIR" ]; then
  copy_dir "$MEDIA_DIR" media
fi

echo "Copying restored dump..."
copy_file "$DUMP_FILE" restore-dump.sql.gz

COMPOSE="docker compose"
if [ -z "$SCRATCH_HOST" ]; then
  COMPOSE="docker compose -p carwal-scratch"
fi

echo "Starting database service and waiting for it to be healthy..."
remote_run "$COMPOSE up -d --wait --wait-timeout 120 db"

echo "Restoring the Postgres dump..."
remote_run "gunzip -c restore-dump.sql.gz | $COMPOSE exec -T db psql -U carwal carwal"

echo "Running migrations..."
remote_run "$COMPOSE run --rm app bin/carwal eval 'CarWal.Release.migrate()'"

echo "Starting application..."
remote_run "$COMPOSE up -d app"

echo "Polling app health endpoint..."
timeout=120
interval=3
deadline=$(( $(date +%s) + timeout ))
while true; do
  http_code=$(remote_run "$COMPOSE exec -T app curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:4000/health" || true)
  if [ "$http_code" = "200" ]; then
    echo "Restore verified! App health check passed."
    break
  fi
  echo "App is not healthy yet (HTTP status/code: $http_code). Waiting..."
  sleep $interval
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "Error: Health check timed out after $timeout seconds."
    exit 1
  fi
done

echo "Checking login page renders..."
login_code=$(remote_run "$COMPOSE exec -T app curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:4000/users/log-in" || true)
if [ "$login_code" != "200" ]; then
  echo "Error: login page smoke test failed (HTTP status/code: $login_code)."
  exit 1
fi
echo "Login page smoke test passed."
