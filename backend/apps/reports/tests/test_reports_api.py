import datetime
import shutil
import tempfile
from decimal import Decimal

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.utils import timezone

from apps.core.testing import (
    LabAPITestCase, make_lab, make_member, make_patient, make_plan, make_product, make_variant, stock_in,
)
from apps.jobs.models import Job
from apps.labs.models import LabUser
from apps.purchasing.models import Supplier
from apps.sales.models import Invoice

R = "/api/v1/reports/"
CHECKOUT = "/api/v1/sales/checkout/"
ALL_REPORTS = ("sales", "profit", "credit", "stock", "jobs", "suppliers")


class ReportsBase(LabAPITestCase):
    def setUp(self):
        super().setUp()
        self.lab = make_lab(plan=make_plan(report_export=True))
        self.owner = make_member(self.lab, LabUser.Role.OWNER)
        self.staff = make_member(self.lab)
        self.trusted = make_member(self.lab, can_view_costs=True)
        self.frame = make_product(self.lab, name="Frame A", sale_price="50000", reorder_level=5)
        stock_in(self.frame, 6, "20000")
        self.lens = make_product(self.lab, "stock_lens", name="CR39", sale_price="10000")
        self.variant = make_variant(self.lens)
        stock_in(self.variant, 4, "3000")
        self.patient = make_patient(self.lab, full_name="Ali", phone="0770")
        self.login_as(self.owner)
        # Cash sale: 2 frames (100000) − 10000 invoice discount; credit sale: 1 lens, 4000 down.
        self.client.post(CHECKOUT, {
            "customer_name": "walk-in", "lines": [{"product": self.frame.id, "qty": 2}],
            "invoice_discount_type": "amount", "invoice_discount_value": "10000",
        }, format="json")
        self.client.post(CHECKOUT, {
            "patient": self.patient.id, "payment_type": "credit", "lines": [{"variant": self.variant.id, "qty": 1}],
            "payment": {"amount": "4000"},
        }, format="json")
        cancelled = self.client.post(CHECKOUT, {
            "customer_name": "x", "lines": [{"product": self.frame.id, "qty": 1}],
        }, format="json").json()
        self.client.post(f"/api/v1/sales/invoices/{cancelled['id']}/cancel/", {"reason": "mistake"})


class DashboardTests(ReportsBase):
    def test_owner_dashboard(self):
        body = self.client.get(f"{R}dashboard/").json()
        self.assertEqual((body["today"]["invoices"], body["today"]["sales_total"]), (2, "100000.00"))
        self.assertEqual(body["today"]["collected"], "94000.00")  # 90000 cash + 4000 down payment
        self.assertEqual(body["month"]["profit"], "57000.00")  # 100000 − (40000 + 3000)
        self.assertEqual(body["credit"], {"customers": 1, "balance": "6000.00"})
        self.assertEqual(body["stock"]["low"], 1)  # 4 frames left ≤ reorder level 5
        self.assertEqual(len(body["sales_last_7_days"]), 7)
        self.assertEqual(body["sales_last_7_days"][-1]["total"], "100000.00")
        self.assertNotIn("referrals", body)

    def test_staff_dashboard_has_no_profit(self):
        self.login_as(self.staff)
        body = self.client.get(f"{R}dashboard/").json()
        self.assertNotIn("profit", body["month"])
        self.assertEqual(body["today"]["invoices"], 2)

    def test_open_work_counts(self):
        today = timezone.localdate()
        Job.objects.create(lab=self.lab, number=1, patient=self.patient, promised_date=today - datetime.timedelta(1))
        Job.objects.create(lab=self.lab, number=2, patient=self.patient, status="ready")
        body = self.client.get(f"{R}dashboard/").json()
        self.assertEqual(body["jobs"], {"open": 2, "overdue": 1, "ready": 1})


