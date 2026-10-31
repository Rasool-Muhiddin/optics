# CLAUDE.md — Optics Lab Management System (optics)

Management system for optical labs (مختبرات العوينات): eye-exam centers that sell lenses, frames and glasses.
Built by Tera (تيرا) — tera-software1.com. Owner: Eng. Rasool Tahseen.

Read this file fully before every task. It is the source of truth for architecture and conventions;
the per-phase decisions, domain model and roadmap it links to live in `docs/claude/` (see "Where the details live").
If a task conflicts with this file, stop and ask instead of guessing.

---

## 1. Product summary

Desktop app for the lab, plus an optional doctor account.

- **Inventory**: lenses, frames, contact lenses, accessories, with categories and full item details
  (purchase price, sale price, quantity, type, brand, etc.).
- **POS (نافذة البيع)**: direct sale, credit sales (بالآجل) with later payments, discounts, invoice printing.
- **Patients (المراجعين)**: profile, exam history, diagnosis, prescription (Rx), chosen lens/frame, status.
- **Doctor accounts (optional)**: a doctor sends a patient's data/prescription to a lab, so the lab
  dispenses the right lens. Labs without a doctor ("free labs") must work fully without this feature.
- **Printing**: prescriptions, vision-exam reports, invoices, and any document a patient takes to another lab.
- **Supplier orders (الطلبات)**: what the lab ordered from suppliers, when, from whom, type, paid or not, status.
- **Customer jobs (طلبات الزبائن)**: where each customer's glasses are (ordered → in workshop → ready → delivered).

The structure must stay flexible: more screens and fields will be added later.

---

## 2. Architecture decision: ONLINE-FIRST

Decided deliberately — do not reintroduce a full offline mode.

- The Django server is the **single source of truth**. All writes go to the API.
- Flutter keeps a **local SQLite cache (read-only)** so that during an internet outage the user can still
  browse patients, inventory, orders, and print prescriptions/reports from cached data.
- **Writes are blocked when offline** (no local write queue). Show a clear Arabic message.
- Connectivity = real server reachability via `GET /api/v1/health/`, not just network presence.
- Phase-2 option (NOT now): an offline queue for sales only, if customers ask for it.

Why: doctor→lab linking needs a server anyway; optical sales volume is low and jobs take days, so short
outages are tolerable; patient history must not be lost with a broken PC; multi-device from day one;
avoids building and maintaining every domain twice (lesson learned from pharmacy_APP).

---

## 4. Tenancy, roles, accounts

- **Lab** is the tenant. Every lab-owned row has `lab` FK. Every queryset is filtered by the lab of the
  request's token — enforce in a shared base viewset/mixin, never per-view by hand.
- **LabUser** roles: `owner`, `staff` (extendable to `optometrist`, `technician`). Owner manages users, prices,
  reports. Staff can sell and manage patients but not see purchase prices/profit unless permitted.
- **Doctor** is an independent account, NOT a lab member. A doctor can link to many labs; a lab can link to
  many doctors (`DoctorLabLink`: status `pending | accepted | rejected | revoked`). Either side can request.
- Accounts for labs are created by Tera via Django Admin (no public self sign-up for labs in v1).
- Licenses/plans live in `billing` with feature flags (e.g. `doctor_linking`, `report_export`, `max_devices`,
  `max_users`). Check flags server-side; the UI only hides/disables.

---

## Key invariants (apply to almost every task)

- **Tenancy**: the request's lab comes from the token's user (`LabUser.user` is one-to-one) — never from client
  input. Views over lab-owned models use `LabScopedViewSet` / `LabScopedNoDeleteViewSet` /
  `LabScopedReadOnlyViewSet`; FKs to lab rows use `LabScopedPrimaryKeyRelatedField`.
  `core/tests/test_tenancy.py` fails if a view skips `LabScopedMixin`.
- **Errors**: business-rule errors raise `apps.core.exceptions.APIError(detail, code=...)` (also inside serializers,
  so `code` survives). Arabic messages are produced in Flutter from `code` (`lib/core/errors/error_messages.dart`).
- **Stock**: `inventory.services.record_movement()` is the only writer of `quantity` / `average_cost` (row lock,
  inside `transaction.atomic()`); no negative stock; `StockMovement` is an immutable ledger.
- **Costs**: cost fields are hidden (not rendered, not accepted) unless `lab_user.sees_costs` (`CostFieldsMixin`);
  never allow ordering by cost fields.
- **Prescriptions** are stored and printed exactly as entered (plus-cyl stays plus-cyl); the normalized minus-cyl
  copy is internal only.
- **Flutter UI**: every string in `lib/core/strings/app_strings.dart`; colours from the theme / `AppColors.of(context)`
  (never `Colors.green…`); shared widgets in `widgets/ui.dart` + `widgets/common.dart`; screens call repositories only.

## Where the details live (read the relevant part before changing a domain)

