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
  - Validation: SPH −30..+30 step 0.25; CYL −10..+10 step 0.25 (stored and printed **as entered**,
    plus- or minus-cyl; a normalized minus-cyl copy is kept for internal use; transposition helper
    offered); AXIS integer 1..180, required iff CYL ≠ 0; ADD +0.50..+4.00 step 0.25.
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
  stock history exists. Catalog writes: owner or staff with `can_manage_inventory`
  (`CanManageInventoryOrReadOnly`, see "Pre-P6 changes"); everyone reads.
- **Stock**: `inventory.services.record_movement()` is the only writer of `quantity` / `average_cost`
  (row lock via `select_for_update`, must run in `transaction.atomic()`); `Product.quantity` mirrors the
  sum of its variants (F() update) for lists/low-stock. **No negative stock** (`insufficient_stock`).
  `StockMovement` is an immutable ledger (`qty` signed, `unit_cost`, `qty_after`, `average_cost_after`,
  `reference_type`/`reference_id`; admin read-only). Weighted-average cost changes only on incoming
  movements with a stated cost (`purchase`, or a positive `adjustment` with `unit_cost` = opening stock);
  everything else is valued at the current average. `average_cost` is stored with 2 decimals
  (ROUND_HALF_UP) — fine for IQD. `Product.purchase_price` is a reference price (last/expected), editable.
- **Manual stock entry** `POST inventory/movements/ {type, note, lines:[{product|variant, qty, unit_cost?}]}`
  is owner / `can_manage_inventory` only and atomic across lines (the lens grid posts many powers at once). Types: purchase,
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

### Decisions recorded in P3
- **Validation error codes**: validation responses now also carry `error_codes` (same shape as `errors`,
  DRF codes instead of English text). Flutter maps them to Arabic (`fieldCodeMessage(error, path)`,
  `errorMessageFor` prefers the first known nested code).
- **Patient**: lab-scoped; `age` may be sent instead of `birth_date` and is stored as an estimated
  birth date (`birth_date_estimated=true`), so the age stays right in later years. Status is the §5 enum and
  only moves forward automatically (exam/Rx → `exam_done`); it can be set by hand on edit. No delete:
  `is_archived`. Any lab member (staff included) manages patients, exams and prescriptions.
- **Exams & Rx**: `EyeExam` (+ VA/IOP per eye, `examined_by` = recording user unless an external
  `examiner_name` is typed) and `Prescription` (OneToOne `exam`, null = standalone). Exams are created/edited
  with a nested `prescription` in one transaction; the nested Rx must be sent complete. Records are
  **voided, never deleted** (`VoidableModel`: `is_void`, reason, who/when; `POST …/void/`, owner or author
  only; voiding an exam voids its Rx; voided records are read-only, `record_void`). Exam patient cannot
  change (`patient_locked`).
- **Rx rules** (`patients/rx.py`): SPH/CYL/ADD per §5 in 0.25 steps; AXIS 1..180 required iff CYL ≠ 0 and
  dropped when CYL = 0; an eye may be left completely empty but at least one eye needs SPH (`rx_empty`);
  SPH required for an eye that has any power (`sph_required`); prism 0.25..20 needs a base (up/down/in/out);
  PD 40..85 (mono 20..45) in 0.5 mm steps; lens design/index/coatings use the catalog choices.
  ~~Plus-cylinder input is transposed to minus-cyl on save~~ — **replaced** (see "Pre-P6 changes"): the Rx
  is stored and printed exactly as entered. `POST patients/transpose/` and the form's ± button offer the
  helper explicitly. Endpoints: `patients/`, `patients/exams/`,
  `patients/prescriptions/` (filters `patient`, `is_void`…).
- **Printing**: `pdf` + `printing` packages. `services/printing/pdf_kit.dart` (fonts, lab header/footer,
  tables) — Noto Naskh Arabic has **no Latin glyphs**, so Helvetica is the PDF font fallback; Rx tables are
  printed LTR (OD/OS, SPH…) inside an RTL page. Prescription = A5, exam report = A4 (`patient_pdfs.dart`).
  `PrintService` (`printServiceProvider`) sends bytes to `Printing.layoutPdf`; tests inject `printer`.
  The lab logo is downloaded when online and kept on disk (`LogoCache`) so offline prints keep it.
  Linux builds of `printing` download pdfium at CMake time (needs network once).
