import datetime
from decimal import Decimal

from django.utils import timezone

from apps.core.testing import (
    LabAPITestCase, make_lab, make_member, make_patient, make_product, make_variant, stock_in,
)
from apps.inventory.models import StockMovement
from apps.jobs.models import Job
from apps.labs.models import LabUser
from apps.purchasing.models import Supplier, SupplierOrder, SupplierPayment

SUPPLIERS = "/api/v1/purchasing/suppliers/"
ORDERS = "/api/v1/purchasing/orders/"
PAYMENTS = "/api/v1/purchasing/payments/"


class PurchasingBase(LabAPITestCase):
    def setUp(self):
        super().setUp()
        self.lab = make_lab()
        self.owner = make_member(self.lab, LabUser.Role.OWNER)
        self.staff = make_member(self.lab)
        self.manager = make_member(self.lab, can_manage_inventory=True)
        self.supplier = Supplier.objects.create(lab=self.lab, name="Essilor Baghdad")
        self.frame = make_product(self.lab, name="Frame", purchase_price="1000")
        self.lens = make_product(self.lab, "stock_lens", name="CR39")
        self.variant = make_variant(self.lens, sph="-1.00")
        self.login_as(self.owner)

    def _order(self, lines=None, **extra):
        payload = {
            "supplier": self.supplier.id,
            "type": "stock",
            "lines": lines or [
                {"product": self.frame.id, "qty": 4, "unit_cost": "2000"},
                {"variant": self.variant.id, "qty": 10, "unit_cost": "500"},
            ],
            **extra,
        }
        return self.client.post(ORDERS, payload, format="json")


class SupplierTests(PurchasingBase):
    def test_crud_and_duplicate_name(self):
        response = self.client.post(SUPPLIERS, {"name": " Hoya  Iraq ", "phone": "0770"})
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["name"], "Hoya Iraq")
        self.assertEqual(self.client.post(SUPPLIERS, {"name": "hoya iraq"}).json()["code"], "duplicate_name")
        self.assertEqual(self.client.delete(f"{SUPPLIERS}{response.json()['id']}/").status_code, 405)

    def test_plain_staff_reads_without_balance_and_cannot_write(self):
        self._order()
        self.login_as(self.staff)
        rows = self.client.get(SUPPLIERS).json()["results"]
        self.assertNotIn("balance", rows[0])
        self.assertEqual(rows[0]["open_orders"], 1)
        response = self.client.post(SUPPLIERS, {"name": "X"})
        self.assertEqual(response.json()["code"], "inventory_permission_required")

    def test_balance_is_sum_of_order_balances(self):
        order = self._order().json()
        self.client.post(f"{ORDERS}{order['id']}/payments/", {"amount": "3000"}, format="json")
        row = self.client.get(f"{SUPPLIERS}{self.supplier.id}/").json()
        self.assertEqual(row["balance"], "10000.00")  # 8000 + 5000 − 3000
        self.assertEqual(self.client.get(SUPPLIERS, {"has_balance": "true"}).json()["count"], 1)


