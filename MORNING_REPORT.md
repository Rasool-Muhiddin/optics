# Morning report — Users screen + P9 + P10

Branch: `claude/festive-turing-7uajlt`. The previous PR had been merged, so the branch was restarted from
`main` and pushed after every part. A PR to `main` is opened at the end.
Flutter used in the cloud session: **3.44.8 / Dart 3.12.2** (exactly the pinned version).

| Commit | Part |
|---|---|
| `551bf7f` | Users screen (users + devices, plan limits) |
| `5b246c2` | P9 Offline read cache completion |
| `fca9545` | P10 (1/3) Encrypted token / device-key storage + migration |
| `a2a3e20` | P10 (2/3) Desktop update flow |
| `4adcdf6` | P10 (3/3) Production readiness, installer, DEPLOY.md / RELEASE.md |

## Test counts

| | Start of session | End |
|---|---|---|
| Backend (`pytest`, also runs with `manage.py test`) | 252 | **265 passed** |
| Flutter (`flutter test`) | 96 | **113 passed** |
| `flutter analyze` / `dart analyze` | clean | **clean** |
| `makemigrations --check` | No changes | **No changes** |
| `manage.py check --deploy` (production settings) | warnings | **clean** (now a test) |
| `ruff --select F,E9` (not a repo requirement) | clean | clean |

All migrations were also applied from zero on a fresh SQLite database.

---

## What was done, per part

### Users screen (owner only)
- **"المستخدمون والأجهزة" screen** with two tabs.
  - **Users:**
    - add staff
    - edit first/last name and **phone** (new field on `LabUser`)
    - reset the password
    - choose the role
    - switch "يرى التكاليف" (`can_view_costs`) and "يدير المخزون" (`can_manage_inventory`)
    - deactivate or reactivate a user
  - **Devices:** rename, revoke, reactivate. The device you are using is marked "هذا الجهاز" and cannot
    be revoked from the app.
- **Plan limits:**
  - New `GET lab/usage/` returns active users and devices against `max_users` / `max_devices`.
  - Chips such as "2 / 3" turn red when full, with an Arabic explanation.
  - Adding is blocked locally when the plan is full, and the server still refuses with an Arabic message.
  - Weak-password codes also get an Arabic message.
- **Security:** a password reset or deactivation ends that user's open sessions immediately. Revoking a
  device deletes its tokens.

### P9 Offline read cache
- **Full sync of every domain** for offline use.
  - **What it pulls:**
    - catalog: products, categories, brands, lens powers, recent stock movements
    - patients: patients, exams, prescriptions
    - sales: invoices **with lines**
    - jobs
    - purchasing: suppliers, supplier orders
    - referrals and doctor links (with the plan feature)
    - users and devices (owner)
    - credit customers and the dashboard

    Doctor mode syncs only its own links and referrals.
  - **When it runs:** when the app opens, after login, and when the server comes back (at most every
    15 minutes). There is also "مزامنة الآن" in the sidebar, which shows the last sync time.
  - If one part fails, the rest still sync.
- **Every screen header** now shows, while offline: "بدون اتصال — تعرض نسخة محفوظة — آخر تحديث …", or
  "no saved copy on this device yet". POS adds "selling needs the server".
- **Printing from cache works everywhere a print exists:** invoice A4/A5/80 mm, prescription, exam report,
  job ticket. Synced invoices print offline even if they were never opened online. This uses a new
  `?with_lines=true` option on the invoice list.
- **Reports:** the last result of each exact report query is shown offline.
- **Offline search** works on every cached list.

### P10 Release preparation
- **Encrypted secrets.**
  - The token and device key moved out of `optics_auth.json`.
  - **Windows:** stored in a **DPAPI**-encrypted file for the current user, via FFI with no plugin.
  - **macOS:** Keychain. **Linux:** libsecret, with a plain-file fallback for dev boxes without it.
  - On first start, existing plain values are moved into secure storage and removed from the JSON file.
- **Desktop updates.**
  - **Server:** `DesktopAppVersion` in admin (upload the installer; SHA-256 and size are computed
    automatically), and a public `GET desktop/latest-version/` endpoint (works before login).
  - **App:** an "يتوفر إصدار جديد" banner, red when the update is mandatory. "تحديث الآن" downloads with
    progress, **verifies SHA-256**, runs the installer silently and closes; the installer starts the new
    version.
