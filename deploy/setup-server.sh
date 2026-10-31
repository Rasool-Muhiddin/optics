#!/usr/bin/env bash
# One-shot setup of the Optics API on a fresh Ubuntu 22.04/24.04 server (or next to the
# pharmacy backend: nothing of it is touched). Safe to re-run: every step checks first and
# skips what is already done; secrets that exist are never regenerated.
#
#   git clone <repo> ~/optics && cd ~/optics          # any copy of the repository
#   sudo DOMAIN=optics-api.example.com TLS_MODE=cloudflare bash deploy/setup-server.sh
#
# Settings (environment variables; the first run saves them to /srv/optics/deploy.conf and later
# runs reuse them, so a re-run is just `sudo bash deploy/setup-server.sh`):
#   DOMAIN             API host name                      (default optics-api.tera-software1.com)
#   REPO_URL           git URL the server pulls from      (default git@github.com:Rasool-Muhiddin/optics.git)
#   BRANCH             branch to deploy                   (default main)
#   TLS_MODE           cloudflare  = Cloudflare Origin certificate in /etc/ssl/cloudflare/ (default)
#                      letsencrypt = free certificate from Let's Encrypt via certbot
#   LETSENCRYPT_EMAIL  required with TLS_MODE=letsencrypt (expiry notices)
#   BEHIND_CLOUDFLARE  yes/no: domain proxied by Cloudflare (orange cloud) (default: yes for
#                      cloudflare TLS, no for letsencrypt)
#   DB_MODE            local    = PostgreSQL on this server; database + role created here (default)
#                      external = you give DATABASE_URL (managed/other PostgreSQL server)
#   DATABASE_URL       only with DB_MODE=external, e.g. postgres://user:pass@db-host:5432/optics
set -euo pipefail

main() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=deploy/lib.sh
  . "$here/lib.sh"
  cd /
  require_root
  load_settings
  preflight
  install_packages
  create_user_and_folders
  get_code
  python_env
  database
  env_file
  install_units
  django
  start_api
  tls_and_nginx
  firewall
  backups
  finish
}

# --- settings -----------------------------------------------------------------------
load_settings() {
  # Explicit environment variables win over the saved choices, which win over defaults.
  local e_domain="${DOMAIN:-}" e_repo="${REPO_URL:-}" e_branch="${BRANCH:-}" e_tls="${TLS_MODE:-}" \
        e_email="${LETSENCRYPT_EMAIL:-}" e_cf="${BEHIND_CLOUDFLARE:-}" e_db="${DB_MODE:-}"
  # shellcheck disable=SC1090
  [ -f "$DEPLOY_CONF" ] && . "$DEPLOY_CONF"
  DOMAIN="${e_domain:-${DOMAIN:-optics-api.tera-software1.com}}"
  REPO_URL="${e_repo:-${REPO_URL:-git@github.com:Rasool-Muhiddin/optics.git}}"
  BRANCH="${e_branch:-${BRANCH:-main}}"
  TLS_MODE="${e_tls:-${TLS_MODE:-cloudflare}}"
  LETSENCRYPT_EMAIL="${e_email:-${LETSENCRYPT_EMAIL:-}}"
  DB_MODE="${e_db:-${DB_MODE:-local}}"
  if [ "$TLS_MODE" = cloudflare ]; then BEHIND_CLOUDFLARE="${e_cf:-${BEHIND_CLOUDFLARE:-yes}}"
  else BEHIND_CLOUDFLARE="${e_cf:-${BEHIND_CLOUDFLARE:-no}}"; fi

  case "$TLS_MODE" in cloudflare|letsencrypt) ;; *) die "TLS_MODE must be cloudflare or letsencrypt" ;; esac
  case "$DB_MODE" in local|external) ;; *) die "DB_MODE must be local or external" ;; esac
  case "$BEHIND_CLOUDFLARE" in yes|no) ;; *) die "BEHIND_CLOUDFLARE must be yes or no" ;; esac
  [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die "DOMAIN '$DOMAIN' is not a host name"
  if [ "$TLS_MODE" = letsencrypt ] && [ -z "$LETSENCRYPT_EMAIL" ]; then
    die "TLS_MODE=letsencrypt needs LETSENCRYPT_EMAIL=you@example.com"
  fi
}

