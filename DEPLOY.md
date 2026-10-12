# Deploying the Optics API (Ubuntu 24.04, behind Cloudflare)

Target: `https://optics-api.tera-software1.com`, on the **same Hetzner server as the pharmacy
backend, without touching it**. Everything below is separate from the pharmacy:

| | Optics | Pharmacy (untouched) |
|---|---|---|
| Linux user | `optics` | its own |
| Folder | `/srv/optics` | its own |
| Database / role | `optics` / `optics` (same PostgreSQL server, new DB) | its own DB |
| gunicorn | `optics-api.service`, socket `/run/optics/gunicorn.sock` | its own unit/port |
| nginx | `/etc/nginx/sites-available/optics-api` | its own site file |
| Backups | `optics-backup.timer` → R2 bucket `optics-backups` | its own |

Never run `systemctl restart nginx` blindly: always `nginx -t` first, then `reload` (a reload keeps
the pharmacy site serving). Never edit the pharmacy's files, database or units.

Files used below are in `deploy/` of this repository.

---

## 0. Before you start (check, don't change)

```bash
lsb_release -a                     # Ubuntu 24.04
sudo systemctl list-units --type=service | grep -i -E 'gunicorn|pharm|nginx|postgres'
sudo ls /etc/nginx/sites-enabled/  # note the pharmacy site name
sudo -u postgres psql -c '\l'      # existing databases (the pharmacy one stays as is)
psql --version                     # PostgreSQL major version (16 on 24.04)
```

## 1. Cloudflare

1. **DNS** → add `A` record `optics-api` → the server IPv4 (and `AAAA` if the server has IPv6),
   **Proxied** (orange cloud).
2. **SSL/TLS mode** is per zone and shared with the pharmacy subdomain. If the zone is already on
   **Full (strict)**, keep it. If not, do **not** change the zone mode: add a *Configuration Rule*
   (Rules → Configuration Rules) for hostname `optics-api.tera-software1.com` → SSL: Full (strict).
3. **Origin certificate**: SSL/TLS → Origin Server → Create certificate for
   `optics-api.tera-software1.com` (RSA, 15 years). Save both parts on the server:
   ```bash
   sudo mkdir -p /etc/ssl/cloudflare
   sudo nano /etc/ssl/cloudflare/optics-api.pem   # certificate
   sudo nano /etc/ssl/cloudflare/optics-api.key   # private key
   sudo chmod 600 /etc/ssl/cloudflare/optics-api.key
   ```

## 2. User, folders, code

```bash
sudo adduser --system --group --home /srv/optics --shell /bin/bash optics
sudo usermod -aG www-data optics
sudo mkdir -p /srv/optics/{static,media,backups}
sudo chown -R optics:www-data /srv/optics
sudo chmod 750 /srv/optics
sudo chmod 2775 /srv/optics/media          # nginx (www-data) reads, gunicorn writes

# Read-only deploy key: GitHub repo → Settings → Deploy keys.
sudo -u optics ssh-keygen -t ed25519 -f /srv/optics/.ssh/id_ed25519 -N ''
sudo cat /srv/optics/.ssh/id_ed25519.pub   # add as deploy key (read-only)
sudo -u optics git clone git@github.com:Rasool-Muhiddin/optics.git /srv/optics/app
```

## 3. System packages (shared, additive only)

```bash
sudo apt update
sudo apt install -y python3-venv python3-dev build-essential libpq-dev postgresql-client
# nginx and PostgreSQL server are already installed for the pharmacy; nothing to install there.
```
The `postgresql-client` major version must match the server (e.g. 16) for `pg_dump`.

## 4. Python environment

```bash
sudo -u optics python3 -m venv /srv/optics/venv
sudo -u optics /srv/optics/venv/bin/pip install --upgrade pip
sudo -u optics /srv/optics/venv/bin/pip install -r /srv/optics/app/backend/requirements.txt
sudo -u optics /srv/optics/venv/bin/pip install awscli      # for backups to R2
```

## 5. Database (new DB + role on the existing PostgreSQL)

```bash
sudo -u postgres psql <<'SQL'
CREATE ROLE optics LOGIN PASSWORD 'CHANGE_ME_LONG_RANDOM';
CREATE DATABASE optics OWNER optics ENCODING 'UTF8' TEMPLATE template0;
REVOKE ALL ON DATABASE optics FROM PUBLIC;
SQL
```

## 6. Environment file

```bash
sudo -u optics cp /srv/optics/app/deploy/.env.production.example /srv/optics/.env.production
sudo -u optics nano /srv/optics/.env.production   # SECRET_KEY, DATABASE_URL password, ADMIN_URL, R2_*
sudo chmod 600 /srv/optics/.env.production
python3 -c "import secrets; print(secrets.token_urlsafe(64))"   # → SECRET_KEY
```

