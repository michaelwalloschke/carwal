#!/usr/bin/env bash
set -euo pipefail

# Runs on the VPS (via SSH from deploy/backup.sh, or SSH'd into directly).
# Dumps Postgres to a gzipped SQL file under ~/carwal/backups/ and prunes
# dumps older than KEEP_DAYS. restic (run from the Mac) keeps the real
# long-term history; this local retention only bounds VPS disk usage
# between backup runs.

KEEP_DAYS="${KEEP_DAYS:-7}"
BACKUP_DIR=~/carwal/backups
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DUMP_FILE="$BACKUP_DIR/carwal-$TIMESTAMP.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "Dumping carwal database to $DUMP_FILE..."
cd ~/carwal
docker compose exec -T db pg_dump -U carwal carwal | gzip > "$DUMP_FILE"

echo "Pruning dumps older than $KEEP_DAYS days..."
find "$BACKUP_DIR" -name 'carwal-*.sql.gz' -mtime "+$KEEP_DAYS" -print -delete

echo "Backup dump complete: $DUMP_FILE"
