#!/usr/bin/env bash
set -euo pipefail

# Runs on the operator's FileVault'd Mac (triggered by launchd, see
# deploy/com.carwal.backup.plist). Pull-based: this script, not the VPS,
# initiates every step.
#
# 1. SSH to the VPS to trigger backup-remote.sh (fresh pg_dump + prune).
# 2. rsync ~/carwal/backups/ and ~/carwal/media/ from the VPS into a local
#    staging directory over SSH (the "pull" — restic itself only reads
#    local paths, so the remote fetch happens here, not inside restic).
# 3. `restic backup` the local staging directory into the restic repo.
#
# Env contract (see deploy/README.md):
#   CARWAL_HOST         user@vps-host, same convention as deploy/deploy.sh
#   RESTIC_REPOSITORY   restic repo location (local path, sftp:, or rest:)
#   RESTIC_PASSWORD     restic repo password
# Loaded from a chmod 600 env file, path given as $1 (default: ~/.carwal-backup.env).

ENV_FILE="${1:-$HOME/.carwal-backup.env}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: backup env file not found at $ENV_FILE (see deploy/README.md)."
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

if [ -z "${CARWAL_HOST:-}" ] || [ -z "${RESTIC_REPOSITORY:-}" ] || [ -z "${RESTIC_PASSWORD:-}" ]; then
  echo "Error: CARWAL_HOST, RESTIC_REPOSITORY, and RESTIC_PASSWORD must all be set in $ENV_FILE."
  exit 1
fi
export RESTIC_REPOSITORY RESTIC_PASSWORD

STAGING_DIR="${CARWAL_BACKUP_STAGING:-$HOME/.carwal-backup-staging}"
mkdir -p "$STAGING_DIR/backups" "$STAGING_DIR/media"

echo "Shipping backup-remote.sh to $CARWAL_HOST..."
scp "$(dirname "$0")/backup-remote.sh" "$CARWAL_HOST":~/carwal/backup-remote.sh
ssh "$CARWAL_HOST" "chmod +x ~/carwal/backup-remote.sh"

echo "Triggering remote dump on $CARWAL_HOST..."
ssh "$CARWAL_HOST" "cd ~/carwal && ./backup-remote.sh"

echo "Pulling dumps and media from $CARWAL_HOST into $STAGING_DIR..."
rsync -az -e ssh "$CARWAL_HOST":~/carwal/backups/ "$STAGING_DIR/backups/"
rsync -az -e ssh "$CARWAL_HOST":~/carwal/media/ "$STAGING_DIR/media/"

echo "Running restic backup..."
restic backup "$STAGING_DIR" --tag carwal

echo "Backup complete."
