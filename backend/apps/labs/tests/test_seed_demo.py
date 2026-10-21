from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.db.models import Sum
from django.test import TestCase
from django.utils import timezone

from apps.catalog.models import LensVariant, Product
from apps.doctors.models import DoctorLabLink, Referral
from apps.inventory.models import StockMovement
from apps.jobs.models import Job
from apps.labs.models import Lab
from apps.patients.models import Patient
from apps.purchasing.models import SupplierOrder
from apps.sales.models import Invoice


class SeedDemoTests(TestCase):
    """`seed_demo` builds a consistent demo lab covering every list and status."""

    @classmethod
    def setUpTestData(cls):
        # The test runner turns DEBUG off, which the command refuses without the flag.
        call_command("seed_demo", noinput=True, allow_production=True, verbosity=0)

    def test_lab_and_owner(self):
        lab = Lab.objects.get()
        self.assertEqual(lab.name, "مختبر عوينات الجامعة")
        ali = get_user_model().objects.get(username="ali")
        self.assertTrue(ali.check_password("aasddff"))
        self.assertEqual(ali.lab_membership.role, "owner")
        self.assertTrue(ali.is_superuser)

    def test_every_status_is_represented(self):
        self.assertEqual(set(Job.objects.values_list("status", flat=True)), {s for s, _ in Job.Status.choices})
        self.assertEqual(
            set(SupplierOrder.objects.values_list("status", flat=True)),
            {s for s, _ in SupplierOrder.Status.choices},
        )
        self.assertEqual(set(SupplierOrder.objects.values_list("type", flat=True)), {"stock", "rx_for_job", "other"})
        self.assertEqual(set(Referral.objects.values_list("status", flat=True)), {s for s, _ in Referral.Status.choices})
        self.assertEqual(set(Invoice.objects.values_list("status", flat=True)), {s for s, _ in Invoice.Status.choices})
        self.assertEqual(set(DoctorLabLink.objects.values_list("status", flat=True)), {"accepted", "pending"})
        self.assertEqual(
            set(Product.objects.values_list("kind", flat=True)), {k for k, _ in Product.Kind.choices}
        )
        today = timezone.localdate()
        overdue = Job.objects.filter(
            promised_date__lt=today, status__in=["pending", "lens_ordered", "in_workshop"]
        )
        self.assertGreaterEqual(overdue.count(), 3)

    def test_numbers_follow_the_dates(self):
        for model in (Invoice, Job, SupplierOrder):
            by_date = list(model.objects.order_by("created_at", "id").values_list("number", flat=True))
            self.assertEqual(by_date, sorted(by_date), model.__name__)
        self.assertFalse(Invoice.objects.filter(created_at__gt=timezone.now()).exists())

    def test_stock_matches_the_ledger(self):
        for product in Product.objects.filter(track_stock=True):
            ledger = StockMovement.objects.filter(product=product).aggregate(t=Sum("qty"))["t"] or 0
            self.assertEqual(product.quantity, ledger, product.name)
            self.assertGreaterEqual(product.quantity, 0)
            if product.uses_variants:
                variants = LensVariant.objects.filter(product=product).aggregate(t=Sum("quantity"))["t"] or 0
                self.assertEqual(product.quantity, variants, product.name)

    def test_walk_ins_credit_and_lens_arrival(self):
        self.assertTrue(Invoice.objects.filter(patient=None).exclude(customer_name="").exists())
        self.assertTrue(Invoice.objects.filter(patient=None, customer_name="").exists())
        self.assertTrue(Invoice.objects.filter(status="partially_paid", payment_type="credit").exists())
        # A ready job whose invoice is unpaid (delivery warning), and one lab frame without an invoice.
        self.assertTrue(Job.objects.filter(status="ready", invoice__balance__gt=0).exists())
        self.assertTrue(Job.objects.filter(frame_source="lab", invoice=None, status="pending").exists())
        # The fully received rx order moved its job to the workshop.
        received_rx = SupplierOrder.objects.filter(type="rx_for_job", status="received")
        self.assertTrue(received_rx.filter(job__status="in_workshop").exists())
        self.assertGreaterEqual(Patient.objects.count(), 20)