## 7. Django: migrate, static files, admin user

```bash
cd /srv/optics/app/backend
sudo -u optics bash -c 'set -a; . /srv/optics/.env.production; set +a;
  export DJANGO_SETTINGS_MODULE=config.settings.production;
  /srv/optics/venv/bin/python manage.py check --deploy &&
  /srv/optics/venv/bin/python manage.py migrate &&
  /srv/optics/venv/bin/python manage.py collectstatic --noinput &&
  /srv/optics/venv/bin/python manage.py createsuperuser'
```
Create a shell helper for later commands:
```bash
sudo tee /usr/local/bin/optics-manage >/dev/null <<'SH'
#!/usr/bin/env bash
cd /srv/optics/app/backend
exec sudo -u optics bash -c 'set -a; . /srv/optics/.env.production; set +a;
  DJANGO_SETTINGS_MODULE=config.settings.production exec /srv/optics/venv/bin/python manage.py "$@"' _ "$@"
SH
sudo chmod +x /usr/local/bin/optics-manage
optics-manage showmigrations | tail -3
```

## 8. gunicorn service

```bash
sudo cp /srv/optics/app/deploy/systemd/optics-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now optics-api
sudo systemctl status optics-api --no-pager
ls -l /run/optics/gunicorn.sock
```

## 9. nginx site

```bash
sudo cp /srv/optics/app/deploy/nginx/optics-api.conf /etc/nginx/sites-available/optics-api
sudo ln -s /etc/nginx/sites-available/optics-api /etc/nginx/sites-enabled/optics-api
sudo nginx -t && sudo systemctl reload nginx
curl -s https://optics-api.tera-software1.com/api/v1/health/
# → {"status": "ok", "database": "ok", ...}
```
Check the pharmacy still answers (its health URL) right after the reload.

## 10. Backups to Cloudflare R2

1. Cloudflare → R2 → create bucket `optics-backups` (private). Add a lifecycle rule: delete objects
   under `db/` after 60 days.
2. R2 → Manage API tokens → token with *Object Read & Write* on that bucket → put the key id/secret
   and the account id into `/srv/optics/.env.production` (`R2_*`, `AWS_*`).
3. Install and test:
   ```bash
   sudo cp /srv/optics/app/deploy/systemd/optics-backup.{service,timer} /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl start optics-backup.service && journalctl -u optics-backup -n 20 --no-pager
   sudo systemctl enable --now optics-backup.timer
   systemctl list-timers | grep optics
   ```
4. **Test a restore** once (into a scratch database, never the live one):
   ```bash
   sudo -u postgres createdb optics_restore_test -O optics
   aws s3 cp s3://optics-backups/db/<file>.dump /tmp/ --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com
   pg_restore --no-owner -d optics_restore_test /tmp/<file>.dump
   sudo -u postgres dropdb optics_restore_test
   ```

## 11. First data

In the admin (`https://optics-api.tera-software1.com/<ADMIN_URL>`):
1. **Plans**: create the plans you sell (`max_users`, `max_devices`, `doctor_linking`, `report_export`).
2. **Labs**: create each lab with its license. The *activation code* is on the lab page: give it to
   the lab for the first PC.
3. **Doctors** (optional): create the user, then the doctor profile; give the doctor its username,
   password and link code.
4. **Desktop app versions**: upload the installer (see `RELEASE.md`).

## 12. Updating the server later

```bash
cd /srv/optics/app && sudo -u optics git pull --ff-only
sudo -u optics /srv/optics/venv/bin/pip install -r backend/requirements.txt
optics-manage migrate
optics-manage collectstatic --noinput
optics-manage check --deploy
sudo systemctl restart optics-api
curl -s https://optics-api.tera-software1.com/api/v1/health/
```
Take a backup first (`sudo systemctl start optics-backup.service`) when the release has migrations.
Rollback: `git checkout <previous tag>`, reinstall requirements, restart; restore the pre-update dump
only if a migration must be undone.

## 13. Checklist

- [ ] `curl https://optics-api.tera-software1.com/api/v1/health/` → `status: ok`
- [ ] `https://optics-api.tera-software1.com/admin/` → 404 (admin lives at `ADMIN_URL` only)
- [ ] Admin loads with styles (static files served by nginx)
- [ ] A lab logo uploaded from the desktop settings screen opens under `/media/lab_logos/…`
- [ ] Throttling sees real IPs: `journalctl -u optics-api` shows client IPs, not `127.0.0.1`
- [ ] Backup timer listed and one backup present in R2; restore tested
- [ ] Pharmacy site still works
- [ ] Refresh `backend/config/settings/proxies.py` from https://www.cloudflare.com/ips/ before each deploy
