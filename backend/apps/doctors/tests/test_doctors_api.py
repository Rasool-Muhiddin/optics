import re

from django.contrib.auth import get_user_model
from django.urls import URLPattern, URLResolver, get_resolver

from apps.accounts.models import AuthToken
from apps.core.testing import (
    PASSWORD, LabAPITestCase, make_lab, make_member, make_patient, make_plan, make_product, stock_in,
)
from apps.doctors.models import DoctorLabLink, DoctorProfile, Referral
from apps.labs.models import LabUser
from apps.patients.models import EyeExam, Patient, Prescription

LINKS = "/api/v1/doctor/links/"
REFS = "/api/v1/doctor/referrals/"
LAB_LINKS = "/api/v1/referrals/links/"
INBOX = "/api/v1/referrals/"


def make_doctor(name="Dr. Samer", **fields):
    user = get_user_model().objects.create_user(username=f"doc_{name.split()[-1].lower()}", password=PASSWORD)
    return DoctorProfile.objects.create(user=user, full_name=name, **fields)


class DoctorBase(LabAPITestCase):
    def setUp(self):
        super().setUp()
        self.lab = make_lab("Al-Noor", plan=make_plan(doctor_linking=True), phone="0770")
        self.owner = make_member(self.lab, LabUser.Role.OWNER)
        self.staff = make_member(self.lab)
        self.doctor = make_doctor()

    def as_doctor(self, doctor=None):
        _, key = AuthToken.issue((doctor or self.doctor).user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {key}")

    def link(self, status=DoctorLabLink.Status.ACCEPTED, lab=None, doctor=None):
        return DoctorLabLink.objects.create(
            lab=lab or self.lab, doctor=doctor or self.doctor, status=status, requested_by="doctor"
        )

    def referral_payload(self, **extra):
        return {
            "lab": self.lab.id,
            "patient_name": "  زينب   علي ",
            "patient_age": 35,
            "patient_gender": "female",
            "patient_phone": "07701112222",
            "diagnosis": "Myopic astigmatism",
            "va_od": "6/12",
            "prescription": {
                "od_sph": "-2.50", "od_cyl": "+0.50", "od_axis": 80, "os_sph": "-2.00", "pd_distance": "62",
                "lens_coatings": ["ar"],
            },
            "notes": "Progressive lenses please",
            **extra,
        }


class DoctorAuthTests(DoctorBase):
    def test_doctor_login_and_me(self):
        response = self.client.post("/api/v1/desktop/doctor-login/", {"username": "doc_samer", "password": PASSWORD})
        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertEqual((body["role"], body["doctor"]["full_name"]), ("doctor", "Dr. Samer"))
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {body['token']}")
        self.assertEqual(self.client.get("/api/v1/doctor/me/").json()["doctor"]["link_code"], self.doctor.link_code)
        # A doctor is not a lab member: the lab session endpoint refuses.
        self.assertEqual(self.client.get("/api/v1/auth/me/").json()["code"], "no_lab_membership")

    def test_lab_user_cannot_use_doctor_login_or_endpoints(self):
        response = self.client.post(
            "/api/v1/desktop/doctor-login/", {"username": self.owner.user.username, "password": PASSWORD}
        )
        self.assertEqual(response.json()["code"], "not_a_doctor")
        self.login_as(self.owner)
        self.assertEqual(self.client.get(REFS).json()["code"], "not_a_doctor")

    def test_bad_password_and_inactive_doctor(self):
        bad = self.client.post("/api/v1/desktop/doctor-login/", {"username": "doc_samer", "password": "x"})
        self.assertEqual(bad.json()["code"], "invalid_credentials")
        self.doctor.is_active = False
        self.doctor.save()
        response = self.client.post("/api/v1/desktop/doctor-login/", {"username": "doc_samer", "password": PASSWORD})
        self.assertEqual(response.json()["code"], "doctor_inactive")


class LinkTests(DoctorBase):
    def test_doctor_requests_with_lab_code_and_owner_accepts(self):
        self.as_doctor()
        response = self.client.post(LINKS, {"code": self.lab.doctor_link_code.lower()})
        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual((body["status"], body["lab_name"], body["lab_phone"]), ("pending", "Al-Noor", "0770"))
        self.assertEqual(self.client.post(LINKS, {"code": self.lab.doctor_link_code}).json()["code"],
                         "already_requested")
        # The doctor cannot accept their own request.
        self.assertEqual(self.client.post(f"{LINKS}{body['id']}/accept/").json()["code"], "cannot_answer_own_request")

        self.login_as(self.staff)
        self.assertEqual(self.client.post(f"{LAB_LINKS}{body['id']}/accept/").json()["code"], "owner_required")
        self.login_as(self.owner)
        rows = self.client.get(LAB_LINKS).json()["results"]
        self.assertEqual((rows[0]["doctor_name"], rows[0]["requested_by"]), ("Dr. Samer", "doctor"))
        self.assertEqual(self.client.post(f"{LAB_LINKS}{body['id']}/accept/").json()["status"], "accepted")

    def test_lab_requests_with_doctor_code_and_doctor_rejects_then_revoke_rerequest(self):
        self.login_as(self.owner)
        link = self.client.post(LAB_LINKS, {"code": self.doctor.link_code}).json()
        self.assertEqual(link["requested_by"], "lab")
        self.as_doctor()
        self.assertEqual(self.client.post(f"{LINKS}{link['id']}/reject/").json()["status"], "rejected")
        # A new request after a rejection reopens the same link; the lab then accepts.
        self.assertEqual(self.client.post(LINKS, {"code": self.lab.doctor_link_code}).json()["status"], "pending")
        self.login_as(self.owner)
        self.client.post(f"{LAB_LINKS}{link['id']}/accept/")
        self.as_doctor()
        self.assertEqual(self.client.post(f"{LINKS}{link['id']}/revoke/").json()["status"], "revoked")
        self.assertEqual(DoctorLabLink.objects.count(), 1)

    def test_both_sides_asking_links_at_once(self):
        self.login_as(self.owner)
        self.client.post(LAB_LINKS, {"code": self.doctor.link_code})
        self.as_doctor()
        self.assertEqual(self.client.post(LINKS, {"code": self.lab.doctor_link_code}).json()["status"], "accepted")

    def test_codes_and_feature_gate(self):
        self.as_doctor()
        self.assertEqual(self.client.post(LINKS, {"code": "NOPE1234"}).json()["code"], "invalid_link_code")
        basic = make_lab(plan=make_plan(doctor_linking=False))
        response = self.client.post(LINKS, {"code": basic.doctor_link_code})
        self.assertEqual((response.status_code, response.json()["code"]), (403, "feature_not_in_plan"))
        self.login_as(make_member(basic, LabUser.Role.OWNER))
        for url in (LAB_LINKS, INBOX, f"{LAB_LINKS}code/"):
            self.assertEqual(self.client.get(url).json()["code"], "feature_not_in_plan", url)

    def test_lab_code_is_owner_only_and_can_be_regenerated(self):
        self.login_as(self.staff)
        self.assertEqual(self.client.get(f"{LAB_LINKS}code/").json()["code"], "owner_required")
        self.login_as(self.owner)
        old = self.client.get(f"{LAB_LINKS}code/").json()["code"]
        new = self.client.post(f"{LAB_LINKS}code/").json()["code"]
        self.assertNotEqual(old, new)
        self.as_doctor()
        self.assertEqual(self.client.post(LINKS, {"code": old}).json()["code"], "invalid_link_code")
        # The lab code never leaks through the lab settings / session.
        self.login_as(self.owner)
        self.assertNotIn("doctor_link_code", self.client.get("/api/v1/lab/").json())


class ReferralTests(DoctorBase):
    def test_referral_needs_accepted_link(self):
        self.as_doctor()
        self.assertEqual(self.client.post(REFS, self.referral_payload(), format="json").json()["code"], "not_linked")
        self.link(DoctorLabLink.Status.PENDING)
        self.assertEqual(self.client.post(REFS, self.referral_payload(), format="json").json()["code"], "not_linked")

    def test_send_validates_rx_and_keeps_it_as_entered(self):
        self.link()
        self.as_doctor()
        bad = self.referral_payload(prescription={"od_sph": "-2.10"})
        self.assertEqual(self.client.post(REFS, bad, format="json").json()["error_codes"]["prescription"]["od_sph"],
                         ["invalid_sph"])
        response = self.client.post(REFS, self.referral_payload(), format="json")
        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual((body["status"], body["patient_name"], body["lab_name"]), ("sent", "زينب علي", "Al-Noor"))
        self.assertEqual((body["prescription"]["od_cyl"], body["prescription"]["od_axis"]), ("0.50", 80))

    def test_lab_accepts_creating_patient_exam_and_rx(self):
        self.link()
        self.as_doctor()
        ref_id = self.client.post(REFS, self.referral_payload(), format="json").json()["id"]
        self.login_as(self.staff)
        inbox = self.client.get(INBOX, {"open": "true"}).json()
        self.assertEqual((inbox["count"], inbox["results"][0]["doctor_name"]), (1, "Dr. Samer"))
        self.assertEqual(self.client.post(f"{INBOX}{ref_id}/receive/").json()["status"], "received")
        body = self.client.post(f"{INBOX}{ref_id}/accept/", {}, format="json").json()
        self.assertEqual(body["status"], "in_progress")
        patient = Patient.objects.get(pk=body["patient"])
        self.assertEqual((patient.full_name, patient.age, patient.gender, patient.status),
                         ("زينب علي", 35, "female", "exam_done"))
        exam = EyeExam.objects.get(pk=body["exam"])
        self.assertEqual((exam.examiner_name, exam.diagnosis, exam.created_by), ("د. Dr. Samer", "Myopic astigmatism",
                                                                                  self.staff.user))
        rx = Prescription.objects.get(exam=exam)
        self.assertEqual((str(rx.od_sph), str(rx.od_cyl), rx.od_axis), ("-2.50", "0.50", 80))  # as entered
        self.assertEqual(rx.prescribed_by, "د. Dr. Samer")
        self.assertEqual(self.client.post(f"{INBOX}{ref_id}/accept/", {}).json()["code"], "invalid_transition")
        self.assertEqual(self.client.post(f"{INBOX}{ref_id}/complete/").json()["status"], "completed")
        # The doctor sees the status only.
        self.as_doctor()
        seen = self.client.get(f"{REFS}{ref_id}/").json()
        self.assertEqual(seen["status"], "completed")
        self.assertFalse({"patient", "exam", "handled_by_name", "doctor"} & set(seen))

    def test_accept_into_existing_patient_and_reject(self):
        self.link()
        self.as_doctor()
        first = self.client.post(REFS, self.referral_payload(prescription=None), format="json").json()["id"]
        second = self.client.post(REFS, self.referral_payload(), format="json").json()["id"]
        existing = make_patient(self.lab, full_name="Zainab Ali")
        other_lab_patient = make_patient(make_lab())
        self.login_as(self.owner)
        response = self.client.post(f"{INBOX}{first}/accept/", {"patient": other_lab_patient.id}, format="json")
        self.assertEqual(response.status_code, 400)
        body = self.client.post(f"{INBOX}{first}/accept/", {"patient": existing.id}, format="json").json()
        self.assertEqual(body["patient"], existing.id)
        self.assertFalse(Prescription.objects.exists())  # referral without Rx
        self.assertEqual(Patient.objects.filter(lab=self.lab).count(), 1)
        body = self.client.post(f"{INBOX}{second}/reject/", {"reason": "We do not stock 1.74"}).json()
        self.assertEqual((body["status"], body["reject_reason"]), ("rejected", "We do not stock 1.74"))
        summary = self.client.get(f"{INBOX}summary/").json()
        self.assertEqual((summary["counts"]["in_progress"], summary["counts"]["rejected"], summary["open"]), (1, 1, 0))

    def test_plan_downgrade_blocks_new_referrals(self):
        self.link()
        plan = self.lab.license.plan
        plan.doctor_linking = False
        plan.save()
        self.as_doctor()
        response = self.client.post(REFS, self.referral_payload(), format="json")
        self.assertEqual(response.json()["code"], "feature_not_in_plan")


class DoctorIsolationTests(DoctorBase):
    """A doctor never sees lab invoices, prices or any unlinked lab's data."""

    def setUp(self):
        super().setUp()
        self.link()
        other_lab = make_lab("Other", plan=make_plan(doctor_linking=True))
        self.other_doctor = make_doctor("Dr. Huda")
        self.link(lab=other_lab, doctor=self.other_doctor)
        # Lab data a doctor must never reach: products/prices, an invoice, patients.
        frame = make_product(self.lab, sale_price="90000", purchase_price="40000")
        stock_in(frame, 2)
        self.login_as(self.owner)
        checkout = self.client.post("/api/v1/sales/checkout/", {
            "customer_name": "x", "lines": [{"product": frame.id, "qty": 1}],
        }, format="json")
        self.assertEqual(checkout.status_code, 201, checkout.content)
        make_patient(self.lab, full_name="Secret patient")
        # The other doctor's referral to the other lab.
        Referral.objects.create(lab=other_lab, doctor=self.other_doctor, patient_name="Hidden")
        self.as_doctor()

    def _lab_routes(self, resolver=None, prefix=""):
        for entry in (resolver or get_resolver()).url_patterns:
            pattern = prefix + str(entry.pattern)
            if isinstance(entry, URLResolver):
                yield from self._lab_routes(entry, pattern)
            elif isinstance(entry, URLPattern) and pattern.startswith("api/v1/"):
                path = re.sub(r"\(\?P<[^>]+>[^)]+\)", "1", pattern)
                path = re.sub(r"<[^>]+>", "1", path).replace("^", "").replace("$", "").replace("\\.", ".")
                if "(?P" in path or "format" in path or path.startswith("api/v1/doctor/"):
                    continue
                yield "/" + path

    def test_doctor_token_is_refused_by_every_lab_endpoint(self):
        public = {"/api/v1/health/", "/api/v1/desktop/activate/", "/api/v1/desktop/login/",
                  "/api/v1/desktop/doctor-login/", "/api/v1/desktop/latest-version/"}
        checked = 0
        for path in sorted(set(self._lab_routes()) - public):
            response = self.client.get(path)
            self.assertIn(response.status_code, (403, 404, 405), f"GET {path} → {response.status_code}")
            body = response.content.decode()
            for secret in ("90000", "40000", "Secret patient"):
                self.assertNotIn(secret, body, path)
            checked += 1
        self.assertGreater(checked, 20)

    def test_doctor_sees_only_own_links_and_referrals(self):
        self.client.post(REFS, self.referral_payload(), format="json")
        refs = self.client.get(REFS).json()
        self.assertEqual([r["patient_name"] for r in refs["results"]], ["زينب علي"])
        hidden = Referral.objects.get(patient_name="Hidden")
        self.assertEqual(self.client.get(f"{REFS}{hidden.id}/").status_code, 404)
        links = self.client.get(LINKS).json()["results"]
        self.assertEqual([l["lab_name"] for l in links], ["Al-Noor"])
        other_link = DoctorLabLink.objects.get(doctor=self.other_doctor)
        self.assertEqual(self.client.post(f"{LINKS}{other_link.id}/revoke/").status_code, 404)
        # Sending to a lab the doctor is not linked to is refused.
        payload = self.referral_payload(lab=other_link.lab_id)
        self.assertEqual(self.client.post(REFS, payload, format="json").json()["code"], "not_linked")

    def test_doctor_responses_carry_no_prices(self):
        self.client.post(REFS, self.referral_payload(), format="json")
        for url in (LINKS, REFS, "/api/v1/doctor/me/"):
            body = self.client.get(url).content.decode()
            for key in ("price", "cost", "total", "invoice", "balance"):
                self.assertNotIn(key, body, url)

    def test_lab_never_sees_another_labs_referrals(self):
        self.login_as(self.owner)
        self.assertEqual(self.client.get(INBOX).json()["count"], 0)
        hidden = Referral.objects.get(patient_name="Hidden")
        self.assertEqual(self.client.get(f"{INBOX}{hidden.id}/").status_code, 404)
        self.assertEqual(self.client.post(f"{INBOX}{hidden.id}/accept/", {}).status_code, 404)