save_settings() {
  cat > "$DEPLOY_CONF" <<EOF
# Written by deploy/setup-server.sh; read by setup-server.sh and update.sh. No secrets here.
DOMAIN=$DOMAIN
REPO_URL=$REPO_URL
BRANCH=$BRANCH
TLS_MODE=$TLS_MODE
LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL
BEHIND_CLOUDFLARE=$BEHIND_CLOUDFLARE
DB_MODE=$DB_MODE
EOF
  chmod 644 "$DEPLOY_CONF"
}

preflight() {
  step "Settings"
  echo "    domain=$DOMAIN  tls=$TLS_MODE  cloudflare-proxy=$BEHIND_CLOUDFLARE  db=$DB_MODE"
  echo "    repo=$REPO_URL ($BRANCH)"
  . /etc/os-release
  [ "${ID:-}" = ubuntu ] || warn "written for Ubuntu; this is ${PRETTY_NAME:-unknown}"
  case "${VERSION_ID:-}" in 22.04|24.04) ;; *) warn "tested on Ubuntu 22.04/24.04; this is ${VERSION_ID:-?}" ;; esac
  if [ "$DB_MODE" = external ] && [ ! -f "$ENV_FILE" ] && [ -z "${DATABASE_URL:-}" ]; then
    die "DB_MODE=external needs DATABASE_URL=postgres://user:password@host:5432/dbname"
  fi
}

# --- system packages ----------------------------------------------------------------
installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

install_packages() {
  step "System packages (only missing ones are installed; nothing is upgraded)"
  local want=(git curl ca-certificates openssl python3 python3-venv python3-dev build-essential
              libpq-dev postgresql-client nginx) missing=() p
  [ "$DB_MODE" = local ] && want+=(postgresql)
  [ "$TLS_MODE" = letsencrypt ] && want+=(certbot)
  for p in "${want[@]}"; do installed "$p" || missing+=("$p"); done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "    installing: ${missing[*]}"
    apt-get update -q
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-upgrade "${missing[@]}"
  fi
  systemctl enable --now nginx >/dev/null
  [ "$DB_MODE" = local ] && systemctl enable --now postgresql >/dev/null
  ok "packages present"
}

# --- user, folders, code ------------------------------------------------------------
create_user_and_folders() {
  step "User 'optics' and folders under $OPTICS_HOME"
  if ! id optics >/dev/null 2>&1; then
    adduser --system --group --home "$OPTICS_HOME" --shell /bin/bash optics
  fi
  usermod -aG www-data optics
  mkdir -p "$OPTICS_HOME"/{static,media,cache,backups} "$OPTICS_HOME/.ssh"
  chown optics:www-data "$OPTICS_HOME" "$OPTICS_HOME"/{static,media,cache,backups}
  chown optics:optics "$OPTICS_HOME/.ssh"
  chmod 750 "$OPTICS_HOME"; chmod 700 "$OPTICS_HOME/.ssh" "$OPTICS_HOME/cache"
  chmod 2775 "$OPTICS_HOME/media"           # nginx (www-data) reads, gunicorn writes
  chmod 2750 "$OPTICS_HOME/static"
  chmod 750 "$OPTICS_HOME/backups"
  save_settings
  ok "done"
}

