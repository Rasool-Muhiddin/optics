from decimal import Decimal

from apps.core.testing import (
    LabAPITestCase, make_lab, make_member, make_patient, make_product, make_variant, stock_in,
)
from apps.inventory.models import StockMovement
from apps.labs.models import LabUser
from apps.sales.models import Invoice, Payment

CHECKOUT = "/api/v1/sales/checkout/"
PREVIEW = "/api/v1/sales/checkout/preview/"
INVOICES = "/api/v1/sales/invoices/"


class SalesBase(LabAPITestCase):
    def setUp(self):
        super().setUp()
        self.lab = make_lab(max_discount_percent=Decimal("10"))
        self.owner = make_member(self.lab, LabUser.Role.OWNER)
        self.staff = make_member(self.lab)
        self.frame = make_product(self.lab, name="Frame", sale_price="100000")
        stock_in(self.frame, 5, "60000")
        self.lens = make_product(self.lab, "stock_lens", name="CR-39", sale_price="20000")
        self.power = make_variant(self.lens, sph="-1.00", sale_price="25000")
        stock_in(self.power, 4, "8000")
        self.service = make_product(self.lab, "service", name="Fitting", sale_price="5000", purchase_price="1000")
        self.patient = make_patient(self.lab, full_name="Ali")
        self.login_as(self.staff)

    def _cart(self, **extra):
        return {
            "lines": [
                {"product": self.frame.id, "qty": 1},
                {"variant": self.power.id, "qty": 2},
                {"product": self.service.id, "qty": 1},
            ],
            **extra,
        }


class CheckoutTests(SalesBase):
    def test_cash_sale_prices_stock_and_payment(self):
        response = self.client.post(CHECKOUT, self._cart(customer_name="Walk-in"))
        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body["number"], 1)
        self.assertEqual(body["subtotal"], "155000.00")  # 100000 + 2×25000 (variant price) + 5000
        self.assertEqual((body["total"], body["paid"], body["balance"], body["status"]), ("155000.00", "155000.00", "0.00", "paid"))
        self.assertEqual(body["lines"][1]["description"], "CR-39 (SPH -1.00 CYL +0.00)")
        self.frame.refresh_from_db()
        self.power.refresh_from_db()
        self.lens.refresh_from_db()
        self.assertEqual((self.frame.quantity, self.power.quantity, self.lens.quantity), (4, 2, 2))
        sale = StockMovement.objects.filter(type="sale", reference_id=body["id"])
        self.assertEqual(sale.count(), 2)  # the service tracks no stock
        invoice = Invoice.objects.get()
        self.assertEqual(invoice.cost_total, Decimal("60000") + 2 * Decimal("8000") + Decimal("1000"))
        self.assertEqual(invoice.cashier, self.staff.user)
        self.assertEqual(Payment.objects.get().amount, Decimal("155000"))

    def test_numbers_are_sequential_per_lab(self):
        self.client.post(CHECKOUT, {"lines": [{"product": self.service.id, "qty": 1}]})
        second = self.client.post(CHECKOUT, {"lines": [{"product": self.service.id, "qty": 1}]}).json()
        self.assertEqual(second["number"], 2)
        other = make_lab()
        other_member = make_member(other)
        service = make_product(other, "service")
        self.login_as(other_member)
        self.assertEqual(self.client.post(CHECKOUT, {"lines": [{"product": service.id, "qty": 1}]}).json()["number"], 1)

    def test_client_prices_and_totals_are_ignored(self):
        response = self.client.post(CHECKOUT, {
            "lines": [{"product": self.frame.id, "qty": 1, "unit_price": "1", "line_total": "1"}],
            "total": "1", "number": 999, "paid": "1",
        })
        body = response.json()
        self.assertEqual((body["total"], body["number"]), ("100000.00", 1))

    def test_insufficient_stock_rolls_everything_back(self):
        response = self.client.post(CHECKOUT, {"lines": [
            {"product": self.frame.id, "qty": 1},
            {"variant": self.power.id, "qty": 99},
        ]})
        self.assertEqual(response.json()["code"], "insufficient_stock")
        self.frame.refresh_from_db()
        self.assertEqual(self.frame.quantity, 5)
        self.assertFalse(Invoice.objects.exists())
        self.assertFalse(StockMovement.objects.filter(type="sale").exists())
        # The number was not consumed either.
        self.assertEqual(self.client.post(CHECKOUT, {"lines": [{"product": self.service.id, "qty": 1}]}).json()["number"], 1)

    def test_lens_needs_power_and_inactive_rejected(self):
        response = self.client.post(CHECKOUT, {"lines": [{"product": self.lens.id, "qty": 1}]})
        self.assertEqual(response.json()["code"], "variant_required")
        self.frame.is_active = False
        self.frame.save()
        response = self.client.post(CHECKOUT, {"lines": [{"product": self.frame.id, "qty": 1}]})
        self.assertEqual(response.json()["code"], "product_inactive")

    def test_empty_cart_and_bad_qty(self):
        self.assertEqual(self.client.post(CHECKOUT, {"lines": []}).status_code, 400)
        self.assertEqual(self.client.post(CHECKOUT, {"lines": [{"product": self.frame.id, "qty": 0}]}).status_code, 400)


