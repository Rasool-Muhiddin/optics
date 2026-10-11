# CLAUDE.md — Optics Lab Management System (optics)

Management system for optical labs (مختبرات العوينات): eye-exam centers that sell lenses, frames and glasses.
Built by Tera (تيرا) — tera-software1.com. Owner: Eng. Rasool Tahseen.

Read this file fully before every task. It is the source of truth for architecture and conventions.
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

## 3. Repository layout

```
optics_APP/
├── CLAUDE.md
├── backend/                 # Django + Django REST Framework
│   ├── config/              # settings (split: base / local / production), urls, wsgi
│   ├── apps/
│   │   ├── core/            # base models (TimeStamped, LabScoped), health, permissions, pagination
│   │   ├── accounts/        # User, roles, token auth, device activation
│   │   ├── labs/            # Lab (tenant), LabUser membership, settings (print header, logo, currency)
│   │   ├── billing/         # subscription plans, licenses, plan feature flags
│   │   ├── catalog/         # categories, brands, products, lens power variants
│   │   ├── inventory/       # stock movements ledger, stock levels, weighted-average cost
│   │   ├── patients/        # patients, exams, prescriptions
│   │   ├── sales/           # invoices, invoice lines, payments, credit balances
│   │   ├── jobs/            # customer glasses jobs (lifecycle)
│   │   ├── purchasing/      # suppliers, supplier orders, supplier payments
│   │   ├── doctors/         # doctor profiles, doctor↔lab links, referrals
│   │   ├── reports/         # read-only aggregate endpoints
│   │   └── app_updates/     # desktop version check (same mechanism as pharmacy_APP)
│   ├── requirements.txt
│   └── manage.py
└── app/                     # Flutter desktop (Windows primary; Linux/macOS must still compile)
    └── lib/
        ├── main.dart
        ├── core/            # config, theme (RTL), router, errors, formatters
        ├── data/
        │   ├── api/         # one ApiService per domain
        │   ├── cache/       # sqflite_common_ffi cache DB + DAOs
        │   └── repositories/# one Repository per domain (the ONLY thing screens call)
        ├── models/
        ├── services/        # connectivity, auth storage, update, printing
        ├── screens/         # one folder per feature
        └── widgets/
```

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

## 5. Domain model (v1)

All models: `created_at`, `updated_at`, `created_by` where meaningful. Money: `DecimalField(max_digits=14,
decimal_places=2)`. Default currency IQD (lab setting). Never use float for money.

### catalog
- `Category` (tree via `parent`), lab-scoped.
- `Brand`.
- `Product`: `kind` = `frame | stock_lens | rx_lens | contact_lens | accessory | solution | service`,
  name, brand, category, sku/barcode, sale_price, track_stock (bool), is_active, notes.
  - Frame fields: model, color, size (eye–bridge–temple, e.g. 52-18-140), material, gender, shape.
  - Lens fields: material, index (1.50/1.56/1.60/1.67/1.74), design (single vision / bifocal / progressive),
    coatings (multi: AR, blue-cut, photochromic, hard coat…), diameter.
  - Use a `kind`-specific detail table or a validated JSON `attributes` field — keep it extendable.
- `LensVariant` (for `stock_lens` / `contact_lens`): product + `sph` + `cyl` (+ `add` optional).
  **Stock for lenses is tracked per power variant**, not per product.
- `rx_lens` = made-to-order lens: no stock; it is ordered per job from a supplier.

### inventory
- `StockMovement` ledger: item (product or variant), qty (+/−), type
  (`purchase | sale | return_in | return_out | adjustment | damage`), unit_cost, reference (invoice/order).
- Current quantity is derived/maintained atomically (`select_for_update` / `F()` expressions) — no
  read-modify-write from the client.
- Costing: **weighted-average cost** (same approach as pharmacy_APP). Profit reports use it.

### patients
- `Patient`: full_name, age or birth_date, gender, phone, address, notes, status, lab (owner of the record).
- `EyeExam`: patient, date, examined_by (lab user or doctor), diagnosis, diagnosis_details, visual acuity
  (VA) per eye, IOP optional, notes.