- Flutter: cache v3 adds `patients, eye_exams, prescriptions`. Screens `/patients` (search name/phone,
  status filter) and `/patients/:id` (profile, exams tab with Rx summary + print/edit/void, prescriptions
  tab). Reusable `widgets/rx_form.dart` (`RxFormController` mirrors the server rules, ± transposition).
  `patientExtraActionsProvider` lets later phases add buttons (new sale/job) to the profile header.
  All `DropdownButtonFormField`s use `isExpanded: true` (avoids overflow with long Arabic labels).

### Decisions recorded in P4
- **Checkout** `POST sales/checkout/` (atomic: number → invoice → lines → `sale` movements → payment) takes
  only `lines [{product|variant, qty, discount | discount_percent}]`, `invoice_discount_type/value`,
  `payment_type`, `patient` or walk-in `customer_name/phone`, `payment {amount, method}`, `notes`. Any
  client price/total/number is ignored. `POST sales/checkout/preview/` returns the server's pricing for the
  same body (incl. `available` stock per line and `requires_owner`) and saves nothing — the POS shows totals
  only from it (no client money arithmetic). Variant `sale_price` overrides the product price.
- **Numbering**: `sales.InvoiceCounter` (one row per lab, `select_for_update`), sequential integers from 1;
  a failed checkout does not consume a number.
- **Discount limit**: `Lab.max_discount_percent` (default 10, owner edits via `PATCH lab/`). Total discount
  (line + invoice) as % of the subtotal above the limit → staff get 403 `discount_requires_owner`; owner
  unlimited. Discounts can't exceed the amount (`invalid_discount`).
- **Payments / credit**: cash sales are always paid in full at checkout. **Credit (آجل) requires a patient
  file** (`credit_requires_patient`) so balances belong to someone; an optional down payment. Status:
  `open` (nothing paid) / `partially_paid` / `paid` / `cancelled`, recomputed from non-void payments.
  `POST sales/invoices/{id}/payments/` (any member, no overpayment), `POST sales/payments/{id}/void/`
  (owner). `GET sales/credit-customers/` aggregates open balances per patient; `POST
  sales/credit-customers/{patient}/pay/` spreads one payment over the oldest invoices first.
- **Cancel** `POST sales/invoices/{id}/cancel/` (owner): stock returns as `return_in` at the sold unit
  cost (average restored), payments are voided (money refunded), invoice kept with reason. Invoices are
  read-only otherwise (no edit/delete, admin read-only).
- **Costs**: lines snapshot `unit_cost` (average at sale; for non-stock kinds the product's reference
  `purchase_price`); invoice `cost_total`/`profit` and line `unit_cost` are cost fields (hidden from staff
  without `can_view_costs`). A checkout moves the patient to `lens_selected` (forward only).
- Lookups for missing barcodes / other-lab patients now answer **404** (`not_found`).
- Flutter: cache v4 `invoices, credit_customers` (invoice detail cached with lines → printable offline;
  selling itself needs the server — `OfflineWriteException`). `PosController` (kept alive across navigation)
  holds items only; `cartPreviewProvider` re-prices on every change. Lens powers are picked from the power
  grid. Barcode scanners type + Enter → `catalog/lookup/`. New sidebar sections `/invoices` (+ detail with
  payments, owner cancel/void, prints) and `/credit`. Patient profile gets a "بيع" action (POS with that
  patient). Invoice PDFs: A4/A5 table layout and 80 mm roll (`PdfPageFormat.roll80`) compact layout.
  Dialogs that own `TextEditingController`s are StatefulWidgets (disposing after `showDialog` returns
  crashes during the exit animation).

### Decisions recorded in P5
- **Job**: lab-scoped, server-numbered per lab (`jobs.JobCounter`, like invoices); links: `patient`
  (required, cannot change), `prescription` (must be that patient's, not void), `invoice` (same patient when
  the invoice has one, not cancelled); `frame_source` = `lab` (optional frame product, kind `frame`) |
  `customer` ("customer's own frame", no product, describe it in `frame_notes`) | `none` (lenses only);
  `lens` product (stock / rx / contact lens) with optional stock powers per eye (`lens_od`, `lens_os`, must
  belong to that lens) and `lens_notes`; `promised_date`; `notes`.
