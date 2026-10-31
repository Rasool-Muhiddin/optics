# Architectural decisions by phase

Moved verbatim from CLAUDE.md. Append new "Decisions recorded …" sections here (CLAUDE.md links to this file).

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

### Decisions recorded in P7
- **Doctor accounts**: `doctors.DoctorProfile` (OneToOne `user`, name, specialty, clinic, phone, address,
  `link_code`, `is_active`) created by Tera in Django Admin or `python manage.py create_doctor "<name>"
  <username> <password>`. A user is either a lab member or a doctor (both `clean()`s refuse the other).
  Doctors log in with `POST desktop/doctor-login/ {username, password}` (throttled like lab login) **without
  device activation** — they are not tied to a lab, so device limits do not apply; the token has no device.
  `GET doctor/me/` = doctor session (`role: "doctor"`, `user`, `doctor`). Permission `doctors.permissions.IsDoctor`
  (`not_a_doctor`, `doctor_inactive`). Doctor tokens get 403 on every lab endpoint (no membership → `LabAccess`).
- **Finding each other = link codes** (8 unambiguous chars, `apps/core/codes.py`): `DoctorProfile.link_code`
  (shown in doctor mode) and `Lab.doctor_link_code` (owner only: `GET/POST referrals/links/code/`, POST makes a
  new one; never in lab settings/session; migration `labs.0004` fills existing labs). No directory of labs or
  doctors is exposed. `DoctorLabLink` (unique lab+doctor; `requested_by` doctor|lab): `POST doctor/links/
  {code}` or `POST referrals/links/ {code}` (owner); only the other side answers (`…/{id}/accept|reject/`,
  `cannot_answer_own_request`); both sides asking = accepted; either side `revoke`s (also withdraws a pending
  request); asking again after reject/revoke reopens the same row. Lab-side link management is owner-only.
- **Gating**: every lab-side endpoint (`referrals/…`) needs plan `doctor_linking` (`requires_feature`); a doctor
  cannot request/accept a link with, or send to, a lab whose plan lacks it (`feature_not_in_plan`), or that is
  inactive / unlicensed (`lab_unavailable`). Sending needs an **accepted** link (`not_linked`).
- **Referral** (lab-scoped, `doctor` FK): patient snapshot (name, age, gender, phone), exam (date, complaint,
  diagnosis, details, VA, IOP), `prescription_data` JSON validated with the same `clean_rx` rules and kept as
  entered (decimals as strings), `notes`. Status sent → received → in_progress → completed, or rejected (with
  reason) from sent/received. Lab actions (any member): `receive/`, `accept/ {patient?}`, `reject/ {reason}`,
  `complete/`, `GET referrals/summary/`. **Accept** (one transaction) creates a Patient (age → estimated birth
  date) or attaches to the given existing patient, an `EyeExam` (`examiner_name` "د. <doctor>",
  `created_by` = lab user) and, if sent, its `Prescription` (`prescribed_by` = doctor); patient → `exam_done`.
  Referrals are not editable after sending; read-only in Django Admin.
- **What the doctor sees**: own links (lab name/phone/address) and own referrals (what they sent + status,
  timestamps, reject reason, lab name). Never the lab's patient id/exam/handler, invoices, prices or any
  unlinked lab. Tests walk every lab route with a doctor token (403/404/405, no prices or patient names) and
  scan doctor responses for price/cost/invoice keys.
- Flutter: `DoctorLoggedIn` auth state (`AuthStorage.isDoctorSession` = stored session has `role: doctor`;
  activation is not needed or touched); `/doctor-login` reachable from the activation and login screens
  ("أنا طبيب"); doctor mode has its own `DoctorShell` sidebar (`/doctor` referrals with the RxForm,
  `/doctor/labs` link code + links); router confines doctors to `/doctor…` and labs away from it. Lab side
  `/referrals` (sidebar item gated by the plan feature): inbox (open by default) + "الأطباء المرتبطون" tab
  (owner: lab code, request by doctor code, accept/reject/revoke); `/referrals/:id` with receive / accept (new
  or existing patient via the patient picker) / reject / complete / open patient file. Shared `LinksPanel`,
  `ReferralView`, `RxTableView`. Cache v7: `referrals, lab_doctor_links, doctor_side_links,
  doctor_side_referrals`.

