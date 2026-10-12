#!/usr/bin/env bash
# Daily backup of the Optics database (and uploaded media) to Cloudflare R2.
#
# Needs (from /srv/optics/.env.production): DATABASE_URL, R2_ACCOUNT_ID, R2_BUCKET,
# AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY (R2 API token), optionally BACKUP_DIR,
# BACKUP_KEEP_DAYS. Tools: pg_dump (postgresql-client), aws (awscli).
# Restore: aws s3 cp s3://$R2_BUCKET/db/<file> . --endpoint-url ... && pg_restore -d <db> --clean <file>
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL is not set}"
: "${R2_ACCOUNT_ID:?R2_ACCOUNT_ID is not set}"
: "${R2_BUCKET:?R2_BUCKET is not set}"
BACKUP_DIR="${BACKUP_DIR:-/srv/optics/backups}"
KEEP_DAYS="${BACKUP_KEEP_DAYS:-7}"
MEDIA_DIR="${MEDIA_ROOT:-/srv/optics/media}"
ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
export AWS_DEFAULT_REGION=auto

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BACKUP_DIR"
dump="$BACKUP_DIR/optics-$stamp.dump"

# Custom format: compressed, restorable table by table with pg_restore.
pg_dump --format=custom --no-owner --no-privileges --dbname="$DATABASE_URL" --file="$dump"
pg_restore --list "$dump" > /dev/null   # fails if the dump is unreadable

aws s3 cp "$dump" "s3://$R2_BUCKET/db/$(basename "$dump")" --endpoint-url "$ENDPOINT" --only-show-errors
# Logos and installers (only changed files are sent).
if [ -d "$MEDIA_DIR" ]; then
  aws s3 sync "$MEDIA_DIR" "s3://$R2_BUCKET/media/" --endpoint-url "$ENDPOINT" --only-show-errors
fi

# Local copies: keep a few days (R2 keeps the history; set a lifecycle rule there, e.g. 60 days).
find "$BACKUP_DIR" -name 'optics-*.dump' -mtime +"$KEEP_DAYS" -delete
echo "backup ok: $(basename "$dump") ($(du -h "$dump" | cut -f1))"