- `docs/claude/decisions.md` — every architectural decision by phase: P0 scaffold, P1 accounts/tenancy/devices/
  billing, P2 catalog/inventory, P3 patients/exams/Rx/printing, P4 POS/sales, P5 jobs, pre-P6 Rx + inventory
  permission, P6 supplier orders, P7 doctor linking, P8 reports/settings, Users screen, P9 offline sync,
  P10 secrets/updates/installer/deploy, owner UX review, UI redesign. Grep it for the app or feature you touch.
- `docs/claude/domain-model.md` — v1 domain model and validation ranges (catalog, inventory, patients/Rx, sales,
  jobs, purchasing, doctors).
- `docs/claude/roadmap.md` — the roadmap (P0–P10 all done).

Section numbers are kept from the original single file (§3 repository layout was dropped, §5 and §9 moved), so
references like "§5" inside `decisions.md` still point to the right place.

---

## 6. API conventions

- Django REST Framework, base path `/api/v1/`. Token auth (same style as pharmacy_APP).
- Pagination on every list endpoint; filtering/search with `django-filter`.
- Errors: JSON `{ "detail": "...", "code": "..." }`; Arabic user-facing messages are produced in Flutter from
  `code`, not hard-coded in the backend.
- Desktop endpoints reused from pharmacy_APP style: `POST /api/v1/desktop/activate/`,
  `POST /api/v1/desktop/login/`, `GET /api/v1/desktop/latest-version/`, `GET /api/v1/health/`.
- Every endpoint gets tests (pytest + pytest-django): permissions, lab isolation (lab A can never read lab B),
  and the main happy path.

---

## 7. Flutter conventions

- Arabic-first UI: `Directionality(textDirection: TextDirection.rtl)`, Arabic fonts bundled
  (IBM Plex Sans Arabic for the UI, Noto Naskh Arabic for PDFs), all strings in one place for future localization.
- Screens call **repositories only**. Repository decides: online → API then refresh cache; offline → cache
  read; offline write → throw a typed exception shown as an Arabic message.
- `ConnectivityService` pings `/api/v1/health/`.
- API base URL via `--dart-define=API_BASE_URL=...` (default `http://127.0.0.1:8000/api/v1` for dev).
- Known Windows issue from pharmacy_APP: set `Content-Length` explicitly on JSON POSTs (Django runserver does
  not handle chunked requests well).
- Cache DB: `sqflite_common_ffi` + `sqlite3_flutter_libs`, rows keyed by server id, `last_synced_at`.
  (`package:sqlite3` 3.x bundles SQLite itself via build hooks; `sqlite3_flutter_libs` is pinned to the
  no-op `0.6.0+eol` so the old 0.5.x build scripts are never pulled in.)
- State management: **Riverpod** (`flutter_riverpod` 3.x), decided in P0 — use it everywhere. Routing: `go_router`.
- Printing: generate PDFs in Flutter with the `pdf` + `printing` packages (works from cache while offline).
  Templates: prescription, exam report, invoice (A4/A5 and 80mm thermal), job ticket.
  Header uses lab settings (name, logo, phone, address).
- Reuse from pharmacy_APP (copy & adapt, do not import across repos): activation flow, auth storage,
  update service (Inno Setup installer download), connectivity service.
- Target Flutter 3.44.8 (Dart 3.12.2), the owner's local version. In cloud sessions install exactly this version, not the latest, and never raise package constraints beyond what it supports.


---

## 8. Environments & deployment

- Dev machine: Windows. Backend runs locally with `.env.local` (never committed). Postgres in production,
  SQLite allowed for local dev.
- Production: same Hetzner server as pharmacy backend, separate Django project/service and
  database, `optics-api.tera-software1.com`, nginx + gunicorn + systemd, Cloudflare SSL,
  daily DB backup to R2, `DEBUG=False`, strong `SECRET_KEY`, `ALLOWED_HOSTS`, `DATABASE_URL`.
  Step by step: `DEPLOY.md` (files in `deploy/`); desktop releases: `RELEASE.md` (files in `installer/`).
- Do NOT touch the pharmacy_APP project, its database or its service.

### Cloud-session note (Claude Code on the web)
The cloud sandbox is Linux with no display: it cannot run or visually test the Windows app.
In cloud sessions: write code, run `python manage.py test` / `pytest`, `python manage.py makemigrations --check`,
`flutter analyze`, `flutter test`. Visual testing and `flutter build windows` happen on the owner's PC.
Keep each session to one roadmap item; commit with clear messages.

---

## 10. Rules

- Never trust client-sent prices, totals, costs or invoice numbers.
- All multi-row writes (checkout, receiving, referral accept) in `transaction.atomic()`.
- Every new model: admin registration, serializer, lab-scoping, tests, migration.
- No hard deletes for business records (invoices, payments, stock movements, exams); use cancel/void flags.
- Keep the docs updated: tick roadmap items in `docs/claude/roadmap.md` and record any architectural decision as a
  new section in `docs/claude/decisions.md` (only rules every task needs belong in this file).