- `Prescription` (structured, one per exam, can be standalone):
  per eye (OD right / OS left): `sph`, `cyl`, `axis`, `add`, `prism`, `base`, `va`;
  plus `pd_distance`, `pd_near` (or mono PD per eye), `usage` (distance/near/both), recommended lens
  type/index/coatings, recommended frame notes.
  - Validation: SPH −30..+30 step 0.25; CYL −10..+10 step 0.25 (store minus-cyl convention, offer
    transposition helper); AXIS integer 1..180, required iff CYL ≠ 0; ADD +0.50..+4.00 step 0.25.
- Patient status examples: `new | exam_done | lens_selected | in_job | delivered` — make it a lab-configurable
  list later, enum for now.

### sales
- `Invoice`: number (server-generated, sequential per lab), patient (optional), lines, subtotal,
  line discounts + invoice discount (amount or %), total, paid, balance, `payment_type = cash | credit`,
  status `open | paid | partially_paid | cancelled`, cashier.
- `InvoiceLine`: product/variant, qty, unit_price (copied from server price at sale), discount, line_total,
  unit_cost snapshot for profit.
- `Payment`: invoice, amount, method, date, received_by. Credit (آجل) = invoice with balance > 0 + later payments.
- **The server computes all totals, prices and the invoice number.** The client sends only items, qty and
  requested discounts. Checkout is one atomic endpoint (stock movements + invoice + payment in one transaction).
- Discount above a lab-configured limit requires owner role.

### jobs (customer glasses orders)
- `Job`: patient, prescription, frame (product or "customer's own frame"), lenses (stock variant or rx_lens),
  invoice link, status `pending | lens_ordered | in_workshop | ready | delivered | cancelled`,
  promised_date, notes, status history (`JobStatusLog`).

### purchasing (supplier orders — نافذة الطلبات)
- `Supplier`: name, phone, address, notes, balance.
- `SupplierOrder`: supplier, order_date, type (`stock | rx_for_job | other`), linked job (optional), items,
  total, `payment_status = unpaid | partial | paid`, status `pending | ordered | received | partially_received
  | cancelled`, expected_date, notes.
- Receiving an order creates `purchase` stock movements and updates weighted-average cost.
- `SupplierPayment`. Pending orders screen = filter by status + age.

### doctors
- `DoctorProfile`: user, full name, specialty, clinic name, phone.
- `DoctorLabLink` (see §4).
- `Referral`: doctor → lab, patient snapshot (name, age, gender, phone), exam + prescription data,
  notes, status `sent | received | in_progress | completed | rejected`.
  Accepting a referral creates/links a `Patient` + `EyeExam` + `Prescription` in that lab.
  The doctor sees referral status only — not the lab's invoices or prices.

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

- Arabic-first UI: `Directionality(textDirection: TextDirection.rtl)`, Arabic font bundled
  (e.g. Cairo or Noto Naskh Arabic), all strings in one place for future localization.
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

### Decisions recorded in P0
- Backend: `django-environ` for settings (`.env.local` read by `base.py` in dev only);
  `requirements.txt` (runtime) + `requirements-dev.txt` (pytest). Custom `accounts.User` (AbstractUser)
  exists from day one. `core.TimeStampedModel` is in place; `LabScopedModel` + lab-scoped base viewset
  come in P1 with `labs.Lab`. Tests are written as `APITestCase`/`TestCase` classes so both `pytest` and
  `python manage.py test` run them.
- Error format: `{ "detail", "code" }`; validation errors use `code = "validation_error"` and add `errors`
  (per-field dict). Raise business errors with `apps.core.exceptions.APIError(detail, code=...)`.
- `GET /api/v1/health/` is public and also checks the DB (`503` + `status: degraded` if the DB is down).
- Flutter: bundled font is **Noto Naskh Arabic** (OFL). All UI strings in `lib/core/strings/app_strings.dart`;
  Arabic error messages by `code` in `lib/core/errors/error_messages.dart`. HTTP via `package:http`
  (`ApiClient`, explicit `Content-Length`). Requires Flutter with Dart ≥ 3.12 (current deps).