### Decisions recorded in P8
- **`reports` app** (no models; `reports/services.py` aggregates, all filtered by lab; cancelled invoices
  excluded; dates are local (`Asia/Baghdad`), default range = this month so far, `?date_from&date_to`
  inclusive, `group=day|month`). Every report = `{columns, rows, totals, …extra sections}` so the desktop renders
  any report as a table and the same rows export to CSV.
- `GET reports/dashboard/` (any member): today (invoices, sales, collected = non-void payments received today),
  this month (invoices, sales, `profit` only with cost permission), credit (customers, balance), jobs
  (open = active + ready, overdue, ready), low-stock product count, supplier orders (open, late), referrals open
  (only with plan `doctor_linking`), sales of the last 7 days. Cached offline (cache v8 `dashboard`, one row).
- **Reports are for the owner and staff with `can_view_costs`** (§4: reports are the owner's; profit needs the
  cost permission) — `ReportAccess`, code `cost_permission_required`; the sidebar item uses
  `NavItem.reportsOnly` (`Session.canViewReports`). Reports: `sales/` (+ payments by method, top 10 products),
  `profit/` (revenue − cost snapshots per period, by product kind — kind rows are before invoice-level
  discounts; `estimated_cost_lines` counts lines still at the reference price), `credit/` (per patient +
  ageing 0–30/31–60/61–90/91+ days by oldest unpaid invoice), `stock/` (low stock; `all=true` every
  stock-tracked product; value at weighted average + value by kind incl. lens variants), `jobs/` (overdue
  list + counts per status), `suppliers/` (balances + open orders; `all=true` includes zero balances).
- **Export**: `?export=csv` on any report, server-side gate plan `report_export` (`feature_not_in_plan`;
  viewing stays allowed). CSV = main table + totals, UTF-8 with BOM, Arabic headers/kind/status labels
  (`reports/csv_labels.py` — the CSV is a user document; the JSON API keeps stable keys). Flutter saves it to
  the Downloads folder (`fileSaverProvider`, documents folder fallback) and shows the path; the button is
  disabled when the plan lacks the flag. `ApiClient.getBytes` for non-JSON downloads.
- **Lab settings screen** `/settings` (owner only, existing `PATCH lab/`): name, phone, address, print header
  (multi-line) / footer, `max_discount_percent` (0–100), logo upload (multipart, PNG/JPEG ≤ 1 MB →
  `logo_too_large`; `remove_logo=true` clears it). `ApiClient.multipart`; file chosen with the official
  **`file_selector`** plugin (new dependency, desktop-supported; `logoPickerProvider` is the test seam). After
  saving, `AuthController.refreshSession()` re-reads `auth/me/` so the sidebar and print headers update.
  `LabInfo.maxDiscountPercent` added. Currency stays as is (not on the screen).
- Flutter: home = dashboard (KPI cards linking to their sections, red border when something is overdue/late/
  low, 7-day bar chart drawn with plain containers — no chart package) + the old session card; `/reports`
  (report chips, date range + day/month for sales/profit, "show all" for stock/suppliers, generic
  `ReportTableCard`, totals, extra sections).

### Decisions recorded for the Users screen (after P8)
- `/users` (owner only, existing `lab/users/` + `lab/devices/`): users tab (add staff, edit first/last name,
  **`LabUser.phone`** (new field), password reset, role, `can_view_costs`, `can_manage_inventory`, deactivate)
  and devices tab (rename, revoke = deactivate, reactivate). The device the owner is using is marked
  "هذا الجهاز" and cannot be revoked from the app (it would log the owner out). The owner cannot change
  their own role/active flag (`cannot_modify_self`, the form hides those fields for self).
