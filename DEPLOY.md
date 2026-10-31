# Deploying the Optics API

This guide puts the Django API online at an address such as `https://optics-api.tera-software1.com`,
on an **Ubuntu 22.04 or 24.04** server. Two scripts do the work:

| Script | When | What it does |
|---|---|---|
| `deploy/setup-server.sh` | first time (and safe to run again) | packages, user, code, Python, PostgreSQL, secrets, migrations, static files, gunicorn, nginx, HTTPS, backups |
| `deploy/update.sh` (`sudo optics-update`) | every later release | pull, packages, backup if needed, migrate, static files, restart, health check |

It can share a server with the pharmacy backend **without touching it**: own Linux user, folder,
database, gunicorn service, nginx site and backups. nginx is only ever *reloaded* after `nginx -t`
passes, never restarted, and no existing package is upgraded.

| | Optics | Pharmacy (untouched) |
|---|---|---|
| Linux user | `optics` | its own |
| Folder | `/srv/optics` | its own |
| Database / role | `optics` / `optics` (same PostgreSQL, new database) | its own |
| gunicorn | `optics-api.service`, socket `/run/optics/gunicorn.sock` | its own |
| nginx | `/etc/nginx/sites-available/optics-api` | its own site file |
| Backups | `optics-backup.timer` → R2 bucket `optics-backups` | its own |

---

## Step 0: decide three things

1. **Domain**: the API address, e.g. `optics-api.tera-software1.com`.
2. **HTTPS certificate** (`TLS_MODE`):
   - `cloudflare` (default): the domain is in Cloudflare with the orange cloud (proxied). You make
     a free *Origin certificate* in Cloudflare and paste it on the server (step 2).
   - `letsencrypt`: no Cloudflare proxy (grey cloud or another DNS provider). The script gets a free
     certificate with certbot and renews it automatically. Needs an e-mail address.
3. **Database** (`DB_MODE`):
   - `local` (default): PostgreSQL on the same server. The script installs it if missing and
     creates the `optics` database with a random password. **Recommended.**
   - `external`: a PostgreSQL server elsewhere; you pass its `DATABASE_URL`.
   SQLite is for development only; do not use it in production.

## Step 1: DNS

In your DNS (Cloudflare → DNS), add an **A record**: name `optics-api`, value = the server's IPv4
(and an `AAAA` record if the server has IPv6).
- `cloudflare` mode: **Proxied** (orange cloud). In SSL/TLS make sure the mode for this host is
  **Full (strict)**. If the zone is shared with the pharmacy and is not already Full (strict),
  don't change the zone mode; add a *Configuration Rule* (Rules → Configuration Rules) for this
  hostname → SSL: Full (strict).
- `letsencrypt` mode: **DNS only** (grey cloud), and ports 80 and 443 open to the internet.

## Step 2: Cloudflare Origin certificate (only for `cloudflare` mode)

Cloudflare → SSL/TLS → Origin Server → **Create certificate** → hostname
`optics-api.tera-software1.com`, RSA, 15 years. Keep the page open, then on the server:

```bash
sudo mkdir -p /etc/ssl/cloudflare
sudo nano /etc/ssl/cloudflare/optics-api.pem   # paste the "Origin Certificate", save
sudo nano /etc/ssl/cloudflare/optics-api.key   # paste the "Private key", save
```

(If you forget this step, the setup script stops and tells you to do it, then you run it again.)

## Step 3: get the scripts onto the server

Log in to the server with SSH as a user that can run `sudo`, then copy the repository anywhere,
for example your home folder:

```bash
git clone https://github.com/Rasool-Muhiddin/optics.git ~/optics   # asks for your GitHub login/token
cd ~/optics
```

This copy is only used to start the setup. The server's own copy goes to `/srv/optics/app` and
is pulled with a read-only *deploy key* (next step).

## Step 4: run the setup

Pick the line that matches your choices from step 0:

```bash
# Cloudflare proxy + local PostgreSQL (the usual case)
sudo DOMAIN=optics-api.tera-software1.com TLS_MODE=cloudflare bash deploy/setup-server.sh

# No Cloudflare proxy: Let's Encrypt certificate
sudo DOMAIN=optics-api.example.com TLS_MODE=letsencrypt LETSENCRYPT_EMAIL=you@example.com \
     bash deploy/setup-server.sh

# Database on another server
sudo DOMAIN=... DB_MODE=external DATABASE_URL='postgres://user:password@db-host:5432/optics' \
     bash deploy/setup-server.sh
```

Other settings: `REPO_URL` (default `git@github.com:Rasool-Muhiddin/optics.git`) and `BRANCH`
(default `main`). Your choices are saved in `/srv/optics/deploy.conf`, so the next time you only
type `sudo bash deploy/setup-server.sh`.

What happens, and when it pauses:

1. **Deploy key.** The first run prints an SSH public key and stops. On GitHub open the repository →
   Settings → Deploy keys → *Add deploy key*, paste it, leave *Allow write access* **off**, save.
   Run the same command again.
2. It installs what is missing, creates the database, and writes `/srv/optics/.env.production` with
   a new `SECRET_KEY`, database password and private admin address.
3. It asks you to create the **Tera admin account** (username, e-mail, password).
4. It starts the API, sets up nginx and HTTPS, and checks `/api/v1/health/`.
5. At the end it prints the API address and the **admin address**. Write the admin address down
   (it is also in `/srv/optics/.env.production` as `ADMIN_URL`).

If any step fails the script stops with a message. Fix the problem and run the same command
again: finished steps are skipped and existing secrets are never replaced.