class ReportTests(ReportsBase):
    def test_sales_report(self):
        body = self.client.get(f"{R}sales/").json()
        self.assertEqual(body["totals"], {
            "invoices": 2, "subtotal": "110000.00", "discount": "10000.00", "total": "100000.00", "balance": "6000.00",
        })
        self.assertEqual(body["rows"][0]["period"], timezone.localdate().isoformat())
        self.assertEqual({p["method"]: p["amount"] for p in body["payments_by_method"]}, {"cash": "94000.00"})
        self.assertEqual(body["top_products"][0]["name"], "Frame A")
        month = self.client.get(f"{R}sales/", {"group": "month"}).json()
        self.assertEqual(month["rows"][0]["period"], timezone.localdate().strftime("%Y-%m"))
        old = self.client.get(f"{R}sales/", {"date_from": "2020-01-01", "date_to": "2020-01-31"}).json()
        self.assertEqual(old["totals"]["invoices"], 0)

    def test_profit_report(self):
        body = self.client.get(f"{R}profit/").json()
        self.assertEqual(body["totals"], {"revenue": "100000.00", "cost": "43000.00", "profit": "57000.00",
                                          "margin": "57.0"})
        kinds = {k["kind"]: k for k in body["by_kind"]}
        self.assertEqual(kinds["frame"]["revenue"], "100000.00")  # before the invoice discount
        self.assertEqual(kinds["stock_lens"]["cost"], "3000.00")

    def test_credit_report(self):
        body = self.client.get(f"{R}credit/").json()
        self.assertEqual(body["rows"][0]["name"], "Ali")
        self.assertEqual((body["rows"][0]["balance"], body["rows"][0]["days"]), ("6000.00", 0))
        self.assertEqual(body["ageing"][0]["customers"], 1)
        Invoice.objects.filter(patient=self.patient).update(created_at=timezone.now() - datetime.timedelta(days=45))
        self.assertEqual(self.client.get(f"{R}credit/").json()["ageing"][1]["customers"], 1)

    def test_stock_report(self):
        body = self.client.get(f"{R}stock/").json()
        self.assertEqual([r["name"] for r in body["rows"]], ["Frame A"])
        self.assertEqual(body["rows"][0]["value"], "80000.00")
        self.assertEqual({v["kind"]: v["value"] for v in body["value_by_kind"]},
                         {"frame": "80000.00", "stock_lens": "9000.00"})
        self.assertEqual(len(self.client.get(f"{R}stock/", {"all": "true"}).json()["rows"]), 2)

    def test_jobs_and_suppliers_reports(self):
        today = timezone.localdate()
        Job.objects.create(lab=self.lab, number=1, patient=self.patient, promised_date=today - datetime.timedelta(3))
        rows = self.client.get(f"{R}jobs/").json()["rows"]
        self.assertEqual((rows[0]["patient"], rows[0]["days_late"]), ("Ali", 3))
        supplier = Supplier.objects.create(lab=self.lab, name="Hoya")
        self.client.post("/api/v1/purchasing/orders/", {
            "supplier": supplier.id, "lines": [{"product": self.frame.id, "qty": 2, "unit_cost": "15000"}],
        }, format="json")
        body = self.client.get(f"{R}suppliers/").json()
        self.assertEqual((body["rows"][0]["name"], body["rows"][0]["balance"]), ("Hoya", "30000.00"))
        self.assertEqual(body["totals"]["balance"], "30000.00")


class ReportPermissionTests(ReportsBase):
    def test_plain_staff_cannot_open_reports(self):
        self.login_as(self.staff)
        for name in ALL_REPORTS:
            response = self.client.get(f"{R}{name}/")
            self.assertEqual((response.status_code, response.json()["code"]), (403, "cost_permission_required"))

    def test_trusted_staff_reads_reports(self):
        self.login_as(self.trusted)
        for name in ALL_REPORTS:
            self.assertEqual(self.client.get(f"{R}{name}/").status_code, 200, name)

    def test_lab_isolation(self):
        other = make_lab()
        self.login_as(make_member(other, LabUser.Role.OWNER))
        self.assertEqual(self.client.get(f"{R}sales/").json()["totals"]["invoices"], 0)
        self.assertEqual(self.client.get(f"{R}credit/").json()["rows"], [])
        self.assertEqual(self.client.get(f"{R}stock/", {"all": "true"}).json()["rows"], [])
        self.assertEqual(self.client.get(f"{R}dashboard/").json()["today"]["invoices"], 0)