- **Limits**: `GET lab/usage/` (owner) → active users/devices vs plan `max_users`/`max_devices` (0 =
  unlimited), shown as chips (red when full) with an Arabic explanation; "add" is refused locally when full
  and the server still enforces `user_limit_reached` / `device_limit_reached`.
- **Sessions end on security changes**: a password reset or a deactivation deletes that user's tokens;
  revoking a device deletes its tokens (both were already refused by auth; now they are also removed).
  Django password-validator codes (`password_too_short`…) map to one Arabic message.
- Flutter cache v9 `lab_users, devices`. No section shows "coming soon" any more.

### Decisions recorded in P9
- **Full sync** (`services/offline_sync_service.dart`): `OfflineSyncService.sync(sources)` pulls each
  `SyncSource` (table + endpoint, `page_size` 500, bounded `maxPages`) into its JSON cache table; one failing
  source (403, plan feature…) never stops the others (`SyncResult.failed`); afterwards the credit customers and the
  dashboard refresh through their repositories; the time is stored in `cache_meta.last_full_sync`. Lab sources:
  products, categories, brands, lens variants, recent stock movements, patients (non-archived), exams,
  prescriptions, **invoices with lines** (`GET sales/invoices/?with_lines=true` — new: full invoices in the list, so
  every synced invoice opens and prints offline), jobs, suppliers, supplier orders; + referrals/doctor links with
  plan `doctor_linking`; + lab users/devices for owners. Doctor mode syncs its links and referrals only.
- **When**: `SyncController` (Riverpod `Notifier`) syncs when the shell first shows, after login, and whenever the
  server becomes reachable again — at most every 15 minutes (`minInterval`); "مزامنة الآن" in the sidebar
  (`SyncStatusTile`, both shells) forces one and shows the last full sync time. Tests disable auto sync with
  `autoSyncEnabledProvider` (overridden `false` in `pumpOpticsApp`) so fake servers only see the requests under test.
- **Per-screen offline notice**: `PageHeader(cacheTables: [...], offlineHint:)` renders `OfflineNotice` while the
  server is unreachable: "saved copy — last updated <time>" (max `last_synced_at` of those tables,
  `CacheDatabase.lastSyncedAt`) or "nothing saved on this device yet"; every screen declares its tables (POS adds
  "selling needs the server", settings the offline-write message, home the dashboard table). The global red
  banner stays.
- **Reports offline**: the last result of each exact query is cached (`report_results`, id = FNV-1a hash of name +
  sorted params, `reportCacheId`). Plan usage (`lab/usage/`) and the lab link code stay online-only (limits and
  secrets must be live). Offline search runs in Dart on every cached list (patients, products, invoices, credit
  customers, jobs, orders, suppliers, referrals). Printing reads only cached models + the on-disk logo, so every
  existing print (invoice A4/A5/80 mm, prescription, exam report, job ticket) works offline for synced data.
- Cache v10 adds `report_results` (v9 = `lab_users, devices`).

### Decisions recorded in P10
- **Secrets storage** (`services/secret_store.dart`): `device_key` and `token` live in a `SecretStore`, everything else
  stays in `optics_auth.json`. Windows = `DpapiSecretStore`: one JSON map encrypted with **DPAPI**
  (`CryptProtectData`, current user, extra entropy, `CRYPTPROTECT_UI_FORBIDDEN`) in `optics_secrets.bin` via
  `dart:ffi` + `package:ffi` (no plugin). macOS = Keychain via `/usr/bin/security`; Linux = libsecret via
  `secret-tool`; Linux without libsecret = `PlainFileSecretStore` (0600 file, `secretsEncrypted == false`; dev only).
  `AuthStorage.open()` migrates once: secrets found in the old plain file are written to the store and removed
  from the file (rewritten). Getters stay synchronous (in-memory copy). `AuthStorage.open(store)` in tests uses
  a `MemorySecretStore` unless one is passed. New direct deps `ffi`, `crypto` (already in the lock as transitive).
