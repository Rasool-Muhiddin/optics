# Shared helpers for deploy/setup-server.sh and deploy/update.sh (sourced, not run).
# Fixed layout (also baked into the systemd units and the nginx template):
#   /srv/optics/app            git checkout          /srv/optics/venv         app virtualenv
#   /srv/optics/.env.production secrets (chmod 600)  /srv/optics/tools-venv   awscli for backups
#   /srv/optics/deploy.conf    choices made by setup-server.sh (domain, TLS mode, ...)
#   /srv/optics/{static,media,cache,backups}

OPTICS_HOME=/srv/optics
APP_DIR=$OPTICS_HOME/app
VENV=$OPTICS_HOME/venv
TOOLS_VENV=$OPTICS_HOME/tools-venv
ENV_FILE=$OPTICS_HOME/.env.production
DEPLOY_CONF=$OPTICS_HOME/deploy.conf
NGINX_SITE=/etc/nginx/sites-available/optics-api
ACME_ROOT=/var/www/optics-acme
CF_CERT=/etc/ssl/cloudflare/optics-api.pem
CF_KEY=/etc/ssl/cloudflare/optics-api.key

if [ -t 1 ]; then B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'; else B= G= Y= R= N=; fi
step() { echo; echo "${B}==> $*${N}"; }
ok()   { echo "${G}    ok${N} $*"; }
warn() { echo "${Y}    warning:${N} $*"; }
die()  { echo "${R}ERROR:${N} $*" >&2; exit 1; }

require_root() { [ "$(id -u)" -eq 0 ] || die "run with sudo (e.g. sudo bash $0)"; }

# Run manage.py as the optics user with the production environment.
manage() {
  (cd "$APP_DIR/backend" && sudo -u optics bash -c '
    set -a; . "$0"; set +a
    export DJANGO_SETTINGS_MODULE=config.settings.production
    exec "$1/bin/python" manage.py "${@:2}"' "$ENV_FILE" "$VENV" "$@")
}

# Value of KEY in the env file (empty if absent).
env_get() { sed -n "s/^$1=//p" "$ENV_FILE" | tail -n1; }

# Set KEY=VALUE in the env file (replaces the line, or appends it).
env_set() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp)"
  awk -v k="$key" -v v="$value" 'BEGIN{done=0}
    $0 ~ "^"k"=" { if (!done) print k"="v; done=1; next } { print }
    END { if (!done) print k"="v }' "$ENV_FILE" > "$tmp"
  cat "$tmp" > "$ENV_FILE"; rm -f "$tmp"
}

# Refuse to start the API with placeholder secrets; warn about optional ones.
check_env_file() {
  [ -f "$ENV_FILE" ] || die "$ENV_FILE is missing (run deploy/setup-server.sh)"
  local v
  v="$(env_get SECRET_KEY)"
  { [ "${#v}" -ge 50 ] && [[ "$v" != *change-me* ]]; } || die "SECRET_KEY in $ENV_FILE is missing or a placeholder"
  [[ "$(env_get DATABASE_URL)" != *CHANGE_ME* ]] || die "DATABASE_URL in $ENV_FILE still has the CHANGE_ME password"
  [[ "$(env_get ADMIN_URL)" != *CHANGE-ME* ]] || die "ADMIN_URL in $ENV_FILE is still the placeholder"
  # Keys added to the example after this env file was created.
  local key
  for key in $(sed -n 's/^\([A-Z_][A-Z0-9_]*\)=.*/\1/p' "$APP_DIR/deploy/.env.production.example"); do
    grep -q "^$key=" "$ENV_FILE" || warn "$key is not in $ENV_FILE (see deploy/.env.production.example; the default is used)"
  done
}

backups_configured() {
  [ -f "$ENV_FILE" ] || return 1
  local id key
  id="$(env_get R2_ACCOUNT_ID)"; key="$(env_get AWS_ACCESS_KEY_ID)"
  [ -n "$id" ] && [ -n "$key" ] && [ "$id" != your-cloudflare-account-id ] && [ "$key" != r2-access-key-id ]
}

# Folders and the awscli venv that newer releases expect (servers set up by an older guide lack
# them; optics-api.service refuses to start if a ReadWritePaths folder is missing).
ensure_layout() {
  mkdir -p "$OPTICS_HOME/cache"
  chown optics:www-data "$OPTICS_HOME/cache"; chmod 700 "$OPTICS_HOME/cache"
  [ -x "$TOOLS_VENV/bin/python" ] || sudo -H -u optics python3 -m venv "$TOOLS_VENV"
  [ -x "$TOOLS_VENV/bin/aws" ] || sudo -H -u optics "$TOOLS_VENV/bin/pip" install -q awscli
}

