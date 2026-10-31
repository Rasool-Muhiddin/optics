# Domain model (v1)

Moved verbatim from CLAUDE.md §5. Read before changing models or validation.

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