- **Desktop updates** (approach recorded here as the reference for pharmacy_APP-style updates): Tera publishes
  `app_updates.DesktopAppVersion` in admin (platform windows, version + build, uploaded `.exe` → SHA-256 + size
  computed on save, or external URL + given SHA-256, Arabic release notes, `is_mandatory`, `min_supported_version`,
  `is_active`, `published_at`). `GET desktop/latest-version/?platform=windows&version=x.y.z` is public (works
  before login), throttled per IP (`UPDATE_THROTTLE_RATE`, default 120/min) and answers the newest active
  published release (numeric version compare, then build) with `update_available` and `mandatory`. Flutter
  `UpdateService`: check at start-up (`updateInfoProvider`, errors = no banner) → `UpdateBanner` in both shells
  and on the activation/login card (red when mandatory) → dialog with notes → download to the temp folder with
  progress → **SHA-256 must match** (`update_checksum`, file deleted) → start the installer detached with
  `/SILENT /SP- /NOCANCEL /CLOSEAPPLICATIONS /NORESTART` (UAC prompt, admin install) → `exit(0)`; the installer's
  `[Run]` entry (`skipifnotsilent runasoriginaluser`) starts the new version unelevated. Windows only
  (`update_unsupported` elsewhere). Mandatory is shown, not enforced by the server (no login block).
- **Installer** `installer/optics.iss` (Inno Setup 6): fixed `AppId`, per-machine `{autopf}\Tera\Optics Lab`, Arabic +
  English languages (`Arabic.isl` from Inno 6.3+) with custom messages, app icon, optional desktop shortcut, close
  the running app, user data in `%APPDATA%\com.terasoftware\Optics Lab` kept on update/uninstall.
  `installer/build_release.ps1 -Version x.y.z -BuildNumber n`: tests, `flutter build windows --release` with
  `--build-name`, `--build-number`, `--dart-define=API_BASE_URL=…` and `APP_VERSION` (must equal build-name), then
  `iscc`, prints the SHA-256. Instructions in `RELEASE.md`.
- **Production settings**: `.env.local` is never read when `DJANGO_SETTINGS_MODULE` ends with `.production`;
  `STATIC_ROOT`/`MEDIA_ROOT` from env (default `/srv/optics/static|media`, served by nginx); `ADMIN_URL` env (admin
  path); HSTS 1 year by default without subdomains/preload (W005/W021 silenced on purpose); referrer policy,
  `X_FRAME_OPTIONS=DENY`, `CONN_HEALTH_CHECKS`, uploads > 5 MB stream to temp files; logs to stdout (journald).
  `core/tests/test_production_settings.py` runs `check --deploy --fail-level WARNING` and `collectstatic` in a
  subprocess and checks that missing secrets fail.
- **Deployment** (`deploy/`, `DEPLOY.md`): separate user/folder/DB/role/unit/socket from the pharmacy; nginx site
  (`listen 443 ssl http2` for nginx 1.24, Cloudflare origin cert, `/static/` + `/media/` aliases, 300 MB uploads,
  forwards `X-Forwarded-For`, `X-Forwarded-Proto`, `CF-Connecting-IP`); `optics-api.service` (gunicorn on
  `/run/optics/gunicorn.sock`, 3 workers, hardening); daily `optics-backup.timer` → `deploy/backup/optics-backup.sh`
  (`pg_dump -Fc` checked with `pg_restore --list`, upload + media sync to R2 with awscli from the venv, 7 days
  local); `deploy/.env.production.example`. Cloudflare SSL mode is per zone: use a Configuration Rule for this host
  instead of changing the zone (pharmacy).

### Decisions recorded after P10 (owner UX review)
- **Patient form** asks name, phone and age only. `birth_date`, `gender`, `address`, `notes` stay in the model/API
  (optional, no migration): doctors' referrals send gender and old files keep their values (the form does not
  send them, so editing never erases them); the profile shows gender/address only when set.