- **Installer:** `installer/optics.iss` (Inno Setup 6).
  - Arabic + English setup texts, app icon, optional desktop shortcut.
  - Closes the running app during updates. User data is kept.
  - `installer/build_release.ps1` builds everything in one command.
- **Production readiness.**
  - **Settings review:**
    - static/media paths from the environment
    - `ADMIN_URL`
    - HSTS, referrer policy, frame deny
    - DB connection health checks
    - production never reads `.env.local`
    - `check --deploy` and `collectstatic` are now tested
  - **`deploy/` folder:**
    - nginx site with `/static/` and `/media/`
    - gunicorn systemd service
    - daily PostgreSQL + media backup to R2 (script + timer)
    - `.env.production.example`
  - **`DEPLOY.md`** walks through Ubuntu 24.04 behind Cloudflare, next to the pharmacy backend
    **without touching it**: separate user, folder, DB, socket, service and nginx site, and `nginx -t`
    before every reload.
  - **`RELEASE.md`** covers the build: `flutter build windows` with the production `--dart-define`s,
    then the installer.

---

## Decisions you should review
All of these are recorded in `CLAUDE.md` ("Decisions recorded for the Users screen", "in P9", "in P10").

1. **Your own device cannot be revoked from the app** (it would log you out). Revoke it from another PC
   or from Django Admin.
2. **The owner cannot change their own role or deactivate themselves** (as before). The form hides those
   fields for yourself.
3. **Auto-sync is limited to once every 15 minutes.** It pulls at most ~5,000 products and lens powers,
   3,000 patients, 2,000 exams/prescriptions, and 1,000 invoices/jobs/orders (the most recent). Bigger
   labs keep only the newest records offline.
4. **Plan usage and the lab's doctor link code are online-only on purpose** (limits and secrets must be
   live).
5. **Linux without libsecret** keeps the secrets in a 0600 plain file. This is dev only and does not
   affect Windows.
6. **The update installer needs administrator approval** (per-machine install under Program Files).
   Windows shows a UAC prompt during the update.
7. **"Mandatory" updates are shown, not enforced.** Old versions can still log in. If you want old
   versions blocked, it is a small server change.
8. **`latest-version` is public** (it shows only version, URL, SHA-256 and notes). It has its own
   throttle of 120/min per IP.
9. **HSTS defaults to 1 year** for this host only (no subdomains, no preload). Set
   `SECURE_HSTS_SECONDS=3600` for the very first deploy if you want a safety margin.
10. **The Cloudflare SSL mode is per zone.** DEPLOY.md says to use a **Configuration Rule** for
    `optics-api` instead of changing the zone, so the pharmacy is unaffected.
11. **Installers live in `/media/installers/` and are publicly downloadable** (needed before login).
    Hosting them on R2 is supported (URL + SHA-256 in admin).

## Unfinished / limitations / not verified
- **Nothing was run on Windows:**
  - no `flutter build windows` (now including `ffi`, `crypto` and `file_selector`)
  - no Inno Setup compile, no real silent update
  - **DPAPI was not exercised for real.** Its code compiles and the logic around it is unit-tested with
    memory/file stores, but the real `crypt32.dll` path only runs on Windows.
- **Nothing was deployed.** The deploy files were written but not run on a server. nginx and the systemd
  units were not syntax-checked on Ubuntu; the backup script passed `bash -n` only.
- **Arabic setup texts** rely on `Arabic.isl`, which ships with Inno Setup 6.3+ (older versions need it
  downloaded, see RELEASE.md).
- The **Cloudflare IP list** in `config/settings/proxies.py` must be refreshed before the deploy.
- **Not built:**
  - server-side blocking of outdated app versions
  - automatic update download in the background (the user clicks "تحديث الآن")
  - code signing of the installer (Windows SmartScreen will warn until a certificate is used)

---

## What to test manually on Windows

Setup as before (`migrate`, `create_lab … --plan pro`, `create_doctor …`, `runserver`, `flutter run -d windows`).

**Users screen**
1. "المستخدمون" (owner): the usage chips show users/devices against the plan.
2. **Add staff:** with name, phone and "يدير المخزون". Log in as them: inventory actions are there, costs
   are not.
3. **Limits:** set `max_users` to the current count in Admin. "إضافة موظف" now shows the Arabic limit
   message.
4. **Password reset:** reset a user's password. That user is logged out at their next action.
5. **Deactivate:** deactivate a user (confirm). They cannot log in.
6. **Devices:** rename another device, then revoke it. Its session ends; it needs the activation code
   again. "هذا الجهاز" has no revoke button.