class DiscountTests(SalesBase):
    def test_line_and_invoice_discounts(self):
        response = self.client.post(PREVIEW, {
            "lines": [{"product": self.frame.id, "qty": 1, "discount": "5000"}, {"product": self.service.id, "qty": 2, "discount_percent": "10"}],
            "invoice_discount_type": "amount", "invoice_discount_value": "1000",
        })
        body = response.json()
        self.assertEqual(response.status_code, 200, body)
        # subtotal 110000; line discounts 5000 + 1000; invoice discount 1000 → total 103000
        self.assertEqual((body["subtotal"], body["lines_discount"], body["invoice_discount"], body["total"]),
                         ("110000.00", "6000.00", "1000.00", "103000.00"))
        self.assertEqual(body["discount_percent"], "6.36")
        self.assertFalse(body["requires_owner"])
        self.assertFalse(Invoice.objects.exists())  # preview saves nothing

    def test_percent_invoice_discount(self):
        body = self.client.post(PREVIEW, {
            "lines": [{"product": self.frame.id, "qty": 1}], "invoice_discount_type": "percent", "invoice_discount_value": "5",
        }).json()
        self.assertEqual(body["total"], "95000.00")

    def test_staff_discount_above_limit_needs_owner(self):
        cart = {"lines": [{"product": self.frame.id, "qty": 1}], "invoice_discount_value": "15000"}
        preview = self.client.post(PREVIEW, cart).json()
        self.assertTrue(preview["requires_owner"])
        response = self.client.post(CHECKOUT, cart)
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["code"], "discount_requires_owner")
        self.assertFalse(Invoice.objects.exists())
        self.login_as(self.owner)
        self.assertEqual(self.client.post(CHECKOUT, cart).status_code, 201)

    def test_discount_cannot_exceed_amount(self):
        self.login_as(self.owner)
        response = self.client.post(CHECKOUT, {"lines": [{"product": self.frame.id, "qty": 1, "discount": "100001"}]})
        self.assertEqual(response.json()["code"], "invalid_discount")
        response = self.client.post(CHECKOUT, {"lines": [{"product": self.frame.id, "qty": 1}], "invoice_discount_value": "200000"})
        self.assertEqual(response.json()["code"], "invalid_discount")

    def test_limit_is_lab_setting(self):
        self.lab.max_discount_percent = Decimal("20")
        self.lab.save()
        cart = {"lines": [{"product": self.frame.id, "qty": 1}], "invoice_discount_value": "15000"}
        self.assertEqual(self.client.post(CHECKOUT, cart).status_code, 201)