class OrderTests(PurchasingBase):
    def test_create_numbers_and_totals(self):
        first = self._order()
        self.assertEqual(first.status_code, 201, first.content)
        body = first.json()
        self.assertEqual((body["number"], body["status"], body["payment_status"]), (1, "ordered", "unpaid"))
        self.assertEqual((body["total"], body["balance"]), ("13000.00", "13000.00"))
        self.assertEqual(body["lines"][1]["variant_label"], "SPH -1.00 CYL +0.00")
        self.assertEqual(self._order(status="pending").json()["number"], 2)

    def test_stock_order_needs_stock_items_and_powers(self):
        rx = make_product(self.lab, "rx_lens")
        self.assertEqual(self._order([{"product": rx.id, "qty": 1}]).json()["code"], "not_stock_tracked")
        self.assertEqual(self._order([{"product": self.lens.id, "qty": 1}]).json()["code"], "variant_required")
        response = self._order([{"description": "free text", "qty": 1}], type="other")
        self.assertEqual(response.status_code, 201, response.content)

    def test_receive_partially_then_rest_moves_stock_and_average(self):
        stock_in(self.frame, 2, "1000")
        order = self._order().json()
        frame_line, lens_line = order["lines"]
        response = self.client.post(
            f"{ORDERS}{order['id']}/receive/", {"lines": [{"line": frame_line["id"], "qty": 2}]}, format="json"
        )
        self.assertEqual(response.json()["status"], "partially_received")
        self.frame.refresh_from_db()
        self.assertEqual((self.frame.quantity, self.frame.average_cost), (4, Decimal("1500.00")))
        self.assertEqual(self.frame.purchase_price, Decimal("2000.00"))  # last received cost
        response = self.client.post(f"{ORDERS}{order['id']}/receive/", {}, format="json")
        body = response.json()
        self.assertEqual(body["status"], "received")
        self.assertEqual([l["qty_remaining"] for l in body["lines"]], [0, 0])
        self.variant.refresh_from_db()
        self.assertEqual((self.variant.quantity, self.variant.average_cost), (10, Decimal("500.00")))
        moves = StockMovement.objects.filter(reference_type="supplier_order", reference_id=order["id"])
        self.assertEqual(moves.count(), 3)
        self.assertEqual(self.client.post(f"{ORDERS}{order['id']}/receive/", {}).json()["code"], "order_closed")

    def test_over_receive_and_foreign_line(self):
        order = self._order().json()
        line = order["lines"][0]
        response = self.client.post(
            f"{ORDERS}{order['id']}/receive/", {"lines": [{"line": line["id"], "qty": 5}]}, format="json"
        )
        self.assertEqual(response.json()["code"], "over_receive")
        other = self._order().json()
        response = self.client.post(
            f"{ORDERS}{order['id']}/receive/", {"lines": [{"line": other["lines"][0]["id"], "qty": 1}]}, format="json"
        )
        self.assertEqual(response.json()["code"], "invalid_line")
        self.assertEqual(self.frame.stock_movements.count(), 0)

    def test_edit_only_before_receiving(self):
        order = self._order().json()
        url = f"{ORDERS}{order['id']}/"
        response = self.client.patch(url, {"lines": [{"product": self.frame.id, "qty": 1, "unit_cost": "100"}]}, format="json")
        self.assertEqual(response.json()["total"], "100.00")
        self.assertEqual(len(response.json()["lines"]), 1)
        self.client.post(f"{ORDERS}{order['id']}/receive/", {})
        self.assertEqual(self.client.patch(url, {"notes": "x"}, format="json").json()["code"], "order_locked")

    def test_status_pending_ordered_and_cancel(self):
        order = self._order(status="pending").json()
        url = f"{ORDERS}{order['id']}/"
        self.assertEqual(self.client.post(f"{url}payments/", {"amount": "1"}).json()["code"], "order_not_sent")
        self.assertEqual(self.client.post(f"{url}status/", {"status": "ordered"}).json()["status"], "ordered")
        self.assertEqual(self.client.post(f"{url}status/", {"status": "received"}).status_code, 400)
        line = order["lines"][0]
        self.client.post(f"{url}receive/", {"lines": [{"line": line["id"], "qty": 1}]}, format="json")
        self.client.post(f"{url}payments/", {"amount": "5000"}, format="json")
        # 5000 paid > 2000 received: cannot cancel the rest yet.
        self.assertEqual(self.client.post(f"{url}cancel/", {"reason": "x"}).json()["code"], "cancel_refund_required")
        payment = SupplierPayment.objects.get()
        self.assertEqual(self.client.post(f"{PAYMENTS}{payment.id}/void/", {"reason": "typo"}).status_code, 200)
        body = self.client.post(f"{url}cancel/", {"reason": "supplier out of stock"}).json()
        self.assertEqual((body["status"], body["balance"]), ("cancelled", "2000.00"))  # only the received frame

    def test_payments_and_payment_status(self):
        order = self._order().json()
        url = f"{ORDERS}{order['id']}/payments/"
        self.assertEqual(self.client.post(url, {"amount": "20000"}).json()["code"], "overpayment")
        body = self.client.post(url, {"amount": "3000", "method": "transfer"}).json()
        self.assertEqual((body["payment_status"], body["paid"], body["balance"]), ("partial", "3000.00", "10000.00"))
        body = self.client.post(url, {"amount": "10000"}).json()
        self.assertEqual(body["payment_status"], "paid")

    def test_pay_supplier_spreads_oldest_first(self):
        old = self._order(order_date=str(timezone.localdate() - datetime.timedelta(days=10))).json()
        new = self._order([{"product": self.frame.id, "qty": 1, "unit_cost": "1000"}]).json()
        response = self.client.post(f"{SUPPLIERS}{self.supplier.id}/pay/", {"amount": "13500"})
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual([p["order"] for p in response.json()["payments"]], [old["id"], new["id"]])
        self.assertEqual(SupplierOrder.objects.get(pk=old["id"]).payment_status, "paid")
        self.assertEqual(SupplierOrder.objects.get(pk=new["id"]).balance, Decimal("500.00"))
        response = self.client.post(f"{SUPPLIERS}{self.supplier.id}/pay/", {"amount": "501"})
        self.assertEqual(response.json()["code"], "overpayment")

    def test_filters_ageing_and_summary(self):
        today = timezone.localdate()
        self._order(order_date=str(today - datetime.timedelta(days=20)), expected_date=str(today - datetime.timedelta(days=5)))
        self._order(status="pending")
        received = self._order().json()
        self.client.post(f"{ORDERS}{received['id']}/receive/", {})
        self.assertEqual(self.client.get(ORDERS, {"open": "true"}).json()["count"], 2)
        self.assertEqual(self.client.get(ORDERS, {"late": "true"}).json()["count"], 1)
        self.assertEqual(self.client.get(ORDERS, {"min_age": 15}).json()["count"], 1)
        self.assertEqual(self.client.get(ORDERS, {"status": "pending,received"}).json()["count"], 2)
        row = self.client.get(ORDERS, {"late": "true"}).json()["results"][0]
        self.assertEqual((row["age_days"], row["is_late"]), (20, True))
        summary = self.client.get(f"{ORDERS}summary/").json()
        self.assertEqual((summary["open"], summary["late"]), (2, 1))
        self.assertEqual([b["count"] for b in summary["ageing"]], [1, 0, 1, 0])
        self.assertEqual(summary["owed"], "39000.00")


