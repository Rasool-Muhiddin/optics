# Morning report — pre-P6 changes + P6, P7, P8

Branch: `claude/festive-turing-7uajlt` (pushed after every phase). PR to `main` opened at the end.
Flutter used in the cloud session: **3.44.8 / Dart 3.12.2** (exactly the pinned version).

| Commit | Phase |
|---|---|
| `bc2cc8f` | Changes to existing work: Rx stored/printed as entered + `can_manage_inventory` |
| `137b98e` | P6 Supplier orders |
| `dfe24a7` | P7 Doctor linking |
| `dd34637` | P8 Dashboard, reports, export + lab settings screen |

## Test counts

| | Start of session | End |
|---|---|---|
| Backend (`pytest`, also runs with `manage.py test`) | 194 | **252 passed** |
| Flutter (`flutter test`) | 77 | **96 passed** |
| `flutter analyze` / `dart analyze` | clean | **clean** |
| `makemigrations --check` | No changes | **No changes** |
| `ruff --select F,E9` (unused imports / syntax; not a repo requirement) | clean | clean |

I also ran an end-to-end smoke test on a **fresh SQLite DB** (all migrations from zero). It created a
lab and a doctor with the management commands, then ran the main flows of all three phases through the API.
Every step returned the expected result:

- **Patient and sale:** activate → login → frame + rx lens → a stock order from a supplier, received →
  patient with a **plus-cyl** exam Rx (it came back as entered) → credit sale → job.
- **Rx order for the job:** placing it moved the job to "lens ordered". Receiving it changed the invoice
  cost from the reference 40,000 to the real 35,000.
- **Doctor:** doctor login with the lab's link code → the lab accepts the link → the doctor sends a
  referral → the lab accepts it, which creates the patient file. The doctor token gets 403 on invoices.
- **Reports:** dashboard, profit report, supplier balances and CSV export.

---

## What was done, per phase

### Changes to existing work (before P6)
- **Rx exactly as entered.** Plus-cyl stays plus-cyl in the database, the API, the form, the Rx summary
  and every printout (prescription, exam report, job ticket).
  - `Prescription.save()` also keeps a **normalized minus-cyl copy** (`od_mc_*` / `os_mc_*`). It is
    internal only: not in the API, never printed.
  - Old rows were already stored minus-cyl, so the migration just copies them.
  - The copy is used by a new **stock matching** endpoint,
    `catalog/products/{id}/match/?prescription=`. The job form has an "اختيار القوى المطابقة للوصفة"
    button that fills OD/OS with the matching stock powers.
  - Validation is unchanged. The ± transpose helper is still there, but now it is only an explicit choice.
- **`LabUser.can_manage_inventory`.** Staff with it can:
  - create and edit categories, brands, products and lens powers
  - generate power grids
  - record stock entries (purchase, adjustment, damage, returns)

  Costs stay hidden unless they also have `can_view_costs`. They *can type* a purchase unit cost, which the
  weighted average needs, but they never get costs back. Owners keep full access. The flag is in the
  session, in `lab/users/` and in Django Admin, and the Flutter inventory screens follow it.

### P6 Supplier orders
- **Data model:**
  - Suppliers (unique name, no delete).
  - Supplier orders numbered per lab, typed **stock / rx_for_job / other**.
  - Statuses: pending (draft, not sent) → ordered → partially received / received, or cancelled.
  - Payment status: unpaid / partial / paid.
  - Order lines: a product, a lens power, or free text, with an eye (OD/OS) for rx orders.
- **Receiving** (all lines or per line, in one transaction):
  - Stock items get `purchase` movements, which moves the **weighted average**.
  - Rx lenses and services are only marked received.
  - The product's reference purchase price becomes the last received cost.
- **Payments:** pay one order, or **pay a supplier** (spread over the oldest orders first). Owner-only void.
- **Supplier balance** = the sum of the order balances. A cancelled order is only owed for what was
  received.
- **Rx orders for a job:**
  - Placing one moves the job to "lens ordered".
  - When it is received, its **real cost replaces the reference purchase price** on the job's invoice.
    Profit is then real, and `InvoiceLine.cost_source` shows `supplier`.
  - The job page lists its supplier orders.
- **Ageing:** each order has `age_days` and `is_late`. Filters: open, late, minimum age, status, type,
  supplier. A summary gives counts, ageing buckets 0–7 / 8–14 / 15–30 / 31+ days, and the total owed.
- **Flutter:**
  - "طلبات الموردين" screen: open orders first, filters, summary chips (tap an age bucket to filter),
    late orders in red.
  - Order page: lines with received/remaining, a receive dialog, send, cancel, and payments.
  - Order form, and a suppliers dialog (add/edit, balance, pay).
  - "طلب عدسة من المورد" on the job page creates an rx order pre-filled from the job's Rx.