class CreditTests(SalesBase):
    def test_credit_sale_with_down_payment_then_payments(self):
        response = self.client.post(CHECKOUT, self._cart(
            payment_type="credit", patient=self.patient.id, payment={"amount": "55000", "method": "cash"},
        ))
        self.assertEqual(response.status_code, 201, response.content)
        invoice = response.json()
        self.assertEqual((invoice["paid"], invoice["balance"], invoice["status"]), ("55000.00", "100000.00", "partially_paid"))
        self.assertEqual(invoice["customer_name"], "Ali")
        self.patient.refresh_from_db()
        self.assertEqual(self.patient.status, "lens_selected")

        url = f"{INVOICES}{invoice['id']}/payments/"
        self.assertEqual(self.client.post(url, {"amount": "100001"}).json()["code"], "overpayment")
        self.assertEqual(self.client.post(url, {"amount": "0"}).json()["code"], "invalid_amount")
        body = self.client.post(url, {"amount": "100000", "method": "card"}).json()
        self.assertEqual((body["balance"], body["status"], len(body["payments"])), ("0.00", "paid", 2))

    def test_credit_without_payment_is_open_and_requires_patient(self):
        response = self.client.post(CHECKOUT, self._cart(payment_type="credit"))
        self.assertEqual(response.json()["code"], "credit_requires_patient")
        body = self.client.post(CHECKOUT, self._cart(payment_type="credit", patient=self.patient.id)).json()
        self.assertEqual((body["status"], body["paid"]), ("open", "0.00"))
        self.assertEqual(body["payments"], [])

    def test_credit_customers_and_fifo_payment(self):
        first = self.client.post(CHECKOUT, {"lines": [{"product": self.service.id, "qty": 2}], "payment_type": "credit", "patient": self.patient.id}).json()
        second = self.client.post(CHECKOUT, {"lines": [{"product": self.service.id, "qty": 1}], "payment_type": "credit", "patient": self.patient.id}).json()
        other = make_patient(self.lab, full_name="Sara", phone="0790")
        self.client.post(CHECKOUT, {"lines": [{"product": self.frame.id, "qty": 1}], "payment_type": "credit", "patient": other.id})

        rows = self.client.get("/api/v1/sales/credit-customers/").json()["results"]
        self.assertEqual([(r["name"], r["balance"], r["invoices"]) for r in rows], [("Sara", "100000.00", 1), ("Ali", "15000.00", 2)])
        self.assertEqual(self.client.get("/api/v1/sales/credit-customers/", {"search": "079"}).json()["count"], 1)

        url = f"/api/v1/sales/credit-customers/{self.patient.id}/pay/"
        self.assertEqual(self.client.post(url, {"amount": "15001"}).json()["code"], "overpayment")
        response = self.client.post(url, {"amount": "12000"})
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual([p["amount"] for p in response.json()["payments"]], ["10000.00", "2000.00"])
        self.assertEqual(Invoice.objects.get(pk=first["id"]).status, "paid")
        self.assertEqual(Invoice.objects.get(pk=second["id"]).balance, Decimal("3000"))
        self.assertEqual(self.client.get(INVOICES, {"has_balance": "true", "patient": self.patient.id}).json()["count"], 1)


class CancelAndVoidTests(SalesBase):
    def test_owner_cancels_invoice_restoring_stock_and_cost(self):
        invoice = self.client.post(CHECKOUT, self._cart()).json()
        self.assertEqual(self.client.post(f"{INVOICES}{invoice['id']}/cancel/", {"reason": "x"}).status_code, 403)
        self.login_as(self.owner)
        body = self.client.post(f"{INVOICES}{invoice['id']}/cancel/", {"reason": "customer changed mind"}).json()
        self.assertEqual((body["status"], body["paid"], body["balance"]), ("cancelled", "0.00", "0.00"))
        self.assertTrue(all(p["is_void"] for p in body["payments"]))
        self.frame.refresh_from_db()
        self.power.refresh_from_db()
        self.assertEqual((self.frame.quantity, self.frame.average_cost), (5, Decimal("60000.00")))
        self.assertEqual(self.power.quantity, 4)
        self.assertEqual(self.client.post(f"{INVOICES}{invoice['id']}/cancel/", {"reason": "x"}).json()["code"], "invoice_cancelled")
        self.assertEqual(self.client.post(f"{INVOICES}{invoice['id']}/payments/", {"amount": "1"}).json()["code"], "invoice_cancelled")

    def test_owner_voids_a_payment(self):
        invoice = self.client.post(CHECKOUT, self._cart(payment_type="credit", patient=self.patient.id, payment={"amount": "5000"})).json()
        payment_id = invoice["payments"][0]["id"]
        self.assertEqual(self.client.post(f"/api/v1/sales/payments/{payment_id}/void/", {"reason": "typo"}).status_code, 403)
        self.login_as(self.owner)
        self.assertTrue(self.client.post(f"/api/v1/sales/payments/{payment_id}/void/", {"reason": "typo"}).json()["is_void"])
        self.assertEqual(Invoice.objects.get().status, "open")

    def test_invoices_are_read_only(self):
        invoice = self.client.post(CHECKOUT, self._cart()).json()
        self.assertEqual(self.client.patch(f"{INVOICES}{invoice['id']}/", {"total": "1"}).status_code, 405)
        self.assertEqual(self.client.delete(f"{INVOICES}{invoice['id']}/").status_code, 405)
        self.assertEqual(self.client.post(INVOICES, {}).status_code, 405)