### Decisions recorded in P1
- **One lab per user**: `LabUser.user` is a `OneToOneField` (`user.lab_membership`). The request's lab is
  always resolved from the token's user — never from client input. Doctors (P7) are users without a membership.
- **Tenancy plumbing** (all in `apps.core`): `LabScopedModel` (abstract, `lab` FK, `.for_lab()`);
  `LabAccess` permission sets `request.lab` / `request.lab_user` and blocks with codes `no_lab_membership`,
  `membership_inactive`, `lab_inactive`, `no_license`, `license_expired`; `IsLabOwner`,
  `IsLabOwnerOrReadOnly` (`owner_required`); `requires_feature("<flag>")` (`feature_not_in_plan`).
  Viewsets over lab-owned models use `LabScopedViewSet` / `LabScopedNoDeleteViewSet` /
  `LabScopedReadOnlyViewSet` (filter by lab, set `lab` + `created_by` on create); FKs to lab-owned rows use
  `LabScopedPrimaryKeyRelatedField`. `core/tests/test_tenancy.py` walks the URLconf and fails if a view over a
  `LabScopedModel` skips `LabScopedMixin`. Test helpers live in `apps.core.testing`.
- **Billing**: `Plan` has explicit boolean flag fields listed in `billing/features.py::FEATURE_FLAGS`
  (`doctor_linking`, `report_export`) + limits `max_users`, `max_devices` (0 = unlimited). One `License`
  per lab (`starts_on`, `expires_on` null = never, `is_active`). Limits are enforced in the API and in model
  `clean()` (so Django Admin respects them too).
- **Devices & tokens**: DRF `authtoken` was replaced by `accounts.AuthToken` (one token per login/device,
  stored as SHA-256 digest, header still `Authorization: Token <key>`) via
  `accounts.authentication.DeviceTokenAuthentication`. `accounts.Device` = an activated installation
  (`device_id` from the app, server-generated `device_key` stored as digest). Activation:
  `POST desktop/activate/ {activation_code, device_id, device_name, app_version}` → `device_key`
  (re-activating the same `device_id` reuses its slot, rotates the key and revokes its tokens). Login:
  `POST desktop/login/ {username, password, device_key}` → `token` + session payload (user, membership, lab,
  plan features/limits, device); the user's lab must equal the device's lab (`device_lab_mismatch`).
  `GET auth/me/` returns the same payload; `POST auth/logout/` revokes only this token; deactivating a device
  revokes its tokens immediately (`device_deactivated`). Activation/login are throttled (`AUTH_THROTTLE_RATE`).
  Lab `activation_code` (12 hex chars, case/dash-insensitive) is created with the lab and is not exposed by
  the API — Tera hands it out.
- Other P1 endpoints: `GET/PATCH lab/` (lab settings; owner edits), `lab/users/` (owner manages users,
  creates their login; no delete), `lab/devices/` (owner renames/deactivates). `LabUser.can_view_costs`
  lets staff see costs/profit (owners always can; exposed as `membership.can_view_costs`).
- Business-rule errors raised from serializers use `APIError` (not `ValidationError`) so `code` survives.
- Tests use `config.settings.test` (local + MD5 hasher) via `pytest.ini`; `manage.py test` still works.
  Dev helper: `python manage.py create_lab "<name>" <owner_username> <password> [--plan code]`.
- **Real client IP (post-P1 fix)**: throttles key on `apps.core.client_ip.get_client_ip` via
  `apps.core.throttling.ClientIPScopedRateThrottle`. Forwarding headers are believed only when the direct
  peer is in `TRUSTED_PROXIES` (IPs/CIDRs; empty in dev → `REMOTE_ADDR`). Production defaults to loopback
  (nginx) + Cloudflare ranges (`config/settings/proxies.py`, toggle `TRUST_CLOUDFLARE`). `CF-Connecting-IP`
  is used only if the hop that reached nginx is itself trusted (a Cloudflare edge); otherwise
  `X-Forwarded-For` is walked right-to-left skipping trusted hops. nginx must keep
  `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;` and pass `CF-Connecting-IP` through.