**P9 Offline**
1. **Sync:** log in and wait a few seconds, or press "مزامنة الآن". The sidebar shows the time.
2. **Go offline** (stop `runserver`). Every screen shows the tertiary "نسخة محفوظة — آخر تحديث …" strip.
3. **Search and open from cache:** search patients / invoices / jobs / orders offline. Open an invoice
   you never opened before and print it (A4, A5, 80 mm).
4. **Print from a patient:** open a patient and print the prescription and exam report. Then a job
   ticket.
5. **Reports:** a report opened before going offline shows again; a new date range says it is not
   cached.
6. **Writes are blocked:** try to sell or save anything; you get the Arabic offline message.

**P10**
1. **Encrypted storage:**
   - Start the new build on a PC that was already activated. It does not ask for activation again.
   - `%APPDATA%\com.terasoftware\Optics Lab\optics_auth.json` no longer contains `token` or
     `device_key`.
   - `optics_secrets.bin` exists and is unreadable.
2. **Installer:**
   - Build it: `.\installer\build_release.ps1 -Version 1.0.0 -BuildNumber 1 -ApiBaseUrl http://127.0.0.1:8000/api/v1`.
   - Install in Arabic and in English. The shortcut appears and the app starts.
3. **Update:**
   - Build `1.0.1` and upload it in Admin → Desktop app versions.
   - Start 1.0.0: the banner appears. "تحديث الآن" → progress → UAC → the app closes, installs and
     reopens as 1.0.1. You stay activated and logged in.
4. **Checksum:** edit the SHA-256 in Admin to a wrong value (use an external URL row). The update is
   refused with the Arabic "ملف التحديث تالف" message.

---

## What you must do manually to go live

**Accounts and services**
1. **Cloudflare DNS:** add `optics-api` (A/AAAA, proxied).
2. **Cloudflare SSL:** create an **Origin Certificate** for `optics-api.tera-software1.com`. Set SSL to
   **Full (strict)** for this host with a Configuration Rule (don't change the zone).
3. **Cloudflare R2:** create bucket `optics-backups` (private), a 60-day lifecycle rule on `db/`, and an
   API token with read/write on that bucket. Note the account id, key id and secret.
4. **GitHub:** add a read-only **deploy key** for the server (DEPLOY.md step 2).

**Server** (follow `DEPLOY.md` in order; nothing touches the pharmacy)
5. **Check what is there first:** Ubuntu version, existing services, the nginx sites, the Postgres
   version.
6. **User, folders, code:** create user `optics` and `/srv/optics/{static,media,backups}`, then clone
   the repo to `/srv/optics/app`.
7. **Packages and Python:** `apt install python3-venv python3-dev build-essential libpq-dev
   postgresql-client`, then create the venv and install `requirements.txt` + `awscli`.
8. **Database:** create PostgreSQL role and database `optics` with a strong password.
9. **Environment file:** fill `/srv/optics/.env.production` from `deploy/.env.production.example`
   (chmod 600):
   - `SECRET_KEY`, `DATABASE_URL`
   - `ADMIN_URL`, `CSRF_TRUSTED_ORIGINS`
   - the `R2_*` / `AWS_*` values
10. **Before the first deploy:** refresh `backend/config/settings/proxies.py` from
    https://www.cloudflare.com/ips/.
11. **Django:** `check --deploy` → `migrate` → `collectstatic` → `createsuperuser`.
12. **Services:** install the `optics-api.service` unit, then the nginx site, then `nginx -t && systemctl
    reload nginx`.
13. **Verify:** `curl https://optics-api.tera-software1.com/api/v1/health/` returns `status: ok`. Check
    the pharmacy still works.
14. **Backups:** install the backup service and timer, run one backup by hand, and **test a restore**
    into a scratch database.

**Data**
15. **Admin setup:** create the plans, the labs (licenses → activation codes) and any doctors.

**Desktop release** (on your Windows PC, `RELEASE.md`)
16. **Build tools:** install Inno Setup 6.3+.
17. **Build:** `.\installer\build_release.ps1 -Version 1.0.0 -BuildNumber 1` (production URL is the
    default).
18. **Publish:** upload `installer\Output\optics-setup-1.0.0.exe` in Admin → Desktop app versions.
19. **Install at each lab:** install, activate with the lab's code, and log in as the owner. Create staff
    in "المستخدمون".
20. **Optional:** buy a code-signing certificate and sign the installer, so SmartScreen does not warn.