class PurchasingPermissionTests(PurchasingBase):
    COST_KEYS = {"unit_cost", "line_total", "total", "paid", "balance", "payments", "owed", "amount"}

    def _keys(self, data):
        if isinstance(data, dict):
            for key, value in data.items():
                yield key
                yield from self._keys(value)
        elif isinstance(data, list):
            for item in data:
                yield from self._keys(item)

    def test_manager_without_costs_orders_and_receives_but_sees_no_money(self):
        self.login_as(self.manager)
        response = self._order()
        self.assertEqual(response.status_code, 201, response.content)
        order = response.json()
        self.assertFalse(self.COST_KEYS & set(self._keys(order)))
        self.assertEqual(SupplierOrder.objects.get().total, Decimal("13000.00"))
        response = self.client.post(f"{ORDERS}{order['id']}/receive/", {})
        self.assertEqual(response.json()["status"], "received")
        for url in (ORDERS, f"{ORDERS}{order['id']}/", f"{ORDERS}summary/", SUPPLIERS):
            self.assertFalse(self.COST_KEYS & set(self._keys(self.client.get(url).json())), url)
        self.assertEqual(self.client.get(PAYMENTS).json()["count"], 0)
        other = self._order().json()
        response = self.client.patch(f"{ORDERS}{other['id']}/", {"lines": [{"product": self.frame.id, "qty": 1}]},
                                     format="json")
        self.assertEqual(response.json()["code"], "cost_permission_required")
        self.assertEqual(self.client.patch(f"{ORDERS}{other['id']}/", {"notes": "call"}, format="json").status_code, 200)
        response = self.client.post(f"{ORDERS}{order['id']}/payments/", {"amount": "1"})
        self.assertEqual(response.json()["code"], "cost_permission_required")

    def test_plain_staff_reads_only(self):
        order = self._order().json()
        self.login_as(self.staff)
        self.assertEqual(self.client.get(f"{ORDERS}{order['id']}/").status_code, 200)
        for url in (f"{ORDERS}{order['id']}/receive/", f"{ORDERS}{order['id']}/cancel/"):
            self.assertEqual(self.client.post(url, {"reason": "x"}).status_code, 403, url)
        self.assertEqual(self._order().status_code, 403)

    def test_void_payment_is_owner_only(self):
        order = self._order().json()
        self.client.post(f"{ORDERS}{order['id']}/payments/", {"amount": "10"})
        payment = SupplierPayment.objects.get()
        self.login_as(make_member(self.lab, can_manage_inventory=True, can_view_costs=True))
        self.assertEqual(self.client.post(f"{PAYMENTS}{payment.id}/void/", {"reason": "x"}).status_code, 403)

    def test_lab_isolation(self):
        order = self._order().json()
        other_lab = make_lab()
        other_supplier = Supplier.objects.create(lab=other_lab, name="Other")
        self.login_as(make_member(other_lab, LabUser.Role.OWNER))
        self.assertEqual(self.client.get(ORDERS).json()["count"], 0)
        self.assertEqual(self.client.get(SUPPLIERS).json()["count"], 1)
        for url in (f"{ORDERS}{order['id']}/", f"{SUPPLIERS}{self.supplier.id}/"):
            self.assertEqual(self.client.get(url).status_code, 404)
        self.assertEqual(self.client.post(f"{ORDERS}{order['id']}/receive/", {}).status_code, 404)
        response = self.client.post(ORDERS, {
            "supplier": other_supplier.id, "type": "stock",
            "lines": [{"product": self.frame.id, "qty": 1, "unit_cost": "1"}],
        }, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertIn("lines", response.json()["errors"])


class RxForJobTests(PurchasingBase):
    def setUp(self):
        super().setUp()
        self.patient = make_patient(self.lab)
        self.rx_lens = make_product(self.lab, "rx_lens", name="Progressive 1.67", sale_price="100000",
                                    purchase_price="30000")
        stock_in(self.frame, 1)
        checkout = self.client.post("/api/v1/sales/checkout/", {
            "patient": self.patient.id, "payment_type": "cash",
            "lines": [{"product": self.rx_lens.id, "qty": 2}, {"product": self.frame.id, "qty": 1}],
        }, format="json")
        self.assertEqual(checkout.status_code, 201, checkout.content)
        self.invoice_id = checkout.json()["id"]
        job = self.client.post("/api/v1/jobs/", {
            "patient": self.patient.id, "invoice": self.invoice_id, "lens": self.rx_lens.id,
        }, format="json")
        self.assertEqual(job.status_code, 201, job.content)
        self.job = Job.objects.get(pk=job.json()["id"])

    def _rx_order(self, **extra):
        return self.client.post(ORDERS, {
            "supplier": self.supplier.id, "type": "rx_for_job", "job": self.job.id,
            "lines": [
                {"description": "OD", "eye": "od", "qty": 1, "unit_cost": "25000"},
                {"description": "OS", "eye": "os", "qty": 1, "unit_cost": "27000"},
            ],
            **extra,
        }, format="json")

    def _invoice(self):
        return self.client.get(f"/api/v1/sales/invoices/{self.invoice_id}/").json()

    def test_rx_order_needs_job_and_moves_job_to_lens_ordered(self):
        response = self.client.post(ORDERS, {
            "supplier": self.supplier.id, "type": "rx_for_job",
            "lines": [{"product": self.rx_lens.id, "qty": 1}],
        }, format="json")
        self.assertEqual(response.json()["error_codes"]["job"], ["job_required"])
        order = self._rx_order().json()
        self.assertEqual((order["job_number"], order["lines"][0]["product"]), (self.job.number, self.rx_lens.id))
        self.job.refresh_from_db()
        self.assertEqual(self.job.status, "lens_ordered")
        job = self.client.get(f"/api/v1/jobs/{self.job.id}/").json()
        self.assertEqual(job["supplier_orders"][0]["number"], order["number"])

    def test_received_cost_replaces_reference_price_on_the_invoice(self):
        line = next(l for l in self._invoice()["lines"] if l["product"] == self.rx_lens.id)
        self.assertEqual((line["unit_cost"], line["cost_source"]), ("30000.00", "reference"))
        order = self._rx_order().json()
        self.client.post(f"{ORDERS}{order['id']}/receive/", {})
        invoice = self._invoice()
        line = next(l for l in invoice["lines"] if l["product"] == self.rx_lens.id)
        self.assertEqual((line["unit_cost"], line["cost_source"]), ("26000.00", "supplier"))  # 52000 / 2
        self.assertEqual(invoice["cost_total"], "53000.00")  # 52000 + frame 1000
        self.assertFalse(StockMovement.objects.filter(product=self.rx_lens).exists())  # made to order

    def test_linking_invoice_later_applies_received_cost(self):
        self.job.invoice = None
        self.job.save()
        order = self._rx_order().json()
        self.client.post(f"{ORDERS}{order['id']}/receive/", {})
        self.client.patch(f"/api/v1/jobs/{self.job.id}/", {"invoice": self.invoice_id}, format="json")
        line = next(l for l in self._invoice()["lines"] if l["product"] == self.rx_lens.id)
        self.assertEqual(line["cost_source"], "supplier")

    def test_non_rx_order_cannot_link_job(self):
        response = self._order(job=self.job.id)
        self.assertEqual(response.json()["error_codes"]["job"], ["invalid_job"])