# Copy the systemd units and command helpers from the checkout (idempotent).
install_units() {
  local changed=0 timer_changed=0 f
  for f in optics-api.service optics-backup.service optics-backup.timer; do
    if ! cmp -s "$APP_DIR/deploy/systemd/$f" "/etc/systemd/system/$f"; then
      install -m 644 "$APP_DIR/deploy/systemd/$f" "/etc/systemd/system/$f"; changed=1
      [ "$f" = optics-backup.timer ] && timer_changed=1
    fi
  done
  [ "$changed" -eq 1 ] && systemctl daemon-reload
  # A new schedule takes effect only when an active timer is restarted (only re-arms the timer;
  # it never runs a backup by itself).
  if [ "$timer_changed" -eq 1 ] && systemctl is-active --quiet optics-backup.timer; then
    systemctl restart optics-backup.timer
  fi
  ln -sf "$APP_DIR/deploy/backup/optics-restore.sh" /usr/local/bin/optics-restore
  ln -sf "$APP_DIR/deploy/update.sh" /usr/local/bin/optics-update
  cat > /usr/local/bin/optics-manage <<'SH'
#!/usr/bin/env bash
# Run a Django management command on the Optics server, e.g. `optics-manage showmigrations`.
cd /srv/optics/app/backend || exit 1
exec sudo -u optics bash -c 'set -a; . /srv/optics/.env.production; set +a
  export DJANGO_SETTINGS_MODULE=config.settings.production
  exec /srv/optics/venv/bin/python manage.py "$@"' _ "$@"
SH
  chmod 755 /usr/local/bin/optics-manage
  ok "systemd units and the optics-manage / optics-update / optics-restore commands are installed"
}

# Write the nginx site from the template for $DOMAIN / $TLS_MODE, test it, reload nginx.
# On a failed `nginx -t` the previous site file is put back, so other sites keep working.
render_nginx() {
  local cert key tmp backup=""
  case "$TLS_MODE" in
    cloudflare)  cert=$CF_CERT; key=$CF_KEY ;;
    letsencrypt) cert=/etc/letsencrypt/live/$DOMAIN/fullchain.pem; key=/etc/letsencrypt/live/$DOMAIN/privkey.pem ;;
    *) die "unknown TLS_MODE '$TLS_MODE' (cloudflare or letsencrypt)" ;;
  esac
  [ -f "$cert" ] && [ -f "$key" ] || die "TLS certificate not found: $cert / $key"
  tmp="$(mktemp)"
  sed -e "s|__DOMAIN__|$DOMAIN|g" -e "s|__SSL_CERT__|$cert|g" -e "s|__SSL_KEY__|$key|g" \
    "$APP_DIR/deploy/nginx/optics-api.conf" > "$tmp"
  if cmp -s "$tmp" "$NGINX_SITE" && [ -L /etc/nginx/sites-enabled/optics-api ]; then
    rm -f "$tmp"; ok "nginx site unchanged"; return
  fi
  if [ -f "$NGINX_SITE" ]; then backup="$(mktemp)"; cp "$NGINX_SITE" "$backup"; fi
  install -m 644 "$tmp" "$NGINX_SITE"; rm -f "$tmp"
  ln -sf "$NGINX_SITE" /etc/nginx/sites-enabled/optics-api
  if ! nginx -t 2>&1; then
    if [ -n "$backup" ]; then cp "$backup" "$NGINX_SITE"; else rm -f "$NGINX_SITE" /etc/nginx/sites-enabled/optics-api; fi
    die "nginx -t failed; the previous optics site was restored and nginx was NOT reloaded"
  fi
  rm -f "$backup"
  systemctl reload nginx   # reload, never restart: other sites (pharmacy) keep serving
  ok "nginx site written and reloaded"
}

# GET /api/v1/health/ through nginx on this machine (works before DNS points here).
health_check() {
  local out i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    out="$(curl -sk --max-time 5 --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/api/v1/health/" || true)"
    if [[ "$out" == *'"status":"ok"'* || "$out" == *'"status": "ok"'* ]]; then
      ok "health: $out"; return 0
    fi
    sleep 2
  done
  warn "health check failed: ${out:-no answer}"
  echo "    look at: journalctl -u optics-api -n 50 --no-pager ; tail /var/log/nginx/optics-api.error.log"
  return 1
}