- Flutter: `AuthStorage` persists device id/key, lab, token and the last session JSON in
  `optics_auth.json` (app-support dir, plain JSON — no new plugin). `AuthController`
  (`AsyncNotifier<AuthState>`: `NeedsActivation | LoggedOut | LoggedIn`) drives go_router redirects
  (`authRedirect`). At startup a stored token is checked with `auth/me/`; if the server is unreachable (or
  5xx) the stored session is used read-only; 401/403 → login with the Arabic reason. Any 401 on an
  authenticated request ends the session (`ApiClient.onUnauthorized`). Activating for a different lab wipes
  the read cache. Sidebar sections live in `screens/shell/nav_items.dart` (`ownerOnly` / `feature` only hide
  items; the router also blocks direct navigation); unbuilt sections show a "coming soon" page.
  `httpClientProvider` is the seam for tests (`MockClient`).

### Decisions recorded in P2
- **Permission bug fixed (from P1)**: `IsLabOwner` / `IsLabOwnerOrReadOnly` / `requires_feature` ignored
  `LabAccess` returning False, so anonymous GETs passed (empty lists / 500). They now return False → 401.
  `core/tests/test_permissions.py::AnonymousIsRejectedEverywhereTests` walks every `/api/v1/` route.
- **Catalog**: `Category` (tree, cycle-checked), `Brand` (unique name per lab) and `Product` are lab-scoped;
  `Product.kind` per §5; kind-specific details in validated JSON `attributes` (`catalog/attributes.py`
  holds the schema per kind — unknown keys rejected; add a key there + in the Flutter `AttributeSpec`).
  `rx_lens` / `service` force `track_stock=False`; `stock_lens` / `contact_lens` force `True` and keep stock
  on `LensVariant` (SPH + CYL ≤ 0 minus-cyl + ADD, **ADD 0 = none**, not null, so the unique constraint
  works on every DB). `sku`/`barcode` unique per lab across products *and* variants. Variants may override
  `sale_price` (null = product price). Kind cannot change, and a variant's power cannot change, once
  stock history exists. Catalog writes are **owner-only** (`IsLabOwnerOrReadOnly`); everyone reads.
- **Stock**: `inventory.services.record_movement()` is the only writer of `quantity` / `average_cost`
  (row lock via `select_for_update`, must run in `transaction.atomic()`); `Product.quantity` mirrors the
  sum of its variants (F() update) for lists/low-stock. **No negative stock** (`insufficient_stock`).
  `StockMovement` is an immutable ledger (`qty` signed, `unit_cost`, `qty_after`, `average_cost_after`,
  `reference_type`/`reference_id`; admin read-only). Weighted-average cost changes only on incoming
  movements with a stated cost (`purchase`, or a positive `adjustment` with `unit_cost` = opening stock);
  everything else is valued at the current average. `average_cost` is stored with 2 decimals
  (ROUND_HALF_UP) — fine for IQD. `Product.purchase_price` is a reference price (last/expected), editable.
- **Manual stock entry** `POST inventory/movements/ {type, note, lines:[{product|variant, qty, unit_cost?}]}`
  is **owner-only** and atomic across lines (the lens grid posts many powers at once). Types: purchase,
  adjustment (signed), damage, return_in, return_out. Sales post `sale` movements from checkout (P4).
- **Cost hiding**: `core.costs.CostFieldsMixin` drops `cost_fields` from serializers (not rendered, not
  accepted) unless `lab_user.sees_costs`. Ordering by cost fields is not allowed (would be an oracle).
  `inventory/tests/test_stock.py::CostVisibilityTests` scans every catalog/inventory response for cost keys.
- Other endpoints: `catalog/products/{id}/grid/` (unpaginated variants for the power grid),
  `catalog/products/{id}/generate-variants/` (SPH×CYL range, ≤ 2000, existing skipped),
  `catalog/lookup/?code=` (barcode/SKU → product + variant), `catalog/options/` (kinds + choices).
  Shared optics rules (ranges, 0.25 steps, axis, transposition) live in `apps/core/optics.py`.