class SalesVisibilityAndIsolationTests(SalesBase):
    def test_staff_never_sees_costs_or_profit(self):
        invoice = self.client.post(CHECKOUT, self._cart()).json()
        for data in (invoice, self.client.get(f"{INVOICES}{invoice['id']}/").json(), self.client.get(INVOICES).json()):
            text = str(data)
            for key in ("cost_total", "profit", "unit_cost"):
                self.assertNotIn(f"'{key}'", text)
        self.login_as(self.owner)
        detail = self.client.get(f"{INVOICES}{invoice['id']}/").json()
        self.assertEqual(detail["cost_total"], "77000.00")
        self.assertEqual(detail["profit"], "78000.00")

    def test_lab_isolation(self):
        other = make_lab()
        other_product = make_product(other, "service")
        other_patient = make_patient(other)
        response = self.client.post(CHECKOUT, {"lines": [{"product": other_product.id, "qty": 1}]})
        self.assertEqual(response.status_code, 400)
        response = self.client.post(CHECKOUT, {**self._cart(), "patient": other_patient.id})
        self.assertIn("patient", response.json()["errors"])
        other_member = make_member(other)
        self.login_as(other_member)
        self.client.post(CHECKOUT, {"lines": [{"product": other_product.id, "qty": 1}], "payment_type": "credit", "patient": other_patient.id})
        self.login_as(self.staff)
        self.assertEqual(self.client.get(INVOICES).json()["count"], 0)
        self.assertEqual(self.client.get("/api/v1/sales/credit-customers/").json()["count"], 0)
        other_invoice = Invoice.objects.get(lab=other)
        self.assertEqual(self.client.get(f"{INVOICES}{other_invoice.id}/").status_code, 404)
        self.assertEqual(self.client.post(f"{INVOICES}{other_invoice.id}/payments/", {"amount": "1"}).status_code, 404)
        self.assertEqual(self.client.post(f"/api/v1/sales/credit-customers/{other_patient.id}/pay/", {"amount": "1"}).status_code, 404)


class DiscountLimitSettingTests(SalesBase):
    def test_owner_sets_limit_staff_cannot(self):
        self.assertEqual(self.client.get("/api/v1/lab/").json()["max_discount_percent"], "10.00")
        self.assertEqual(self.client.patch("/api/v1/lab/", {"max_discount_percent": "50"}).status_code, 403)
        self.login_as(self.owner)
        self.assertEqual(self.client.patch("/api/v1/lab/", {"max_discount_percent": "15"}).status_code, 200)
        self.assertEqual(self.client.patch("/api/v1/lab/", {"max_discount_percent": "101"}).status_code, 400)
        self.lab.refresh_from_db()
        self.assertEqual(self.lab.max_discount_percent, Decimal("15"))


class InvoiceListWithLinesTests(LabAPITestCase):
    def test_with_lines_returns_full_invoices(self):
        from apps.core.testing import make_lab, make_member, make_product, stock_in
        from apps.labs.models import LabUser

        lab = make_lab()
        self.login_as(make_member(lab, LabUser.Role.OWNER))
        frame = make_product(lab)
        stock_in(frame, 1)
        self.client.post("/api/v1/sales/checkout/", {"customer_name": "x", "lines": [{"product": frame.id, "qty": 1}]},
                         format="json")
        plain = self.client.get("/api/v1/sales/invoices/").json()["results"][0]
        self.assertNotIn("lines", plain)
        full = self.client.get("/api/v1/sales/invoices/", {"with_lines": "true"}).json()["results"][0]
        self.assertEqual(len(full["lines"]), 1)
        self.assertIn("payments", full)