- **POS**: walk-in phone field (`customer_phone`); `PosState.sale` is bumped by `clear()` and keys the customer /
  payment sections, so fields that keep their own text (`initialValue`) start empty after a sale (the stale name
  field used to send `''` → invoices showed "زبون عابر"); cart rows are keyed by product/variant, not index.
  After checkout, "إنشاء طلب نظارة لهذه الفاتورة" opens the job form with a `JobDraft` (invoice fixed, patient,
  first frame, first lens and up to two sold powers = OD/OS, latest Rx of the patient).
- **Naming**: jobs are "نظارات الزبائن" everywhere (a job = "نظارة الزبون"); supplier orders "طلبات الموردين";
  categories are "المجموعات". Order types: "شراء للمخزن" / "عدسة تفصيل لزبون" / "أخرى (مصاريف، دين قديم)".
- **Supplier order form**: a hint line per type; stock = product lines only, other = free-text lines only, rx =
  glasses picker (number — customer — lens) that fills one line per eye from the glasses' Rx; "أُرسل للمورد الآن"
  (unchecked = draft `pending`).
- **Lens arrival**: a fully received `rx_for_job` order moves its job `pending | lens_ordered → in_workshop`
  (`purchasing.services._job_lens_arrived`, logged "PO #n received"; partial receipts wait, never backwards).
  Orders expose `job_status`; the order screen shows "وصلت العدسة…" after such a receipt.
- **Delivery checks** (Flutter, `moveJob`): an unpaid invoice balance opens a dialog to take the payment
  (`sales/invoices/{id}/payments/`) then deliver, deliver without paying, or cancel; a lab frame with no invoice
  asks for confirmation. The job form and detail warn when the frame is from the lab and there is no invoice
  (stock leaves only at checkout).
- **Product form**: barcode first (autofocus, Enter/leaving the field looks the code up → "مسجَّل مسبقاً" + open
  button), kind as icon chips, name/brand/"المجموعة (اختياري)", prices + "نبّهني عندما تنزل الكمية إلى", the kind's
  details ("مواصفات الإطار"… with "لمن" / "شكل الحافة" / "مادة الصنع"), then collapsed "خيارات إضافية" (SKU, track
  stock, active, notes). Stock/contact lenses show a hint that each power has its own barcode in the power grid.
- **Demo data**: `python manage.py seed_demo [--noinput]` **flushes the whole database** and loads
  "مختبر عوينات الجامعة" (owner `ali`, also a Django Admin superuser; staff `zahraa`, `mustafa`; doctors `dr_ahmed`,
  `dr_sara`, `dr_haider`; all with password `aasddff`). Scenarios are generators interleaved by date under a
  patched clock and go through the real services, so numbers follow dates and stock/balances match the ledger
  (`labs/tests/test_seed_demo.py`). Refused when DEBUG is off unless `--allow-production`.

### Decisions recorded for the UI redesign (after P10)
- **Design system** (UI only — no API, model or business-logic change): tokens in `core/theme/app_tokens.dart`
  (`AppSpacing`, `AppRadius`, `AppPalette`, `Tone`, `AppColors` ThemeExtension with success/warning/danger/info,
  border, zebra, sidebar colours; `AppText.tabular` digits). `AppTheme.light()` / `AppTheme.dark()` style every
  Material component; screens read colours from the theme/`AppColors.of(context)`, never `Colors.green…`.
- **Font**: UI uses **IBM Plex Sans Arabic** (OFL, Arabic + Latin, weights 400–700, `assets/fonts/`). PDFs keep
  Noto Naskh Arabic (`pdf_kit.dart`).
- **Light/dark/system** switch in the top bar, stored per device in `optics_ui.json` (`services/ui_prefs.dart`,
  `UiPrefs.open()` in `main()`, in-memory in tests) together with the collapsed-sidebar choice.
