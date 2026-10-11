# Morning report — P1 fixes + P2, P3, P4, P5

Branch: `claude/happy-ramanujan-gckbr7` (pushed after every phase; no PR opened).
Flutter used in the cloud session: **3.44.8 / Dart 3.12.2** (exactly the pinned version).

| Commit | Phase |
|---|---|
| `5099fc3` | P1 fixes: real client IP for throttling + P10 encrypted-token item |
| `928e91b` | P2 Catalog & inventory (+ a P1 permission bug fix, see below) |
| `3b21e0d` | P3 Patients, exams, prescriptions |
| `800eca5` | P4 POS & sales |
| `7d83f98` | P5 Customer jobs |

## Test counts

| | Start of session | End |
|---|---|---|
| Backend (`pytest`, also runs with `manage.py test`) | 80 | **194 passed** |
| Flutter (`flutter test`) | 47 | **77 passed** |
| `flutter analyze` | clean | **clean** |
| `makemigrations --check` | — | **No changes** |
| `ruff --select F,E9` (unused imports / syntax; not a repo requirement) | — | clean |

I also ran an end-to-end smoke test against `runserver` on a **fresh SQLite DB** (all migrations from zero):
activate → login → create frame + stock lens → generate the power grid → purchase entry → patient
→ exam with a plus-cyl Rx (stored transposed) → credit checkout with a down payment → job linked to
the Rx and invoice → status change → credit-customers list and jobs summary. Every step returned the
expected result.

---

## What was done, per phase

### P1 fixes
- **(a) Real client IP for the auth throttle.** `apps/core/client_ip.py` + `ClientIPScopedRateThrottle`.
  The forwarding headers count only when the direct peer is listed in `TRUSTED_PROXIES`. That setting
  is empty in dev, and production defaults to loopback + the Cloudflare ranges in
  `config/settings/proxies.py`.
  - `CF-Connecting-IP` is used only when the hop that reached nginx is itself a Cloudflare address.
    Otherwise `X-Forwarded-For` is read right to left, skipping trusted hops.
  - Tests cover spoofing, IPv6, garbage headers, and two customers behind the same proxy getting
    separate throttle buckets.
- **(b)** P10 roadmap item added: move the token and device key from `optics_auth.json` to encrypted
  storage (DPAPI on Windows, Keychain/libsecret elsewhere), with a one-time migration.
- **Bug found and fixed (security, from P1).** `IsLabOwner`, `IsLabOwnerOrReadOnly` and
  `requires_feature` ignored the parent check returning False.
  - Effect: **anonymous GET requests passed**. They got empty lists, and `GET /lab/` crashed with a 500.
  - All three now return 401 for anonymous requests.
  - A new test walks every `/api/v1/` route and asserts 401 for anonymous GET, POST and PATCH.

### P2 Catalog & inventory
- **Data model:** categories (tree), brands, and products by kind. Each kind has its own details,
  validated in JSON `attributes`.
- **Lens stock:** lens power variants hold their own stock.
- **Ledger:** the stock movement ledger is immutable. Updates are atomic (row lock), and stock can
  never go negative.
- **Costing:** weighted-average cost.
- **API extras:**
  - Power-grid endpoint, plus a generator for a whole SPH×CYL range.
  - Barcode/SKU lookup.
  - Manual stock entry with many lines in one transaction.
- **Costs hidden from staff:** staff without `can_view_costs` never receive purchase prices or costs.
  The fields are removed from the serializers, and ordering by cost is blocked. A test scans every
  catalog and inventory response for cost keys.
- **Flutter:**
  - Inventory list with filters (kind, category, brand, low stock, search). The cost column appears
    only for users who may see costs.
  - Add/edit form per kind. Categories and brands manager.
  - Product page with the **lens power grid** (stock colour-coded). It has an ADD selector, a
    "grid entry mode" for entering received quantities across many powers in one go, and per-power
    edit and stock entry.
  - Stock ledger on the product page.

### P3 Patients, exams, prescriptions
- **Patients:** age or birth date (an entered age is stored as an estimated birth date), status, and
  archiving.
- **Exams:** exams carry VA and IOP per eye. A prescription can be nested in an exam (saved in one
  transaction) or created on its own.
- **Rx validation follows §5 exactly.** Plus-cylinder input is **transposed to minus-cyl on save**.
  There is a transpose endpoint, and a ± button in the form.
- **Void, never delete:** exams and prescriptions are voided with a reason, by the owner or the
  author.
- **Validation responses** now also return `error_codes`, so Flutter shows field errors in Arabic.
- **Flutter:**
  - Patient list and profile with exams, prescriptions and jobs tabs.
  - OD/OS Rx entry table that mirrors the server rules.
  - **Printing:** prescription on A5 and exam report on A4, built with the `pdf` and `printing`
    packages. Printing works from the cache while offline, and the lab logo is cached on disk.

### P4 POS & sales
- **Checkout is one atomic endpoint:** invoice number → lines → `sale` stock movements → payment.
  The server prices everything; client prices, totals and numbers are ignored.
- **`checkout/preview/`** returns the server's totals, so the POS never does money arithmetic on the
  client.