class ExportTests(ReportsBase):
    def test_csv_export_with_feature(self):
        response = self.client.get(f"{R}sales/", {"export": "csv"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response["Content-Type"], "text/csv; charset=utf-8")
        text = response.content.decode("utf-8")
        self.assertTrue(text.startswith("﻿"))
        self.assertIn("الإجمالي", text.splitlines()[0])
        self.assertIn("100000.00", text)
        stock = self.client.get(f"{R}stock/", {"export": "csv"}).content.decode("utf-8")
        self.assertIn("إطار", stock)  # kind values are labelled

    def test_export_needs_the_plan_feature(self):
        plan = self.lab.license.plan
        plan.report_export = False
        plan.save()
        response = self.client.get(f"{R}profit/", {"export": "csv"})
        self.assertEqual((response.status_code, response.json()["code"]), (403, "feature_not_in_plan"))
        self.assertEqual(self.client.get(f"{R}profit/").status_code, 200)  # viewing stays allowed


class LabSettingsTests(LabAPITestCase):
    def setUp(self):
        super().setUp()
        self.media = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.media, ignore_errors=True)
        self.lab = make_lab("Old name")
        self.owner = make_member(self.lab, LabUser.Role.OWNER)
        self.login_as(self.owner)

    def test_owner_edits_settings(self):
        response = self.client.patch("/api/v1/lab/", {
            "name": "  مختبر   النور ", "phone": "0770", "address": "بغداد", "print_header": "سطر 1\nسطر 2",
            "print_footer": "شكراً", "max_discount_percent": "15",
        }, format="json")
        self.assertEqual(response.status_code, 200, response.content)
        self.lab.refresh_from_db()
        self.assertEqual((self.lab.name, self.lab.max_discount_percent), ("مختبر النور", Decimal("15")))
        self.assertEqual(self.client.patch("/api/v1/lab/", {"max_discount_percent": "120"}, format="json").status_code,
                         400)
        self.assertEqual(self.client.patch("/api/v1/lab/", {"name": " "}, format="json").status_code, 400)

    def test_logo_upload_size_and_removal(self):
        png = b"\x89PNG\r\n\x1a\n" + b"0" * 100
        with override_settings(MEDIA_ROOT=self.media):
            response = self.client.patch(
                "/api/v1/lab/", {"logo": SimpleUploadedFile("logo.png", png, content_type="image/png")},
                format="multipart",
            )
            self.assertEqual(response.status_code, 200, response.content)
            self.assertIn("lab_logos/", response.json()["logo"])
            big = SimpleUploadedFile("big.png", b"0" * (1024 * 1024 + 1), content_type="image/png")
            response = self.client.patch("/api/v1/lab/", {"logo": big}, format="multipart")
            self.assertEqual(response.json()["error_codes"]["logo"], ["logo_too_large"])
            bad = SimpleUploadedFile("x.gif", b"GIF89a", content_type="image/gif")
            self.assertEqual(self.client.patch("/api/v1/lab/", {"logo": bad}, format="multipart").status_code, 400)
            response = self.client.patch("/api/v1/lab/", {"remove_logo": True}, format="json")
            self.assertIsNone(response.json()["logo"])
            self.lab.refresh_from_db()
            self.assertFalse(self.lab.logo)

    def test_staff_cannot_edit(self):
        self.login_as(make_member(self.lab))
        self.assertEqual(self.client.patch("/api/v1/lab/", {"name": "x"}, format="json").json()["code"],
                         "owner_required")