- **Shell** (`widgets/shell_parts.dart`, shared by lab and doctor modes): dark sidebar (always rendered with the
  dark theme) grouped by `NavItem.group`, active indicator, icon rail when collapsed or the window is < 1100 px;
  top bar = section title, quick-jump search (sections only), connection pill, theme menu, user menu and the
  `logout-button`.
- **Shared widgets** (`widgets/ui.dart`, re-exported by `common.dart`): `SectionCard`/`SurfaceBox` (Material
  surface so ListTile ink shows), `KpiCard`, `StatusBadge` + `StatusTones` (status → tone per domain),
  `MoneyText`/`AmountRow`/`NumText` (LTR, tabular), `EmptyState`, `SkeletonList` (`AsyncView(skeleton: true)`),
  `FilterBar`, `NoticeBox`, `FormSection`, and the table kit `TableCol`/`DataTableHeader`/`DataRowView`/
  `AppDataTable` (sticky header, zebra rows, numeric columns end-aligned, client-side sort of loaded rows only,
  `TableFooter` row count / load more). `FormDialog` takes an optional `icon`.


### Decisions recorded for deploy-ready (after P10)

- **Scripts, not hand steps**: `deploy/setup-server.sh` (first install, idempotent: checks before each step, never
  regenerates existing secrets, never upgrades existing packages, only *reloads* nginx after `nginx -t`) and
  `deploy/update.sh` (`sudo optics-update`: pull → pip → backup if migrations are pending → migrate →
  collectstatic → `check --deploy` → restart → health check). Shared helpers in `deploy/lib.sh`. Layout under
  `/srv/optics` is fixed; choices (`DOMAIN`, `TLS_MODE=cloudflare|letsencrypt`, `BEHIND_CLOUDFLARE`,
  `DB_MODE=local|external`, `REPO_URL`, `BRANCH`) are saved in `/srv/optics/deploy.conf`.
- **nginx file is a template** (`__DOMAIN__`, `__SSL_CERT__`, `__SSL_KEY__`), rendered by the scripts. Adds gzip
  for JSON, `server_tokens off`, security headers on static/media, denies html/svg/scripts under `/media/`.
- **gunicorn settings** in `deploy/gunicorn.conf.py` (`GUNICORN_WORKERS`, default 3; worker recycling).
- **Throttle cache**: production uses a `FileBasedCache` in `/srv/optics/cache` so DRF throttles count across
  gunicorn workers (per-process LocMem multiplied the allowed rate by the worker count).
- **Error alerts**: optional Sentry (`SENTRY_DSN`); `send_default_pii=False`, `max_request_body_size="never"`,
  `include_local_variables=False`, so patient data never leaves the server.
- **Pinned dependencies**: `requirements.txt` uses exact `==` pins (direct + transitive). awscli lives in its own
  venv (`/srv/optics/tools-venv`) so it never changes the app's packages.
- **Restore**: `deploy/backup/optics-restore.sh` (`sudo optics-restore`): default is a test restore into a scratch
  DB; `--live` asks for confirmation, saves a pre-restore dump, restores in one transaction; `--media` syncs files.
- **Release guard**: `installer/build_release.ps1` refuses an `ApiBaseUrl` that is not `https://…/api/v1` or
  points to localhost.
- **Public repo → HTTPS clone**: `REPO_URL` defaults to `https://github.com/Rasool-Muhiddin/optics.git`; the setup
  checks anonymous read (`ls-remote`, prompts disabled) and needs no deploy key. An SSH URL is first tried as its HTTPS
  twin; the deploy-key pause only happens for a private repository.
- **Shared-server safety**: apt runs with `NEEDRESTART_SUSPEND=1` (Ubuntu 24.04 would otherwise auto-restart other
  apps' services); preflight stops if ports 80/443 belong to anything but the system nginx, or 5432 to a PostgreSQL
  not installed by apt. DEPLOY.md asks for a server snapshot first.