### P7 Doctor linking
- **Doctor accounts** (no lab), created by Tera in Admin or with `manage.py create_doctor`.
  - Doctors log in from the desktop **without activating the device**.
  - Doctor tokens are refused by every lab endpoint.
- **Links by code:** each doctor and each lab has an 8-character link code. Either side requests a link
  with the other side's code, and the other side accepts or rejects. Either side can revoke.
- **Referrals:**
  - A referral carries a patient snapshot, the exam and the Rx (same validation, kept as entered).
  - The lab inbox can receive, **accept** (creates a new patient file or links an existing one, plus an
    EyeExam and a Prescription, in one transaction), reject with a reason, or complete.
- **The doctor sees only** their links and their own referrals with status. A test walks **every** lab
  route with a doctor token and checks that no prices, invoices or patient names leak, and that other
  labs' data never shows up.
- **Gated by `doctor_linking`** on the lab side. Doctors cannot link with or send to labs without it.
- **Flutter:**
  - "أنا طبيب" login link on the activation and login screens.
  - **Doctor mode** with its own sidebar: my referrals + a new-referral form with the OD/OS Rx form,
    and linked labs with my code.
  - Lab side "إحالات الأطباء" (shown only with the plan feature): inbox, linked-doctors tab (owner:
    lab code, request, accept/reject/revoke), and a referral page.

### P8 Dashboard & reports + lab settings
- **Dashboard** (home screen, all members):
  - today's sales and money collected, this month's sales
  - profit — only for users with the cost permission
  - credit balance
  - open / overdue / ready jobs
  - low stock count
  - open / late supplier orders
  - open referrals
  - a 7-day bar chart

  Each card links to its section, and it is cached for offline viewing.
- **Reports** (owner + staff with `can_view_costs`):
  - sales (+ by payment method, top products)
  - profit (per period and by product kind)
  - credit balances with ageing
  - low stock / all stock with stock value
  - overdue jobs
  - supplier balances

  Sales and profit have a date range with day/month grouping.
- **CSV export** of any report: Excel-friendly with Arabic headers. It is gated on the server by
  **`report_export`**, and the button is disabled without it.
- **Lab settings screen** (owner):
  - name, phone, address
  - print header/footer
  - staff discount limit
  - **logo upload/removal** (PNG/JPG ≤ 1 MB)

  After saving, the session reloads so printouts use the new header and logo.

---

## Decisions you should review
All of these are recorded in `CLAUDE.md` ("Decisions recorded before P6", "in P6", "in P7", "in P8").
The ones most likely to need your call:

1. **Old prescriptions stay transposed.** Rows saved before this change were already converted to
   minus-cyl, and the original plus-cyl input cannot be recovered. Only new or edited Rx are kept as
   entered.
2. **Inventory managers without the cost permission may type a purchase cost**, but never see it again.
   The alternative was to forbid purchases for them.
3. **New supplier orders default to "ordered"** ("تم إرسال الطلب" ticked). Untick it to keep a draft
   ("pending"). Paying a draft is refused.
4. **No supplier opening balance field.** Enter an old debt as an "other" order with a free-text line.
5. **Cancelling an order** keeps what was received (in stock and owed). It is refused while more was paid
   than received: void the extra payment first.
6. **Paying suppliers needs both permissions** (manage inventory + view costs); the owner has both.
   Voiding a supplier payment is owner-only.
7. **Editing an order's lines needs the cost permission.** Lines are replaced as a whole, so someone who
   cannot see the costs would wipe them.
8. **Rx lens real cost.** On receipt, the received value of the job's rx orders for that lens is spread
   over the invoice lines selling it, replacing the reference price. If nothing has been received yet (or
   the order is cancelled), the reference price is used.
9. **The job auto-moves pending → lens ordered** when an rx order is placed. Receiving does *not* move it
   to the workshop; staff do that.
10. **Doctors log in without device activation**, so no device limit applies to them. They can use any
    PC with the app.
11. **Labs and doctors find each other only with link codes.** There is no searchable directory. The lab
    code is owner-only and can be regenerated; the old code stops working.
12. **Lab-side link management is owner-only.** Any member can work the referral inbox.
13. **Referrals cannot be edited after sending.** A doctor who made a mistake sends a new one, and the lab
    rejects the old one with a reason.
14. **On accept, the exam's examiner is "د. <doctor name>"**, and `created_by` is the lab user who
    accepted.
15. **Reports are for the owner and staff with `can_view_costs`.** Plain staff only see the dashboard,
    without profit. Staff still have the credit, low-stock and overdue filters on their own screens.
16. **Profit by product kind is before invoice-level discounts** (those are not split across lines). The
    per-period totals do include them.
17. **CSV headers are in Arabic, generated by the server.** The CSV is a user document; the JSON API keeps
    stable keys.
18. **New dependency `file_selector`** (official Flutter plugin) for choosing the logo. Generated plugin
    registrants were updated for Windows/Linux/macOS.
19. **Currency is not on the settings screen.** It is still editable through the API / Admin.