- **Jobs do not move stock** — stock leaves at checkout (P4); the job only tracks where the glasses are.
  Ordering an `rx_lens` from a supplier is P6 (`SupplierOrder.type = rx_for_job`, linked job).
- **Lifecycle**: `pending → lens_ordered → in_workshop → ready → delivered`, `cancelled` from any open
  status; also allowed: `lens_ordered → pending`, `in_workshop → lens_ordered` (re-order), `ready →
  in_workshop` (rework), and skipping forward (`pending → in_workshop/ready`). `delivered`/`cancelled` are
  final (no moves, no edits: `job_closed`). Status changes only via `POST jobs/{id}/status/ {status, note}`
  (`invalid_transition`), each one written to `JobStatusLog` (who/when/note; creation logs `'' → pending`).
  Patient status follows forward only: job created → `in_job`, delivered → `delivered`.
- **Overdue** = `promised_date < today` while `pending | lens_ordered | in_workshop` (a `ready` job waits on
  the customer, it is not late). Exposed as `is_overdue`, filter `?overdue=true`, `GET jobs/summary/`
  (counts per status + overdue). Any lab member manages jobs.
- Flutter: cache v5 `jobs`; `/jobs` Kanban board (open jobs + delivered in the last 14 days, overdue first
  with a red border/badge, "move to next" button + full status dialog), `/jobs/:id` detail (history, edit,
  status, print), job form (patient picker, Rx and invoice of that patient, frame source, product pickers,
  lens powers picked from the power grid). Patient profile: "طلب نظارة جديد" action + jobs tab. Shared
  pickers in `widgets/product_pickers.dart` / `widgets/patient_picker.dart`. Job ticket PDF: A5 or 80 mm
  (patient, promised date, frame, lens powers, Rx table + PD, invoice balance, signature line).
  `Job.overdueOn(today)` re-evaluates overdue for cached rows offline.

### Decisions recorded before P6 (changes to existing work)
- **Rx as entered (replaces the P3 "transpose on save" rule)**: `Prescription.od_*/os_*` are stored, returned
  and printed exactly as typed — plus-cyl stays plus-cyl. `Prescription.save()` always recomputes a
  normalized minus-cyl copy `od_mc_sph/cyl/axis`, `os_mc_*` (`normalize()`, `minus_cyl(eye)`), never exposed by
  the API nor printed — internal only (stock matching, comparisons). Migration `patients.0002` fills the copy
  for old rows (they were stored minus-cyl already, so their values stay as they are). Validation is unchanged
  (CYL −10..+10). `GET catalog/products/{id}/match/?prescription=` returns the stock power per eye matching
  the Rx (minus-cyl copy + ADD; axis is not part of a stock power); the job form's "اختيار القوى المطابقة
  للوصفة" uses it. `Prescription.summary` / PDFs format signs with `Powers.format` (`PatientPdfs.rxRows`).
- **`LabUser.can_manage_inventory`** (separate from `can_view_costs`; owners always have both): create/edit
  categories, brands, products, lens variants, generate powers, and record manual stock entries (purchase,
  adjustment, damage, returns). Permissions `CanManageInventory` / `CanManageInventoryOrReadOnly`
  (code `inventory_permission_required`). Costs stay hidden (and cost fields are not accepted, e.g.
  `purchase_price`) unless `can_view_costs` too; such staff *may* type a purchase `unit_cost` (needed for the
  weighted average) but never get costs back. Exposed as `membership.can_manage_inventory` in the session
  (`Session.canManageInventory` in Flutter), on `lab/users/` and in Django Admin.

### Decisions recorded in P6
- **Models** (`purchasing`): `Supplier` (unique name per lab, no delete, `is_active`); `SupplierOrder` numbered per
  lab (`SupplierOrderCounter`), `type` stock | rx_for_job | other, `job` (rx_for_job only, required there),
  `status` pending (not sent yet) | ordered | partially_received | received | cancelled, `payment_status`
  unpaid | partial | paid, `order_date`, `expected_date`, `supplier_ref`; stored `total` / `paid` / `balance`
  recomputed by `refresh_totals()` (like invoices). `SupplierOrderLine`: product and/or variant or free-text
  `description`, `eye` (od/os for rx), `qty`, `unit_cost`, `qty_received`. `SupplierPayment` (always against
  one order; voided, never deleted). Orders are read-only in Django Admin (writes only through services).
