#!/usr/bin/env bash
# Restore an Optics backup from Cloudflare R2 (or a local .dump file).
#
#   sudo optics-restore --list                     # backups available in R2
#   sudo optics-restore                            # TEST: latest backup → scratch DB optics_restore_test
#   sudo optics-restore --file optics-20261031T031500Z.dump      # TEST with a specific backup
#   sudo optics-restore --file latest --live       # REAL restore over the live database (asks first)
#   sudo optics-restore --media                    # copy uploaded files (logos, installers) back from R2
#
# A test restore never touches the live database. A live restore stops the API, first saves the
# current database to /srv/optics/backups/pre-restore-*.dump, restores in one transaction (all or
# nothing), then starts the API again.
set -euo pipefail

ENV_FILE=/srv/optics/.env.production
AWS=/srv/optics/tools-venv/bin/aws
SCRATCH_DB=optics_restore_test

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo." >&2; exit 1; }
[ -r "$ENV_FILE" ] || { echo "Missing $ENV_FILE" >&2; exit 1; }
set -a; . "$ENV_FILE"; set +a

: "${DATABASE_URL:?}" "${R2_ACCOUNT_ID:?}" "${R2_BUCKET:?}"
ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
BACKUP_DIR="${BACKUP_DIR:-/srv/optics/backups}"
MEDIA_DIR="${MEDIA_ROOT:-/srv/optics/media}"
export AWS_DEFAULT_REGION=auto AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
       AWS_RESPONSE_CHECKSUM_VALIDATION=when_required

file="latest"; live=0; mode=restore
while [ $# -gt 0 ]; do
  case "$1" in
    --list)  mode=list ;;
    --media) mode=media ;;
    --live)  live=1 ;;
    --file)  file="${2:?--file needs a name}"; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

r2() { sudo -u optics -E "$AWS" s3 "$@" --endpoint-url "$ENDPOINT" --only-show-errors; }

if [ "$mode" = list ]; then
  sudo -u optics -E "$AWS" s3 ls "s3://$R2_BUCKET/db/" --endpoint-url "$ENDPOINT" | sort
  exit 0
fi

if [ "$mode" = media ]; then
  echo "Copying uploaded files from R2 into $MEDIA_DIR (existing files are kept)..."
  r2 sync "s3://$R2_BUCKET/media/" "$MEDIA_DIR"
  chown -R optics:www-data "$MEDIA_DIR"
  echo "media restored."
  exit 0
fi

# --- pick the dump ------------------------------------------------------------------
mkdir -p "$BACKUP_DIR"
if [ -f "$file" ]; then
  dump="$file"
else
  if [ "$file" = latest ]; then
    file="$(sudo -u optics -E "$AWS" s3 ls "s3://$R2_BUCKET/db/" --endpoint-url "$ENDPOINT" \
            | awk '{print $4}' | grep '^optics-.*\.dump$' | sort | tail -n1)"
    [ -n "$file" ] || { echo "No backups found in R2." >&2; exit 1; }
  fi
  dump="$BACKUP_DIR/$file"
  [ -f "$dump" ] || r2 cp "s3://$R2_BUCKET/db/$file" "$dump"
fi
pg_restore --list "$dump" > /dev/null
echo "Backup: $dump"

# Database URL with another database name (same host/user/password).
url_for_db() {
  python3 -c 'import sys, urllib.parse as u; p = u.urlsplit(sys.argv[1]); print(u.urlunsplit(p._replace(path="/" + sys.argv[2])))' "$DATABASE_URL" "$1"
}
db_part() {
  python3 -c 'import sys, urllib.parse as u; p = u.urlsplit(sys.argv[1]); print({"name": p.path.lstrip("/"), "user": u.unquote(p.username or ""), "host": p.hostname or ""}[sys.argv[2]])' "$DATABASE_URL" "$1"
}
DB_NAME="$(db_part name)"; DB_USER="$(db_part user)"; DB_HOST="$(db_part host)"

if [ "$live" -eq 0 ]; then
  # --- test restore into a scratch database ----------------------------------------
  case "$DB_HOST" in 127.0.0.1|localhost|::1|"") ;;
    *) echo "Test restore needs the local PostgreSQL. With an external database server, create" >&2
       echo "an empty database there and run: pg_restore --no-owner -d <its URL> $dump" >&2; exit 1 ;;
  esac
  sudo -u postgres dropdb --if-exists "$SCRATCH_DB"
  sudo -u postgres createdb -O "$DB_USER" "$SCRATCH_DB"
  pg_restore --no-owner --no-privileges --exit-on-error --dbname="$(url_for_db "$SCRATCH_DB")" "$dump"
  echo "Restored into scratch database '$SCRATCH_DB'. Row counts:"
  psql "$(url_for_db "$SCRATCH_DB")" -At -c "
    SELECT 'labs', count(*) FROM labs_lab UNION ALL
    SELECT 'patients', count(*) FROM patients_patient UNION ALL
    SELECT 'stock movements', count(*) FROM inventory_stockmovement;" 2>/dev/null \
    | sed 's/|/: /' || true
  sudo -u postgres dropdb "$SCRATCH_DB"
  echo "Test restore OK (scratch database removed). The live database was not touched."
  exit 0
fi

# --- live restore -------------------------------------------------------------------
echo
echo "!! This REPLACES the live database '$DB_NAME' with $(basename "$dump")."
echo "!! Everything entered after that backup was taken will be lost."
read -r -p "Type RESTORE to continue: " answer
[ "$answer" = RESTORE ] || { echo "Cancelled."; exit 1; }

safety="$BACKUP_DIR/pre-restore-$(date -u +%Y%m%dT%H%M%SZ).dump"
echo "Saving the current database to $safety ..."
sudo -u optics pg_dump --format=custom --no-owner --no-privileges --dbname="$DATABASE_URL" --file="$safety"

systemctl stop optics-api
trap 'systemctl start optics-api' EXIT
pg_restore --clean --if-exists --no-owner --no-privileges --single-transaction --exit-on-error \
  --dbname="$DATABASE_URL" "$dump"
echo "Live database restored from $(basename "$dump")."
echo "If something is wrong, restore the safety copy: sudo optics-restore --file $safety --live"
