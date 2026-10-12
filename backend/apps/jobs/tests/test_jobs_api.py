import datetime

from django.utils import timezone

from apps.core.testing import (
    LabAPITestCase, make_lab, make_member, make_patient, make_product, make_rx, make_variant, stock_in,
)
from apps.jobs.models import Job, JobStatusLog
from apps.labs.models import LabUser

JOBS = "/api/v1/jobs/"


class JobBase(LabAPITestCase):
    def setUp(self):
        super().setUp()
        self.lab = make_lab()
        self.owner = make_member(self.lab, LabUser.Role.OWNER)
        self.staff = make_member(self.lab)
        self.patient = make_patient(self.lab, full_name="Ali")
        self.rx = make_rx(self.patient)
        self.frame = make_product(self.lab, "frame", name="RB")
        self.lens = make_product(self.lab, "stock_lens", name="CR-39")
        self.od = make_variant(self.lens, sph="-1.00")
        self.os = make_variant(self.lens, sph="-1.25")
        self.login_as(self.staff)

    def _create(self, **extra):
        payload = {
            "patient": self.patient.id, "prescription": self.rx.id, "frame_source": "lab", "frame": self.frame.id,
            "lens": self.lens.id, "lens_od": self.od.id, "lens_os": self.os.id,
            "promised_date": (timezone.localdate() + datetime.timedelta(days=3)).isoformat(), **extra,
        }
        return self.client.post(JOBS, payload)


class JobLifecycleTests(JobBase):
    def test_create_numbers_and_logs(self):
        response = self._create()
        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual((body["number"], body["status"], body["is_overdue"]), (1, "pending", False))
        self.assertEqual(body["lens_od_label"], "SPH -1.00 CYL +0.00")
        self.assertEqual(body["prescription_detail"]["id"], self.rx.id)
        self.assertEqual(len(body["status_logs"]), 1)
        self.assertEqual(self._create().json()["number"], 2)
        self.patient.refresh_from_db()
        self.assertEqual(self.patient.status, "in_job")

    def test_status_flow_with_log_and_delivery(self):
        job_id = self._create().json()["id"]
        url = f"{JOBS}{job_id}/status/"
        for status in ("lens_ordered", "in_workshop", "ready"):
            response = self.client.post(url, {"status": status, "note": f"to {status}"})
            self.assertEqual(response.status_code, 200, response.content)
        body = self.client.post(url, {"status": "delivered"}).json()
        self.assertEqual(body["status"], "delivered")
        self.assertIsNotNone(body["delivered_at"])
        self.assertEqual(
            [(log["from_status"], log["to_status"]) for log in body["status_logs"]],
            [("", "pending"), ("pending", "lens_ordered"), ("lens_ordered", "in_workshop"),
             ("in_workshop", "ready"), ("ready", "delivered")],
        )
        self.assertEqual(body["status_logs"][1]["note"], "to lens_ordered")
        self.patient.refresh_from_db()
        self.assertEqual(self.patient.status, "delivered")
        # Final: no more moves, no edits.
        self.assertEqual(self.client.post(url, {"status": "ready"}).json()["code"], "invalid_transition")
        self.assertEqual(self.client.patch(f"{JOBS}{job_id}/", {"notes": "x"}).json()["code"], "job_closed")

    def test_invalid_transitions(self):
        job_id = self._create().json()["id"]
        url = f"{JOBS}{job_id}/status/"
        self.assertEqual(self.client.post(url, {"status": "delivered"}).json()["code"], "invalid_transition")
        self.assertEqual(self.client.post(url, {"status": "pending"}).json()["code"], "invalid_transition")
        self.assertEqual(self.client.post(url, {"status": "cancelled"}).json()["status"], "cancelled")
        self.assertEqual(JobStatusLog.objects.filter(job_id=job_id).count(), 2)

    def test_rework_from_ready(self):
        job_id = self._create().json()["id"]
        url = f"{JOBS}{job_id}/status/"
        self.client.post(url, {"status": "ready"})
        self.assertEqual(self.client.post(url, {"status": "in_workshop", "note": "scratch"}).json()["status"], "in_workshop")

    def test_status_not_writable_by_patch(self):
        job_id = self._create().json()["id"]
        self.client.patch(f"{JOBS}{job_id}/", {"status": "delivered", "notes": "rush"})
        job = Job.objects.get(pk=job_id)
        self.assertEqual((job.status, job.notes), ("pending", "rush"))

    def test_customer_own_frame(self):
        response = self._create(frame_source="customer", frame=None, frame_notes="Black metal, customer's")
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["frame_source"], "customer")
        self.assertEqual(self._create(frame_source="customer").json()["code"], "invalid_frame")

    def test_overdue_flag_filter_and_summary(self):
        past = (timezone.localdate() - datetime.timedelta(days=1)).isoformat()
        late = self._create(promised_date=past).json()
        self._create()
        ready_late = self._create(promised_date=past).json()
        self.client.post(f"{JOBS}{ready_late['id']}/status/", {"status": "ready"})
        self.assertTrue(late["is_overdue"])
        rows = self.client.get(JOBS, {"overdue": "true"}).json()["results"]
        self.assertEqual([r["id"] for r in rows], [late["id"]])  # ready is not overdue
        summary = self.client.get(f"{JOBS}summary/").json()
        self.assertEqual(summary["overdue"], 1)
        self.assertEqual((summary["counts"]["pending"], summary["counts"]["ready"]), (2, 1))
        self.assertEqual(self.client.get(JOBS, {"status": "pending,ready"}).json()["count"], 3)