- **Supplier balance is not stored**: `Σ order.balance` (annotated). A cancelled order is payable only for what
  was received (`payable`); cancelling is refused while more was paid than received (`cancel_refund_required`).
  No opening-balance field: enter an old debt as an `other` order (free-text line).
- **Statuses**: new orders default to `ordered` (the form's "تم إرسال الطلب" box; `pending` = draft not sent);
  manual moves only pending ⇄ ordered (`POST …/status/`); `partially_received` / `received` only by receiving;
  `cancelled` by `POST …/cancel/ {reason}` (the rest of the order; received stock stays). Editing (lines replaced
  wholesale) only while pending/ordered with nothing received (`order_locked`). Paying a `pending` order is
  refused (`order_not_sent`).
- **Receiving** `POST …/receive/ {lines?: [{line, qty}], supplier_ref?}` (no lines = everything remaining), one
  transaction: `purchase` movements (`reference_type="supplier_order"`) at the line cost → weighted average;
  non-stock lines (rx lens, service) are only marked received; the product's reference `purchase_price` becomes
  the last received cost. Over-receiving → `over_receive`. Stock orders accept stock-tracked products only.
- **rx_for_job ↔ job**: placing an rx order (status `ordered`) moves its job `pending → lens_ordered` (logged
  "PO #n"). Free-text lines of an rx order become the job's lens product (when it has no variants).
  `apply_job_lens_cost(job)` (on receive, cancel, and when a job's invoice/lens is edited) sets the job
  invoice's lines for that lens to the **received supplier cost** (Σ received value ÷ sold qty) and recomputes
  `cost_total`; with nothing received it falls back to the reference price. New `InvoiceLine.cost_source`
  = average | reference | supplier (cost field; migration marks old non-stock lines `reference`). Jobs expose
  `supplier_orders` (number/status/supplier/expected date, no costs).
- **Permissions**: everyone reads suppliers/orders (all money fields — `total`, `paid`, `balance`, `unit_cost`,
  `line_total`, payments, supplier `balance`, summary `owed` — hidden without `can_view_costs`; the
  `has_balance` filter is ignored for them). Writes (suppliers, orders, receive, status, cancel) need
  `CanManageInventory`. Order line `unit_cost` may be *entered* by such staff (`CostOutputMixin`: accepted on
  write, dropped from responses) but replacing lines of an existing order needs cost permission
  (`cost_permission_required`, they would wipe costs they cannot see). Payments (order / supplier "pay") need
  inventory management **and** cost permission (`CanPaySuppliers`); voiding a payment is owner-only;
  `purchasing/payments/` is empty for users without costs.
- **Ageing**: orders expose `age_days` (today − order_date) and `is_late` (expected date passed while open).
  Filters `open`, `late`, `min_age`, `status`/`type`/`payment_status` lists, `supplier`, `job`, date range.
  `GET purchasing/orders/summary/` → counts per status, `open`, `late`, ageing buckets 0–7 / 8–14 / 15–30 / 31+
  days of open orders, `owed` (cost permission only). Supplier "pay" spreads oldest order first (like credit
  customers).
- Flutter: cache v6 `suppliers, supplier_orders`; `/orders` (open orders by default, oldest first, filters,
  summary chips — tapping an ageing bucket sets `min_age`, late rows red), `/orders/:id` (lines with
  received/remaining, receive dialog per line, send, cancel, payments + owner void; costs only with
  permission), order form (type, supplier, job picker for rx orders, product/variant or free-text lines with
  eye), suppliers dialog (add/edit, balance, pay). Job detail: "طلب عدسة من المورد" (pre-filled rx order, one
  line per eye described from the Rx) and the job's supplier orders. `SupplierOrder.ageOn/lateOn` re-evaluate
  cached rows offline.

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
- [x] **P3 Patients, exams, prescriptions**: models, validation, transposition helper. Flutter: patient
      profile, exam history, Rx entry form (OD/OS table), print prescription + exam report.
- [x] **P4 POS & sales**: atomic checkout, discounts, credit + payments, invoice numbering. Flutter: POS
      screen, credit customers list, invoice print (A4/A5 + thermal).
- [x] **P5 Customer jobs**: lifecycle + status log, link to invoice/prescription. Flutter: jobs board.
- [x] **P6 Supplier orders**: suppliers, orders, receiving → stock, payments. Flutter: pending orders screen.
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