get_code() {
  step "Code in $APP_DIR"
  if [ -d "$APP_DIR/.git" ]; then
    ok "already cloned (use optics-update to deploy new commits)"; return
  fi
  if [[ "$REPO_URL" == git@* || "$REPO_URL" == ssh://* ]]; then
    local key="$OPTICS_HOME/.ssh/id_ed25519" host
    host="$(echo "$REPO_URL" | sed -E 's#^(ssh://)?git@([^:/]+).*#\2#')"
    [ -f "$key" ] || sudo -u optics ssh-keygen -q -t ed25519 -N '' -C "optics@$(hostname)" -f "$key"
    sudo -u optics bash -c "ssh-keyscan -t ed25519 '$host' >> '$OPTICS_HOME/.ssh/known_hosts' 2>/dev/null; sort -u -o '$OPTICS_HOME/.ssh/known_hosts' '$OPTICS_HOME/.ssh/known_hosts'"
    if ! sudo -u optics git ls-remote "$REPO_URL" >/dev/null 2>&1; then
      echo
      echo "    The server cannot read the repository yet. Add this READ-ONLY deploy key"
      echo "    (GitHub → repository → Settings → Deploy keys → Add deploy key):"
      echo
      cat "$key.pub"
      echo
      die "add the key, then run this script again"
    fi
  fi
  sudo -u optics git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
  ok "cloned $BRANCH"
}

python_env() {
  step "Python virtualenvs"
  [ -x "$VENV/bin/python" ] || sudo -u optics python3 -m venv "$VENV"
  sudo -H -u optics "$VENV/bin/pip" install -q --upgrade pip
  sudo -H -u optics "$VENV/bin/pip" install -q -r "$APP_DIR/backend/requirements.txt"
  # awscli (backups to R2) in its own venv, so it never changes the app's pinned packages.
  [ -x "$TOOLS_VENV/bin/python" ] || sudo -u optics python3 -m venv "$TOOLS_VENV"
  [ -x "$TOOLS_VENV/bin/aws" ] || sudo -H -u optics "$TOOLS_VENV/bin/pip" install -q awscli
  ok "app: $("$VENV/bin/python" -c 'import django; print("Django", django.get_version())'), backups: $("$TOOLS_VENV/bin/aws" --version 2>&1 | cut -d' ' -f1)"
}

# --- database -----------------------------------------------------------------------
DB_PASSWORD=""
database() {
  step "Database"
  if [ "$DB_MODE" = external ]; then ok "external database (DATABASE_URL)"; return; fi
  local psql=(sudo -u postgres psql -v ON_ERROR_STOP=1 -qtA)
  if [ "$("${psql[@]}" -c "SELECT 1 FROM pg_roles WHERE rolname='optics'")" != 1 ]; then
    DB_PASSWORD="$(openssl rand -hex 24)"
    "${psql[@]}" -c "CREATE ROLE optics LOGIN PASSWORD '$DB_PASSWORD'"
    ok "role optics created"
  elif [ ! -f "$ENV_FILE" ]; then
    # Role exists but its password is unknown here (env file lost): set a new one.
    DB_PASSWORD="$(openssl rand -hex 24)"
    "${psql[@]}" -c "ALTER ROLE optics PASSWORD '$DB_PASSWORD'"
    warn "role optics existed; its password was reset because $ENV_FILE was missing"
  fi
  if [ "$("${psql[@]}" -c "SELECT 1 FROM pg_database WHERE datname='optics'")" != 1 ]; then
    "${psql[@]}" -c "CREATE DATABASE optics OWNER optics ENCODING 'UTF8' TEMPLATE template0"
    "${psql[@]}" -c "REVOKE ALL ON DATABASE optics FROM PUBLIC"
    ok "database optics created"
  else
    ok "database optics exists"
  fi
  # pg_dump must not be older than the server, or backups fail.
  local server client
  server="$("${psql[@]}" -c 'SHOW server_version_num')"; server=$((server / 10000))
  client="$(pg_dump --version | grep -oE '[0-9]+' | head -n1)"
  [ "$client" -ge "$server" ] || warn "pg_dump $client is older than PostgreSQL $server: install postgresql-client-$server for backups"
}

# --- environment file ---------------------------------------------------------------
env_file() {
  step "Environment file $ENV_FILE"
  if [ -f "$ENV_FILE" ]; then
    [ -n "$DB_PASSWORD" ] && env_set DATABASE_URL "postgres://optics:$DB_PASSWORD@127.0.0.1:5432/optics"
    ok "exists (kept as is)"
  else
    install -m 600 -o optics -g optics "$APP_DIR/deploy/.env.production.example" "$ENV_FILE"
    env_set SECRET_KEY "$(python3 -c 'import secrets; print(secrets.token_urlsafe(64))')"
    env_set ALLOWED_HOSTS "$DOMAIN"
    env_set CSRF_TRUSTED_ORIGINS "https://$DOMAIN"
    env_set ADMIN_URL "tera-admin-$(openssl rand -hex 6)/"
    if [ "$DB_MODE" = local ]; then
      env_set DATABASE_URL "postgres://optics:$DB_PASSWORD@127.0.0.1:5432/optics"
    else
      env_set DATABASE_URL "$DATABASE_URL"
    fi
    if [ "$BEHIND_CLOUDFLARE" = yes ]; then env_set TRUST_CLOUDFLARE True; else env_set TRUST_CLOUDFLARE False; fi
    ok "created with a new SECRET_KEY, database password and admin path"
  fi
  chown optics:optics "$ENV_FILE"; chmod 600 "$ENV_FILE"
  check_env_file
}

# --- Django ---------------------------------------------------------------------------
django() {
  step "Django: checks, migrations, static files"
  manage check --deploy --fail-level WARNING
  manage migrate --noinput
  manage collectstatic --noinput -v 0
  ok "migrated; static files in $OPTICS_HOME/static"
  local has_admin
  has_admin="$(manage shell -c 'from django.contrib.auth import get_user_model as g; print(g().objects.filter(is_superuser=True).exists())' | tail -n1)"
  if [ "$has_admin" != True ]; then
    if [ -t 0 ]; then
      echo "    Create the Tera admin account (used at https://$DOMAIN/$(env_get ADMIN_URL)):"
      manage createsuperuser
    else
      warn "no admin account yet: run  optics-manage createsuperuser"
    fi
  fi
}

start_api() {
  step "gunicorn service optics-api"
  systemctl enable optics-api >/dev/null 2>&1
  systemctl restart optics-api
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do [ -S /run/optics/gunicorn.sock ] && break; sleep 1; done
  systemctl is-active --quiet optics-api || { journalctl -u optics-api -n 30 --no-pager; die "optics-api did not start"; }
  ok "running ($(systemctl show -p MainPID --value optics-api))"
}

# --- HTTPS + nginx --------------------------------------------------------------------
tls_and_nginx() {
  step "HTTPS certificate ($TLS_MODE) and nginx site"
  if [ "$TLS_MODE" = cloudflare ]; then
    if [ ! -s "$CF_CERT" ] || [ ! -s "$CF_KEY" ]; then
      mkdir -p /etc/ssl/cloudflare
      echo
      echo "    Cloudflare Origin certificate missing. In Cloudflare: SSL/TLS → Origin Server →"
      echo "    Create certificate for $DOMAIN (RSA, 15 years). Then on this server:"
      echo "      sudo nano $CF_CERT    # paste the certificate"
      echo "      sudo nano $CF_KEY     # paste the private key"
      echo "    and run this script again."
      die "certificate files not found"
    fi
    chmod 644 "$CF_CERT"; chmod 600 "$CF_KEY"
  else
    if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
      # Temporary port-80-only site so Let's Encrypt can reach the challenge folder.
      mkdir -p "$ACME_ROOT"
      cat > "$NGINX_SITE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root $ACME_ROOT; }
    location / { return 404; }
}
EOF
      ln -sf "$NGINX_SITE" /etc/nginx/sites-enabled/optics-api
      nginx -t || { rm -f "$NGINX_SITE" /etc/nginx/sites-enabled/optics-api; die "nginx -t failed"; }
      systemctl reload nginx
      certbot certonly --webroot -w "$ACME_ROOT" -d "$DOMAIN" \
        --email "$LETSENCRYPT_EMAIL" --agree-tos --non-interactive --no-eff-email \
        || die "certbot failed: $DOMAIN must point (DNS A record) to this server and port 80 must be open"
    fi
    mkdir -p "$ACME_ROOT" /etc/letsencrypt/renewal-hooks/deploy
    cat > /etc/letsencrypt/renewal-hooks/deploy/optics-nginx-reload.sh <<'EOF'
#!/bin/sh
# Renewed certificates take effect without dropping connections.
nginx -t && systemctl reload nginx
EOF
    chmod 755 /etc/letsencrypt/renewal-hooks/deploy/optics-nginx-reload.sh
    systemctl enable --now certbot.timer >/dev/null 2>&1 || true
    ok "certificate present; renewed automatically by certbot.timer"
  fi
  render_nginx
  health_check || die "the API does not answer through nginx"
}

firewall() {
  if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
    step "Firewall (ufw is active): allowing HTTP/HTTPS"
    ufw allow 'Nginx Full' >/dev/null
    ok "ports 80/443 open"
  fi
}

# --- backups --------------------------------------------------------------------------
backups() {
  step "Backups to Cloudflare R2"
  if backups_configured; then
    systemctl enable --now optics-backup.timer >/dev/null
    ok "daily backup timer enabled ($(systemctl show -p NextElapseUSecRealtime --value optics-backup.timer | cut -c1-30))"
  else
    warn "R2 keys not filled in yet: edit $ENV_FILE (R2_ACCOUNT_ID, AWS_ACCESS_KEY_ID,"
    warn "AWS_SECRET_ACCESS_KEY), then run this script again to enable daily backups."
  fi
}

finish() {
  step "Done"
  cat <<EOF
    API:     https://$DOMAIN/api/v1/health/
    Admin:   https://$DOMAIN/$(env_get ADMIN_URL)   (keep this address private)
    Secrets: $ENV_FILE
    Logs:    journalctl -u optics-api -f      /var/log/nginx/optics-api.*.log
    Deploy new commits later:   sudo optics-update
    Django commands:            optics-manage <command>
    Backups:  sudo systemctl start optics-backup.service ; sudo optics-restore --list
EOF
}

main "$@"
