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
- State management: pick one (recommended: Riverpod) in Phase 0 and use it everywhere.
- Printing: generate PDFs in Flutter with the `pdf` + `printing` packages (works from cache while offline).
  Templates: prescription, exam report, invoice (A4/A5 and 80mm thermal), job ticket.
  Header uses lab settings (name, logo, phone, address).
- Reuse from pharmacy_APP (copy & adapt, do not import across repos): activation flow, auth storage,
  update service (Inno Setup installer download), connectivity service.

---

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

- [ ] **P0 Scaffold**: Django project + apps skeleton, settings split, DRF, token auth, health endpoint,
      pytest setup; Flutter desktop project with RTL theme, router, ApiService base, ConnectivityService,
      cache DB base, repository base class.
- [ ] **P1 Accounts & tenancy**: Lab, LabUser roles, lab-scoped base viewset, activation/login, billing plans
      + feature flags, Django Admin for all of it. Flutter: activation + login + main layout with sidebar.
- [ ] **P2 Catalog & inventory**: categories, brands, products by kind, lens power variants, stock ledger,
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

---

## 10. Rules

- Never trust client-sent prices, totals, costs or invoice numbers.
- All multi-row writes (checkout, receiving, referral accept) in `transaction.atomic()`.
- Every new model: admin registration, serializer, lab-scoping, tests, migration.
- No hard deletes for business records (invoices, payments, stock movements, exams); use cancel/void flags.
- Keep this file updated: tick roadmap items and record any architectural decision here when it changes.