- Flutter: cache v2 adds tables `products, categories, brands, lens_variants, stock_movements`
  (`JsonCacheDao`, offline filtering in Dart via `ProductQuery.matches`); `NotCachedException`
  (`not_cached`) when offline and never cached. Screens: `/inventory` (filters, cost column only when the
  session `can_view_costs`), `/inventory/:id` (info, lens power grid with ADD selector, grid entry mode,
  per-power edit/stock, ledger). Shared widgets in `widgets/common.dart`; power helpers in
  `core/optics/powers.dart`. Test helpers: `FakeAuthServer.routes`, `openTestCache()` (no-isolate ffi),
  `loggedInStorage()` / `loggedInServer()`.

## 8. Environments & deployment

- Dev machine: Windows. Backend runs locally with `.env.local` (never committed). Postgres in production,
  SQLite allowed for local dev.
- Production (proposed): same Hetzner server as pharmacy backend, separate Django project/service and
  database, subdomain e.g. `optics-api.tera-software1.com`, nginx + gunicorn + systemd, Cloudflare SSL,
  daily DB backup to R2, `DEBUG=False`, strong `SECRET_KEY`, `ALLOWED_HOSTS`, `DATABASE_URL`.
- Do NOT touch the pharmacy_APP project, its database or its service.

### Cloud-session note (Claude Code on the web)
The cloud sandbox is Linux with no display: it cannot run or visually test the Windows app.
In cloud sessions: write code, run `python manage.py test` / `pytest`, `python manage.py makemigrations --check`,
`flutter analyze`, `flutter test`. Visual testing and `flutter build windows` happen on the owner's PC.
Keep each session to one roadmap item; commit with clear messages.

---

## 9. Roadmap (one item per session, in order)

- [x] **P0 Scaffold**: Django project + apps skeleton, settings split, DRF, token auth, health endpoint,
      pytest setup; Flutter desktop project with RTL theme, router, ApiService base, ConnectivityService,
      cache DB base, repository base class.
- [x] **P1 Accounts & tenancy**: Lab, LabUser roles, lab-scoped base viewset, activation/login, billing plans
      + feature flags, Django Admin for all of it. Flutter: activation + login + main layout with sidebar.
- [x] **P2 Catalog & inventory**: categories, brands, products by kind, lens power variants, stock ledger,
      weighted-average cost. Flutter: inventory screens (list, filters, add/edit per kind, lens power grid).
- [ ] **P3 Patients, exams, prescriptions**: models, validation, transposition helper. Flutter: patient
      profile, exam history, Rx entry form (OD/OS table), print prescription + exam report.
- [ ] **P4 POS & sales**: atomic checkout, discounts, credit + payments, invoice numbering. Flutter: POS
      screen, credit customers list, invoice print (A4/A5 + thermal).
- [ ] **P5 Customer jobs**: lifecycle + status log, link to invoice/prescription. Flutter: jobs board.
- [ ] **P6 Supplier orders**: suppliers, orders, receiving → stock, payments. Flutter: pending orders screen.
- [ ] **P7 Doctor linking**: doctor accounts, links, referrals, accept → patient/exam/Rx in lab.
      Flutter: doctor mode (separate sidebar), lab inbox for referrals. Gated by plan flag.
- [ ] **P8 Dashboard & reports**: sales, profit, credit balances, stock low/levels, jobs overdue,
      supplier balances; export gated by plan.
- [ ] **P9 Offline read cache** completion across all domains + offline banners.
- [ ] **P10 Release**: Inno Setup installer, update endpoint, production deploy, production build.
      Before release: move token/device-key storage from plain `optics_auth.json` to encrypted storage
      (Windows DPAPI via `CryptProtectData`, or equivalent: Keychain on macOS, libsecret on Linux), with a
      one-time migration of the existing file and deletion of the plain copy.

---

## 10. Rules

- Never trust client-sent prices, totals, costs or invoice numbers.
- All multi-row writes (checkout, receiving, referral accept) in `transaction.atomic()`.
- Every new model: admin registration, serializer, lab-scoping, tests, migration.
- No hard deletes for business records (invoices, payments, stock movements, exams); use cancel/void flags.
- Keep this file updated: tick roadmap items and record any architectural decision here when it changes.