## Step 5: fill in the values only you have

```bash
sudo nano /srv/optics/.env.production
```

| Value | Where to get it | Required? |
|---|---|---|
| `R2_ACCOUNT_ID` | Cloudflare → R2 → *Account ID* (right-hand side) | for backups |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Cloudflare → R2 → *Manage API tokens* → create a token with **Object Read & Write** on bucket `optics-backups` | for backups |
| `R2_BUCKET` | create a **private** bucket named `optics-backups` in R2 (or change the name here) | for backups |
| `SENTRY_DSN` | sentry.io → new *Django* project → DSN. You get an e-mail on every server error. Only stack traces are sent, never patient data | optional |

Everything else was filled in by the script. Don't put comments after a value on the same line,
and don't add quotes. Then run the setup again; it applies the change and turns on daily backups:

```bash
cd ~/optics && sudo bash deploy/setup-server.sh
```

In R2, add a lifecycle rule on the bucket: delete objects under `db/` after 60 days.

## Step 6: check everything

```bash
curl -s https://optics-api.tera-software1.com/api/v1/health/       # → "status":"ok"
sudo systemctl start optics-backup.service                           # one backup now
journalctl -u optics-backup -n 5 --no-pager                          # → "backup ok: ..."
sudo optics-restore                                                  # test restore (live DB untouched)
```

- [ ] Health returns `"status":"ok"`.
- [ ] `https://<domain>/admin/` returns **404** (the admin lives only at the private `ADMIN_URL`).
- [ ] The admin page at `ADMIN_URL` loads **with styles**.
- [ ] The backup appears in R2 and `sudo optics-restore` ends with "Test restore OK".
- [ ] A lab logo uploaded from the desktop app opens under `/media/lab_logos/…`.
- [ ] `journalctl -u optics-api -n 20` shows real client IPs, not `127.0.0.1` (throttling works).
- [ ] The pharmacy site still works (open it in a browser).
- [ ] Add a free uptime monitor (e.g. UptimeRobot) on `https://<domain>/api/v1/health/`, so you
      get an e-mail if the server goes down.

## Step 7: first data (in the admin)

1. **Plans**: the plans you sell (`max_users`, `max_devices`, `doctor_linking`, `report_export`).
2. **Labs**: each lab with its license. The lab page shows the *activation code* to give the lab
   for its first PC.
3. **Doctors** (optional): create the user, then the doctor profile; give the doctor its
   username, password and link code.
4. **Desktop app versions**: upload the installer (see `RELEASE.md`).

---

## Updating the server (every new release)

```bash
sudo optics-update
```

It pulls the branch, installs the pinned packages, **takes a backup first if there are database
migrations**, migrates, collects static files, restarts the API and checks health. It prints the
previous commit so you can roll back:

```bash
cd /srv/optics/app && sudo -u optics git checkout <previous-commit>
sudo optics-update --no-pull
```

(Roll back the database only if a migration has to be undone; see restore below. The next normal
`sudo optics-update` goes back to the branch.)

Before a release, refresh the Cloudflare IP list in `backend/config/settings/proxies.py` from
https://www.cloudflare.com/ips/ (used to find the real client IP for throttling).

## Backups and restoring

- **What**: the whole database (`pg_dump`, every night at 03:15) and the uploaded files (logos,
  installers) → R2 bucket. The last 7 dumps also stay in `/srv/optics/backups`.
- **See backups**: `sudo optics-restore --list`
- **Test a backup** (safe, any time): `sudo optics-restore`. It restores the newest backup into a
  scratch database, prints row counts and deletes it. Do this once a month.
- **Real restore** (data loss: everything after the backup is gone):
  ```bash
  sudo optics-restore --list                                  # pick a file
  sudo optics-restore --file optics-20261031T031500Z.dump --live
  ```
  It asks you to type `RESTORE`, saves the current database to
  `/srv/optics/backups/pre-restore-….dump`, stops the API, restores everything in one transaction
  (all or nothing) and starts the API again.
- **Uploaded files** (e.g. after moving to a new server): `sudo optics-restore --media`.
- **Moving to a new server**: run the setup there (steps 1–5, same R2 values), then
  `sudo optics-restore --file latest --live` and `sudo optics-restore --media`.

## Day-to-day commands

| Task | Command |
|---|---|
| API logs (live) | `journalctl -u optics-api -f` |
| nginx logs | `/var/log/nginx/optics-api.access.log`, `optics-api.error.log` |
| Restart the API | `sudo systemctl restart optics-api` |
| Django command | `optics-manage <command>` (e.g. `optics-manage createsuperuser`) |
| Backup now | `sudo systemctl start optics-backup.service` |
| Next backup time | `systemctl list-timers optics-backup.timer` |
| Change a setting | `sudo nano /srv/optics/.env.production` then `sudo systemctl restart optics-api` |

## Where things live on the server

| Path | What |
|---|---|
| `/srv/optics/app` | the code (git checkout; don't edit by hand) |
| `/srv/optics/.env.production` | secrets and settings (chmod 600, never copy it anywhere public) |
| `/srv/optics/deploy.conf` | the setup choices (domain, TLS mode, …), no secrets |
| `/srv/optics/venv`, `/srv/optics/tools-venv` | Python packages for the app / for backups (awscli) |
| `/srv/optics/static`, `/srv/optics/media` | admin static files / uploaded logos and installers (served by nginx) |
| `/srv/optics/backups` | local copies of the last backups |
| `deploy/gunicorn.conf.py` | workers (`GUNICORN_WORKERS` in the env file, default 3) and timeouts |