- **Invoice numbers** are sequential per lab, and a failed checkout does not use one up.
- **Discount limit** (`Lab.max_discount_percent`, default 10%): above it, staff get
  `discount_requires_owner`.
- **Credit (آجل):** down payment, later payments, and a credit customers list. You can receive one
  payment for a customer and it is spread over their oldest invoices first.
- **Owner-only actions:** cancel an invoice (stock returns at the sold cost and payments are voided)
  and void a payment.
- **Costs and profit on invoices** are hidden from staff without the cost permission.
- **Flutter:**
  - POS screen: search plus barcode-scanner Enter, and the lens power grid to pick powers.
  - Customer: walk-in or patient picker. Cash/credit, line and invoice discounts, server totals and
    stock warnings.
  - Invoices list and detail (payments, cancel, void).
  - Credit customers screen.
  - **Invoice printing on A4, A5 and 80 mm thermal.**
  - "Sell" button on the patient profile.

### P5 Customer jobs
- **Job record:** server job numbers. Each job links to the patient, an Rx (must be that patient's)
  and an invoice (same patient, not cancelled).
- **Frame:** from the lab, **the customer's own frame**, or no frame.
- **Lens:** lens product with optional stock powers per eye.
- **Status lifecycle:** every move is validated and written to `JobStatusLog` (who, when, note).
- **Overdue** = promised date passed while the job is pending, lens ordered or in the workshop.
- **Flutter:**
  - Kanban **jobs board**. Overdue cards get a red border and badge, and each card has a "move to
    next" button.
  - Job form with pickers, and a job detail page with history.
  - **Job ticket printing on A5 and 80 mm.**
  - "New job" button and a jobs tab on the patient profile.

---

## Decisions you should review
These are all recorded in `CLAUDE.md` under "Decisions recorded in P2/P3/P4/P5". The ones most likely
to need your call:

1. **Catalog writes are owner-only.** Products, prices, categories and power grids can only be
   edited by the owner. Staff can read everything (costs hidden).
2. **Manual stock entries are owner-only.** This covers purchase, adjustment, damage and returns.
   Staff cannot record damage. You might want to allow staff with `can_view_costs`.
3. **No negative stock.** A sale fails with `insufficient_stock` instead of letting stock go negative.
4. **Average cost is stored with 2 decimals** (fine for IQD).
   - Only purchases, customer returns and positive adjustments *that state a cost* move the average.
   - Opening stock = an adjustment with a unit cost.
5. **ADD = 0 means "no addition"** on lens variants (not null), so the uniqueness rule works on every
   database.
6. **Plus-cyl prescriptions are transposed to minus-cyl automatically on save**, so a plus-cyl Rx is
   stored and printed transposed. Per §5's "store minus-cyl" rule. Confirm the labs are fine seeing
   the transposed form on printouts.
7. **An eye may be left empty** (monocular Rx). At least one eye needs SPH. The Rx nested in an exam
   must be sent complete when edited.
8. **Who can void exams and prescriptions:** the owner or the author. Voiding an exam also voids its
   Rx.
9. **Credit sales require a patient file**, so every debt belongs to someone. Cash sales are always
   paid in full.
10. **Discount limit** = total discount (line + invoice) as a % of the subtotal, compared with
    `Lab.max_discount_percent` (default **10%**). The owner can change it through `PATCH /lab/`;
    there is no settings screen yet, but it is also in Django Admin.
11. **Cancelling an invoice is all-or-nothing** (owner only). Stock comes back and payments are
    voided. There are **no partial returns or refunds** yet.
12. **Cost snapshot for non-stock items** (rx lens, services) on invoices uses the product's reference
    `purchase_price`. So profit on made-to-order lenses is only as good as that price until P6 links
    real supplier costs.
13. **Jobs do not move stock.** Stock leaves at checkout. Ordering an rx lens from a supplier for a job
    is P6.
14. **Job lifecycle rules.** Skipping forward is allowed, and so are some steps back:
    - re-order: in workshop → lens ordered
    - rework: ready → in workshop
    - lens ordered → pending

    Delivered and cancelled are final. A **ready** job is not counted as overdue.
15. **New sidebar sections** "الفواتير" (invoices) and "الزبائن بالآجل" (credit customers) sit under
    POS.
16. **Missing barcode / other lab's patient** now answer **404** (was 400 with code `not_found`).
17. **Cloudflare IP ranges are hard-coded** in `config/settings/proxies.py`. Refresh them before
    deploying (https://www.cloudflare.com/ips/). Set `TRUST_CLOUDFLARE=False` if production is ever
    not behind Cloudflare.

## Unfinished / limitations / not verified
- **Nothing was run on Windows.** There was no visual check of any screen, no `flutter build
  windows`, and no real printing. Widget tests use the Ahem test font, so Arabic text lengths and
  layout must be checked by eye.
- **The `printing` plugin is new.** On Windows it should build as-is. A Linux build downloads pdfium
  at CMake time (needs network once).
- The **PDF font fallback** depends on Helvetica. The bundled Noto Naskh Arabic has **no Latin
  glyphs** (OD/OS, SPH…), so check that mixed Arabic/Latin lines render correctly on real paper.
- **Thermal 80 mm** layout was not tried on a real printer. Paper is `PdfPageFormat.roll80`, which
  is a continuous roll.
- **Offline cache:** lists and details are cached for every new domain, but offline search is basic
  (done in Dart). Completion and offline banners per screen are P9. Selling, saving and status changes
  are blocked offline by design.
- There is **no lab settings screen** in Flutter yet (discount limit, print header/footer, logo).
  Settings are edited via the API or Django Admin.
- **Not built (outside P2–P5 scope):**
  - invoice returns / partial refunds
  - editing an invoice after checkout
  - supplier orders (P6)
  - reports (P8)
- No real concurrency test (SQLite in tests). Stock and number locking rely on `select_for_update`,
  which is a no-op on SQLite and real on Postgres.

---

## What to test manually on Windows

Setup:
```
cd backend
python manage.py migrate
python manage.py create_lab "مختبر تجربة" owner1 <password>
python manage.py runserver
cd ../app
flutter pub get
flutter run -d windows
```
Activate with the printed code, log in as the owner, and create a staff user in Admin (one with and
one without `can_view_costs`).

**P1 fixes**
- Hard to test locally. On the server, after deploying, check that 30+ bad logins from one IP throttle
  only that IP. Logs should show real client IPs, not 127.0.0.1.

**P2 Inventory**
1. **Categories and brands:** add a category with a sub-category and a brand ("الأصناف والماركات").
2. **Frame:** add a frame with size `52-18-140`, purchase price and sale price. Try `52/18`; you should
   get an error.
3. **Stock lens:** add a stock lens (index 1.56, coatings), open it, then "توليد القوى" SPH −6..+4,
   CYL 0..−2. Check that the grid shows **plus SPH at the top** and CYL 0 → −2 from left to right.
4. **Grid entry:** use "إدخال كميات للشبكة", type quantities in a few cells plus a unit cost, and save.
   Cells turn green, the ledger shows purchase lines, and the product total updates.
5. **Single power:** click one power cell → stock entry → damage 1. Quantity drops; the average stays
   the same.
6. **Staff view:** log in as staff without cost permission. There is no cost column, no purchase
   price, no "add" buttons, and no costs in the ledger. Then log in as staff *with* the permission:
   costs are visible.
7. **Low stock:** set the reorder level on a frame; the low-stock filter shows it in red.
8. **Offline:** stop the server. The inventory list still shows from the cache and the banner appears.
   Saving shows the Arabic offline message.

**P3 Patients**
1. **New patient:** create one with an age only. Reopen it and check the age shows correctly.
2. **New exam with Rx:**
   - Type CYL without AXIS; you should see "المحور مطلوب".
   - Type SPH `-2.10`; you should get an invalid-power error.
   - Enter OD `-1.00 +0.50 ×90` and save. It is stored as `-0.50 -0.50 ×180`.
3. **± button:** it flips the cylinder sign in the form.
4. **Print prescription (A5) and exam report (A4).** Check:
   - Arabic text is shaped and right-to-left
   - the OD/OS table is left-to-right
   - lab name/phone/logo appear in the header
   - Latin labels (SPH, CYL, OD, PD) are not blank boxes
5. **Standalone prescription:** add one ("وصفة جديدة"), then void it with a reason (owner).
6. **Offline printing:** stop the server, open the patient, and print again from the cache.

**P4 POS**
1. **Cart:** scan or type a frame barcode + Enter → it is added. Search a stock lens → the power grid
   opens → pick a power. Raise the quantity.
2. **Totals:** they update from the server. A quantity above stock shows "الكمية غير متوفرة", and
   checkout is refused with the Arabic message.
3. **Discount limit (staff):** give a 15% invoice discount; you see the warning, and checkout is
   refused. As the owner, it is allowed.
4. **Cash sale:** check out, then print **thermal 80 mm**, **A5** and **A4**. Check the number
   increments (1, 2, 3…).
5. **Credit sale:** with no patient, you get the "requires patient" error. Pick a patient and add a
   down payment. Then in "الزبائن بالآجل", receive a payment larger than the oldest invoice: it spreads
   to the next one.
6. **Owner cancels an invoice:** stock is back in inventory, payments are crossed out, and the status
   is "ملغاة".
7. **Sell from the profile:** the patient profile → "بيع" opens POS with that patient selected.

**P5 Jobs**
1. **New job:** from the patient profile → "طلب نظارة جديد". Choose the Rx, the invoice, "إطار
   الزبون" with a description, a lens + OD/OS powers from the grid, and a promised date.
2. **Overdue:** create one with a promised date in the past. It shows a red border and the "متأخر"
   badge on the board. Moving it to "جاهز للتسليم" removes the overdue badge.
3. **Statuses:** move through the statuses with "نقل إلى…" and the full status dialog (add a note).
   The history on the detail page lists every change with user and time. Delivered jobs cannot be
   edited.
4. **Job ticket:** print it (A5 and 80 mm). It shows the Rx table, PD, frame, lens powers and the
   remaining invoice balance.
5. **Offline:** stop the server. The board still opens from the cache and overdue is still computed.