## Unfinished / limitations / not verified
- **Nothing was run on Windows.** There was no visual check of any new screen, no `flutter build windows`
  (including the new `file_selector` plugin), no real printing, and no real CSV opened in Excel.
- **There is no "Users" screen yet** (it still shows "coming soon"). `can_manage_inventory` and
  `can_view_costs` are set in Django Admin or through `lab/users/`.
- **Logo files in production:** Django serves media only with `DEBUG`. Production needs nginx to serve
  `/media/` (P10).
- **Offline:**
  - New lists and details are cached: supplier orders, suppliers, referrals, doctor-mode lists, the
    dashboard.
  - Reports are online only (they show the "not cached" message offline).
  - Full offline coverage and banners are P9 (not started, as asked).
- **Not built (outside scope):**
  - returns to supplier from an order (manual `return_out` stock entries still work)
  - editing referrals
  - doctor profile editing in the app (Admin only)
  - report printing to PDF (CSV export only)
- **No real concurrency test** (SQLite in tests). Order numbering and receiving rely on
  `select_for_update`.

---

## What to test manually on Windows

Setup:
```
cd backend
python manage.py migrate
python manage.py create_lab "مختبر تجربة" owner1 <password> --plan pro
python manage.py create_doctor "د. سامر" doctor1 <password>
python manage.py runserver
cd ../app
flutter pub get
flutter run -d windows
```
In Admin, tick `doctor_linking` and `report_export` on plan "pro". Create a staff user with
**can_manage_inventory** only, and another with **can_view_costs**.

**Changes to existing work**
1. **Rx as entered:** add an exam with OD `-1.00 +0.50 ×90`. Reopen it: it still shows `+0.50 ×90`.
   Print the prescription, exam report and job ticket: all show `+0.50` and `90°`.
2. **Matching stock powers:** have a stock lens with power `-0.50 / -0.50`. In a job with that Rx, choose
   the lens, then "اختيار القوى المطابقة للوصفة". OD is filled with `-0.50 -0.50`.
3. **Inventory manager (no cost permission):**
   - They see "add product" and stock entry, but no cost column or purchase price.
   - A purchase entry with a unit cost works, and the cost is not shown afterwards.
   - A plain staff user still has no add buttons.

**P6 Supplier orders**
1. **Supplier and stock order:** "طلبات الموردين" → "الموردون" → add a supplier. Create a stock order
   (frame ×4 + a lens power ×10, with costs).
2. **Receive and stock:** receive 2 frames → "مستلم جزئياً". In inventory the frame quantity and average
   cost change. Receive the rest → "مستلم".
3. **Ageing:** create an order dated 20 days ago with an expected date in the past. It is red/"متأخر",
   and the "15–30" age chip filters to it.
4. **Payments:** pay part of an order, then "دفع للمورد" from the suppliers dialog. It spreads over the
   oldest orders. Owner: void a payment.
5. **Rx order for a job:**
   - Sell an rx lens on credit, then create a job for it.
   - On the job page, use "طلب عدسة من المورد". The lines are pre-filled per eye, and the job moves to
     "تم طلب العدسة".
   - Receive the order. The invoice (owner view) cost now shows the supplier cost.
6. **Inventory manager without costs:** they can order and receive but see no money and cannot pay.

**P7 Doctor linking**
1. **Doctor login:** on the activation (or login) screen, "أنا طبيب" → log in as doctor1. You get the
   doctor sidebar (إحالاتي / المختبرات المرتبطة) and no lab sections.
2. **Link the lab and the doctor:**
   - As the owner: "إحالات الأطباء" → "الأطباء المرتبطون" shows the lab code.
   - As the doctor: enter the lab code → the request is pending.
   - As the owner: accept it.
3. **Referral:** the doctor sends one with a plus-cyl Rx. In the lab inbox: open it → "قبول وإنشاء ملف" →
   new file. "فتح ملف المراجع" shows the exam with examiner "د. …" and the Rx as entered. Then reject
   another referral with a reason. The doctor sees the statuses and the reason.
4. **Feature flag:** untick `doctor_linking` on the plan. The lab section disappears, and the doctor
   cannot send.

**P8 Dashboard, reports, settings**
1. **Dashboard:** the home screen shows the KPI cards (profit only for owner / cost staff) and the 7-day
   chart. Cards open their sections.
2. **Reports:** go through each report. Sales/profit date range and day/month. "عرض الكل" for stock and
   suppliers.
3. **Export CSV:** a file appears in Downloads. Open it in Excel and check the Arabic headers. Untick
   `report_export`: the button is disabled.
4. **Permissions:** a plain staff user has no "التقارير" item. A staff user with `can_view_costs` has it.
5. **Lab settings (owner):** change the name, header lines, footer and discount limit, then save. The
   sidebar name updates. Choose a PNG logo, then print an invoice: the new header and logo are there.
   Remove the logo. A file over 1 MB shows the Arabic error.