class JobValidationTests(JobBase):
    def test_links_must_match_patient(self):
        other = make_patient(self.lab)
        self.assertEqual(self._create(prescription=make_rx(other).id).json()["code"], "prescription_mismatch")

    def test_invoice_link_and_mismatch(self):
        from apps.sales.models import Invoice

        service = make_product(self.lab, "service", name="Fitting")
        sale = {"lines": [{"product": service.id, "qty": 1}], "payment_type": "credit", "patient": self.patient.id}
        invoice = self.client.post("/api/v1/sales/checkout/", sale).json()
        body = self._create(invoice=invoice["id"]).json()
        self.assertEqual((body["invoice_number"], body["invoice_balance"]), (invoice["number"], invoice["balance"]))
        other = make_patient(self.lab)
        other_invoice = self.client.post("/api/v1/sales/checkout/", {**sale, "patient": other.id}).json()
        self.assertEqual(self._create(invoice=other_invoice["id"]).json()["code"], "invoice_mismatch")
        Invoice.objects.filter(pk=invoice["id"]).update(status="cancelled")
        self.assertEqual(self._create(invoice=invoice["id"]).json()["code"], "invoice_cancelled")

    def test_frame_and_lens_kinds(self):
        self.assertEqual(self._create(frame=self.lens.id).json()["code"], "invalid_frame")
        self.assertEqual(self._create(lens=self.frame.id, lens_od=None, lens_os=None).json()["code"], "invalid_lens")
        other_lens = make_product(self.lab, "stock_lens")
        self.assertEqual(self._create(lens_od=make_variant(other_lens).id).json()["code"], "invalid_lens")
        rx_lens = make_product(self.lab, "rx_lens", name="Progressive 1.67")
        response = self._create(lens=rx_lens.id, lens_od=None, lens_os=None, lens_notes="order from supplier")
        self.assertEqual(response.status_code, 201, response.content)

    def test_patient_locked_and_no_delete(self):
        job_id = self._create().json()["id"]
        other = make_patient(self.lab)
        self.assertEqual(self.client.patch(f"{JOBS}{job_id}/", {"patient": other.id}).json()["code"], "patient_locked")
        self.assertEqual(self.client.delete(f"{JOBS}{job_id}/").status_code, 405)

    def test_job_does_not_touch_stock(self):
        stock_in(self.od, 2)
        self._create()
        self.od.refresh_from_db()
        self.assertEqual(self.od.quantity, 2)


class JobIsolationTests(JobBase):
    def test_other_labs_jobs_and_rows(self):
        other_lab = make_lab()
        other_patient = make_patient(other_lab)
        other_job = Job.objects.create(lab=other_lab, number=1, patient=other_patient)
        self.assertEqual(self.client.get(JOBS).json()["count"], 0)
        self.assertEqual(self.client.get(f"{JOBS}{other_job.id}/").status_code, 404)
        self.assertEqual(self.client.post(f"{JOBS}{other_job.id}/status/", {"status": "ready"}).status_code, 404)
        self.assertEqual(self.client.get(f"{JOBS}summary/").json()["counts"]["pending"], 0)
        response = self.client.post(JOBS, {"patient": other_patient.id})
        self.assertIn("patient", response.json()["errors"])
        other_frame = make_product(other_lab, "frame")
        self.assertIn("frame", self._create(frame=other_frame.id).json()["errors"])
